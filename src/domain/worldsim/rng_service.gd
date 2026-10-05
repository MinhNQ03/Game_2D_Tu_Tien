extends RefCounted
class_name RngService
## RngService — Aetheria domain (the deterministic RNG seam: one world seed → many streams).
##
## The frozen shape from `docs/SYSTEM_DEPENDENCY_MATRIX.md` §4c (D-040 / C-010), introduced
## here because Phase 08 is its FIRST genuine consumer:
##
## ```
## RUN / WORLD SEED
##    ├── world simulation stream
##    ├── combat stream              (P-09, reuses this seam)
##    ├── enemy AI stream            (P-10)
##    ├── loot / economy stream
##    └── future subsystem / instance streams
## ```
##
## Frozen properties, all satisfied here: **deterministic · seeded · injectable ·
## subsystem-scoped · serializable · presentation-independent · no global `rand*()`.**
##
## INJECTABLE, NOT AN AUTOLOAD. `03-architecture.md` lists `RNG` among the *anticipated*
## autoloads, and D-017 freezes the budget at five. This is a plain `RefCounted` handed to
## whoever needs it — the same choice already made for `RelationshipService` and
## `KnowledgeService` (`SYSTEM_DEPENDENCY_MATRIX.md` §5: "Neither the Knowledge Core nor the
## RNG seam is an autoload"). A global RNG would also make the determinism untestable, since
## two tests in one process would share a sequence.
##
## WHY ONLY THE STREAMS WITH A REAL CONSUMER ARE NAMED HERE. The matrix lists the future
## streams above, but a constant for a stream nothing draws from yet is exactly the speculative
## surface L-005 forbids. Phase 08 named ONE id, and Phase 09 added the second the day
## `CombatService` actually drew from it. The API takes any `StringName`, so the next stream is
## a constant plus a consumer, in the same commit — never a constant on its own.

## The world-simulation stream (Phase 08).
const STREAM_WORLD_SIM := &"world_sim"

## The combat stream (Phase 09, D-007). Drawn from by `CombatService` for the critical-hit
## roll. It is a stream of its own, not a shared one, because `derive_state()` makes streams
## start independently: a combat roll can never shift the world simulation's sequence, so two
## runs with the same seed evolve the same world whether or not the player fought on the way.
const STREAM_COMBAT := &"combat"

## Seed bounds. The world seed is a 32-bit value because that is the width the stream mixer
## works in; a wider seed would have bits that cannot affect anything, which is worse than a
## narrower one because it would LOOK like it mattered.
const SEED_MIN := 0
const SEED_MAX := RngStream.MASK_32

var _world_seed: int = 0
## stream_id(String) -> RngStream. Created on demand, then kept, so repeated `stream()` calls
## return the SAME advancing stream rather than silently restarting the sequence.
var _streams: Dictionary = {}


## Build the seam for one run/world. An out-of-range seed is REJECTED at construction by
## clamping to a reported error rather than wrapping silently — a seed is the identity of a
## whole world, and a wrapped seed would produce a world the player's save file does not name.
## Use `is_valid()` to check; `WorldSimulationService` refuses to start on an invalid seam.
func _init(world_seed: int = 0) -> void:
	if world_seed < SEED_MIN or world_seed > SEED_MAX:
		push_error("[rng] world seed %d is outside [%d, %d]; the seam is INVALID and will "
			% [world_seed, SEED_MIN, SEED_MAX] + "refuse to produce streams")
		_world_seed = -1
		return
	_world_seed = world_seed


## True when the seam holds a usable world seed. A caller that can fail closed must check
## this (B20: an invalid seed is an explicit error, never a silent default).
func is_valid() -> bool:
	return _world_seed >= SEED_MIN and _world_seed <= SEED_MAX


func world_seed() -> int:
	return _world_seed


## The stream for `stream_id`, created on first use from `(world_seed, stream_id)`.
##
## Returns null (loud) on an invalid seam or an empty id — never a "default" stream, because a
## caller that silently received an unseeded generator would produce a world that cannot be
## reproduced, which is the one failure mode this whole seam exists to prevent.
func stream(stream_id: StringName) -> RngStream:
	if not is_valid():
		push_error("[rng] stream('%s') refused: the seam has no valid world seed" % stream_id)
		return null
	if stream_id == &"":
		push_error("[rng] stream() requires a non-empty stream id")
		return null
	var key := String(stream_id)
	var existing: RngStream = _streams.get(key)
	if existing != null:
		return existing
	var created := RngStream.new(stream_id, derive_state(_world_seed, stream_id))
	_streams[key] = created
	return created


## Has a stream for `stream_id` been created yet? (Distinguishes "never drawn from" from
## "drawn from and back at its start", which `draw_count()` alone cannot.)
func has_stream(stream_id: StringName) -> bool:
	return _streams.has(String(stream_id))


## Every created stream id, sorted — so serialization and any iteration over streams is
## deterministic regardless of the order they happened to be created in.
func stream_ids_sorted() -> Array[StringName]:
	var keys: Array = _streams.keys()
	keys.sort()
	var out: Array[StringName] = []
	for key in keys:
		out.append(StringName(String(key)))
	return out


## Derive a stream's STARTING state from the world seed and its id.
##
## The stream id is folded in one character at a time through the same mixer the stream uses,
## so two different ids starting from one seed land far apart in the sequence space. This is
## what makes stream isolation a property of the CONSTRUCTION rather than a hope: the streams
## do not merely advance independently, they also START independently, so `world_sim` and
## `combat` under the same world seed are unrelated sequences rather than the same sequence
## read at two offsets.
##
## Static and pure, so a test can assert the derivation without building a service.
static func derive_state(world_seed: int, stream_id: StringName) -> int:
	var acc := RngStream.mix(world_seed & RngStream.MASK_32)
	var text := String(stream_id)
	for i in text.length():
		acc = RngStream.mix((acc ^ text.unicode_at(i)) & RngStream.MASK_32)
	return acc & RngStream.MASK_32


# --- Serialization (persistent; `docs/SAVE_FORMAT.md` §3b) -------------------

## Serialize the seed AND every live stream's position.
##
## The seed alone is NOT sufficient and that gap is recorded in `SAVE_FORMAT.md` §3b: a seed
## reproduces a run only FROM THE BEGINNING, so a save taken forty hours in must also record
## how far each stream has advanced or the post-load world diverges from the pre-load one.
## Streams are emitted in sorted id order so the snapshot is byte-stable.
func to_dict() -> Dictionary:
	var streams := {}
	for stream_id in stream_ids_sorted():
		var s: RngStream = _streams[String(stream_id)]
		streams[String(stream_id)] = s.to_dict()
	return {
		"world_seed": _world_seed,
		"streams": streams,
	}


## Hydrate seed + stream positions, STRICTLY typed and ATOMIC: everything is staged and the
## receiver is only written once every entry has validated, so a rejected payload leaves the
## seam exactly as it was (L-024 / the staged-then-commit shape).
func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[rng] from_dict: payload is not a Dictionary")
		return false
	var dict: Dictionary = data

	var seed_value: Variant = dict.get("world_seed", null)
	if typeof(seed_value) != TYPE_INT:
		push_error("[rng] from_dict: world_seed must be an int (got %s)"
			% type_string(typeof(seed_value)))
		return false
	var in_seed: int = seed_value
	if in_seed < SEED_MIN or in_seed > SEED_MAX:
		push_error("[rng] from_dict: world_seed %d outside [%d, %d]"
			% [in_seed, SEED_MIN, SEED_MAX])
		return false

	var streams_value: Variant = dict.get("streams", {})
	if typeof(streams_value) != TYPE_DICTIONARY:
		push_error("[rng] from_dict: 'streams' is not a Dictionary")
		return false
	var staged := {}
	var keys: Array = (streams_value as Dictionary).keys()
	keys.sort()
	for key in keys:
		var key_type := typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME:
			push_error("[rng] from_dict: stream key must be a String/StringName (got %s)"
				% type_string(key_type))
			return false
		var restored := RngStream.new()
		if not restored.from_dict((streams_value as Dictionary)[key]):
			push_error("[rng] from_dict: stream '%s' payload is malformed" % String(key))
			return false
		if String(restored.stream_id) != String(key):
			push_error("[rng] from_dict: stream key '%s' disagrees with its payload id '%s'"
				% [String(key), restored.stream_id])
			return false
		staged[String(key)] = restored

	_world_seed = in_seed
	_streams = staged
	return true

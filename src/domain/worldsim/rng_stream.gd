extends RefCounted
class_name RngStream
## RngStream — Aetheria domain (ONE deterministic, serializable random stream).
##
## The unit of the deterministic RNG seam introduced in Phase 08
## (`docs/SYSTEM_DEPENDENCY_MATRIX.md` §4c, D-040 / C-010). A stream is created by
## `RngService` from `(world_seed, stream_id)` and advances INDEPENDENTLY of every other
## stream, which is the whole point: with one shared generator, adding a single extra draw in
## combat would silently shift every subsequent world-simulation roll, so a bug fix in one
## subsystem would change unrelated outcomes and "same seed → same world" would stop being
## true.
##
## WHY NOT `RandomNumberGenerator`. The engine's RNG is per-instance (so it would satisfy
## "no global `rand*()`") and even exposes a `state` property to save/restore. It was rejected
## for ONE reason: a save must be able to resume a world EXACTLY (`docs/SAVE_FORMAT.md` §3b),
## which means the generator's state is part of our persisted format. Storing an
## engine-internal state blob would tie the save format — and therefore a player's world — to
## an engine implementation detail we do not control and cannot migrate. The mixer below is
## nine lines, we own its contract, and it serializes as two plain integers.
##
## THE ALGORITHM (deliberately minimal — B5: "may remain minimal and deterministic").
## A 32-bit Weyl counter (`+ 0x9E3779B9`) fed through the well-known `lowbias32` finalizer.
## Properties that matter here:
##   * every intermediate value is masked to 32 bits and every product therefore fits inside
##     the 64-bit `int` GDScript gives us, so NOTHING overflows and the result cannot depend
##     on how a platform handles overflow;
##   * `>>` is only ever applied to a NON-NEGATIVE value, so GDScript's arithmetic (sign
##     propagating) shift behaves identically to a logical shift here — the classic portability
##     trap in hand-rolled 64-bit PRNGs is avoided by construction;
##   * the counter is a plain increment, so the state is a single 32-bit integer and the
##     period is exactly 2^32 — ample for "which elder trains today", and a draw count that
##     large is itself a bug worth noticing.
## Statistical quality is adequate for discrete world-simulation choices. It is NOT a CSPRNG
## and must never be used as one.

## 2^32, the modulus every operation is reduced by.
const MOD_32 := 4294967296
## 32-bit mask (2^32 - 1).
const MASK_32 := 4294967295
## The Weyl increment: 2^32 / golden ratio, odd, so the counter visits every residue.
const WEYL_INCREMENT := 2654435769
## `lowbias32` finalizer constants (Chris Wellons' search for a minimal-bias 32-bit mixer).
const MIX_A := 569420461
const MIX_B := 1935289751

## This stream's identity (e.g. `&"world_sim"`). Serialized as the key, kept here so a stream
## handed around on its own can still report which sequence it is.
var stream_id: StringName = &""

## The Weyl counter. Advances by exactly one per draw, so `draws` and the distance travelled
## are the same thing and a resumed stream is provably at the same position.
var _state: int = 0

## How many values this stream has produced. Serialized. It is not needed to REPRODUCE the
## sequence (the state alone determines that) — it is kept because it is the one number that
## makes a determinism failure diagnosable: two runs that disagree will disagree on the draw
## count first, which immediately distinguishes "a different value was drawn" from "a
## different NUMBER of values was drawn" (an extra call somewhere — the exact failure mode
## per-stream state exists to prevent).
var _draws: int = 0


## Build a stream with an explicit starting state. `RngService` is the normal constructor;
## this is public so a test (or a future replay tool) can pin a stream exactly.
func _init(new_stream_id: StringName = &"", initial_state: int = 0) -> void:
	stream_id = new_stream_id
	_state = initial_state & MASK_32


## The next raw 32-bit value, in [0, 2^32). Always non-negative.
func next_raw() -> int:
	_state = (_state + WEYL_INCREMENT) & MASK_32
	_draws += 1
	return mix(_state)


## The `lowbias32` finalizer, exposed as a static pure function so `RngService` can derive a
## stream's starting state with the SAME mixing the stream itself uses (one algorithm, not
## two) and so a test can assert the mixer independently of any stream's state.
static func mix(value: int) -> int:
	var z := value & MASK_32
	z = ((z ^ (z >> 16)) * MIX_A) & MASK_32
	z = ((z ^ (z >> 15)) * MIX_B) & MASK_32
	return (z ^ (z >> 15)) & MASK_32


## A value in [0, bound). Returns 0 (loud) for a non-positive bound.
##
## Uses Lemire's multiply-shift (`raw * bound >> 32`) rather than `raw % bound`. Modulo is
## biased toward the low values whenever `bound` does not divide 2^32 — for a bound of 3 (a
## three-way world-event choice) that bias is tiny but systematic, and it would be baked into
## every seeded world forever. The product is at most (2^32-1) * bound, which stays inside a
## 64-bit int for any bound a simulation would use, and the shift is on a non-negative value.
func next_below(bound: int) -> int:
	if bound <= 0:
		push_error("[rng] next_below requires a positive bound (got %d)" % bound)
		return 0
	return (next_raw() * bound) >> 32


## A value in the INCLUSIVE range [low, high]. Returns `low` (loud) if the range is inverted,
## so a mis-authored tuning range degrades to a defined value instead of a negative bound.
func next_range(low: int, high: int) -> int:
	if high < low:
		push_error("[rng] next_range inverted: [%d, %d]" % [low, high])
		return low
	return low + next_below(high - low + 1)


## True with `percent`% probability. `percent <= 0` never fires and `percent >= 100` always
## fires, and BOTH of those still CONSUME a draw. That is deliberate: a tuning value of 0 must
## not change how far the stream advances, or editing a probability to zero would silently
## shift every later draw in the world — the same cross-contamination that per-stream state
## exists to prevent, reintroduced inside one stream.
func next_chance(percent: int) -> bool:
	return next_below(100) < percent


## How many values this stream has produced.
func draw_count() -> int:
	return _draws


## The raw counter state. For serialization + assertions, not for gameplay logic.
func state() -> int:
	return _state


# --- Serialization (persistent; `docs/SAVE_FORMAT.md` §3b) -------------------

func to_dict() -> Dictionary:
	return {
		"stream_id": String(stream_id),
		"state": _state,
		"draws": _draws,
	}


## Hydrate from plain data, STRICTLY typed and fail-closed: a wrong type is rejected, never
## coerced (L-024). `int("123")` would happily turn text into a position in the sequence, and
## a stream silently resumed at the wrong position is the single worst failure this class can
## have — every later world event diverges and nothing reports why. Leaves the receiver
## unchanged on rejection.
func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[rng] from_dict: payload is not a Dictionary")
		return false
	var dict: Dictionary = data

	var id_value: Variant = dict.get("stream_id", "")
	var id_type := typeof(id_value)
	if id_type != TYPE_STRING and id_type != TYPE_STRING_NAME:
		push_error("[rng] from_dict: stream_id must be a String/StringName (got %s)"
			% type_string(id_type))
		return false
	var in_id := StringName(String(id_value))
	if in_id == &"":
		push_error("[rng] from_dict: missing stream_id")
		return false

	var state_value: Variant = dict.get("state", 0)
	if typeof(state_value) != TYPE_INT:
		push_error("[rng] from_dict '%s': state must be an int (got %s)"
			% [in_id, type_string(typeof(state_value))])
		return false
	var in_state: int = state_value
	if in_state < 0 or in_state >= MOD_32:
		push_error("[rng] from_dict '%s': state %d is outside [0, 2^32)" % [in_id, in_state])
		return false

	var draws_value: Variant = dict.get("draws", 0)
	if typeof(draws_value) != TYPE_INT:
		push_error("[rng] from_dict '%s': draws must be an int (got %s)"
			% [in_id, type_string(typeof(draws_value))])
		return false
	var in_draws: int = draws_value
	if in_draws < 0:
		push_error("[rng] from_dict '%s': draws must be >= 0 (got %d)" % [in_id, in_draws])
		return false

	stream_id = in_id
	_state = in_state
	_draws = in_draws
	return true

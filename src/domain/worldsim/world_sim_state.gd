extends RefCounted
class_name WorldSimulationState
## WorldSimulationState — Aetheria domain (the simulation's authoritative PERSISTENT tier).
##
## Everything a save must carry for the world to resume EXACTLY where it left off
## (`docs/SAVE_FORMAT.md` §3/§3b, `docs/WORLD_SIMULATION.md` §5): the clock, the seeded RNG
## seam INCLUDING each stream's position, every actor's simulation record, the scheduled-event
## queue, the undrained catch-up debt, and the bounded world-event log the UI reads.
##
## THE RESUME CONTRACT, stated as the property the tests assert:
## ```
##   save → load → advance K ticks   ==   advance K ticks (never saved)
## ```
## That holds only if EVERY input to a future tick is in this snapshot. Four of them are easy
## to forget and each one on its own would break it:
##   1. **stream positions** — a seed alone reproduces a world only from tick 0
##      (`SAVE_FORMAT.md` §3b spells this out);
##   2. **the pending queue** — a recurring event's NEXT due tick is computed when it fires,
##      so it cannot be re-derived from the catalog alone;
##   3. **carry-over ticks** — an unfinished catch-up is simulation time that has been
##      promised and not yet spent; dropping it silently loses world time
##      (`docs/WORLD_SIMULATION.md` §5 forbids that);
##   4. **`joined_tick` per actor** (on `WorldSimActor`) — the origin of the derived activity.
##
## It holds NO rules. Advancing, firing and applying live in `WorldSimulationService`; this is
## the data that gets advanced. No Node, no presentation, no wall clock.

## Snapshot schema version for this block, independent of the global `save_version`
## (`SAVE_FORMAT.md` §2 owns that one). It exists so a Phase-23 migration can tell a
## pre-existing simulation block apart from a later shape without guessing from which keys
## happen to be present.
const SCHEMA_VERSION := 1

var _clock: WorldClock = null
var _rng: RngService = null

## instance_id(String) -> WorldSimActor.
var _actors: Dictionary = {}

## The OBSERVED (NEAR+MID) subset, as a set of instance ids. An INDEX, not a second source of
## truth — it is derived from each actor's band and maintained by `set_actor_band()`, which is
## the only way a band changes.
##
## It exists because the per-tick loop needs the observed set, and deriving it by filtering the
## whole cast would make every tick O(cast log cast) — which is precisely the O(whole cast)
## per-tick cost LOD exists to avoid, reintroduced inside the thing that implements LOD. The
## performance test measured it: 300 ticks over 200 actors cost 3.57x what 20 actors cost, and
## the sort was the whole difference (see `docs/PERFORMANCE.md` PERF-001).
var _observed: Dictionary = {}

## The scheduled-event queue: `[{ "due_tick": int, "event_id": String }]`, kept sorted by
## (due_tick, event_id). The id tie-break is not cosmetic — two events due on the same tick
## must fire in a FIXED order or the same seed would produce different worlds depending on
## dictionary iteration, which is the whole guarantee gone.
var _pending: Array[Dictionary] = []

## Promised-but-unspent simulation time (see the class note, item 3).
var _carry_over_ticks: int = 0

## Bounded log of what the world did, newest LAST:
## `[{ tick, event_id, kind, target_id, magnitude }]`. This is the player-facing feed
## (`SOCIAL_DESIGN.md` §7: the player must be able to feel the world moved without them) and
## it is capped like `RelationshipEdge.history` so it cannot grow without limit inside a save.
var _event_log: Array[Dictionary] = []
var _log_capacity: int = 0


## Build a simulation state around an already-validated clock and RNG seam. Returns null
## (loud) if either is unusable — a simulation with an invalid calendar or an unseeded
## generator must not come into existence at all, because every later answer it gave would be
## unreproducible (B20).
static func create(
		clock: WorldClock, rng: RngService, log_capacity: int) -> WorldSimulationState:
	if clock == null or not clock.is_valid():
		push_error("[worldsim] state requires a VALID WorldClock")
		return null
	if rng == null or not rng.is_valid():
		push_error("[worldsim] state requires a VALID seeded RngService")
		return null
	if log_capacity < 0:
		push_error("[worldsim] state log capacity must be >= 0 (got %d)" % log_capacity)
		return null
	var state := WorldSimulationState.new()
	state._clock = clock
	state._rng = rng
	state._log_capacity = log_capacity
	return state


func clock() -> WorldClock:
	return _clock


func rng() -> RngService:
	return _rng


func tick() -> int:
	return _clock.tick() if _clock != null else 0


# --- Actors ------------------------------------------------------------------

## Register an actor record. Returns false (loud) on null or a duplicate id — never replacing,
## for the same reason `CharacterRegistry.add()` refuses to.
func add_actor(actor: WorldSimActor) -> bool:
	if actor == null:
		push_error("[worldsim] add_actor got null")
		return false
	var key := String(actor.instance_id)
	if key == "":
		push_error("[worldsim] add_actor: empty instance_id")
		return false
	if _actors.has(key):
		push_error("[worldsim] add_actor: '%s' is already simulated" % key)
		return false
	_actors[key] = actor
	if actor.is_observed():
		_observed[key] = true
	return true


## Set an actor's LOD band, keeping the observed index in step. Returns true if the band
## CHANGED. This is the ONLY sanctioned way to change a band: calling
## `WorldSimActor.set_band()` directly would leave the index stale, so a promoted actor would
## silently stop being ticked (or a demoted one would keep being ticked) with nothing to
## report it.
func set_actor_band(instance_id: StringName, band: int) -> bool:
	var actor: WorldSimActor = _actors.get(String(instance_id))
	if actor == null:
		push_error("[worldsim] set_actor_band: '%s' is not simulated" % instance_id)
		return false
	if not actor.set_band(band):
		return false
	var key := String(instance_id)
	if actor.is_observed():
		_observed[key] = true
	else:
		_observed.erase(key)
	return true


func has_actor(instance_id: StringName) -> bool:
	return _actors.has(String(instance_id))


## The actor record for `instance_id`, or null (quiet — a miss is a normal answer).
func get_actor(instance_id: StringName) -> WorldSimActor:
	return _actors.get(String(instance_id))


func actor_count() -> int:
	return _actors.size()


## Every actor id, sorted (deterministic iteration).
func actor_ids_sorted() -> Array[StringName]:
	var keys: Array = _actors.keys()
	keys.sort()
	var out: Array[StringName] = []
	for key in keys:
		out.append(StringName(String(key)))
	return out


## Every actor record, in sorted id order.
func actors_sorted() -> Array[WorldSimActor]:
	var out: Array[WorldSimActor] = []
	for instance_id in actor_ids_sorted():
		out.append(_actors[String(instance_id)])
	return out


## Only the NEAR+MID actors, in sorted id order — the per-tick working set.
##
## This is the LOD cost model made explicit: the per-tick loop iterates THIS, not the whole
## cast, so a world with five hundred background characters and ten near the player does ten
## actors' worth of work per tick (`docs/WORLD_SIMULATION.md` §6). The performance test
## measures exactly this difference.
func observed_actors_sorted() -> Array[WorldSimActor]:
	var keys: Array = _observed.keys()
	keys.sort()
	var out: Array[WorldSimActor] = []
	for key in keys:
		var actor: WorldSimActor = _actors.get(String(key))
		if actor != null:
			out.append(actor)
	return out


## How many actors sit in each band: `{ Band.NEAR: n, Band.MID: n, Band.FAR: n }`.
func band_census() -> Dictionary:
	var census := {
		WorldSimActor.Band.NEAR: 0, WorldSimActor.Band.MID: 0, WorldSimActor.Band.FAR: 0,
	}
	for actor in _actors.values():
		var band: int = (actor as WorldSimActor).band()
		census[band] = int(census.get(band, 0)) + 1
	return census


# --- Scheduled-event queue ---------------------------------------------------

## Schedule `event_id` for `due_tick`. Rejects (loud) an empty id, a non-positive tick, or a
## duplicate id already queued — one pending entry per event, so a recurring event cannot
## accumulate copies of itself and fire N times on one tick.
func schedule_event(event_id: StringName, due_tick: int) -> bool:
	if event_id == &"":
		push_error("[worldsim] schedule_event: empty event id")
		return false
	if due_tick <= 0:
		push_error("[worldsim] schedule_event '%s': due_tick must be > 0 (got %d)"
			% [event_id, due_tick])
		return false
	for entry in _pending:
		if String(entry.get("event_id", "")) == String(event_id):
			push_error("[worldsim] schedule_event: '%s' is already queued (for tick %d)"
				% [event_id, int(entry.get("due_tick", 0))])
			return false
	_pending.append({"due_tick": due_tick, "event_id": String(event_id)})
	_sort_pending()
	return true


## Remove and return every queued entry due at or before `upto_tick`, in fire order.
## The queue is sorted, so this is a prefix — and the (due_tick, event_id) ordering is what
## makes the fire order identical across runs.
func take_due_events(upto_tick: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	while not _pending.is_empty() and int(_pending[0].get("due_tick", 0)) <= upto_tick:
		due.append(_pending.pop_front())
	return due


## A copy of the queue, in fire order (for reads, tests and serialization).
func pending_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _pending:
		out.append(entry.duplicate())
	return out


func pending_count() -> int:
	return _pending.size()


func _sort_pending() -> void:
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a.get("due_tick", 0))
		var tb := int(b.get("due_tick", 0))
		if ta != tb:
			return ta < tb
		return String(a.get("event_id", "")) < String(b.get("event_id", "")))


# --- Catch-up debt -----------------------------------------------------------

func carry_over_ticks() -> int:
	return _carry_over_ticks


## Add promised-but-unspent ticks. Clamped at 0 so a negative debt is impossible.
func add_carry_over(ticks: int) -> void:
	_carry_over_ticks = maxi(0, _carry_over_ticks + ticks)


## Take up to `limit` ticks of debt out of the queue, returning how many were taken.
func drain_carry_over(limit: int) -> int:
	if limit <= 0 or _carry_over_ticks <= 0:
		return 0
	var taken := mini(limit, _carry_over_ticks)
	_carry_over_ticks -= taken
	return taken


# --- World-event log (bounded; the player-facing feed) ----------------------

## Append an entry, trimming the OLDEST when over capacity. A capacity of 0 means the feed is
## disabled and nothing is recorded (the simulation still runs; only the readout is off).
func append_log(entry: Dictionary) -> void:
	if _log_capacity <= 0:
		return
	_event_log.append(entry.duplicate())
	while _event_log.size() > _log_capacity:
		_event_log.pop_front()


## The log, oldest first (a copy).
func event_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _event_log:
		out.append(entry.duplicate())
	return out


## The most recent entry, or an empty Dictionary when nothing has happened yet.
func latest_event() -> Dictionary:
	if _event_log.is_empty():
		return {}
	return _event_log[_event_log.size() - 1].duplicate()


func log_capacity() -> int:
	return _log_capacity


# --- Serialization -----------------------------------------------------------

## Serialize the whole persistent tier, deterministically (every collection in sorted/queue
## order), using the key names `docs/DATA_SCHEMA.md` already reserves for the `world_sim`
## block (`world_clock`, `pending_transitions`, `rng_seed`) so the documented shape and the
## real one cannot drift apart (L-014).
func to_dict() -> Dictionary:
	var actors := {}
	for instance_id in actor_ids_sorted():
		var actor: WorldSimActor = _actors[String(instance_id)]
		actors[String(instance_id)] = actor.to_dict()
	return {
		"schema": SCHEMA_VERSION,
		"world_clock": _clock.to_dict(),
		"rng_seed": _rng.world_seed(),
		"rng_streams": _rng.to_dict()["streams"],
		"pending_transitions": pending_events(),
		"carry_over_ticks": _carry_over_ticks,
		"actors": actors,
		"event_log": event_log(),
		"event_log_capacity": _log_capacity,
	}


## Hydrate the whole tier, STRICTLY typed and ATOMIC: everything is staged into locals and the
## receiver is written only once every part validated, so a rejected payload leaves the
## simulation byte-identical (B20: no partial hydrate). Returns false (loud) otherwise.
func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[worldsim] state from_dict: payload is not a Dictionary")
		return false
	var dict: Dictionary = data

	if not _check_int(dict, "schema", SCHEMA_VERSION):
		return false
	var in_schema: int = dict.get("schema", SCHEMA_VERSION)
	if in_schema != SCHEMA_VERSION:
		push_error(("[worldsim] state from_dict: schema %d is not %d; a migration is required "
			+ "and this phase ships none, so the payload is REFUSED rather than guessed at")
			% [in_schema, SCHEMA_VERSION])
		return false

	# Clock + RNG are hydrated into FRESH objects: hydrating the live ones in place would
	# leave a half-restored clock behind if the RNG payload turned out to be malformed.
	var staged_clock := WorldClock.new(
		_clock.ticks_per_hour(), _clock.hours_per_day(),
		_clock.days_per_season(), _clock.seasons_per_year())
	if not staged_clock.from_dict(dict.get("world_clock", null)):
		push_error("[worldsim] state from_dict: malformed world_clock")
		return false

	if not _check_int(dict, "rng_seed", 0):
		return false
	var staged_rng := RngService.new(int(dict.get("rng_seed", 0)))
	if not staged_rng.is_valid():
		push_error("[worldsim] state from_dict: rng_seed is not a usable world seed")
		return false
	if not staged_rng.from_dict({
			"world_seed": int(dict.get("rng_seed", 0)),
			"streams": dict.get("rng_streams", {}),
	}):
		push_error("[worldsim] state from_dict: malformed rng_streams")
		return false

	if not _check_int(dict, "carry_over_ticks", 0):
		return false
	var in_carry: int = dict.get("carry_over_ticks", 0)
	if in_carry < 0:
		push_error("[worldsim] state from_dict: carry_over_ticks must be >= 0 (got %d)"
			% in_carry)
		return false

	if not _check_int(dict, "event_log_capacity", _log_capacity):
		return false
	var in_capacity: int = dict.get("event_log_capacity", _log_capacity)
	if in_capacity < 0:
		push_error("[worldsim] state from_dict: event_log_capacity must be >= 0 (got %d)"
			% in_capacity)
		return false

	var staged_actors: Variant = _parse_actors(dict.get("actors", {}))
	if staged_actors == null:
		return false
	var staged_pending: Variant = _parse_pending(
		dict.get("pending_transitions", []), staged_clock.tick())
	if staged_pending == null:
		return false
	var staged_log: Variant = _parse_log(dict.get("event_log", []))
	if staged_log == null:
		return false

	# Commit — no validation below this line.
	_clock = staged_clock
	_rng = staged_rng
	_actors = staged_actors
	_pending = staged_pending as Array[Dictionary]
	_carry_over_ticks = in_carry
	_log_capacity = in_capacity
	_event_log = staged_log as Array[Dictionary]
	_sort_pending()
	_rebuild_observed_index()
	return true


## Rebuild the observed-actor index from the actors' own bands. The index is DERIVED, so a
## hydrate must regenerate it rather than serialize it — a serialized index could disagree with
## the bands it indexes, which is the one failure a derived structure should be incapable of.
func _rebuild_observed_index() -> void:
	_observed.clear()
	for key in _actors:
		if (_actors[key] as WorldSimActor).is_observed():
			_observed[String(key)] = true


## `{ id -> WorldSimActor }` or null (loud) on any malformed row.
func _parse_actors(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		push_error("[worldsim] state from_dict: 'actors' is not a Dictionary")
		return null
	var staged := {}
	var keys: Array = (value as Dictionary).keys()
	keys.sort()
	for key in keys:
		var key_type := typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME:
			push_error("[worldsim] state from_dict: actor key must be a String/StringName "
				+ "(got %s)" % type_string(key_type))
			return null
		var actor := WorldSimActor.new()
		if not actor.from_dict((value as Dictionary)[key]):
			push_error("[worldsim] state from_dict: actor row '%s' is malformed" % String(key))
			return null
		if String(actor.instance_id) != String(key):
			push_error("[worldsim] state from_dict: actor key '%s' disagrees with its row's "
				% String(key) + "instance_id '%s'" % actor.instance_id)
			return null
		staged[String(key)] = actor
	return staged


## The pending queue, or null (loud) on a malformed entry.
##
## An entry due at or before the RESTORED tick is rejected rather than silently fired or
## dropped: the queue is supposed to hold the FUTURE, so a past due tick means the snapshot was
## taken inconsistently, and both ways of papering over it (fire it late, or forget it) change
## the world relative to the save it came from.
func _parse_pending(value: Variant, restored_tick: int) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		push_error("[worldsim] state from_dict: 'pending_transitions' is not an Array")
		return null
	var staged: Array[Dictionary] = []
	var seen := {}
	for item in (value as Array):
		if typeof(item) != TYPE_DICTIONARY:
			push_error("[worldsim] state from_dict: a pending entry is not a Dictionary")
			return null
		var entry: Dictionary = item
		var id_value: Variant = entry.get("event_id", "")
		var id_type := typeof(id_value)
		if id_type != TYPE_STRING and id_type != TYPE_STRING_NAME:
			push_error("[worldsim] state from_dict: pending event_id must be a "
				+ "String/StringName (got %s)" % type_string(id_type))
			return null
		var event_id := String(id_value)
		if event_id == "":
			push_error("[worldsim] state from_dict: pending entry has an empty event_id")
			return null
		if seen.has(event_id):
			push_error("[worldsim] state from_dict: '%s' is queued twice" % event_id)
			return null
		var due_value: Variant = entry.get("due_tick", 0)
		if typeof(due_value) != TYPE_INT:
			push_error("[worldsim] state from_dict: pending '%s' due_tick must be an int "
				% event_id + "(got %s)" % type_string(typeof(due_value)))
			return null
		var due: int = due_value
		if due <= restored_tick:
			push_error(("[worldsim] state from_dict: pending '%s' is due at tick %d but the "
				+ "clock restored to %d; the queue holds the FUTURE, so this snapshot is "
				+ "inconsistent and is REFUSED (firing it late or dropping it would both "
				+ "change the world relative to the save)")
				% [event_id, due, restored_tick])
			return null
		seen[event_id] = true
		staged.append({"due_tick": due, "event_id": event_id})
	return staged


## The event log, or null (loud) if it is not an array of dictionaries. Entry CONTENTS are not
## validated field by field: the log is a presentation feed, not an input to any future tick,
## so a malformed entry can at worst render oddly — and rejecting a whole world because a
## historical readout is odd would be the wrong trade. The structure is still checked, because
## a non-dictionary would crash the renderer.
func _parse_log(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		push_error("[worldsim] state from_dict: 'event_log' is not an Array")
		return null
	var staged: Array[Dictionary] = []
	for item in (value as Array):
		if typeof(item) != TYPE_DICTIONARY:
			push_error("[worldsim] state from_dict: an event_log entry is not a Dictionary")
			return null
		staged.append((item as Dictionary).duplicate())
	return staged


## True when `field` is absent or an int; reports loudly and returns false on a wrong type.
static func _check_int(dict: Dictionary, field: String, _fallback: int) -> bool:
	if not dict.has(field):
		return true
	if typeof(dict[field]) != TYPE_INT:
		push_error("[worldsim] state from_dict: '%s' must be an int (got %s)"
			% [field, type_string(typeof(dict[field]))])
		return false
	return true

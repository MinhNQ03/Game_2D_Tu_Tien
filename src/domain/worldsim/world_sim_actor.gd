extends RefCounted
class_name WorldSimActor
## WorldSimActor — Aetheria domain (the SIMULATION tier of one background character).
##
## Not a character. The character is a `CharacterState` in the `CharacterRegistry`; this is the
## simulation's own record about them — which LOD band they are in, where they are, which
## routine they keep, and when they entered the world. `docs/CHARACTER_SYSTEM.md` §5 reserves
## `CharacterState.sim_state` for exactly this ("where/what when off-screen"), and the
## simulation keeps that field as a DERIVED CACHE of this record, in the same relationship the
## sect roster has with `CharacterState.sect_id` (D-015): one authority, one cache, the
## authority wins on disagreement.
##
## THE ONE DESIGN DECISION THAT MATTERS HERE: **activity is DERIVED, not advanced.**
##
## `activity` is a pure function of `(world_tick - joined_tick, schedule)`. The alternative —
## stepping a phase index forward each tick — looks equivalent and is not, because it makes an
## actor's state depend on HOW OFTEN it was stepped. Under LOD that is fatal: a FAR actor is
## not stepped every tick (that is the entire cost saving), so a stepped actor would fall
## behind, and promoting it to NEAR would then either lose time or require a catch-up loop
## whose result depended on the band history. With a derived activity:
##   * NEAR, MID and FAR actors compute the SAME answer from the same clock,
##   * promotion/demotion cannot lose or invent state (`docs/WORLD_SIMULATION.md` §4),
##   * the band controls only how often we LOOK, never what we see.
## So `_activity` below is a cache of that function, refreshed when the simulation looks, and
## `recompute_activity()` reports whether the cached answer changed — which is the only reason
## it is stored at all (detecting a transition requires remembering the previous answer).

## LOD band (`docs/WORLD_SIMULATION.md` §2). Derived from the actor's location relative to the
## player's, never authored as a fixed property: a band is a RELATIONSHIP to the player, so
## storing it as content would mean an actor that is "nearby" even when the player is a
## continent away.
##
## NEAR is the band in which a later phase instantiates a `CharacterEntity`
## (`CHARACTER_SYSTEM.md` §6). Phase 08 instantiates NOTHING in any band — it only marks the
## band, so the "Far has no entity nodes" guarantee currently holds for every band and the
## tests assert the node count directly rather than trusting the comment.
enum Band { NEAR, MID, FAR }

## Localization keys for the bands, index-aligned with `Band`.
const BAND_NAME_KEYS := [
	&"WORLDSIM_BAND_NEAR", &"WORLDSIM_BAND_MID", &"WORLDSIM_BAND_FAR",
]

## The character this record is about (`CharacterState.instance_id`). Identical to the
## authoring `WorldSimActorData.id` — one identity, see that class's note.
var instance_id: StringName = &""

## The routine being kept (`WorldSimScheduleData.id`). The schedule RESOURCE is not held here:
## domain state stays plain data so it serializes and so a save never points at a `.tres` that
## content may have renamed. The service resolves the id against the catalog.
var schedule_id: StringName = &""

## Where the actor currently is (`MapData.id`). Phase 08 never moves an actor between maps —
## a routine is kept at home — so this equals the authored `home_map_id` for now. It is stored
## rather than re-read from content because MOVEMENT is the obvious next step (a MISSION that
## actually goes somewhere), and when it arrives the location must already be per-save state.
var location_map_id: StringName = &""

## The tick at which this actor entered the world. The origin for the derived activity, and the
## reason an actor added mid-run does not inherit the routine position of one present since
## tick 0.
var joined_tick: int = 0

var _band: int = Band.FAR
var _activity: int = WorldSimScheduleData.Activity.RESTING


## Build a record for an actor entering the world at `tick`.
static func create(
		new_instance_id: StringName,
		new_schedule_id: StringName,
		new_location_map_id: StringName,
		tick: int) -> WorldSimActor:
	if new_instance_id == &"":
		push_error("[worldsim] actor record requires a non-empty instance_id")
		return null
	if new_schedule_id == &"":
		push_error("[worldsim] actor '%s' requires a schedule id" % new_instance_id)
		return null
	if tick < 0:
		push_error("[worldsim] actor '%s' cannot join at a negative tick (%d)"
			% [new_instance_id, tick])
		return null
	var actor := WorldSimActor.new()
	actor.instance_id = new_instance_id
	actor.schedule_id = new_schedule_id
	actor.location_map_id = new_location_map_id
	actor.joined_tick = tick
	return actor


# --- Band (set by the service from the player's location) --------------------

func band() -> int:
	return _band


## True for the bands the simulation inspects every tick. FAR actors are computed on demand
## instead, which is where the LOD cost saving actually comes from: per-tick work is
## proportional to the NEAR+MID population plus the due events, not to the whole cast
## (`docs/WORLD_SIMULATION.md` §6, `05-performance-testing.md`).
func is_observed() -> bool:
	return _band == Band.NEAR or _band == Band.MID


## Set the band. Returns true if it CHANGED (so the caller can emit a promotion/demotion
## event without re-deriving it). Rejects an unknown ordinal loudly and leaves the band alone.
##
## Changing the band deliberately touches NOTHING else — not the activity, not the schedule,
## not `joined_tick`. That is the promotion/demotion contract, and it is cheap to honour only
## because the activity is derived (see the class note).
func set_band(new_band: int) -> bool:
	if new_band < 0 or new_band >= Band.size():
		push_error("[worldsim] actor '%s': %d is not a known Band ordinal"
			% [instance_id, new_band])
		return false
	if _band == new_band:
		return false
	_band = new_band
	return true


# --- Activity (derived; see the class note) ---------------------------------

func activity() -> int:
	return _activity


## How far into its routine the actor is at `world_tick`.
func elapsed_at(world_tick: int) -> int:
	return maxi(0, world_tick - joined_tick)


## Refresh the cached activity from `schedule` at `world_tick`. Returns true if the activity
## CHANGED, which is how the service decides whether to emit `actor_state_changed`.
##
## Idempotent and order-independent: calling it twice at the same tick reports a change at most
## once, and calling it at tick 500 without ever calling it at ticks 1..499 gives the SAME
## answer as having called it every tick. That second property is what lets a FAR actor skip
## 499 ticks of work and still be correct the moment anyone looks.
func recompute_activity(schedule: WorldSimScheduleData, world_tick: int) -> bool:
	if schedule == null:
		push_error("[worldsim] actor '%s': no schedule to compute an activity from"
			% instance_id)
		return false
	var next := schedule.activity_at(elapsed_at(world_tick))
	if next == _activity:
		return false
	_activity = next
	return true


# --- The `CharacterState.sim_state` derived cache (D-015 shape) -------------

## The compact snapshot the simulation writes into `CharacterState.sim_state`.
##
## Deliberately a SUBSET: the band and the activity are what another system would ever want to
## read off a character ("is this elder reachable, and what are they doing"), while
## `joined_tick` and `schedule_id` are simulation bookkeeping that nothing outside here should
## be reading off a character. A smaller cache is a smaller surface to drift.
func sim_state_cache() -> Dictionary:
	return {
		"band": _band,
		"activity": _activity,
		"location_map_id": String(location_map_id),
	}


## True when `cache` matches what this record would write. Used by the service's
## post-condition check, so a drifted cache is REPORTED rather than silently trusted — the
## same discipline `SectService.verify_character_cache()` applies to membership.
## The comparison is EXACT, including the key count. The simulation owns the whole `sim_state`
## field, so an extra key is drift too — somebody writing to a field they do not own — and a
## subset check would silently accept it. That is the difference between "the values I care
## about agree" and "this cache is mine and untouched", and only the second is a useful answer.
func matches_sim_state_cache(cache: Dictionary) -> bool:
	var expected := sim_state_cache()
	if cache.size() != expected.size():
		return false
	for key in expected:
		if not cache.has(key) or cache[key] != expected[key]:
			return false
	return true


# --- Serialization -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"schedule_id": String(schedule_id),
		"location_map_id": String(location_map_id),
		"joined_tick": joined_tick,
		"band": _band,
		"activity": _activity,
	}


## Hydrate, STRICTLY typed and fail-closed; the receiver is unchanged on rejection (L-024).
func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[worldsim] actor from_dict: payload is not a Dictionary")
		return false
	var dict: Dictionary = data

	var in_instance_id := _parse_id(dict, "instance_id")
	if in_instance_id == &"":
		return false
	var in_schedule_id := _parse_id(dict, "schedule_id")
	if in_schedule_id == &"":
		return false
	# A location is allowed to be empty (an actor not placed on the map graph yet), so it is
	# type-checked without the non-empty requirement the two ids above carry.
	if dict.has("location_map_id") and not _is_id_token(dict["location_map_id"]):
		push_error("[worldsim] actor from_dict '%s': location_map_id must be a "
			% in_instance_id + "String/StringName (got %s)"
			% type_string(typeof(dict["location_map_id"])))
		return false

	var in_joined := _parse_int(dict, "joined_tick", in_instance_id)
	if in_joined < 0:
		return false
	var in_band := _parse_int(dict, "band", in_instance_id)
	if in_band < 0 or in_band >= Band.size():
		push_error("[worldsim] actor from_dict '%s': band %d is not a known Band ordinal"
			% [in_instance_id, in_band])
		return false
	var in_activity := _parse_int(dict, "activity", in_instance_id)
	if in_activity < 0 or in_activity >= WorldSimScheduleData.Activity.size():
		push_error("[worldsim] actor from_dict '%s': activity %d is not a known Activity "
			% [in_instance_id, in_activity] + "ordinal")
		return false

	instance_id = in_instance_id
	schedule_id = in_schedule_id
	location_map_id = StringName(String(dict.get("location_map_id", "")))
	joined_tick = in_joined
	_band = in_band
	_activity = in_activity
	return true


## The localization key for `band`, or the FAR key (loud) for an unknown ordinal.
static func band_name_key(band_ordinal: int) -> StringName:
	if band_ordinal < 0 or band_ordinal >= BAND_NAME_KEYS.size():
		push_error("[worldsim] no name key for band ordinal %d" % band_ordinal)
		return BAND_NAME_KEYS[Band.FAR]
	return BAND_NAME_KEYS[band_ordinal]


# --- Parsing helpers (strict; reject rather than coerce) --------------------

## A required, non-empty id field. Returns `&""` (loud) on a wrong type or an empty value.
static func _parse_id(dict: Dictionary, field: String) -> StringName:
	var value: Variant = dict.get(field, "")
	if not _is_id_token(value):
		push_error("[worldsim] actor from_dict: '%s' must be a String/StringName (got %s)"
			% [field, type_string(typeof(value))])
		return &""
	var text := String(value)
	if text == "":
		push_error("[worldsim] actor from_dict: '%s' must not be empty" % field)
		return &""
	return StringName(text)


## A required int field. Returns -1 (loud) on a wrong type, which every caller treats as a
## rejection — every int this class stores is legitimately >= 0.
static func _parse_int(dict: Dictionary, field: String, who: StringName) -> int:
	var value: Variant = dict.get(field, 0)
	if typeof(value) != TYPE_INT:
		push_error("[worldsim] actor from_dict '%s': '%s' must be an int (got %s)"
			% [who, field, type_string(typeof(value))])
		return -1
	return value


static func _is_id_token(value: Variant) -> bool:
	var t := typeof(value)
	return t == TYPE_STRING or t == TYPE_STRING_NAME

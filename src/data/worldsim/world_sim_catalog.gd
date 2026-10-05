extends Resource
class_name WorldSimCatalog
## WorldSimCatalog — Aetheria data (the whole authored world simulation + its tuning).
##
## One resource carries the calendar, the tick costs, the catch-up budget, the cast and the
## scheduled events, plus the cross-entry checks no single entry can perform (unique ids,
## every actor's schedule present, every event's magnitude sane). Adding an actor, a routine
## or a world event is editing this plus one new `.tres`.
##
## WHY THE TUNING LIVES HERE RATHER THAN IN A SEPARATE CONFIG RESOURCE. Every number below is
## meaningless without the others: a `catch_up_budget_ticks` of 64 means something completely
## different at 4 ticks-per-hour than at 60, and `ticks_per_map_transition` only makes sense
## against the same calendar the schedules are authored in. Splitting them into two files would
## let a save-breaking mismatch exist in a state where each file was individually valid —
## exactly the class of drift L-014 records. They are one decision, so they are one resource.
##
## NO RNG SEED IS AUTHORED HERE. The world seed belongs to a RUN, not to content: two players
## must get different worlds from the same catalog. The seed is supplied per session
## (`WorldSimulationRuntime.start_session`), derived from the run id so a given run always
## reproduces, and persisted with the simulation (`docs/SAVE_FORMAT.md` §3b).

# --- Calendar (see `WorldClock`; `WORLD_BIBLE.md` freezes no calendar) -------

@export var ticks_per_hour: int = 1
@export var hours_per_day: int = 12
@export var days_per_season: int = 30
@export var seasons_per_year: int = 4

# --- Advancement (explicit beats only — see `WorldSimulationRuntime`) --------

## Ticks the world advances when the player arrives in a map.
##
## This is the ONLY beat wired in Phase 08, because it is the only gameplay beat that exists
## yet (hub ↔ field is the whole loop). It is authored rather than hard-coded so the owner can
## retune how fast the world moves relative to play without touching code, and so later phases
## can add their own beats (a rest, a breakthrough, a chapter transition) as data beside it
## rather than by editing the simulation.
@export var ticks_per_map_transition: int = 6

## Ticks the world advances the moment a session begins, so a brand-new world is not frozen at
## tick 0 with nothing scheduled having happened. Must be >= 0; 0 means "the world starts
## exactly as authored".
@export var ticks_on_session_start: int = 0

# --- Catch-up (bounded; `docs/WORLD_SIMULATION.md` §5, B15) ------------------

## The most ticks one `advance_ticks()` call will process. Anything beyond it becomes
## CARRY-OVER and is processed on the following calls — deterministically, in order, never
## dropped. This is the load-time spike cap §5 asks for: returning to a world after a long
## absence must not stall on a thousand ticks in one frame.
@export var catch_up_budget_ticks: int = 64

# --- Content ----------------------------------------------------------------

@export var schedules: Array[WorldSimScheduleData] = []
@export var actors: Array[WorldSimActorData] = []
@export var events: Array[WorldSimEventData] = []

## How many past world events the simulation keeps for the player-facing feed. Bounded for the
## same reason `RelationshipConfigData.history_capacity` is: an unbounded log grows forever
## inside the save file.
@export var event_log_capacity: int = 16


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	_validate_calendar(errors)
	_validate_budgets(errors)
	_validate_schedules(errors)
	_validate_actors(errors)
	_validate_events(errors)
	return errors


func _validate_calendar(errors: Array[String]) -> void:
	for pair in [
		["ticks_per_hour", ticks_per_hour], ["hours_per_day", hours_per_day],
		["days_per_season", days_per_season], ["seasons_per_year", seasons_per_year],
	]:
		var field := String((pair as Array)[0])
		var value := int((pair as Array)[1])
		if value < WorldClock.MIN_UNIT:
			errors.append("%s must be >= %d (got %d)" % [field, WorldClock.MIN_UNIT, value])


func _validate_budgets(errors: Array[String]) -> void:
	if ticks_per_map_transition <= 0:
		errors.append("ticks_per_map_transition must be > 0 (got %d): a beat that advances "
			% ticks_per_map_transition + "nothing is a world that never moves")
	if ticks_on_session_start < 0:
		errors.append("ticks_on_session_start must be >= 0 (got %d)" % ticks_on_session_start)
	if catch_up_budget_ticks <= 0:
		errors.append("catch_up_budget_ticks must be > 0 (got %d): a zero budget could never "
			% catch_up_budget_ticks + "drain the carry-over queue, so the world would stall "
			+ "forever instead of catching up")
	if event_log_capacity < 0:
		errors.append("event_log_capacity must be >= 0 (got %d)" % event_log_capacity)


func _validate_schedules(errors: Array[String]) -> void:
	var seen := {}
	for i in schedules.size():
		var schedule := schedules[i]
		if schedule == null:
			errors.append("schedules[%d] is null" % i)
			continue
		if not schedule.is_valid():
			errors.append("schedules[%d] ('%s') invalid: %s"
				% [i, schedule.id, str(schedule.validation_errors())])
			continue
		var key := String(schedule.id)
		if seen.has(key):
			errors.append("duplicate schedule id '%s'" % key)
			continue
		seen[key] = true


## Actors must be unique, valid, and reference a schedule that is actually IN this catalog.
##
## That last check is the one worth having: `WorldSimActorData.schedule` is a direct resource
## reference, so an actor whose schedule is not listed here would still work at runtime — and
## would then be invisible to every catalog-level query, including the localization drift guard
## that checks each schedule's activity keys exist in both languages. A reference the catalog
## cannot see is a reference nothing can audit.
func _validate_actors(errors: Array[String]) -> void:
	var listed_schedules := {}
	for schedule in schedules:
		if schedule != null:
			listed_schedules[String(schedule.id)] = true
	var seen := {}
	for i in actors.size():
		var actor := actors[i]
		if actor == null:
			errors.append("actors[%d] is null" % i)
			continue
		if not actor.is_valid():
			errors.append("actors[%d] ('%s') invalid: %s"
				% [i, actor.id, str(actor.validation_errors())])
			continue
		var key := String(actor.id)
		if seen.has(key):
			errors.append("duplicate actor id '%s'" % key)
			continue
		seen[key] = true
		if not listed_schedules.has(String(actor.schedule.id)):
			errors.append(("actor '%s' uses schedule '%s', which is not listed in this "
				+ "catalog; an unlisted schedule cannot be audited (localization keys, "
				+ "cycle length) by any catalog-level check")
				% [key, actor.schedule.id])


func _validate_events(errors: Array[String]) -> void:
	var seen := {}
	for i in events.size():
		var event := events[i]
		if event == null:
			errors.append("events[%d] is null" % i)
			continue
		if not event.is_valid():
			errors.append("events[%d] ('%s') invalid: %s"
				% [i, event.id, str(event.validation_errors())])
			continue
		var key := String(event.id)
		if seen.has(key):
			errors.append("duplicate event id '%s' (the id is also the scheduling key)" % key)
			continue
		seen[key] = true


# --- Cross-catalog checks (performed where both catalogs exist) --------------

## Every actor's `home_map_id` must name a real map. Returns the violations (empty == ok).
##
## This cannot live in `validation_errors()`: the map catalog is not visible from here, and
## guessing would mean either skipping the check or hard-coding map ids into the simulation.
## `WorldSimulationRuntime` is the first place both catalogs exist, so it calls this and fails
## the session — an actor living in a map that does not exist would silently be permanently
## FAR, i.e. a character the player could never meet.
func validation_errors_against_maps(known_map_ids: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for actor in actors:
		if actor == null:
			continue
		if not known_map_ids.has(actor.home_map_id):
			errors.append(("actor '%s' lives in map '%s', which is not in the map catalog; "
				+ "it would be permanently FAR — a character the player could never meet")
				% [actor.id, actor.home_map_id])
	return errors


# --- Lookups (deterministic) -------------------------------------------------

func find_schedule(schedule_id: StringName) -> WorldSimScheduleData:
	for schedule in schedules:
		if schedule != null and schedule.id == schedule_id:
			return schedule
	return null


func find_actor(actor_id: StringName) -> WorldSimActorData:
	for actor in actors:
		if actor != null and actor.id == actor_id:
			return actor
	return null


func find_event(event_id: StringName) -> WorldSimEventData:
	for event in events:
		if event != null and event.id == event_id:
			return event
	return null


## Every actor, in id order — so the cast is built in a deterministic sequence whatever order
## the resource happens to list them in. Ordering matters here beyond tidiness: the actors are
## enrolled into sects/factions in this order, and faction influence is read back by tests.
func actors_sorted() -> Array[WorldSimActorData]:
	var out: Array[WorldSimActorData] = []
	for actor in actors:
		if actor != null:
			out.append(actor)
	out.sort_custom(func(a: WorldSimActorData, b: WorldSimActorData) -> bool:
		return String(a.id) < String(b.id))
	return out


## Every event, in id order (the same determinism argument as `actors_sorted`).
func events_sorted() -> Array[WorldSimEventData]:
	var out: Array[WorldSimEventData] = []
	for event in events:
		if event != null:
			out.append(event)
	out.sort_custom(func(a: WorldSimEventData, b: WorldSimEventData) -> bool:
		return String(a.id) < String(b.id))
	return out

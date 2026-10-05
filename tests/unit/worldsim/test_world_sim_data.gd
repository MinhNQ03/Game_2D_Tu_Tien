extends TestCase
## Unit tests for the authored World Simulation DATA (Phase 08): schedules, actors, events,
## the catalog's cross-entry integrity, and a drift guard over the content that actually ships.
##
## Every `@export` touched here is TYPED, and a typed property will not accept an untyped
## value — the resulting VM error ABORTS the assigning method, which the runner then reports as
## PASS because it only counts recorded assertion failures (L-026). So every fixture builds a
## TYPED LOCAL and assigns that, every helper returns the CONCRETE class, and each negative
## case differs from a KNOWN-GOOD fixture in exactly one field (L-024).

const ScheduleScript := preload("res://src/data/worldsim/world_sim_schedule_data.gd")
const ActorScript := preload("res://src/data/worldsim/world_sim_actor_data.gd")
const EventScript := preload("res://src/data/worldsim/world_sim_event_data.gd")
const CatalogScript := preload("res://src/data/worldsim/world_sim_catalog.gd")
const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

## The content the game actually ships, for the drift guards at the end.
const AUTHORED_CATALOG_PATH := "res://data/worldsim/world_sim_catalog.tres"
const AUTHORED_MAP_CATALOG_PATH := "res://data/maps/map_catalog.tres"
const AUTHORED_SECT_CATALOG_PATH := "res://data/sects/sect_catalog.tres"
const AUTHORED_FACTION_CATALOG_PATH := "res://data/factions/faction_catalog.tres"


# --- typed fixtures ----------------------------------------------------------

## A valid 12-tick routine: 8 ticks TRAINING then 4 RESTING.
func _schedule(sid: StringName = &"schedule_x") -> WorldSimScheduleData:
	var phases: Array[Dictionary] = [
		{"activity": ScheduleScript.Activity.TRAINING, "ticks": 8},
		{"activity": ScheduleScript.Activity.RESTING, "ticks": 4},
	]
	var s: WorldSimScheduleData = ScheduleScript.new()
	s.id = sid
	s.phases = phases
	return s


func _character(cid: StringName) -> CharacterTemplateData:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var t: CharacterTemplateData = CharacterTemplateScript.new()
	t.id = cid
	t.name_key = &"NAME"
	t.base_stats = stats
	return t


func _actor(aid: StringName = &"actor_x") -> WorldSimActorData:
	var a: WorldSimActorData = ActorScript.new()
	a.id = aid
	a.character_template = _character(&"char_x")
	a.schedule = _schedule()
	a.home_map_id = &"map_hub"
	a.sect_id = &"sect_a"
	a.sect_rank_id = &"rank_outer"
	return a


func _event(eid: StringName = &"wevent_x") -> WorldSimEventData:
	var e: WorldSimEventData = EventScript.new()
	e.id = eid
	e.kind = EventScript.Kind.SECT_INFLUENCE
	e.target_id = &"sect_a"
	e.first_tick = 4
	e.period_ticks = 12
	e.magnitude_min = -2
	e.magnitude_max = 3
	return e


func _catalog() -> WorldSimCatalog:
	var schedules: Array[WorldSimScheduleData] = [_schedule()]
	var actor := _actor()
	actor.schedule = schedules[0]
	var actors: Array[WorldSimActorData] = [actor]
	var events: Array[WorldSimEventData] = [_event()]
	var c: WorldSimCatalog = CatalogScript.new()
	c.ticks_per_hour = 1
	c.hours_per_day = 12
	c.days_per_season = 30
	c.seasons_per_year = 4
	c.ticks_per_map_transition = 6
	c.ticks_on_session_start = 0
	c.catch_up_budget_ticks = 64
	c.event_log_capacity = 8
	c.schedules = schedules
	c.actors = actors
	c.events = events
	return c


# === 1-4. Schedules =========================================================

func test_01_a_well_formed_schedule_validates() -> void:
	var s := _schedule()
	assert_true(s.is_valid(), "a well-formed routine validates: %s" % str(s.validation_errors()))
	assert_eq(s.phases.size(), 2, "the fixture actually carries its phases")
	assert_eq(s.cycle_ticks(), 12, "the cycle is the sum of the phase lengths")


func test_02_schedule_invariants() -> void:
	var s := _schedule()
	s.id = &""
	assert_false(s.is_valid(), "an empty id invalidates")

	s = _schedule()
	s.phases = [] as Array[Dictionary]
	assert_false(s.is_valid(), "a routine with no phase has no activity to report")

	s = _schedule()
	s.phases = [{"activity": 0, "ticks": 0}] as Array[Dictionary]
	assert_false(s.is_valid(), "a zero-tick phase can never be observed")

	s = _schedule()
	s.phases = [{"activity": 0, "ticks": -3}] as Array[Dictionary]
	assert_false(s.is_valid(), "a negative-tick phase invalidates")

	s = _schedule()
	s.phases = [{"activity": 99, "ticks": 4}] as Array[Dictionary]
	assert_false(s.is_valid(), "an out-of-range activity invalidates (closed vocabulary)")

	s = _schedule()
	s.phases = [{"activity": 0, "ticks": "4"}] as Array[Dictionary]
	assert_false(s.is_valid(), "a string tick count is rejected, never coerced")

	s = _schedule()
	s.phases = [{"ticks": 4}] as Array[Dictionary]
	assert_false(s.is_valid(), "a phase with no activity invalidates")

	s = _schedule()
	s.phases = [{"activity": 0}] as Array[Dictionary]
	assert_false(s.is_valid(), "a phase with no tick count invalidates")


## THE PROPERTY THE WHOLE LOD DESIGN RESTS ON: the activity is a PURE FUNCTION of elapsed
## ticks. If it were not, a FAR actor (which is not stepped every tick) would drift from a
## NEAR one and promotion would silently change state.
func test_03_activity_is_a_pure_function_of_elapsed_ticks() -> void:
	var s := _schedule()
	# 0..7 TRAINING, 8..11 RESTING, then it repeats.
	for elapsed in [0, 1, 7, 12, 13, 19, 24]:
		var expected := ScheduleScript.Activity.TRAINING if (int(elapsed) % 12) < 8 \
			else ScheduleScript.Activity.RESTING
		assert_eq(s.activity_at(int(elapsed)), expected,
			"elapsed %d resolves to the authored phase" % int(elapsed))
	assert_eq(s.activity_at(8), ScheduleScript.Activity.RESTING, "the boundary tick flips")
	assert_eq(s.activity_at(11), ScheduleScript.Activity.RESTING, "the last tick of the phase")
	# A full cycle returns to the start — a single-sample assertion would pass for a routine
	# that never advanced at all, so the wrap is asserted explicitly (the L-029 lesson).
	assert_eq(s.activity_at(12), s.activity_at(0), "a full cycle returns to the start")
	assert_eq(s.activity_at(120), s.activity_at(0), "and ten cycles later, still")
	# Calling it twice must agree (no hidden state).
	assert_eq(s.activity_at(5), s.activity_at(5), "the function is stable across calls")
	# A negative elapsed is clamped to the start rather than wrapping to somewhere plausible.
	assert_eq(s.activity_at(-5), s.activity_at(0), "a negative elapsed clamps to the start")


func test_04_every_activity_has_a_localization_key() -> void:
	assert_eq(ScheduleScript.ACTIVITY_NAME_KEYS.size(), ScheduleScript.Activity.size(),
		"the key table covers the whole closed vocabulary (so adding an activity forces a key)")
	for ordinal in ScheduleScript.Activity.size():
		var key := ScheduleScript.activity_name_key(int(ordinal))
		assert_ne(key, &"", "activity %d has a key" % int(ordinal))


# === 5-6. Actors ============================================================

func test_05_a_well_formed_actor_validates() -> void:
	var a := _actor()
	assert_true(a.is_valid(), "a well-formed actor validates: %s" % str(a.validation_errors()))


func test_06_actor_invariants() -> void:
	var a := _actor()
	a.id = &""
	assert_false(a.is_valid(), "an empty id invalidates")

	a = _actor()
	a.character_template = null
	assert_false(a.is_valid(), "an actor with no character is simulation with nobody in it")

	a = _actor()
	a.schedule = null
	assert_false(a.is_valid(), "an actor with no routine has no activity at any band")

	a = _actor()
	a.home_map_id = &""
	assert_false(a.is_valid(), "no home map means no LOD band could be computed")

	# The sect/rank pairing: both or neither.
	a = _actor()
	a.sect_rank_id = &""
	assert_false(a.is_valid(), "a sect with no rank cannot be joined")

	a = _actor()
	a.sect_id = &""
	assert_false(a.is_valid(), "a rank with no sect has nowhere to apply")

	# A faction requires a sect, because a faction is internal to one (D-015).
	a = _actor()
	a.sect_id = &""
	a.sect_rank_id = &""
	a.faction_id = &"faction_a"
	assert_false(a.is_valid(), "a faction seat with no sect membership invalidates")

	# Neither sect nor faction is legitimate: an unaffiliated wanderer.
	a = _actor()
	a.sect_id = &""
	a.sect_rank_id = &""
	assert_true(a.is_valid(), "an unaffiliated actor is valid (most of the world has no sect)")

	# An invalid nested resource invalidates the actor rather than being skipped.
	a = _actor()
	a.schedule = _schedule()
	a.schedule.phases = [] as Array[Dictionary]
	assert_false(a.is_valid(), "an invalid nested schedule invalidates the actor")


# === 7-9. Events ============================================================

func test_07_a_well_formed_event_validates() -> void:
	var e := _event()
	assert_true(e.is_valid(), "a well-formed event validates: %s" % str(e.validation_errors()))
	assert_true(e.is_recurring(), "a positive period makes it recurring")
	e.period_ticks = 0
	assert_true(e.is_valid(), "a one-shot event is valid")
	assert_false(e.is_recurring(), "and is not recurring")


func test_08_event_invariants() -> void:
	var e := _event()
	e.id = &""
	assert_false(e.is_valid(), "an empty id invalidates (the id is the scheduling key)")

	e = _event()
	e.target_id = &""
	assert_false(e.is_valid(), "an event with no subject invalidates")

	e = _event()
	e.kind = 99
	assert_false(e.is_valid(), "an out-of-range kind invalidates (closed vocabulary)")

	e = _event()
	e.first_tick = 0
	assert_false(e.is_valid(),
		"an event due at tick 0 would fire before the world had advanced at all")

	e = _event()
	e.period_ticks = -1
	assert_false(e.is_valid(), "a negative period invalidates")

	e = _event()
	e.magnitude_min = 5
	e.magnitude_max = 1
	assert_false(e.is_valid(), "an inverted magnitude range invalidates")

	# An event that can only ever apply 0 is cost without content (`SOCIAL_DESIGN.md` §7).
	e = _event()
	e.magnitude_min = 0
	e.magnitude_max = 0
	assert_false(e.is_valid(), "a magnitude range of [0,0] can never be felt")


## The kind-specific fields must be required where they are meaningful and REFUSED where they
## are not. An influence event carrying a `dimension` would look authored and do nothing.
func test_09_event_fields_are_gated_by_kind() -> void:
	var rel := _event()
	rel.kind = EventScript.Kind.RELATIONSHIP_SHIFT
	rel.target_id = &"actor_a"
	rel.magnitude_min = 1
	rel.magnitude_max = 2
	assert_false(rel.is_valid(), "a relationship shift with no second endpoint invalidates")
	rel.secondary_id = &"actor_b"
	assert_false(rel.is_valid(), "and with no dimension to move")
	rel.dimension = &"respect"
	assert_true(rel.is_valid(), "with both it validates: %s" % str(rel.validation_errors()))
	rel.secondary_id = &"actor_a"
	assert_false(rel.is_valid(), "a relationship with itself invalidates")

	var influence := _event()
	influence.secondary_id = &"sect_b"
	assert_false(influence.is_valid(),
		"a secondary endpoint is meaningless for an influence event, so it is REFUSED rather "
		+ "than ignored (an authored field that does nothing is a trap)")
	influence = _event()
	influence.dimension = &"respect"
	assert_false(influence.is_valid(), "and so is a dimension")


func test_10_every_event_kind_has_a_localization_key() -> void:
	assert_eq(EventScript.KIND_NAME_KEYS.size(), EventScript.Kind.size(),
		"the key table covers every kind (so adding a kind forces a key)")
	for ordinal in EventScript.Kind.size():
		assert_ne(EventScript.kind_name_key(int(ordinal)), &"",
			"kind %d has a key" % int(ordinal))


# === 11-14. The catalog =====================================================

func test_11_a_well_formed_catalog_validates() -> void:
	var c := _catalog()
	assert_true(c.is_valid(), "a well-formed catalog validates: %s" % str(c.validation_errors()))
	assert_eq(c.schedules.size(), 1, "the fixture carries its schedules")
	assert_eq(c.actors.size(), 1, "and its actors")
	assert_eq(c.events.size(), 1, "and its events")


func test_12_catalog_tuning_invariants() -> void:
	var c := _catalog()
	c.ticks_per_hour = 0
	assert_false(c.is_valid(), "a zero calendar unit invalidates")

	c = _catalog()
	c.ticks_per_map_transition = 0
	assert_false(c.is_valid(), "a beat that advances nothing is a world that never moves")

	c = _catalog()
	c.ticks_on_session_start = -1
	assert_false(c.is_valid(), "a negative opening beat invalidates")

	# The budget is the one that matters most: a zero budget could never drain the carry-over
	# queue, so the world would accumulate debt forever and never catch up.
	c = _catalog()
	c.catch_up_budget_ticks = 0
	assert_false(c.is_valid(), "a zero catch-up budget would stall the world permanently")

	c = _catalog()
	c.event_log_capacity = -1
	assert_false(c.is_valid(), "a negative log capacity invalidates")


func test_13_catalog_cross_entry_integrity() -> void:
	# Duplicate ids.
	var c := _catalog()
	var dup_schedules: Array[WorldSimScheduleData] = [_schedule(), _schedule()]
	c.schedules = dup_schedules
	assert_false(c.is_valid(), "duplicate schedule ids invalidate")

	c = _catalog()
	var dup_actors: Array[WorldSimActorData] = [_actor(), _actor()]
	dup_actors[0].schedule = c.schedules[0]
	dup_actors[1].schedule = c.schedules[0]
	c.actors = dup_actors
	assert_false(c.is_valid(), "duplicate actor ids invalidate")

	c = _catalog()
	var dup_events: Array[WorldSimEventData] = [_event(), _event()]
	c.events = dup_events
	assert_false(c.is_valid(), "duplicate event ids invalidate (the id is the scheduling key)")

	# An actor whose schedule is not LISTED in the catalog: it would work at runtime and be
	# invisible to every catalog-level audit, including the localization drift guard.
	c = _catalog()
	var unlisted: Array[WorldSimActorData] = [_actor()]
	unlisted[0].schedule = _schedule(&"schedule_not_listed")
	c.actors = unlisted
	assert_false(c.is_valid(), "an actor using an unlisted schedule invalidates")
	var joined := str(c.validation_errors())
	assert_true(joined.contains("not listed"),
		"and the error says why (got %s)" % joined)

	# Nulls are reported, not skipped.
	c = _catalog()
	c.schedules = [null] as Array[WorldSimScheduleData]
	assert_false(c.is_valid(), "a null schedule entry invalidates")


## The map cross-check cannot live in `validation_errors()` (the map catalog is not visible
## from a data resource), so it is a separate call the runtime makes — and it must actually
## catch a bad home map, because an actor living nowhere would be permanently FAR: a character
## the player could never meet.
func test_14_the_map_cross_check_catches_a_homeless_actor() -> void:
	var c := _catalog()
	var known := {&"map_hub": null}
	assert_true(c.validation_errors_against_maps(known).is_empty(),
		"an actor whose home map exists passes")
	assert_false(c.validation_errors_against_maps({&"map_other": null}).is_empty(),
		"an actor whose home map is not in the catalog is reported")
	assert_false(c.validation_errors_against_maps({}).is_empty(),
		"and so is every actor when there are no maps at all")


func test_15_catalog_lookups_are_deterministic() -> void:
	var c := _catalog()
	var many: Array[WorldSimActorData] = [_actor(&"actor_zz"), _actor(&"actor_aa")]
	many[0].schedule = c.schedules[0]
	many[1].schedule = c.schedules[0]
	c.actors = many
	assert_true(c.is_valid(), "two distinct actors validate: %s" % str(c.validation_errors()))
	var sorted := c.actors_sorted()
	assert_eq(sorted.size(), 2, "both are returned")
	assert_eq(sorted[0].id, &"actor_aa", "actors_sorted is sorted by id, not authored order")
	assert_not_null(c.find_actor(&"actor_zz"), "find_actor resolves a known id")
	assert_null(c.find_actor(&"nope"), "and returns null for an unknown one")
	assert_not_null(c.find_schedule(&"schedule_x"), "find_schedule resolves")
	assert_not_null(c.find_event(&"wevent_x"), "find_event resolves")

	var events: Array[WorldSimEventData] = [_event(&"wevent_zz"), _event(&"wevent_aa")]
	c.events = events
	assert_eq(c.events_sorted()[0].id, &"wevent_aa", "events_sorted is sorted by id too")


# === 16-19. The authored content drift guards ===============================

## The content the game ships must satisfy every rule, so adding an actor or an event without
## satisfying them fails the suite instead of failing a player's session.
func test_16_the_authored_catalog_is_valid() -> void:
	var c := load(AUTHORED_CATALOG_PATH) as WorldSimCatalog
	assert_not_null(c, "the authored world-sim catalog loads")
	if c == null:
		return
	assert_true(c.is_valid(), "the authored catalog is valid: %s" % str(c.validation_errors()))
	assert_true(c.actors.size() >= 2,
		"a world needs more than one person in it (got %d)" % c.actors.size())
	assert_true(c.events.size() >= 1, "and at least one thing that happens")


## Every authored actor's home map must exist in the SHIPPED map catalog. Neither catalog can
## check this alone, so without this test a renamed map id would only surface as a failed
## session at runtime.
func test_17_authored_actors_live_in_real_maps() -> void:
	var c := load(AUTHORED_CATALOG_PATH) as WorldSimCatalog
	var maps := load(AUTHORED_MAP_CATALOG_PATH) as MapCatalog
	assert_not_null(c, "the world-sim catalog loads")
	assert_not_null(maps, "the map catalog loads")
	if c == null or maps == null:
		return
	var errors := c.validation_errors_against_maps(maps.build_lookup())
	assert_true(errors.is_empty(), "every authored actor lives in a real map: %s" % str(errors))


## Every authored actor's sect, rank and faction must exist in the SHIPPED sect/faction
## catalogs — the same class of cross-catalog guard, for the membership the session enrols.
## A bad id here would fail New Game for a player, which a test should catch first.
func test_18_authored_actor_affiliations_resolve() -> void:
	var c := load(AUTHORED_CATALOG_PATH) as WorldSimCatalog
	var sects := load(AUTHORED_SECT_CATALOG_PATH) as SectCatalog
	var factions := load(AUTHORED_FACTION_CATALOG_PATH) as FactionCatalog
	assert_not_null(c, "the world-sim catalog loads")
	assert_not_null(sects, "the sect catalog loads")
	assert_not_null(factions, "the faction catalog loads")
	if c == null or sects == null or factions == null:
		return
	for actor in c.actors_sorted():
		if actor.sect_id == &"":
			continue
		var sect := sects.find_sect(actor.sect_id)
		assert_not_null(sect, "actor '%s' names sect '%s', which must be authored"
			% [actor.id, actor.sect_id])
		if sect == null:
			continue
		var rank_ids: Array[String] = []
		for rank in sect.rank_ladder:
			if rank != null:
				rank_ids.append(String(rank.rank_id))
		assert_true(rank_ids.has(String(actor.sect_rank_id)),
			"actor '%s' joins at rank '%s', which must be on sect '%s's ladder %s"
				% [actor.id, actor.sect_rank_id, actor.sect_id, str(rank_ids)])
		if actor.faction_id == &"":
			continue
		var faction := factions.find_faction(actor.faction_id)
		assert_not_null(faction, "actor '%s' takes the side of faction '%s', which must be "
			% [actor.id, actor.faction_id] + "authored")
		if faction != null:
			assert_eq(faction.parent_sect_id, actor.sect_id,
				("actor '%s' is in sect '%s' but faction '%s' belongs to sect '%s'; a faction "
					+ "member must be on the PARENT sect's roster (D-015)")
					% [actor.id, actor.sect_id, actor.faction_id, faction.parent_sect_id])


## Every authored relationship event must name two actors the simulation actually knows, and
## the calendar must be self-consistent enough that a routine cycle fits inside a day or two
## (a routine longer than a season would never be observed changing).
func test_19_authored_events_and_schedules_are_coherent() -> void:
	var c := load(AUTHORED_CATALOG_PATH) as WorldSimCatalog
	assert_not_null(c, "the world-sim catalog loads")
	if c == null:
		return
	var actor_ids := {}
	for actor in c.actors_sorted():
		actor_ids[String(actor.id)] = true
	for event in c.events_sorted():
		if event.kind != WorldSimEventData.Kind.RELATIONSHIP_SHIFT:
			continue
		assert_true(actor_ids.has(String(event.target_id)),
			"event '%s' names actor '%s', which must be simulated"
				% [event.id, event.target_id])
		assert_true(actor_ids.has(String(event.secondary_id)),
			"event '%s' names actor '%s', which must be simulated"
				% [event.id, event.secondary_id])
	var ticks_per_day := c.ticks_per_hour * c.hours_per_day
	for schedule in c.schedules:
		if schedule == null:
			continue
		assert_true(schedule.cycle_ticks() > 0,
			"schedule '%s' has a usable cycle" % schedule.id)
		assert_true(schedule.cycle_ticks() <= ticks_per_day * 2,
			("schedule '%s' cycles in %d ticks but a day is %d; a routine much longer than a "
				+ "day would never be seen changing")
				% [schedule.id, schedule.cycle_ticks(), ticks_per_day])
	# The arrival beat must be small relative to the catch-up budget, or a single map
	# transition would immediately create carry-over debt and the world would always lag.
	assert_true(c.ticks_per_map_transition < c.catch_up_budget_ticks,
		("one arrival (%d ticks) must fit inside the catch-up budget (%d), or every single "
			+ "map transition would leave the world in debt")
			% [c.ticks_per_map_transition, c.catch_up_budget_ticks])

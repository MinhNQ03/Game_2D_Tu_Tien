extends TestCase
## Unit tests for the World Simulation ENGINE (Phase 08) — the file that has to hold.
##
## It asserts the five properties the phase exists to deliver, each stated as the failure it
## prevents:
##   1. **Determinism.** Same seed + same initial state + same K ticks == same authoritative
##      world. Without it a save cannot resume, a bug cannot be reproduced and a future server
##      cannot advance the world.
##   2. **Resume.** `save → load → advance K` == `advance K`. A seed alone only reproduces a
##      world from tick 0 (`docs/SAVE_FORMAT.md` §3b).
##   3. **LOD losslessness.** FAR → MID → NEAR → MID → FAR preserves persistent state, and a
##      promoted actor's activity equals what it would have been if observed all along.
##   4. **No dropped ticks.** A bounded catch-up defers time; it never discards it, and
##      processing `a + b` ticks equals processing `a+b` in one call.
##   5. **Mutation through owners.** Sect/faction influence and relationship dimensions move
##      through their own services, with clamping/history intact.
##
## REAL services, not stubs, throughout: a `SectStore` driven by a real `SectService`, a real
## `FactionService`, a real `RelationshipService` over a real config. A stubbed owner would let
## these tests pass while the actual composition was broken — the whole claim being made is
## about going through the real mutation paths.
##
## Everything is `RefCounted` built with `.new()`, so there is nothing to free (L-019 is about
## Nodes) — but the fixture DOES hold services that hold a resolver `Callable` capturing
## `self`, which closes a reference cycle GDScript will never collect, so `after_each` breaks
## it (L-030).

const ScheduleScript := preload("res://src/data/worldsim/world_sim_schedule_data.gd")
const ActorDataScript := preload("res://src/data/worldsim/world_sim_actor_data.gd")
const EventScript := preload("res://src/data/worldsim/world_sim_event_data.gd")
const CatalogScript := preload("res://src/data/worldsim/world_sim_catalog.gd")
const ClockScript := preload("res://src/domain/worldsim/world_clock.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const StateScript := preload("res://src/domain/worldsim/world_sim_state.gd")
const ServiceScript := preload("res://src/domain/worldsim/world_sim_service.gd")
const ActorScript := preload("res://src/domain/worldsim/world_sim_actor.gd")

const RegistryScript := preload("res://src/domain/character/character_registry.gd")
const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

const SectTemplateScript := preload("res://src/data/sects/sect_template_data.gd")
const SectRankScript := preload("res://src/data/sects/sect_rank_data.gd")
const SectStoreScript := preload("res://src/domain/sect/sect_store.gd")
const SectServiceScript := preload("res://src/domain/sect/sect_service.gd")

const FactionGoalScript := preload("res://src/data/factions/faction_goal_data.gd")
const FactionTemplateScript := preload("res://src/data/factions/faction_template_data.gd")
const FactionStoreScript := preload("res://src/domain/faction/faction_store.gd")
const FactionServiceScript := preload("res://src/domain/faction/faction_service.gd")

const RelConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")
const RelStoreScript := preload("res://src/domain/relationship/relationship_store.gd")
const RelServiceScript := preload("res://src/domain/relationship/relationship_service.gd")

const SEED := 20260801
const SECT_A := &"sect_a"
const FACTION_A := &"faction_a"
const ELDER := &"actor_elder"
const DISCIPLE := &"actor_disciple"
const SCOUT := &"actor_scout"
const HOME := &"map_home"
const NEXT_DOOR := &"map_next"
const FARAWAY := &"map_far"

# Live fixture pieces, held so assertions can read the owning stores back.
var _registry: CharacterRegistry = null
var _sects: SectService = null
var _factions: FactionService = null
var _relationship: RelationshipService = null


## Break the resolver cycle (self → service → Callable → self). GDScript reference-counts and
## does not collect cycles, so one leaked fixture pins every script it touches (L-030).
func after_each() -> void:
	if _sects != null:
		_sects.set_character_resolver(Callable())
	if _factions != null:
		_factions.set_character_resolver(Callable())
	_registry = null
	_sects = null
	_factions = null
	_relationship = null


# --- typed fixtures ----------------------------------------------------------

func _schedule(sid: StringName, phases_in: Array) -> WorldSimScheduleData:
	var phases: Array[Dictionary] = []
	for phase in phases_in:
		phases.append(phase)
	var s: WorldSimScheduleData = ScheduleScript.new()
	s.id = sid
	s.phases = phases
	return s


## TRAINING for 4 ticks then RESTING for 2 — a 6-tick cycle, short enough that a handful of
## ticks crosses several boundaries.
func _drill_schedule() -> WorldSimScheduleData:
	return _schedule(&"schedule_drill", [
		{"activity": ScheduleScript.Activity.TRAINING, "ticks": 4},
		{"activity": ScheduleScript.Activity.RESTING, "ticks": 2},
	])


## MISSION 2 / RETURNING 1 / RESTING 1 — a 4-tick cycle, deliberately coprime-ish with the
## drill cycle so the two actors are rarely in step.
func _patrol_schedule() -> WorldSimScheduleData:
	return _schedule(&"schedule_patrol", [
		{"activity": ScheduleScript.Activity.MISSION, "ticks": 2},
		{"activity": ScheduleScript.Activity.RETURNING, "ticks": 1},
		{"activity": ScheduleScript.Activity.RESTING, "ticks": 1},
	])


func _character_template(tid: StringName) -> CharacterTemplateData:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 30
	stats.attack = 4
	stats.defense = 1
	stats.move_speed = 120.0
	var t: CharacterTemplateData = CharacterTemplateScript.new()
	t.id = tid
	t.name_key = &"NAME"
	t.base_stats = stats
	return t


func _actor_data(
		aid: StringName,
		schedule: WorldSimScheduleData,
		home: StringName,
		with_faction: bool = false) -> WorldSimActorData:
	var a: WorldSimActorData = ActorDataScript.new()
	a.id = aid
	a.character_template = _character_template(StringName("char_%s" % String(aid)))
	a.schedule = schedule
	a.home_map_id = home
	a.sect_id = SECT_A
	a.sect_rank_id = &"rank_outer"
	if with_faction:
		a.faction_id = FACTION_A
	return a


func _sect_influence_event() -> WorldSimEventData:
	var e: WorldSimEventData = EventScript.new()
	e.id = &"wevent_sect"
	e.kind = EventScript.Kind.SECT_INFLUENCE
	e.target_id = SECT_A
	e.first_tick = 2
	e.period_ticks = 5
	e.magnitude_min = 1
	e.magnitude_max = 3
	return e


func _faction_influence_event() -> WorldSimEventData:
	var e: WorldSimEventData = EventScript.new()
	e.id = &"wevent_faction"
	e.kind = EventScript.Kind.FACTION_INFLUENCE
	e.target_id = FACTION_A
	e.first_tick = 3
	e.period_ticks = 7
	e.magnitude_min = 1
	e.magnitude_max = 2
	return e


func _relationship_event() -> WorldSimEventData:
	var e: WorldSimEventData = EventScript.new()
	e.id = &"wevent_bond"
	e.kind = EventScript.Kind.RELATIONSHIP_SHIFT
	e.target_id = ELDER
	e.secondary_id = DISCIPLE
	e.dimension = &"respect"
	e.first_tick = 4
	e.period_ticks = 6
	e.magnitude_min = 1
	e.magnitude_max = 2
	return e


## The catalog every test builds on: three actors across three maps (so all THREE bands are
## reachable) and one event of every kind (so all three service seams are exercised).
func _catalog() -> WorldSimCatalog:
	var drill := _drill_schedule()
	var patrol := _patrol_schedule()
	var schedules: Array[WorldSimScheduleData] = [drill, patrol]
	var actors: Array[WorldSimActorData] = [
		_actor_data(ELDER, drill, HOME, true),
		_actor_data(DISCIPLE, patrol, NEXT_DOOR),
		_actor_data(SCOUT, patrol, FARAWAY),
	]
	var events: Array[WorldSimEventData] = [
		_sect_influence_event(), _faction_influence_event(), _relationship_event(),
	]
	var c: WorldSimCatalog = CatalogScript.new()
	c.ticks_per_hour = 1
	c.hours_per_day = 8
	c.days_per_season = 10
	c.seasons_per_year = 4
	c.ticks_per_map_transition = 3
	c.ticks_on_session_start = 0
	c.catch_up_budget_ticks = 10
	c.event_log_capacity = 6
	c.schedules = schedules
	c.actors = actors
	c.events = events
	return c


func _rel_config() -> RelationshipConfigData:
	var dims: Array[Dictionary] = [
		{"id": &"respect", "default": 0, "min": 0, "max": 20},
		{"id": &"rivalry", "default": 0, "min": 0, "max": 100},
	]
	var cfg: RelationshipConfigData = RelConfigScript.new()
	cfg.dimensions = dims
	cfg.history_capacity = 32
	return cfg


func _sect_ladder() -> Array[SectRankData]:
	var out: Array[SectRankData] = []
	var r: SectRankData = SectRankScript.new()
	r.rank_id = &"rank_outer"
	r.name_key = &"R_OUTER"
	r.authority = 10
	out.append(r)
	return out


func _faction_goals() -> Array[FactionGoalData]:
	var g: FactionGoalData = FactionGoalScript.new()
	g.goal_id = &"goal_a"
	g.name_key = &"G_A"
	g.kind = FactionGoalScript.GoalKind.AUTHORITY
	g.priority = 1
	var out: Array[FactionGoalData] = [g]
	return out


## Build the whole live world: registry + sect + faction + relationship + simulation, with
## every actor admitted exactly the way `WorldSimulationRuntime` does it (character → registry
## → sect roster → faction seat → simulation record). Returns the service, or null on failure.
func _world(catalog: WorldSimCatalog, seed_value: int = SEED) -> WorldSimulationService:
	_registry = RegistryScript.new()

	var sect_store: SectStore = SectStoreScript.new()
	_sects = SectServiceScript.new(sect_store)
	_sects.set_character_resolver(_registry.resolver())
	var sect_template: SectTemplateData = SectTemplateScript.new()
	sect_template.id = SECT_A
	sect_template.name_key = &"SECT"
	sect_template.doctrine_key = &"DOCTRINE"
	sect_template.tier = 1
	sect_template.rank_ladder = _sect_ladder()
	sect_template.influence_seed = 40
	if not _sects.register_sect(SectState.create_from_template(sect_template), sect_template):
		return null

	var faction_store: FactionStore = FactionStoreScript.new()
	_factions = FactionServiceScript.new(faction_store)
	_factions.set_sect_store(sect_store)
	_factions.set_character_resolver(_registry.resolver())
	var faction_template: FactionTemplateData = FactionTemplateScript.new()
	faction_template.id = FACTION_A
	faction_template.parent_sect_id = SECT_A
	faction_template.name_key = &"FACTION"
	faction_template.doctrine_key = &"FACTION_DOCTRINE"
	faction_template.influence_seed = 30
	faction_template.goals = _faction_goals()
	if not _factions.register_faction(
			FactionState.create_from_template(faction_template), faction_template):
		return null

	var cfg := _rel_config()
	var rel_store: RelationshipStore = RelStoreScript.new(cfg)
	_relationship = RelServiceScript.new(rel_store, cfg)

	var clock: WorldClock = ClockScript.new(
		catalog.ticks_per_hour, catalog.hours_per_day,
		catalog.days_per_season, catalog.seasons_per_year)
	var rng: RngService = RngServiceScript.new(seed_value)
	var state: WorldSimulationState = StateScript.create(
		clock, rng, catalog.event_log_capacity)
	if state == null:
		return null
	var service: WorldSimulationService = ServiceScript.new(state, catalog)
	service.set_sect_service(_sects)
	service.set_faction_service(_factions)
	service.set_relationship_service(_relationship)
	service.set_character_resolver(_registry.resolver())

	for actor_data in catalog.actors_sorted():
		var character := CharacterState.create_from_template(
			actor_data.character_template, actor_data.id)
		if character == null or not _registry.add(character):
			return null
		if not _sects.join_member(actor_data.sect_id, actor_data.id, actor_data.sect_rank_id):
			return null
		if actor_data.faction_id != &"" \
				and not _factions.join_member(actor_data.faction_id, actor_data.id):
			return null
		if not service.register_actor(actor_data):
			return null
	if not service.prepare_events():
		return null
	if not service.schedule_authored_events():
		return null
	service.assign_bands(HOME, {NEXT_DOOR: true})
	service.sync_character_caches()
	return service


## The authoritative world state as a COMPARABLE STRING: the simulation's own snapshot plus
## everything it changed in the systems that own it.
##
## Comparing this (rather than object identities) is what B12 asks for — "meaningful persistent
## fields, not object instance IDs" — and including the OTHER systems' state is what makes the
## determinism claim worth anything: a simulation that was internally reproducible while
## applying different influence deltas each run would pass a narrower check.
func _world_fingerprint(service: WorldSimulationService) -> String:
	var parts: Array[String] = [str(service.get_state().to_dict())]
	parts.append("sect=%d" % _sects.get_store().get_sect(SECT_A).influence)
	parts.append("faction=%d" % _factions.get_store().get_faction(FACTION_A).influence)
	var eid := ServiceScript.edge_id(ELDER, DISCIPLE)
	var edge: RelationshipEdge = _relationship.get_store().get_edge(eid)
	if edge != null:
		parts.append("respect=%d" % edge.get_dimension(&"respect"))
		parts.append("history=%d" % edge.history_size())
	for character in _registry.all():
		parts.append("%s.sim=%s" % [character.instance_id, str(character.sim_state)])
	return "|".join(parts)


# === 1-2. The world is built correctly ======================================

func test_01_a_world_builds_with_every_seam_live() -> void:
	var service := _world(_catalog())
	assert_not_null(service, "the world builds")
	if service == null:
		return
	assert_true(service.is_usable(), "the service is usable")
	var state := service.get_state()
	assert_eq(state.actor_count(), 3, "all three actors are simulated")
	assert_eq(state.tick(), 0, "the world starts at tick 0")
	assert_eq(state.pending_count(), 3, "all three authored events are queued")
	# The cast went through the OWNING services, so the sect roster is the authority.
	assert_eq(_sects.get_store().get_sect(SECT_A).member_count(), 3,
		"every actor is on the sect roster (enrolled through SectService, D-015)")
	assert_true(_factions.get_store().get_faction(FACTION_A).is_member(ELDER),
		"and the one authored faction seat was taken through FactionService")
	# The derived caches agree with the authoritative records.
	assert_true(service.verify_character_caches(), "every sim_state cache matches its record")
	var elder: CharacterState = _registry.get_character(ELDER)
	assert_false(elder.sim_state.is_empty(), "the character carries a sim_state cache")
	assert_eq(elder.sect_id, SECT_A, "and its sect cache, written by SectService")


## All three bands must be reachable, and FAR must be the default for anywhere else.
func test_02_bands_come_from_the_map_graph() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	var state := service.get_state()
	assert_eq(state.get_actor(ELDER).band(), ActorScript.Band.NEAR,
		"an actor in the player's own map is NEAR")
	assert_eq(state.get_actor(DISCIPLE).band(), ActorScript.Band.MID,
		"an actor one hop away is MID")
	assert_eq(state.get_actor(SCOUT).band(), ActorScript.Band.FAR,
		"an actor anywhere else is FAR")
	var census := state.band_census()
	assert_eq(census[ActorScript.Band.NEAR], 1, "one NEAR")
	assert_eq(census[ActorScript.Band.MID], 1, "one MID")
	assert_eq(census[ActorScript.Band.FAR], 1, "one FAR")
	# Only NEAR+MID are the per-tick working set — that IS the LOD cost model.
	assert_eq(state.observed_actors_sorted().size(), 2,
		"the per-tick working set is NEAR+MID only, not the whole cast")
	# Moving the player re-assigns bands.
	var changed := service.assign_bands(FARAWAY, {})
	assert_true(changed > 0, "moving the player changes bands")
	assert_eq(state.get_actor(SCOUT).band(), ActorScript.Band.NEAR,
		"the far actor becomes NEAR when the player arrives there")
	assert_eq(state.get_actor(ELDER).band(), ActorScript.Band.FAR,
		"and the previously-near actor becomes FAR")


# === 3-4. DETERMINISM =======================================================

## THE HEADLINE PROPERTY: same seed + same initial state + same K ticks == same world.
##
## Compared over the whole fingerprint (simulation snapshot + sect influence + faction
## influence + relationship dimension and history length + every character's sim cache), so a
## divergence anywhere in the chain fails this rather than only an internal one.
func test_03_the_same_seed_produces_the_same_world() -> void:
	var run_a := _world(_catalog())
	if run_a == null:
		return
	run_a.advance_ticks(10)
	var fingerprint_a := _world_fingerprint(run_a)
	after_each()  # drop run A's fixture before building run B

	var run_b := _world(_catalog())
	if run_b == null:
		return
	run_b.advance_ticks(10)
	var fingerprint_b := _world_fingerprint(run_b)

	assert_eq(fingerprint_b, fingerprint_a,
		"two runs from the same seed and the same K ticks produce an IDENTICAL world")
	# And the world actually MOVED — a simulation that did nothing would also be "identical".
	assert_true(fingerprint_a.contains("sect=") and not fingerprint_a.contains("sect=40"),
		"and the sect influence actually changed from its seeded 40 (got %s)" % fingerprint_a)


## A DIFFERENT seed must produce a different world, or the seed would be decorative and
## "reproducible" would just mean "always the same".
func test_04_a_different_seed_produces_a_different_world() -> void:
	var run_a := _world(_catalog(), SEED)
	if run_a == null:
		return
	run_a.advance_ticks(12)
	var fingerprint_a := _world_fingerprint(run_a)
	after_each()

	var run_b := _world(_catalog(), SEED + 1)
	if run_b == null:
		return
	run_b.advance_ticks(12)
	assert_ne(_world_fingerprint(run_b), fingerprint_a,
		"a different world seed produces a different world")


# === 5-6. CATCH-UP (no dropped ticks) =======================================

## A request beyond the budget is DEFERRED, not discarded, and the debt is drained first on
## the next call — so the world is always exactly as old as the time it was given.
func test_05_catch_up_defers_time_and_never_drops_it() -> void:
	var catalog := _catalog()   # budget = 10
	var service := _world(catalog)
	if service == null:
		return
	assert_eq(service.pending_catch_up_ticks(), 0, "no debt to begin with")

	var processed := service.advance_ticks(25)
	assert_eq(processed, 10, "only the budget is processed in one call")
	assert_eq(service.get_state().tick(), 10, "so the clock advanced by exactly the budget")
	assert_eq(service.pending_catch_up_ticks(), 15, "and 15 ticks are owed, not lost")

	processed = service.advance_ticks(1)
	assert_eq(processed, 10, "the next call drains the DEBT first, up to the budget")
	assert_eq(service.pending_catch_up_ticks(), 6, "leaving 6 (15 - 10 + the new 1)")

	processed = service.advance_ticks(1)
	assert_eq(processed, 7, "the next call drains the remaining 7 (6 owed + the new 1)")
	assert_eq(service.pending_catch_up_ticks(), 0, "the debt drains completely")

	service.advance_ticks(1)
	assert_eq(service.pending_catch_up_ticks(), 0, "and stays drained once caught up")
	assert_eq(service.get_state().tick(), 28,
		"the world is exactly as old as the 28 ticks it was given (25+1+1+1), with none "
		+ "dropped and none invented")


## THE EQUIVALENCE that makes a bounded catch-up legitimate: processing N ticks as `a + b` must
## produce the same world as processing N in one call. If it did not, how fast the player
## travelled would change the world's history.
func test_06_split_advancement_equals_one_advancement() -> void:
	var one_shot_catalog := _catalog()
	one_shot_catalog.catch_up_budget_ticks = 100
	var one_shot := _world(one_shot_catalog)
	if one_shot == null:
		return
	assert_eq(one_shot.advance_ticks(18), 18, "a generous budget processes all 18 at once")
	var expected := _world_fingerprint(one_shot)
	after_each()

	var split_catalog := _catalog()
	split_catalog.catch_up_budget_ticks = 100
	var split := _world(split_catalog)
	if split == null:
		return
	split.advance_ticks(5)
	split.advance_ticks(1)
	split.advance_ticks(12)
	assert_eq(split.get_state().tick(), 18, "the split run reached the same tick")
	assert_eq(_world_fingerprint(split), expected,
		"18 ticks as 5+1+12 produce the IDENTICAL world to 18 in one call")


# === 7-8. LOD losslessness (promotion / demotion) ===========================

## FAR → MID → NEAR → MID → FAR must preserve the actor's persistent state. Only the BAND may
## differ, plus the deterministic routine progress the clock caused — which is documented
## progress, not loss.
func test_07_a_full_band_round_trip_preserves_state() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	var state := service.get_state()
	var scout := state.get_actor(SCOUT)
	assert_eq(scout.band(), ActorScript.Band.FAR, "the scout starts FAR")
	var identity := scout.get_instance_id()
	var schedule_id := scout.schedule_id
	var location := scout.location_map_id
	var joined := scout.joined_tick

	# FAR -> MID -> NEAR -> MID -> FAR, with the world ticking between each move.
	for destination in [NEXT_DOOR, FARAWAY, NEXT_DOOR, HOME]:
		service.advance_ticks(3)
		if StringName(destination) == FARAWAY:
			service.assign_bands(FARAWAY, {NEXT_DOOR: true})
		else:
			service.assign_bands(StringName(destination), {FARAWAY: true})

	var after := state.get_actor(SCOUT)
	assert_eq(after.get_instance_id(), identity,
		"it is the SAME actor record, never replaced (so no identity was lost)")
	assert_eq(state.actor_count(), 3, "no actor was duplicated or dropped")
	assert_eq(after.schedule_id, schedule_id, "the routine is unchanged")
	assert_eq(after.location_map_id, location, "the location is unchanged")
	assert_eq(after.joined_tick, joined,
		"and joined_tick is unchanged — the origin of the derived activity survived")
	assert_true(_registry.has(SCOUT), "the CHARACTER still exists")
	assert_true(service.verify_character_caches(),
		"and its sim_state cache is consistent again after the round trip")


## THE PROPERTY THAT MAKES LOD SAFE: an actor that was FAR the whole time has the SAME activity
## as one that was observed every tick. The band changes how often the simulation LOOKS, never
## what it would see — so promotion can never "catch up" to a different answer.
func test_08_a_far_actor_is_never_behind_an_observed_one() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	var state := service.get_state()
	# The disciple (MID, observed) and the scout (FAR, unobserved) keep the SAME routine, so
	# at any tick their derived activity must agree.
	assert_eq(state.get_actor(DISCIPLE).schedule_id, state.get_actor(SCOUT).schedule_id,
		"the two actors keep the same routine (so their activities are comparable)")
	for _step in 5:
		service.advance_ticks(3)
		assert_eq(service.activity_of(SCOUT), service.activity_of(DISCIPLE),
			("at tick %d the FAR actor's activity equals the observed one's; if this fails, "
				+ "LOD is losing simulation time") % state.tick())
	# The derived read is correct even though the FAR actor's CACHE was never refreshed.
	var scout := state.get_actor(SCOUT)
	assert_eq(service.activity_of(SCOUT),
		_patrol_schedule().activity_at(scout.elapsed_at(state.tick())),
		"and the derived read matches the authored routine directly")
	# Promoting it NOW must land on exactly that value, not on a stale one.
	var expected := service.activity_of(SCOUT)
	service.assign_bands(FARAWAY, {})
	assert_eq(state.get_actor(SCOUT).activity(), expected,
		"promotion refreshes the cache to the value it ALREADY should have had")


## The activity really does change over time and wrap — a simulation that reported one
## activity forever would pass every single-sample assertion (the L-029 lesson).
func test_09_activities_advance_and_wrap() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	var seen := {}
	var at_start := service.activity_of(ELDER)
	for _step in 6:
		service.advance_ticks(1)
		seen[service.activity_of(ELDER)] = true
	assert_true(seen.size() >= 2,
		"the elder's activity CHANGED over six ticks (not frozen on one value)")
	# The drill cycle is 6 ticks, so after a full cycle it is back where it began.
	assert_eq(service.activity_of(ELDER), at_start, "a full cycle returns to the start")


# === 10-12. Mutation through the OWNING services ============================

## Sect and faction influence must move through their own services, which is observable
## because those services CLAMP and the simulation does not.
func test_10_influence_moves_through_its_owner_and_is_clamped() -> void:
	var catalog := _catalog()
	# A huge positive magnitude, so the owner's ceiling is the only thing that can stop it.
	catalog.events[1].magnitude_min = 1000
	catalog.events[1].magnitude_max = 1000
	catalog.events[1].period_ticks = 1
	var service := _world(catalog)
	if service == null:
		return
	service.advance_ticks(10)
	var faction := _factions.get_store().get_faction(FACTION_A)
	assert_eq(faction.influence, FactionState.INFLUENCE_MAX,
		("faction influence stopped at the OWNER's ceiling (%d), proving the simulation went "
			+ "through FactionService rather than writing the field")
			% FactionState.INFLUENCE_MAX)


## Relationship deltas must go through `RelationshipService`, which is observable because it
## clamps to the configured range AND writes bounded history — neither of which the simulation
## implements.
func test_11_relationship_shifts_go_through_the_graph_service() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	var eid := ServiceScript.edge_id(ELDER, DISCIPLE)
	var edge: RelationshipEdge = _relationship.get_store().get_edge(eid)
	assert_not_null(edge, "the simulation ENSURED its edge at prepare time, not mid-tick")
	if edge == null:
		return
	assert_true(edge.symmetric, "the edge is symmetric (one edge per pair)")
	assert_eq(edge.from_ref.kind, RelationshipEndpoint.Kind.CHARACTER,
		"its endpoints are typed as CHARACTERS")
	var identity := edge.get_instance_id()
	assert_eq(edge.get_dimension(&"respect"), 0, "and it starts at the configured default")

	service.advance_ticks(10)
	var after: RelationshipEdge = _relationship.get_store().get_edge(eid)
	assert_eq(after.get_instance_id(), identity,
		"the SAME edge was mutated in place; no second edge was created per event")
	assert_true(after.get_dimension(&"respect") > 0, "the dimension moved")
	assert_true(after.history_size() > 0,
		"and the SERVICE wrote history — which the simulation does not implement, so this "
		+ "proves the delta went through the authoritative path (B11)")
	assert_true(after.get_dimension(&"respect") <= 20,
		"and the value is clamped to the configured max of 20")
	# The edge id must be namespaced away from the sect/faction mirrors, or two mirrors would
	# collide on a pair and the second create would be rejected as a duplicate id.
	assert_true(String(eid).begins_with(ServiceScript.EDGE_PREFIX), "the id is namespaced")
	assert_eq(ServiceScript.edge_id(DISCIPLE, ELDER), eid, "and A-B == B-A (one edge per pair)")


## The signals other systems will subscribe to must actually fire, with the right payloads.
func test_12_the_simulation_announces_what_it_did() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	var ticks: Array[int] = []
	var events: Array[String] = []
	var activities: Array[String] = []
	var bands: Array[String] = []
	service.world_tick.connect(func(tick: int) -> void: ticks.append(tick))
	service.world_event_triggered.connect(
		func(eid: StringName, _kind: int, target: StringName, magnitude: int) -> void:
			events.append("%s:%s:%d" % [eid, target, magnitude]))
	service.actor_state_changed.connect(
		func(aid: StringName, activity: int) -> void:
			activities.append("%s:%d" % [aid, activity]))
	service.actor_band_changed.connect(
		func(aid: StringName, band: int) -> void: bands.append("%s:%d" % [aid, band]))

	service.advance_ticks(8)
	assert_eq(ticks.size(), 8, "world_tick fired once per processed tick")
	assert_eq(ticks[0], 1, "starting at tick 1")
	assert_eq(ticks[7], 8, "and ending at tick 8")
	assert_true(events.size() >= 3, "world_event_triggered fired for the due events (got %s)"
		% str(events))
	assert_true(activities.size() >= 2,
		"actor_state_changed fired as observed actors changed activity (got %s)"
			% str(activities))
	# FAR actors are deliberately silent: emitting for the whole cast every tick is the storm
	# LOD exists to avoid.
	for entry in activities:
		assert_false(String(entry).begins_with(String(SCOUT)),
			"the FAR actor emitted nothing (got %s)" % String(entry))
	service.assign_bands(FARAWAY, {})
	assert_true(bands.size() > 0, "actor_band_changed fired on promotion/demotion")


# === 13-14. The world-event feed ============================================

func test_13_the_event_feed_is_bounded_and_newest_last() -> void:
	var catalog := _catalog()  # log capacity = 6
	var service := _world(catalog)
	if service == null:
		return
	service.advance_ticks(10)
	service.advance_ticks(10)
	service.advance_ticks(10)
	var log := service.get_state().event_log()
	assert_true(log.size() > 0, "the feed recorded events")
	assert_true(log.size() <= catalog.event_log_capacity,
		"and is capped at the authored capacity (%d, got %d)"
			% [catalog.event_log_capacity, log.size()])
	var latest := service.get_state().latest_event()
	assert_eq(str(latest), str(log[log.size() - 1]), "latest_event is the LAST entry")
	# Entries carry what the feed needs and nothing presentation-shaped.
	assert_true(latest.has("tick") and latest.has("event_id") and latest.has("kind")
		and latest.has("magnitude"), "an entry carries tick/id/kind/magnitude (got %s)"
			% str(latest))


## A capacity of 0 disables the FEED without stopping the SIMULATION — the readout and the
## world are separate concerns.
func test_14_a_zero_capacity_feed_does_not_stop_the_world() -> void:
	var catalog := _catalog()
	catalog.event_log_capacity = 0
	var service := _world(catalog)
	if service == null:
		return
	service.advance_ticks(10)
	assert_eq(service.get_state().event_log().size(), 0, "nothing is recorded")
	assert_true(service.get_state().latest_event().is_empty(), "and there is no latest event")
	assert_true(_sects.get_store().get_sect(SECT_A).influence != 40,
		"but the world still moved (the feed is a readout, not the simulation)")


# === 15-17. Resume ==========================================================

## THE RESUME CONTRACT: `save → load → advance K` == `advance K` on a run that never stopped.
##
## This is the assertion `docs/SAVE_FORMAT.md` §3b exists for. It fails if ANY input to a
## future tick is missing from the snapshot — the RNG stream positions, the pending queue's
## recomputed due ticks, the carry-over debt, or each actor's `joined_tick`.
func test_15_a_saved_world_resumes_identically() -> void:
	var continuous_catalog := _catalog()
	continuous_catalog.catch_up_budget_ticks = 100
	var continuous := _world(continuous_catalog)
	if continuous == null:
		return
	continuous.advance_ticks(7)
	continuous.advance_ticks(9)
	var expected := _world_fingerprint(continuous)
	after_each()

	# A second world, advanced 7 ticks, SNAPSHOTTED, restored into a fresh world, then
	# advanced the remaining 9.
	var saved_catalog := _catalog()
	saved_catalog.catch_up_budget_ticks = 100
	var first_half := _world(saved_catalog)
	if first_half == null:
		return
	first_half.advance_ticks(7)
	var snapshot := first_half.get_state().to_dict()
	var sect_at_save := _sects.get_store().get_sect(SECT_A).influence
	var faction_at_save := _factions.get_store().get_faction(FACTION_A).influence
	var respect_at_save := _relationship.get_store().get_edge(
		ServiceScript.edge_id(ELDER, DISCIPLE)).get_dimension(&"respect")
	after_each()

	var resumed_catalog := _catalog()
	resumed_catalog.catch_up_budget_ticks = 100
	var resumed := _world(resumed_catalog)
	if resumed == null:
		return
	assert_true(resumed.get_state().from_dict(snapshot), "the snapshot hydrates")
	# The OTHER systems are restored by their own save blocks in a real load (Phase 23); here
	# we bring them to their saved values so the comparison is about the SIMULATION.
	_sects.adjust_influence(SECT_A, sect_at_save - 40)
	_factions.adjust_influence(FACTION_A, faction_at_save - 30)
	_relationship.apply_delta(ServiceScript.edge_id(ELDER, DISCIPLE), &"respect",
		respect_at_save, &"TEST_RESTORE")
	# Re-point the service at the hydrated state's stream, then run the remaining ticks.
	var continued: WorldSimulationService = ServiceScript.new(
		resumed.get_state(), resumed_catalog)
	continued.set_sect_service(_sects)
	continued.set_faction_service(_factions)
	continued.set_relationship_service(_relationship)
	continued.set_character_resolver(_registry.resolver())
	assert_eq(continued.advance_ticks(9), 9, "the resumed world advances the remaining 9")

	var actual := _world_fingerprint(continued)
	assert_eq(actual, expected,
		("a world saved at tick 7 and resumed produced the IDENTICAL result to one that never "
			+ "stopped; a divergence here means something a future tick depends on is missing "
			+ "from the snapshot (stream positions, the pending queue, carry-over, "
			+ "joined_tick)"))


## The state snapshot is byte-stable and uses the key names `DATA_SCHEMA.md` reserves, so the
## documented shape and the real one cannot drift (L-014).
func test_16_the_state_snapshot_is_stable_and_documented() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	service.advance_ticks(5)
	var snapshot := service.get_state().to_dict()
	for key in ["world_clock", "pending_transitions", "rng_seed"]:
		assert_true(snapshot.has(String(key)),
			"the snapshot carries the documented key '%s'" % String(key))
	for key in ["rng_streams", "carry_over_ticks", "actors", "event_log", "schema"]:
		assert_true(snapshot.has(String(key)),
			"and the key '%s' a deterministic resume additionally needs" % String(key))
	assert_eq(snapshot["rng_seed"], SEED, "the world seed is recorded")
	assert_eq(str(service.get_state().to_dict()), str(snapshot),
		"and two snapshots of one state are byte-identical")


## Malformed snapshots are REJECTED and the simulation is left byte-identical (B20: no partial
## hydrate). Each case differs from a known-good snapshot in exactly one field.
func test_17_malformed_state_payloads_fail_closed() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	service.advance_ticks(5)
	var state := service.get_state()
	var good := state.to_dict()
	var before := str(good)

	var cases := {}
	cases["a non-dict payload"] = "nope"
	var wrong_schema: Dictionary = good.duplicate(true)
	wrong_schema["schema"] = StateScript.SCHEMA_VERSION + 1
	cases["an unknown schema version"] = wrong_schema
	var bad_clock: Dictionary = good.duplicate(true)
	bad_clock["world_clock"] = {"tick": "5"}
	cases["a string tick in the clock"] = bad_clock
	var bad_seed: Dictionary = good.duplicate(true)
	bad_seed["rng_seed"] = "123"
	cases["a string rng seed"] = bad_seed
	var bad_streams: Dictionary = good.duplicate(true)
	bad_streams["rng_streams"] = []
	cases["a non-dict stream block"] = bad_streams
	var bad_carry: Dictionary = good.duplicate(true)
	bad_carry["carry_over_ticks"] = -1
	cases["negative carry-over"] = bad_carry
	var bad_actors: Dictionary = good.duplicate(true)
	bad_actors["actors"] = {"x": 5}
	cases["a malformed actor row"] = bad_actors
	var mismatched_actor: Dictionary = good.duplicate(true)
	mismatched_actor["actors"] = {"wrong_key": {
		"instance_id": "actor_elder", "schedule_id": "schedule_drill",
		"location_map_id": "map_home", "joined_tick": 0, "band": 0, "activity": 0,
	}}
	cases["an actor key that disagrees with its row"] = mismatched_actor
	var bad_pending: Dictionary = good.duplicate(true)
	bad_pending["pending_transitions"] = [{"event_id": "x", "due_tick": "9"}]
	cases["a string due tick"] = bad_pending
	var past_pending: Dictionary = good.duplicate(true)
	past_pending["pending_transitions"] = [{"event_id": "x", "due_tick": 1}]
	cases["an event due in the PAST"] = past_pending
	var dup_pending: Dictionary = good.duplicate(true)
	dup_pending["pending_transitions"] = [
		{"event_id": "x", "due_tick": 99}, {"event_id": "x", "due_tick": 100},
	]
	cases["the same event queued twice"] = dup_pending
	var bad_log: Dictionary = good.duplicate(true)
	bad_log["event_log"] = ["not a dict"]
	cases["a malformed log entry"] = bad_log
	var bad_capacity: Dictionary = good.duplicate(true)
	bad_capacity["event_log_capacity"] = -1
	cases["a negative log capacity"] = bad_capacity

	var names: Array = cases.keys()
	names.sort()
	for name in names:
		assert_false(state.from_dict(cases[name]), "%s is REJECTED" % String(name))
		assert_eq(str(state.to_dict()), before,
			"and the simulation is byte-identical afterwards (%s)" % String(name))

	# The known-good snapshot still hydrates, proving every rejection above was about its one
	# change and not about the fixture.
	assert_true(state.from_dict(good), "the known-good snapshot IS accepted")


# === 18-19. Fail-closed setup ===============================================

## An event that cannot be applied must fail PREPARATION, not a tick. A tick cannot abort
## halfway (the clock has moved and a draw is spent), so the only safe place to find out is
## before any time passes.
func test_18_events_that_cannot_be_applied_fail_preparation() -> void:
	# An unknown sect target.
	var catalog := _catalog()
	catalog.events[0].target_id = &"sect_that_does_not_exist"
	var service := _world(catalog)
	assert_null(service,
		"a world whose event names a non-existent sect REFUSES to build")
	after_each()

	# An unknown relationship dimension.
	catalog = _catalog()
	catalog.events[2].dimension = &"not_a_dimension"
	service = _world(catalog)
	assert_null(service, "a world whose event names an unconfigured dimension REFUSES to build")
	after_each()

	# A relationship endpoint that is not a simulated actor.
	catalog = _catalog()
	catalog.events[2].secondary_id = &"actor_who_is_not_here"
	service = _world(catalog)
	assert_null(service, "a world whose relationship event names a stranger REFUSES to build")


## The service refuses to do anything without the owning service a given event needs — the
## D-047 rule (a mutation with nowhere to land is not a mutation that can succeed) applied to
## the simulation.
func test_19_a_missing_owner_service_fails_preparation() -> void:
	var catalog := _catalog()
	var clock: WorldClock = ClockScript.new(1, 8, 10, 4)
	var rng: RngService = RngServiceScript.new(SEED)
	var state: WorldSimulationState = StateScript.create(clock, rng, 4)
	var service: WorldSimulationService = ServiceScript.new(state, catalog)
	# No sect/faction/relationship service installed at all.
	assert_false(service.prepare_events(),
		"preparation fails when the services that OWN the affected state are absent")

	# An invalid clock or seed must stop the state from existing in the first place.
	assert_null(StateScript.create(ClockScript.new(0, 1, 1, 1), rng, 4),
		"a state cannot be built on an invalid calendar")
	assert_null(StateScript.create(clock, RngServiceScript.new(-5), 4),
		"nor on an unusable world seed")
	assert_null(StateScript.create(clock, rng, -1), "nor with a negative log capacity")


# === 20. Registration guards ================================================

func test_20_actor_registration_is_guarded() -> void:
	var catalog := _catalog()
	var service := _world(catalog)
	if service == null:
		return
	# A duplicate registration is refused rather than replacing the record.
	assert_false(service.register_actor(catalog.actors_sorted()[0]),
		"an already-simulated actor is refused")
	assert_eq(service.get_state().actor_count(), 3, "and no duplicate record was created")
	# An actor with no CharacterState is refused: the simulation records state ABOUT
	# characters and must never invent one.
	var stranger := _actor_data(&"actor_unknown", _drill_schedule(), HOME)
	assert_false(service.register_actor(stranger),
		"an actor with no CharacterState in the registry is refused")
	assert_false(service.register_actor(null), "and so is a null actor")
	# A schedule that is not in the catalog is refused (it would be unauditable).
	var unlisted := _actor_data(&"actor_x", _schedule(&"schedule_unlisted", [
		{"activity": 0, "ticks": 2}]), HOME)
	assert_true(_registry.add(CharacterState.create_from_template(
		unlisted.character_template, unlisted.id)), "the character exists")
	assert_false(service.register_actor(unlisted),
		"an actor whose schedule is not in the catalog is refused")


# === 21. The sim_state derived cache ========================================

## `CharacterState.sim_state` is a CACHE of the simulation's own record, in the same
## relationship the sect roster has with `CharacterState.sect_id` (D-015): the record wins, a
## disagreement is REPORTED rather than trusted, and `sync` rebuilds the cache FROM the record.
func test_21_the_sim_cache_follows_the_record() -> void:
	var service := _world(_catalog())
	if service == null:
		return
	var elder: CharacterState = _registry.get_character(ELDER)
	assert_true(service.verify_character_caches(), "the caches start consistent")
	assert_eq(int(elder.sim_state.get("band", -1)), ActorScript.Band.NEAR,
		"the cache carries the band")

	elder.sim_state = {"band": 99, "activity": 99, "location_map_id": "lies"}
	assert_false(service.verify_character_caches(),
		"a drifted cache is DETECTED, not tolerated")
	service.sync_character_caches()
	assert_true(service.verify_character_caches(), "sync rebuilds the cache FROM the record")
	assert_eq(int(elder.sim_state.get("band", -1)), ActorScript.Band.NEAR,
		"and the record's value won")

extends TestCase
## Performance budget for the World Simulation (Phase 08).
##
## The architectural claim Phase 08 makes is that background cost is proportional to the
## OBSERVED population plus the due events — **not** to the whole cast
## (`docs/WORLD_SIMULATION.md` §6, `05-performance-testing.md`). That claim is the entire
## reason LOD exists, so it is measured rather than asserted in a comment.
##
## TWO ASSERTIONS, for two different failure modes:
##   1. **A relative SCALING assertion** (the real one): growing the FAR population tenfold
##      must not grow the per-tick cost anything like tenfold. If somebody replaces the
##      observed-actors walk with a full-cast walk, this is what catches it — and it catches it
##      on any hardware, because it compares the build against ITSELF.
##   2. **An absolute CEILING**, deliberately generous. CI hardware is shared and variable, so
##      a tight millisecond budget would be a flaky test that gets deleted rather than a guard
##      that gets respected. Its job is only to catch an accidental quadratic.
##
## The measured numbers are printed, so the figures recorded in `docs/PERFORMANCE.md` come from
## an actual run rather than from an estimate.

const ScheduleScript := preload("res://src/data/worldsim/world_sim_schedule_data.gd")
const ActorDataScript := preload("res://src/data/worldsim/world_sim_actor_data.gd")
const CatalogScript := preload("res://src/data/worldsim/world_sim_catalog.gd")
const ClockScript := preload("res://src/domain/worldsim/world_clock.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const StateScript := preload("res://src/domain/worldsim/world_sim_state.gd")
const ServiceScript := preload("res://src/domain/worldsim/world_sim_service.gd")

const RegistryScript := preload("res://src/domain/character/character_registry.gd")
const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

## Representative populations. 200 background characters is well beyond what the shipped world
## has and is the order `WORLD_SIMULATION.md` §1 is worried about ("hundreds of NPCs").
const SMALL_CAST := 20
const LARGE_CAST := 200
## Observed (NEAR+MID) actors, held CONSTANT across both runs — that is what isolates the
## variable under test: only the FAR population changes.
const OBSERVED := 10
const TICKS := 300

## Generous absolute ceiling (see the class note). It exists to catch a quadratic, not to tune.
const CEILING_MSEC := 4000

## How much slower the 10x-larger cast may be. An O(whole cast) loop would be ~10x; anything
## under this is consistent with the cost being driven by the OBSERVED set plus the fixed
## per-tick overhead. Set with room to spare precisely so it is not flaky.
const MAX_SCALING_FACTOR := 3.0

const HOME := &"map_home"
const AWAY := &"map_away"

var _registry: CharacterRegistry = null


func after_each() -> void:
	_registry = null


# --- fixture -----------------------------------------------------------------

func _schedule() -> WorldSimScheduleData:
	var phases: Array[Dictionary] = [
		{"activity": ScheduleScript.Activity.TRAINING, "ticks": 3},
		{"activity": ScheduleScript.Activity.MISSION, "ticks": 2},
		{"activity": ScheduleScript.Activity.RESTING, "ticks": 1},
	]
	var s: WorldSimScheduleData = ScheduleScript.new()
	s.id = &"schedule_perf"
	s.phases = phases
	return s


func _character_template() -> CharacterTemplateData:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var t: CharacterTemplateData = CharacterTemplateScript.new()
	t.id = &"char_perf"
	t.name_key = &"NAME"
	t.base_stats = stats
	return t


## A cast of `total` actors, of which the first `OBSERVED` live in the player's map (so they
## are NEAR) and the rest live somewhere unreachable (so they are FAR). No sect, no faction, no
## events: this measures the TICK LOOP, not the owning services' mutation paths, which are
## covered by the service tests.
func _catalog(total: int) -> WorldSimCatalog:
	var schedule := _schedule()
	var schedules: Array[WorldSimScheduleData] = [schedule]
	var actors: Array[WorldSimActorData] = []
	for i in total:
		var a: WorldSimActorData = ActorDataScript.new()
		a.id = StringName("actor_%04d" % i)
		a.character_template = _character_template()
		a.schedule = schedule
		a.home_map_id = HOME if i < OBSERVED else AWAY
		actors.append(a)
	var c: WorldSimCatalog = CatalogScript.new()
	c.ticks_per_hour = 1
	c.hours_per_day = 12
	c.days_per_season = 30
	c.seasons_per_year = 4
	c.ticks_per_map_transition = 1
	c.ticks_on_session_start = 0
	c.catch_up_budget_ticks = TICKS * 2  # measure the loop, not the catch-up bound
	c.event_log_capacity = 4
	c.schedules = schedules
	c.actors = actors
	return c


func _service(catalog: WorldSimCatalog) -> WorldSimulationService:
	_registry = RegistryScript.new()
	var clock: WorldClock = ClockScript.new(
		catalog.ticks_per_hour, catalog.hours_per_day,
		catalog.days_per_season, catalog.seasons_per_year)
	var rng: RngService = RngServiceScript.new(4242)
	var state: WorldSimulationState = StateScript.create(
		clock, rng, catalog.event_log_capacity)
	if state == null:
		return null
	var service: WorldSimulationService = ServiceScript.new(state, catalog)
	service.set_character_resolver(_registry.resolver())
	for actor_data in catalog.actors_sorted():
		var character := CharacterState.create_from_template(
			actor_data.character_template, actor_data.id)
		if character == null or not _registry.add(character):
			return null
		if not service.register_actor(actor_data):
			return null
	# Only HOME is the player's map and nothing is adjacent, so exactly OBSERVED actors are
	# NEAR and the rest are FAR.
	service.assign_bands(HOME, {})
	return service


## Advance `TICKS` ticks and return how many milliseconds it took.
func _measure(service: WorldSimulationService) -> int:
	var started := Time.get_ticks_msec()
	var processed := service.advance_ticks(TICKS)
	var elapsed := Time.get_ticks_msec() - started
	assert_eq(processed, TICKS, "the measured run actually processed every tick")
	return elapsed


# === The budget ==============================================================

## THE SCALING ASSERTION: a tenfold FAR population must not cost tenfold per tick.
func test_far_population_does_not_drive_per_tick_cost() -> void:
	var small := _service(_catalog(SMALL_CAST))
	assert_not_null(small, "the small world builds")
	if small == null:
		return
	assert_eq(small.get_state().observed_actors_sorted().size(), OBSERVED,
		"the small world has the expected observed set")
	var small_msec := _measure(small)
	after_each()

	var large := _service(_catalog(LARGE_CAST))
	assert_not_null(large, "the large world builds")
	if large == null:
		return
	var large_state := large.get_state()
	assert_eq(large_state.actor_count(), LARGE_CAST, "the large world really has %d actors"
		% LARGE_CAST)
	assert_eq(large_state.observed_actors_sorted().size(), OBSERVED,
		"with the SAME observed set, so only the FAR population differs")
	assert_eq(large_state.band_census()[WorldSimActor.Band.FAR], LARGE_CAST - OBSERVED,
		"and the rest are FAR")
	var large_msec := _measure(large)

	print(("[perf][worldsim] %d ticks: cast %d -> %d ms, cast %d -> %d ms "
		+ "(observed %d in both)")
		% [TICKS, SMALL_CAST, small_msec, LARGE_CAST, large_msec, OBSERVED])

	assert_true(large_msec <= CEILING_MSEC,
		("%d ticks over a cast of %d took %d ms, over the %d ms ceiling — that ceiling is "
			+ "deliberately generous, so exceeding it means the cost is superlinear")
			% [TICKS, LARGE_CAST, large_msec, CEILING_MSEC])

	# The ratio is only meaningful if the baseline is measurable at all; on a fast machine the
	# small run can round to 0 ms, in which case the ceiling above is the whole guard.
	if small_msec >= 2:
		var factor := float(large_msec) / float(small_msec)
		assert_true(factor <= MAX_SCALING_FACTOR,
			("a %dx larger FAR population cost %.2fx more per tick (%d ms -> %d ms). The "
				+ "per-tick loop must walk the OBSERVED actors plus the due events, not the "
				+ "whole cast — an O(cast) loop would show roughly %dx here")
				% [LARGE_CAST / SMALL_CAST, factor, small_msec, large_msec,
					LARGE_CAST / SMALL_CAST])


## A simulated cast costs ZERO nodes, in every band. This is the other half of the performance
## claim: "no `_process` on background actors" is only true because there are no background
## NODES at all (`docs/WORLD_SIMULATION.md` §6).
func test_a_large_cast_creates_no_nodes() -> void:
	var before: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var service := _service(_catalog(LARGE_CAST))
	assert_not_null(service, "the large world builds")
	if service == null:
		return
	service.advance_ticks(TICKS)
	var after: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	assert_eq(int(after), int(before),
		("simulating %d characters for %d ticks created ZERO nodes (%d -> %d); background "
			+ "characters are serializable state, not entities")
			% [LARGE_CAST, TICKS, int(before), int(after)])
	# And the state is intact after the long run (no actor lost or duplicated).
	assert_eq(service.get_state().actor_count(), LARGE_CAST, "every actor survived the run")
	assert_eq(service.get_state().tick(), TICKS, "and the clock advanced exactly K ticks")

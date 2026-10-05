extends TestCase
## Performance budget for combat (Phase 09).
##
## Combat is the first per-frame hot path in the game, and the two claims it makes are
## performance claims, so they are measured rather than asserted in a comment:
##
##   1. **An IDLE attacker costs nothing per frame.** `AttackComponent` disables its own
##      `_physics_process` in READY and only re-enables it for the duration of a swing. That
##      matters because every future NPC carries one: a hundred idle villagers must not cost a
##      hundred state-machine ticks a frame (`05-performance-testing.md`).
##   2. **Resolving a swing is LINEAR in candidates, and the expensive work is per HIT.** A
##      swing must look at every registered entity once — that is a broad-phase scan and there
##      is no index to avoid it — so a 10x registry legitimately costs ~10x. What must NOT
##      scale with the registry is the expensive part: no random draw, no allocation and no
##      full field validation per candidate.
##
##      THE FIRST VERSION OF THIS TEST ASSERTED "< 4x", which is a claim the design never
##      made, and it failed at 9x. The failure was still worth having: it showed that every
##      candidate was being fully type-validated before being rejected by distance, and
##      moving the two-field geometric reject in front of that made a swing against 400
##      entities 3x faster (PERF-002). The limit below is now stated as what linear MEANS,
##      with headroom — a quadratic scan would be ~100x and is what this actually catches.
##
## TWO KINDS OF ASSERTION, for two different failure modes — the same shape as the world-sim
## budget: a RELATIVE scaling assertion (the real guard, which compares the build against
## itself and therefore holds on any hardware) and a deliberately generous absolute CEILING
## whose only job is to catch an accidental quadratic. A tight millisecond budget on shared CI
## hardware is a flaky test that gets deleted rather than a guard that gets respected.
##
## The measured numbers are printed, so the figures in `docs/PERFORMANCE.md` come from a real
## run rather than from an estimate.

const AttackDataScript := preload("res://src/data/combat/attack_data.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")

const WORLD_SEED := 20261005

## Registry sizes. 400 is far beyond anything the shipped world has and is the order a busy
## town square would reach.
const SMALL_REGISTRY := 40
const LARGE_REGISTRY := 400
## Targets actually within reach, held CONSTANT across both runs — that is what isolates the
## variable under test: only the number of IRRELEVANT entities changes.
const IN_RANGE := 4
const SWINGS := 2000

## Generous absolute ceiling (see the class note); it catches a quadratic, not a regression of
## a few percent.
const CEILING_MSEC := 4000

## How much slower the 10x-larger registry may be. A LINEAR broad-phase scan is ~10x by
## definition, so this is 10x plus headroom for measurement noise on shared CI hardware. What
## it catches is a QUADRATIC scan (~100x) — e.g. a nested pass over targets, or a per-candidate
## lookup that itself walks the registry.
const MAX_SCALING := 13.0

## Microseconds per CANDIDATE that the broad-phase scan may cost. This is the assertion that
## replaces the mistaken "< 4x": linear is fine, but each step of the line must be CHEAP. At
## the measured ~0.17 µs/candidate a 400-entity registry costs a swing well under a tenth of a
## millisecond, so the limit is generous while still failing if full validation, an
## allocation or a string format creeps back in per candidate.
const MAX_USEC_PER_CANDIDATE := 1.5

## Idle frames to measure. 10 000 frames is ~3 minutes of real play at 60fps, so if an idle
## attacker cost anything measurable this would show it.
const IDLE_FRAMES := 10000


func _attack() -> AttackData:
	var attack: AttackData = AttackDataScript.new()
	attack.id = &"attack_perf"
	attack.windup_seconds = 0.10
	attack.active_seconds = 0.05
	attack.recovery_seconds = 0.20
	attack.reach_pixels = 32.0
	attack.arc_degrees = 180.0
	attack.power_multiplier = 1.0
	attack.critical_chance_percent = 25
	attack.critical_multiplier = 2.0
	return attack


func _service() -> CombatService:
	var rng: RngService = RngServiceScript.new(WORLD_SEED)
	return CombatService.new(rng.stream(RngService.STREAM_COMBAT))


## Build a target list: `in_range` entries beside the attacker, the rest scattered far away.
## Plain dictionaries rather than nodes, because this measures the RESOLUTION cost — adding
## nodes would measure the scene tree instead.
func _targets(total: int, in_range: int) -> Array:
	var out: Array = []
	for i in total:
		var near := i < in_range
		var position := Vector2(8.0, 0.0) if near else Vector2(5000.0 + float(i), 0.0)
		out.append(CombatService.make_target(
			StringName("t_%d" % i), position, 5, false, 6.0))
	return out


## An idle attacker must not tick. Measured through the SAME public surface the game uses
## (`is_physics_processing()`), because "I disabled processing" is only a claim until the
## engine agrees.
func test_an_idle_attacker_does_not_tick() -> void:
	var fighter := Node2D.new()
	add_to_tree(fighter)
	var component := AttackComponent.new()
	fighter.add_child(component)
	await scene_tree.process_frame

	assert_false(component.is_physics_processing(),
		"an UNARMED attacker does not run a physics callback at all")

	var registry := CombatHurtboxRegistry.new()
	assert_true(component.arm(_attack(), _service(), registry, &"attacker"), "it arms")
	await scene_tree.process_frame
	assert_false(component.is_physics_processing(),
		"an ARMED but idle attacker still does not tick — the clock starts with a swing")

	component.set_facing(Vector2.RIGHT)
	component.request_attack()
	assert_true(component.is_physics_processing(), "requesting a swing starts the clock")

	# Run the swing to completion and confirm the clock stops again. A component that stayed
	# enabled after one attack would turn every NPC that ever swung into a permanent per-frame
	# cost — the kind of leak that only shows up as a slow decline.
	component.advance(_attack().total_seconds() + 0.01)
	assert_false(component.is_physics_processing(),
		"and it stops again once the attack is over")

	# An idle component must also be CHEAP to advance by hand, since that is what the physics
	# callback would do: advancing a READY machine returns immediately.
	var started := Time.get_ticks_usec()
	for _i in IDLE_FRAMES:
		component.advance(1.0 / 60.0)
	var elapsed_msec := float(Time.get_ticks_usec() - started) / 1000.0
	print("[perf] %d idle advance() calls: %.2f ms" % [IDLE_FRAMES, elapsed_msec])
	assert_true(elapsed_msec < float(CEILING_MSEC),
		"%d idle advances stay far under the ceiling (%.2f ms)" % [IDLE_FRAMES, elapsed_msec])

	free_node(fighter)


## Resolving a swing must be LINEAR in candidates, CHEAP per candidate, and must not consume
## the random sequence per candidate.
##
## Three assertions because there are three different ways to get this wrong, and only the
## third one is about correctness as well as speed:
##   * scaling stays linear (a quadratic scan is ~100x and fails);
##   * each step of that line is cheap (full validation, an allocation or a string format per
##     candidate fails);
##   * the stream advances once per HIT, never per candidate — which is also a determinism
##     property: a crit sequence that depended on how many distant entities happened to be
##     registered would diverge on replay.
func test_a_swing_is_linear_and_cheap_per_candidate() -> void:
	var small_msec := _measure_swings(SMALL_REGISTRY)
	var large_msec := _measure_swings(LARGE_REGISTRY)
	print("[perf] %d swings | registry %d: %.2f ms | registry %d: %.2f ms" % [
		SWINGS, SMALL_REGISTRY, small_msec, LARGE_REGISTRY, large_msec])

	assert_true(large_msec < float(CEILING_MSEC),
		"%d swings against a %d-entity registry stay under the ceiling (%.2f ms)"
			% [SWINGS, LARGE_REGISTRY, large_msec])

	# Guard against a divide-by-zero on a fast machine where the small run rounds to 0.
	var baseline: float = maxf(small_msec, 0.5)
	var scaling: float = large_msec / baseline
	print("[perf] combat scaling factor for a 10x registry: %.2fx" % scaling)
	assert_true(scaling < MAX_SCALING,
		("a 10x registry must stay LINEAR (got %.2fx, limit %.2fx). Above this the scan is "
			+ "quadratic — a nested pass, or a per-candidate lookup that walks the registry.")
			% [scaling, MAX_SCALING])

	var usec_per_candidate := (large_msec * 1000.0) / float(SWINGS * LARGE_REGISTRY)
	print("[perf] broad-phase cost: %.3f us per candidate" % usec_per_candidate)
	assert_true(usec_per_candidate < MAX_USEC_PER_CANDIDATE,
		("each candidate must be CHEAP to reject (got %.3f us, limit %.3f us). Above this, "
			+ "full field validation, an allocation or a string format is running per "
			+ "candidate instead of per hit.") % [usec_per_candidate, MAX_USEC_PER_CANDIDATE])

	# The expensive, order-sensitive work is per HIT. One draw per hit, never per candidate.
	var rng: RngService = RngServiceScript.new(WORLD_SEED)
	var stream := rng.stream(RngService.STREAM_COMBAT)
	var counted := CombatService.new(stream)
	counted.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 50, _attack(),
		_targets(LARGE_REGISTRY, IN_RANGE))
	assert_eq(stream.draw_count(), IN_RANGE,
		("one random draw per HIT target (%d), not per registered candidate (%d) — got %d")
			% [IN_RANGE, LARGE_REGISTRY, stream.draw_count()])


## Resolve `SWINGS` hit passes against a registry of `total` entities, `IN_RANGE` of them
## within reach. Returns milliseconds.
func _measure_swings(total: int) -> float:
	var service := _service()
	var attack := _attack()
	var targets := _targets(total, IN_RANGE)
	var started := Time.get_ticks_usec()
	for _i in SWINGS:
		service.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 50, attack, targets)
	return float(Time.get_ticks_usec() - started) / 1000.0

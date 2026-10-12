extends TestCase
## Performance budget for enemy AI (Phase 10).
##
## Phase 10 makes two performance claims, and both are claims a test can hold to account:
##
##   1. **There is no per-frame AI thinking.** Movement runs every tick because motion must be
##      smooth; DECISIONS are throttled to each profile's `decision_interval`. So the decision
##      count over a known span must be ~`span / interval`, not ~`frames`.
##   2. **No enemy runs its own frame callback.** One session callback drives all of them, so
##      the cost of N enemies is one measurable number rather than N.
##
## Plus a deliberately generous absolute ceiling, whose only job is to catch an accidental
## quadratic (a per-enemy scan over all enemies, say). A tight millisecond budget on shared CI
## hardware is a flaky test that gets deleted rather than a guard that gets respected — the
## same reasoning as the world-sim and combat budgets.
##
## The measured numbers are printed, so the figures in `docs/PERFORMANCE.md` come from a real
## run rather than from an estimate.

const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const SpawnTableScript := preload("res://src/data/enemies/enemy_spawn_table_data.gd")
const ENEMY_PATH := "res://data/enemies/enemy_mist_wolf.tres"

const WORLD_SEED := 20261005

## Populations. 40 creatures in one map is far beyond anything the shipped field has and is
## the order a dungeon floor would reach.
const SMALL_CAST := 4
const LARGE_CAST := 40
## Frames to simulate, at 60fps.
const FRAMES := 1800          ## 30 seconds of play
const FRAME_DELTA := 1.0 / 60.0

## Generous absolute ceiling (see the class note).
const CEILING_MSEC := 6000

## A 10x cast may cost at most this much more. The tick is LINEAR in enemies by design — each
## one decides and moves independently — so ~10x is correct and this is 10x plus headroom.
## What it catches is a QUADRATIC tick (~100x): an enemy that scans all enemies, or a
## per-enemy registry walk.
const MAX_SCALING := 13.0


func _table(rows: int) -> EnemySpawnTableData:
	var table: EnemySpawnTableData = SpawnTableScript.new()
	table.map_id = &"map_field"
	var data := load(ENEMY_PATH) as EnemyData
	var enemies: Array[EnemyData] = []
	var positions := PackedVector2Array()
	for i in rows:
		enemies.append(data)
		# Spread them out so none starts inside another; the grid is arbitrary but
		# deterministic, which is what matters for a repeatable measurement.
		positions.append(Vector2(120 + (i % 8) * 90, 120 + int(i / 8.0) * 90))
	table.enemies = enemies
	table.positions = positions
	return table


func _runtime(rows: int) -> CombatRuntime:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(RngServiceScript.new(WORLD_SEED))
	runtime.spawn_from_table(_table(rows), runtime)
	return runtime


## No enemy may run its own frame callback, and an enemy-free session must not tick at all.
##
## This is the structural half of the claim: the scaling test below measures the cost, and this
## one proves the cost is concentrated in ONE place where it can be measured. A per-enemy
## `_physics_process` would still pass a timing assertion while making the cost invisible.
func test_no_enemy_runs_its_own_frame_callback() -> void:
	var runtime := _runtime(SMALL_CAST)
	for enemy in runtime.enemies():
		assert_false(enemy.is_physics_processing(),
			"the enemy body does not run its own physics callback")
		assert_false(enemy.ai().is_physics_processing(),
			"and neither does its AIComponent — the session drives every brain")
	assert_true(runtime.is_physics_processing(),
		"the SESSION ticks, so N enemies cost one callback instead of N")

	runtime.despawn_enemies()
	assert_false(runtime.is_physics_processing(),
		"and with nothing to tick it stops entirely — an enemy-free map costs nothing")
	free_node(runtime)


## Decisions are throttled; movement is not.
##
## Counted over a known span rather than inferred from the interval: "the code reads the
## interval" is not evidence that the interval is honoured.
func test_decisions_are_throttled_not_per_frame() -> void:
	await fixed_step()
	var runtime := _runtime(SMALL_CAST)
	var interval: float = (load(ENEMY_PATH) as EnemyData).ai_profile.decision_interval
	for _i in FRAMES:
		runtime.tick_enemies(FRAME_DELTA)
	var expected := int((FRAMES * FRAME_DELTA) / interval)
	for enemy in runtime.enemies():
		var decisions := enemy.ai().decisions()
		print("[perf][ai] %s: %d decisions over %d frames (expected ~%d)" % [
			enemy.instance_id(), decisions, FRAMES, expected])
		# A count anywhere near FRAMES means the AI is thinking every frame.
		assert_true(decisions <= expected + 2,
			("%d decisions for %.0fs at a %.2fs interval must be ~%d, not ~%d frames"
				% [decisions, FRAMES * FRAME_DELTA, interval, expected, FRAMES]))
		assert_true(decisions >= expected - 2,
			"and not fewer than expected (%d vs ~%d) — the brain must not stall"
				% [decisions, expected])
	free_node(runtime)


## The tick must be LINEAR in the population, and cheap per enemy per frame.
func test_the_ai_tick_is_linear_in_the_population() -> void:
	await fixed_step()
	var small_msec := _measure(SMALL_CAST)
	var large_msec := _measure(LARGE_CAST)
	print("[perf][ai] %d frames | cast %d: %.2f ms | cast %d: %.2f ms" % [
		FRAMES, SMALL_CAST, small_msec, LARGE_CAST, large_msec])

	assert_true(large_msec < float(CEILING_MSEC),
		"%d frames with %d enemies stay under the ceiling (%.2f ms)"
			% [FRAMES, LARGE_CAST, large_msec])

	var baseline: float = maxf(small_msec, 0.5)
	var scaling: float = large_msec / baseline
	print("[perf][ai] scaling factor for a 10x cast: %.2fx" % scaling)
	assert_true(scaling < MAX_SCALING,
		("a 10x cast must stay LINEAR (got %.2fx, limit %.2fx). Above this the tick is "
			+ "quadratic — an enemy scanning all enemies, or a per-enemy registry walk.")
			% [scaling, MAX_SCALING])

	var usec_per_enemy_frame := (large_msec * 1000.0) / float(FRAMES * LARGE_CAST)
	print("[perf][ai] %.3f us per enemy per frame" % usec_per_enemy_frame)
	assert_true(usec_per_enemy_frame < 12.0,
		("each enemy must be cheap per frame (got %.3f us). Most frames are movement only; "
			+ "a decision every frame would show up here.") % usec_per_enemy_frame)


## Tick `rows` enemies for `FRAMES` frames and return milliseconds.
func _measure(rows: int) -> float:
	var runtime := _runtime(rows)
	var started := Time.get_ticks_usec()
	for _i in FRAMES:
		runtime.tick_enemies(FRAME_DELTA)
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	free_node(runtime)
	return elapsed


## A large cast must create no NODES beyond the creatures themselves — no per-enemy timer, no
## per-decision allocation of a helper object. The orphan count is the cheapest honest proxy.
func test_a_large_cast_leaks_no_orphans_while_ticking() -> void:
	await fixed_step()
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var runtime := _runtime(LARGE_CAST)
	for _i in 600:
		runtime.tick_enemies(FRAME_DELTA)
	runtime.despawn_enemies()
	free_node(runtime)
	# `queue_free` resolves at the end of the frame, so one frame is awaited before counting.
	await scene_tree.process_frame
	var after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	print("[perf][ai] orphans %d -> %d across a %d-enemy spawn/tick/despawn cycle" % [
		int(before), int(after), LARGE_CAST])
	assert_true(after <= before,
		"ticking and despawning %d enemies leaves no orphan growth (%d -> %d)"
			% [LARGE_CAST, int(before), int(after)])


# === Walking round an obstacle (Q19-04) ======================================
#
# The casts above have no target, so they measure wandering. A creature that is PURSUING and
# finds something in its way makes one look-ahead query a tick while it walks round. This is
# that cost at its worst: every creature hunting a target shut inside a closed pen, so each
# one walks round the pen for the whole span and never gets to stop.

## The pen: four slabs round the target, far too small a gap for anything to enter.
const PEN := Rect2(560, 360, 80, 60)
const PEN_WALL := 8.0
## Per creature per frame while it walks round something. MEASURED at 12.8 us — about 2.7x a
## wandering creature (4.8 us), because it moves at full speed and adds one physics query a
## tick. The ceiling is ~3x the measurement, as loose as the others for the same reason: it is
## there to catch a second query, a search or a quadratic, not to time shared CI hardware. For
## scale: a whole cast of 40 doing nothing but this is 0.5 ms of a 16.6 ms frame.
const DETOUR_MAX_USEC := 40.0


class PennedTarget extends Node2D:
	func is_dead() -> bool:
		return false


class Pen extends RefCounted:
	var runtime: CombatRuntime
	var target: Node2D
	var walls: Array[Node] = []


func _pen(rows: int) -> Pen:
	var pen := Pen.new()
	for rect: Rect2 in [
		Rect2(PEN.position.x, PEN.position.y, PEN.size.x, PEN_WALL),
		Rect2(PEN.position.x, PEN.end.y - PEN_WALL, PEN.size.x, PEN_WALL),
		Rect2(PEN.position.x, PEN.position.y, PEN_WALL, PEN.size.y),
		Rect2(PEN.end.x - PEN_WALL, PEN.position.y, PEN_WALL, PEN.size.y),
	]:
		var wall := StaticBody2D.new()
		wall.collision_layer = CollisionLayers.WORLD
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		wall.add_child(shape)
		add_to_tree(wall)
		wall.global_position = rect.get_center()
		pen.walls.append(wall)
	pen.target = PennedTarget.new()
	add_to_tree(pen.target)
	pen.target.global_position = PEN.get_center()
	# The physics space takes the walls on its next step; nothing moves before it has them.
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	pen.runtime = CombatRuntimeScript.new()
	add_to_tree(pen.runtime)
	pen.runtime.start_session(RngServiceScript.new(WORLD_SEED))
	pen.runtime.set_hunt_target(pen.target)
	var table: EnemySpawnTableData = SpawnTableScript.new()
	table.map_id = &"map_field"
	var data := load(ENEMY_PATH) as EnemyData
	var enemies: Array[EnemyData] = []
	var positions := PackedVector2Array()
	for i in rows:
		enemies.append(data)
		# A ring round the pen, inside the detect radius, so every creature notices at once.
		var angle := TAU * float(i) / float(rows)
		positions.append(PEN.get_center() + Vector2(cos(angle), sin(angle)) * 120.0)
	table.enemies = enemies
	table.positions = positions
	pen.runtime.spawn_from_table(table, pen.runtime)
	# This test is the only clock (the awaits above would otherwise let the session tick too).
	pen.runtime.set_physics_process(false)
	return pen


func _free_pen(pen: Pen) -> void:
	pen.runtime.end_session()
	free_node(pen.runtime)
	free_node(pen.target)
	for wall in pen.walls:
		free_node(wall)


## Returns [milliseconds, look-aheads made by the whole cast, frames any creature stood still
## while chasing].
func _measure_pen(rows: int) -> Array:
	var pen := await _pen(rows)
	var enemies := pen.runtime.enemies()
	var last := PackedVector2Array()
	for enemy in enemies:
		last.append(enemy.global_position)
	var stalled := 0
	var started := Time.get_ticks_usec()
	for _i in FRAMES:
		pen.runtime.tick_enemies(FRAME_DELTA)
		for i in enemies.size():
			var at := enemies[i].global_position
			if enemies[i].ai_state_name() == "CHASE" and at.distance_to(last[i]) < 0.01:
				stalled += 1
			last[i] = at
	var msec := float(Time.get_ticks_usec() - started) / 1000.0
	var probes := 0
	for enemy in enemies:
		probes += (enemy.get_node("MovementComponent") as MovementComponent).detour_probes()
	_free_pen(pen)
	return [msec, probes, stalled]


## Walking round is BOUNDED WORK: never more than one look-ahead per creature per tick, linear
## in the cast, and under a per-creature ceiling of its own. It is also never a stall — a
## creature that cannot reach its target keeps moving round the thing in its way.
func test_walking_round_an_obstacle_is_one_query_a_tick_and_linear() -> void:
	var small: Array = await _measure_pen(SMALL_CAST)
	var large: Array = await _measure_pen(LARGE_CAST)
	var small_msec := float(small[0])
	var large_msec := float(large[0])
	var probes := int(large[1])
	print("[perf][ai-detour] %d frames penned | cast %d: %.2f ms | cast %d: %.2f ms" % [
		FRAMES, SMALL_CAST, small_msec, LARGE_CAST, large_msec])
	print("[perf][ai-detour] %d look-aheads by %d creatures (%.2f per creature per frame)" % [
		probes, LARGE_CAST, float(probes) / float(FRAMES * LARGE_CAST)])

	assert_true(probes > FRAMES * LARGE_CAST / 2,
		"the staging really holds the cast in a detour (%d look-aheads)" % probes)
	assert_true(probes <= FRAMES * LARGE_CAST,
		"at most ONE look-ahead per creature per tick (%d in %d creature-frames)"
			% [probes, FRAMES * LARGE_CAST])
	assert_true(large_msec < float(CEILING_MSEC),
		"%d frames with %d creatures walking round stay under the ceiling (%.2f ms)"
			% [FRAMES, LARGE_CAST, large_msec])
	var scaling: float = large_msec / maxf(small_msec, 0.5)
	print("[perf][ai-detour] scaling factor for a 10x cast: %.2fx" % scaling)
	assert_true(scaling < MAX_SCALING,
		"a 10x cast walking round stays LINEAR (got %.2fx, limit %.2fx)"
			% [scaling, MAX_SCALING])
	var usec_per_enemy_frame := (large_msec * 1000.0) / float(FRAMES * LARGE_CAST)
	print("[perf][ai-detour] %.3f us per creature per frame" % usec_per_enemy_frame)
	assert_true(usec_per_enemy_frame < DETOUR_MAX_USEC,
		"and each creature stays cheap per frame while it walks round (got %.3f us, limit %.0f)"
			% [usec_per_enemy_frame, DETOUR_MAX_USEC])
	# One still frame when a creature first runs into a wall or turns a corner is the rule
	# finding out; a creature at rest against the pen would add ~1800 of them on its own.
	var stalled := int(large[2])
	print("[perf][ai-detour] %d still chase-frames across the cast" % stalled)
	assert_true(stalled < LARGE_CAST * 30,
		"nothing comes to rest against the pen (%d still chase-frames for %d creatures)"
			% [stalled, LARGE_CAST])

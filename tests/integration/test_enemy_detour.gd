extends TestCase
## Integration tests for PURSUIT ROUND AN OBSTACLE (Q19-04): a REAL `CombatRuntime` session,
## REAL Vụ Lang built from the shipped `.tres`, the REAL prop footprints the field map stands on
## (`WorldProp` + `PropData`), and the real physics space — `AIComponent` → `MovementComponent`
## → `move_and_slide`, with no stand-in for any of them.
##
## THE BUG THESE PIN. A creature pursued in a straight line. Against a solid face
## `move_and_slide` slides a body by the part of its velocity that lies along the face, and for
## a pursuer that part points at the target's own row: the slide carries it to where the target
## is dead ahead through the obstacle, and there it is zero. Measured before the fix, on a pine
## trunk with the target 96 px away: started 0, 0.01, 0.5 and 2 px off the target's row, the
## creature came to rest against the trunk at the same x every time, in CHASE, velocity zero,
## for the whole 20 s run. A stable resting point, so "stand behind a tree" was a safe spot.
##
## STEPPING. AI is ticked with exact 1/60 s deltas, which is also the step `move_and_slide`
## integrates over, so a frame here is a frame in the game. Solids are added first and two
## physics frames awaited, so the space holds them before anything moves; after that every
## run is synchronous and the session's own callback is switched off, so nothing else ticks.

const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const SpawnTableScript := preload("res://src/data/enemies/enemy_spawn_table_data.gd")
const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")
const MovementScript := preload("res://src/gameplay/components/movement_component.gd")
const PetScene := preload("res://src/gameplay/entities/pet.tscn")

const ENEMY_PATH := "res://data/enemies/enemy_mist_wolf.tres"
const PET_PATH := "res://data/pets/pet_hoang_khuyen.tres"
const PINE := "res://data/world/props/pine.tres"
const PINE_SMALL := "res://data/world/props/pine_small.tres"
const ROCK := "res://data/world/props/prop_rock.tres"
const WORLD_SEED := 20261005
const FRAME := 1.0 / 60.0

## Where the obstacle stands in every staging; creatures and targets are placed around it.
const TRUNK := Vector2(400, 300)
## How far each side starts from the obstacle. 2 x 48 is the 96 px the playtest stages
## (`tools/playtest_flow.gd`, step 19), which is the arrangement the bug was seen in.
const HALF_GAP := 48.0
## A creature that is pursuing and not yet in reach may be motionless for this many frames in a
## row: the frame it first meets the surface (it finds out by running into it). The stall this
## file exists for was 1100+.
const MAX_STILL_FRAMES := 2


## A stand-in player that is SOLID and can be HIT: the creature collides with the real player
## body, so a target with no shape would let it walk through and prove nothing about arriving.
class TestPlayer extends CharacterBody2D:
	var hp: int = 100

	func get_attack_power() -> int:
		return 20

	func get_defense() -> int:
		return 3

	func get_current_health() -> int:
		return hp

	func is_dead() -> bool:
		return hp <= 0

	func take_damage(amount: int) -> int:
		if hp <= 0 or amount <= 0:
			return 0
		var before := hp
		hp = maxi(0, hp - amount)
		return before - hp


class Owner extends Node2D:
	func is_dead() -> bool:
		return false


## One staged arrangement, built and freed together.
class Stage extends RefCounted:
	var runtime: CombatRuntime
	var player: TestPlayer
	var solids: Array[Node] = []
	var swings: Array[AttackComponent] = []


## What one creature did over a run, frame by frame.
class Trace extends RefCounted:
	var positions := PackedVector2Array()
	var first_swing_frame := -1
	var first_bite_frame := -1
	var longest_still := 0
	var hands: Array[int] = []
	var states := {}
	var farthest_from_home := 0.0
	## Frames it walked round something while FACING somewhere else.
	var misfaced := 0
	## Frames a way round was still held although the brain was no longer pursuing.
	var held_while_not_pursuing := 0


func _prop(path: String, at: Vector2) -> WorldProp:
	var prop := WorldProp.new()
	prop.prop = load(path) as PropData
	add_to_tree(prop)
	prop.global_position = at
	return prop


## A plain solid slab on the world layer — the map's edge, or a wall.
func _slab(rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	add_to_tree(body)
	body.global_position = rect.get_center()
	return body


func _player(at: Vector2) -> TestPlayer:
	var player := TestPlayer.new()
	player.name = "TestPlayer"
	player.collision_layer = CollisionLayers.PLAYER
	player.collision_mask = CollisionLayers.WORLD | CollisionLayers.DUMMY
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(18, 12)  # `player.tscn`
	shape.shape = box
	shape.position = Vector2(0, -6)
	player.add_child(shape)
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"test_player"
	hurtbox.radius = 10.0
	player.add_child(hurtbox)
	add_to_tree(player)
	player.global_position = at
	return player


## Stage `solids` (already in the tree), a player and one creature per entry of `dens`.
func _stage(solids: Array[Node], player_at: Vector2, dens: PackedVector2Array,
		data: EnemyData = null) -> Stage:
	var stage := Stage.new()
	stage.solids = solids
	stage.player = _player(player_at)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	stage.runtime = CombatRuntimeScript.new()
	add_to_tree(stage.runtime)
	stage.runtime.start_session(RngServiceScript.new(WORLD_SEED))
	stage.runtime.register_target(stage.player)
	stage.runtime.set_hunt_target(stage.player)
	var table: EnemySpawnTableData = SpawnTableScript.new()
	table.map_id = &"map_field"
	var enemies: Array[EnemyData] = []
	for _i in dens.size():
		enemies.append(data if data != null else load(ENEMY_PATH) as EnemyData)
	table.enemies = enemies
	table.positions = dens
	assert_eq(stage.runtime.spawn_from_table(table, stage.runtime), dens.size(), "all spawn")
	# The test is the only clock: the session's own physics callback would tick the same
	# creatures again on the frames the runner awaits between tests.
	stage.runtime.set_physics_process(false)
	for enemy in stage.runtime.enemies():
		stage.swings.append(enemy.get_node("AttackComponent") as AttackComponent)
	return stage


func _free(stage: Stage) -> void:
	stage.runtime.end_session()
	free_node(stage.runtime)
	free_node(stage.player)
	for solid in stage.solids:
		free_node(solid)


## Advance the whole stage `frames` frames (stopping early once `stop_on_bite` is satisfied) and
## return what creature `index` did.
func _run(stage: Stage, frames: int, index: int = 0, stop_on_bite: bool = true) -> Trace:
	var trace := Trace.new()
	var enemy := stage.runtime.enemies()[index]
	var movement := enemy.get_node("MovementComponent") as MovementComponent
	var home := enemy.global_position
	var engage := enemy.data().engage_distance
	var hp_before := stage.player.hp
	var still := 0
	for frame in frames:
		var before := enemy.global_position
		stage.runtime.tick_enemies(FRAME)
		# The swing runs on the same clock, so a requested bite can land (L-016).
		for swing in stage.swings:
			swing.advance(FRAME)
		var state := enemy.ai_state_name()
		trace.positions.append(enemy.global_position)
		trace.states[state] = true
		trace.farthest_from_home = maxf(trace.farthest_from_home,
			enemy.global_position.distance_to(home))
		var hand := movement.detour_hand()
		if hand != 0 and (trace.hands.is_empty() or trace.hands[-1] != hand):
			trace.hands.append(hand)
		var step := enemy.global_position - before
		if hand != 0 and step.length() > 0.5 \
				and stage.swings[index].facing().dot(step.normalized()) < 0.99:
			trace.misfaced += 1
		if hand != 0 and not state in ["CHASE", "RETURN"]:
			trace.held_while_not_pursuing += 1
		var gap := enemy.global_position.distance_to(stage.player.global_position)
		var pursuing := state == "CHASE" and gap > engage
		still = still + 1 if pursuing and enemy.global_position.distance_to(before) < 0.01 else 0
		trace.longest_still = maxi(trace.longest_still, still)
		if state == "ATTACK" and trace.first_swing_frame < 0:
			trace.first_swing_frame = frame
		if stage.player.hp < hp_before and trace.first_bite_frame < 0:
			trace.first_bite_frame = frame
			if stop_on_bite:
				break
	return trace


## Tick until `enemy` has gone home and come to rest there (RETURN, then IDLE). Returns the
## frame it rested on, or -1. It stops THERE on purpose: a creature at home idles and then
## wanders off on patrol, so "where is it at the end of the budget" measures the patrol.
func _walk_home(stage: Stage, enemy: Enemy, frames: int) -> int:
	var returning := false
	for frame in frames:
		stage.runtime.tick_enemies(FRAME)
		for swing in stage.swings:
			swing.advance(FRAME)
		var state := enemy.ai_state_name()
		returning = returning or state == "RETURN"
		if returning and state == "IDLE":
			return frame
	return -1


func _body_size(enemy: Node) -> Vector2:
	return ((enemy.get_node("CollisionShape2D") as CollisionShape2D).shape
		as RectangleShape2D).size


## THE BUDGET, from authored numbers only — nothing here is tuned to make a run pass.
##
##   route  = the straight gap + `half_laps` x half the perimeter of the obstacle grown by the
##            creature's own body (the most a walk round one side of a convex footprint adds;
##            a way that turns out to be shut costs a lap there and back, so three)
##   time   = the profile's notice pause + route at the authored chase speed + the bite's
##            windup and active window + three decisions (notice, chase, swing), each of which
##            can wait a full `decision_interval`
func _budget_frames(enemy: Enemy, straight_px: float, footprint: Vector2,
		half_laps: int = 1) -> int:
	var data := enemy.data()
	var profile := data.ai_profile
	var body := _body_size(enemy)
	var route := straight_px + float(half_laps) * (footprint.x + body.x + footprint.y + body.y)
	var seconds := profile.alert_seconds \
		+ route / (data.stats.move_speed * profile.chase_speed_scale) \
		+ data.attack.windup_seconds + data.attack.active_seconds \
		+ 3.0 * profile.decision_interval
	return ceili(seconds / FRAME)


func _footprint(path: String) -> Vector2:
	return (load(path) as PropData).footprint.size


# === The reproduction =======================================================

## THE BUG, exactly as measured: a trunk on the line, the target on the creature's own row and
## a hair off it. Before the fix every one of these rested against the trunk for the whole run.
func test_a_creature_walks_round_a_trunk_that_stands_on_its_line() -> void:
	for offset: float in [0.0, 0.01, 0.5, 2.0, -0.5, -2.0]:
		var solids: Array[Node] = [_prop(PINE, TRUNK)]
		var stage := await _stage(solids, TRUNK + Vector2(HALF_GAP, offset),
			PackedVector2Array([TRUNK - Vector2(HALF_GAP, 0)]))
		var enemy := stage.runtime.enemies()[0]
		var budget := _budget_frames(enemy, 2.0 * HALF_GAP, _footprint(PINE))
		var trace := _run(stage, budget)
		assert_true(trace.first_bite_frame >= 0,
			"offset %.2f: it reached the player and bit within %d frames (state %s, %.1f px away)"
			% [offset, budget, enemy.ai_state_name(),
				enemy.global_position.distance_to(stage.player.global_position)])
		assert_true(trace.longest_still <= MAX_STILL_FRAMES,
			"offset %.2f: while chasing out of reach it never stood still (%d frames in a row)"
			% [offset, trace.longest_still])
		assert_true(trace.hands.size() <= 1,
			"offset %.2f: it chose ONE way round and kept it, got %s" % [offset, trace.hands])
		assert_eq(trace.misfaced, 0,
			"offset %.2f: it faces the way it is walking, not through the trunk" % offset)
		_free(stage)


## Every side, and every footprint the field stands on: a rectangle trunk, the small pine, and
## the round rock (a 16-point convex rim, so the surface normal turns under the creature).
func test_it_goes_round_every_field_footprint_from_every_side() -> void:
	for path: String in [PINE, PINE_SMALL, ROCK]:
		for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var solids: Array[Node] = [_prop(path, TRUNK)]
			var stage := await _stage(solids, TRUNK - side * HALF_GAP,
				PackedVector2Array([TRUNK + side * HALF_GAP]))
			var enemy := stage.runtime.enemies()[0]
			var budget := _budget_frames(enemy, 2.0 * HALF_GAP, _footprint(path))
			var trace := _run(stage, budget)
			var label := "%s from %s" % [path.get_file(), side]
			assert_true(trace.first_bite_frame >= 0,
				"%s: bit within %d frames (state %s, %.1f px away)" % [label, budget,
					enemy.ai_state_name(),
					enemy.global_position.distance_to(stage.player.global_position)])
			assert_true(trace.longest_still <= MAX_STILL_FRAMES,
				"%s: never stood still while chasing (%d frames)" % [label, trace.longest_still])
			assert_true(trace.hands.size() <= 1, "%s: one way round, got %s"
				% [label, trace.hands])
			_free(stage)


## From ANY direction, not only along a row or a column: sixteen bearings through the trunk.
## At a slant the creature first slides (a glancing touch) and only then meets the face
## squarely, so this is also the hand-over between the two — a gap there would be a bearing
## at which it rests against the trunk after all.
func test_it_goes_round_from_every_bearing() -> void:
	var reach := 56.0
	for step in 16:
		var bearing := Vector2.RIGHT.rotated(TAU * float(step) / 16.0)
		var solids: Array[Node] = [_prop(PINE, TRUNK)]
		var stage := await _stage(solids, TRUNK + bearing * reach,
			PackedVector2Array([TRUNK - bearing * reach]))
		var enemy := stage.runtime.enemies()[0]
		var budget := _budget_frames(enemy, 2.0 * reach, _footprint(PINE))
		var trace := _run(stage, budget)
		assert_true(trace.first_bite_frame >= 0,
			"bearing %d/16: bit within %d frames (state %s, %.1f px away)" % [step, budget,
				enemy.ai_state_name(),
				enemy.global_position.distance_to(stage.player.global_position)])
		assert_true(trace.longest_still <= MAX_STILL_FRAMES,
			"bearing %d/16: never stood still while chasing (%d frames)"
			% [step, trace.longest_still])
		assert_true(trace.hands.size() <= 1,
			"bearing %d/16: one way round, got %s" % [step, trace.hands])
		_free(stage)


## It walks ROUND: the body never enters the footprint it is avoiding. A fix that reached the
## player by switching collision off, or by stepping through, would pass every test above.
func test_the_way_round_never_passes_through_the_obstacle() -> void:
	var solids: Array[Node] = [_prop(PINE, TRUNK)]
	var stage := await _stage(solids, TRUNK + Vector2(HALF_GAP, 0),
		PackedVector2Array([TRUNK - Vector2(HALF_GAP, 0)]))
	var enemy := stage.runtime.enemies()[0]
	var trace := _run(stage, _budget_frames(enemy, 2.0 * HALF_GAP, _footprint(PINE)))
	var foot := (load(PINE) as PropData).footprint
	var trunk := Rect2(TRUNK + foot.position, foot.size)
	var body := _body_size(enemy)
	var shape_offset := (enemy.get_node("CollisionShape2D") as CollisionShape2D).position
	var deepest := 0.0
	var went_round := false
	for at in trace.positions:
		var rect := Rect2(at + shape_offset - body * 0.5, body)
		var overlap := rect.intersection(trunk)
		deepest = maxf(deepest, minf(overlap.size.x, overlap.size.y))
		# Round means it was, at some point, wholly above or wholly below the trunk while
		# level with it — not merely that it ended on the far side.
		if rect.position.x < trunk.end.x and rect.end.x > trunk.position.x \
				and (rect.end.y <= trunk.position.y or rect.position.y >= trunk.end.y):
			went_round = true
	assert_true(trace.first_bite_frame >= 0, "it arrived")
	assert_true(deepest < 0.1, "its body never overlapped the trunk (deepest %.3f px)" % deepest)
	assert_true(went_round, "and it passed beside the trunk, level with it")
	_free(stage)


## The same meeting resolves the same way, every time: an exact head-on tie takes the default
## hand (a constant, no draw from any stream), and two runs are identical frame for frame.
func test_a_head_on_tie_is_resolved_the_same_way_every_time() -> void:
	var runs: Array[PackedVector2Array] = []
	for _run_index in 2:
		var solids: Array[Node] = [_prop(PINE, TRUNK)]
		var stage := await _stage(solids, TRUNK + Vector2(HALF_GAP, 0),
			PackedVector2Array([TRUNK - Vector2(HALF_GAP, 0)]))
		var enemy := stage.runtime.enemies()[0]
		var trace := _run(stage, _budget_frames(enemy, 2.0 * HALF_GAP, _footprint(PINE)))
		assert_eq(trace.hands, [MovementScript.DETOUR_DEFAULT_HAND] as Array[int],
			"dead ahead and level, it takes the default hand")
		runs.append(trace.positions)
		_free(stage)
	assert_eq(runs[0], runs[1], "the same staging replays to the same positions, every frame")


## THE PLAYER HIDES RIGHT BEHIND THE TRUNK, touching it. The creature comes into reach while
## the trunk is still in its way, so the swing is decided with a way round still held: it must
## let go (a new intent is a new errand) and bite, not carry on round the player.
func test_a_target_flush_behind_the_trunk_is_bitten_not_circled() -> void:
	var foot := (load(PINE) as PropData).footprint
	var solids: Array[Node] = [_prop(PINE, TRUNK)]
	# The player's body starts 0.5 px off the trunk's far face.
	var flush := TRUNK + Vector2(foot.end.x + 9.0 + 0.5, 0)
	var stage := await _stage(solids, flush, PackedVector2Array([TRUNK - Vector2(HALF_GAP, 0)]))
	var enemy := stage.runtime.enemies()[0]
	var straight := enemy.global_position.distance_to(flush)
	var trace := _run(stage, _budget_frames(enemy, straight, _footprint(PINE)), 0, false)
	assert_true(trace.first_bite_frame >= 0, "it bit the player behind the trunk (%.1f px away)"
		% enemy.global_position.distance_to(flush))
	assert_eq(trace.held_while_not_pursuing, 0,
		"and holds no way round once it stops pursuing (swing, recover)")
	assert_true(trace.longest_still <= MAX_STILL_FRAMES,
		"never stood still while chasing (%d frames)" % trace.longest_still)
	_free(stage)


## ARRIVING IS NOT AN OBSTACLE, at the seam itself. The goal stands at the trunk's corner, so
## the step that clears the trunk is the step that reaches the goal: the look-ahead, with a way
## round still held, touches the GOAL. That is arriving. With no brain to call a halt, the
## pursuit must come to rest there; reading the goal's body as "something in the way" keeps
## the hand and walks on round the goal — an orbit that never ends.
func test_a_pursuit_comes_to_rest_against_its_goal_and_never_orbits_it() -> void:
	var foot := (load(PINE) as PropData).footprint
	var trunk := _prop(PINE, TRUNK)
	# Standing on the trunk's top edge, its near side 2.6 px past the trunk's west face.
	var goal := _player(TRUNK + Vector2(6.0, foot.position.y - 0.1))
	var pursuer := CharacterBody2D.new()
	pursuer.collision_layer = CollisionLayers.DUMMY
	pursuer.collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(18, 12)  # `enemy.tscn`
	shape.shape = box
	shape.position = Vector2(0, -4)
	pursuer.add_child(shape)
	var movement: MovementComponent = MovementScript.new()
	pursuer.add_child(movement)
	add_to_tree(pursuer)
	pursuer.global_position = TRUNK - Vector2(HALF_GAP, 0)
	movement.setup(pursuer)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	var speed := (load(ENEMY_PATH) as EnemyData).stats.move_speed
	var frames := 360
	var path := PackedVector2Array()
	var took_a_hand := false
	for _frame in frames:
		movement.apply_pursuit(goal.global_position - pursuer.global_position, speed, FRAME,
			goal)
		took_a_hand = took_a_hand or movement.detour_hand() != 0
		path.append(pursuer.global_position)
	var wandered := 0.0
	for i in range(frames - 180, frames - 1):
		wandered += path[i].distance_to(path[i + 1])
	assert_true(took_a_hand, "the trunk was in the way, and it walked up its face")
	assert_true(wandered < 1.0,
		"it rests against its goal instead of circling it (%.1f px in the last 3 s)" % wandered)
	assert_eq(movement.detour_hand(), 0, "holding no way round")
	assert_true(pursuer.global_position.distance_to(goal.global_position) < 24.0,
		"touching it (%.1f px between them)"
		% pursuer.global_position.distance_to(goal.global_position))
	free_node(pursuer)
	free_node(goal)
	free_node(trunk)


# === What it must still obey ================================================

## THE MAP'S EDGE IS NOT AN OBSTACLE TO WALK ROUND. Chasing along a wall touches it at a
## glance; sliding already handles that, so no way round is taken and no query is made — and
## the creature stays inside the wall the whole way.
func test_chasing_along_the_edge_slides_and_takes_no_way_round() -> void:
	var edge := Rect2(TRUNK.x - 200.0, TRUNK.y + 10.0, 400.0, 16.0)
	var solids: Array[Node] = [_slab(edge)]
	# Both stand close to the edge. The creature's body reaches 2 px lower than the player's,
	# so a straight chase toward a player standing against the edge runs it into the edge
	# two thirds of the way there, at a shallow angle.
	var stage := await _stage(solids, Vector2(TRUNK.x + HALF_GAP, edge.position.y - 0.1),
		PackedVector2Array([Vector2(TRUNK.x - HALF_GAP, edge.position.y - 3.0)]))
	var enemy := stage.runtime.enemies()[0]
	var movement := enemy.get_node("MovementComponent") as MovementComponent
	var trace := _run(stage, _budget_frames(enemy, 2.0 * HALF_GAP, Vector2.ZERO, 0))
	var body := _body_size(enemy)
	var shape_offset := (enemy.get_node("CollisionShape2D") as CollisionShape2D).position
	var deepest := 0.0
	var touched := false
	for at in trace.positions:
		var rect := Rect2(at + shape_offset - body * 0.5, body)
		touched = touched or rect.end.y > edge.position.y - 0.5
		var overlap := rect.intersection(edge)
		deepest = maxf(deepest, minf(overlap.size.x, overlap.size.y))
	assert_true(touched, "the chase really did run along the edge")
	assert_true(trace.first_bite_frame >= 0, "and it reached the player")
	assert_true(deepest < 0.1, "without entering the edge (deepest %.3f px)" % deepest)
	assert_eq(trace.hands, [] as Array[int], "a glancing touch takes no way round")
	assert_eq(movement.detour_probes(), 0, "and costs no look-ahead")
	_free(stage)



## The chosen way is SHUT (a wall a hair above the trunk — the map's edge behind a tree). It
## turns back once and goes round the other side; it does not grind into the corner.
func test_a_way_round_that_is_shut_is_reversed_once() -> void:
	var foot := (load(PINE) as PropData).footprint
	var row := TRUNK.y + 8.0
	# Its bottom edge sits 1.7 px above the trunk's top: nothing 12 px tall fits between.
	var wall := Rect2(TRUNK.x - 120.0, TRUNK.y + foot.position.y - 1.7 - 16.0, 240.0, 16.0)
	var solids: Array[Node] = [_prop(PINE, TRUNK), _slab(wall)]
	var stage := await _stage(solids, Vector2(TRUNK.x + HALF_GAP, row),
		PackedVector2Array([Vector2(TRUNK.x - HALF_GAP, row)]))
	var enemy := stage.runtime.enemies()[0]
	var budget := _budget_frames(enemy, 2.0 * HALF_GAP, _footprint(PINE), 3)
	var trace := _run(stage, budget)
	var hand := MovementScript.DETOUR_DEFAULT_HAND
	assert_eq(trace.hands, [hand, -hand] as Array[int],
		"the default hand led into the wall, so it reversed — once")
	assert_true(trace.first_bite_frame >= 0,
		"and reached the player the other way within %d frames (%.1f px away)" % [budget,
			enemy.global_position.distance_to(stage.player.global_position)])
	var deepest := 0.0
	var body := _body_size(enemy)
	var shape_offset := (enemy.get_node("CollisionShape2D") as CollisionShape2D).position
	for at in trace.positions:
		var overlap := Rect2(at + shape_offset - body * 0.5, body).intersection(wall)
		deepest = maxf(deepest, minf(overlap.size.x, overlap.size.y))
	assert_true(deepest < 0.1, "it never entered the wall (deepest %.3f px)" % deepest)
	_free(stage)


## THE STATED LIMIT, pinned so it cannot silently become something worse. Shut on BOTH sides
## (a trunk plugging a corridor) there is no way round a single obstacle, and finding another
## route is navigation, which this is not. What it must NOT do is pace: one reversal, then it
## rests; the work stays bounded; and the brain is still in charge — lose the target and it
## goes home.
func test_a_pocket_shut_on_both_sides_is_rested_in_not_paced() -> void:
	var foot := (load(PINE) as PropData).footprint
	var row := TRUNK.y + 8.0
	var above := Rect2(TRUNK.x - 120.0, TRUNK.y + foot.position.y - 1.7 - 16.0, 240.0, 16.0)
	# 8.7 px below the trunk: again less than the body is tall.
	var below := Rect2(TRUNK.x - 120.0, TRUNK.y + foot.end.y + 8.7, 240.0, 16.0)
	var solids: Array[Node] = [_prop(PINE, TRUNK), _slab(above), _slab(below)]
	var den := Vector2(TRUNK.x - HALF_GAP, row)
	var stage := await _stage(solids, Vector2(TRUNK.x + HALF_GAP, row),
		PackedVector2Array([den]))
	var enemy := stage.runtime.enemies()[0]
	var movement := enemy.get_node("MovementComponent") as MovementComponent
	var frames := 600
	var trace := _run(stage, frames)
	assert_eq(trace.first_bite_frame, -1, "the player is out of reach, and stays unbitten")
	assert_true(trace.hands.size() <= 2,
		"it tried the other side once and no more, got %s" % [trace.hands])
	var paced := 0.0
	for i in range(frames - 300, frames - 1):
		paced += trace.positions[i].distance_to(trace.positions[i + 1])
	assert_true(paced < 1.0, "it rests in the pocket instead of pacing (%.2f px in 5 s)" % paced)
	assert_true(movement.detour_probes() <= frames,
		"at most one look-ahead a tick (%d in %d)" % [movement.detour_probes(), frames])

	stage.runtime.set_hunt_target(null)
	var home_frames := ceili((HALF_GAP / (enemy.data().stats.move_speed
		* enemy.data().ai_profile.effective_return_speed_scale())
		+ 2.0 * enemy.data().ai_profile.decision_interval) / FRAME)
	assert_true(_walk_home(stage, enemy, home_frames) >= 0,
		"with the target gone it stopped hunting (state %s)" % enemy.ai_state_name())
	assert_true(enemy.global_position.distance_to(den)
			<= enemy.data().ai_profile.home_arrival_radius,
		"and walked home (%.1f px from its den)"
		% enemy.global_position.distance_to(den))
	_free(stage)


## THE LEASH STILL OUTRANKS THE HUNT. With a leash that trips part-way round the trunk, the
## creature turns for home instead of finishing the detour.
func test_the_leash_still_ends_a_pursuit_that_is_walking_round() -> void:
	var data := (load(ENEMY_PATH) as EnemyData).duplicate() as EnemyData
	data.ai_profile = data.ai_profile.duplicate() as AiProfileData
	# The trunk's near face is 41.4 px from the den; 45 trips just past its corner.
	data.ai_profile.leash_radius = 45.0
	assert_true(data.is_valid(), "the short-leash copy is still valid content")
	var solids: Array[Node] = [_prop(PINE, TRUNK)]
	var stage := await _stage(solids, TRUNK + Vector2(HALF_GAP, 0),
		PackedVector2Array([TRUNK - Vector2(HALF_GAP, 0)]), data)
	var trace := _run(stage, 600)
	# It only finds out at a DECISION, so it can overshoot by what it covers in one interval.
	var overshoot := data.stats.move_speed * data.ai_profile.chase_speed_scale \
		* (data.ai_profile.decision_interval + FRAME)
	assert_eq(trace.first_bite_frame, -1, "the player stands beyond the leash and is not bitten")
	assert_true(trace.states.has("RETURN"), "it turned for home, got %s" % [trace.states.keys()])
	assert_true(trace.farthest_from_home <= data.ai_profile.leash_radius + overshoot,
		"and never strayed past leash + one decision (%.1f <= %.1f)"
		% [trace.farthest_from_home, data.ai_profile.leash_radius + overshoot])
	_free(stage)


## HOME IS PURSUED THE SAME WAY. A creature that has gone round a trunk and then loses its
## target has that trunk between it and its den; before the fix RETURN stalled exactly as CHASE
## did, and a creature stuck in RETURN never looks at the player again.
func test_it_walks_home_round_the_trunk_when_the_target_is_lost() -> void:
	var solids: Array[Node] = [_prop(PINE, TRUNK)]
	var den := TRUNK - Vector2(HALF_GAP, 0)
	var stage := await _stage(solids, TRUNK + Vector2(HALF_GAP, 0), PackedVector2Array([den]))
	var enemy := stage.runtime.enemies()[0]
	var profile := enemy.data().ai_profile
	var out := _run(stage, _budget_frames(enemy, 2.0 * HALF_GAP, _footprint(PINE)))
	assert_true(out.first_bite_frame >= 0, "it went round and bit")
	assert_true(enemy.global_position.x > TRUNK.x, "so it is now on the far side of the trunk")

	stage.runtime.set_hunt_target(null)
	var foot := _footprint(PINE)
	var body := _body_size(enemy)
	var route := enemy.global_position.distance_to(den) + foot.x + body.x + foot.y + body.y
	# The swing in flight finishes first (its recovery roots the body), then the walk.
	var seconds := enemy.data().attack.recovery_seconds + profile.recover_seconds \
		+ route / (enemy.data().stats.move_speed * profile.effective_return_speed_scale()) \
		+ 3.0 * profile.decision_interval
	var arrived := _walk_home(stage, enemy, ceili(seconds / FRAME))
	assert_true(arrived >= 0, "it came to rest at home within %.2f s (state %s)"
		% [seconds, enemy.ai_state_name()])
	assert_true(enemy.global_position.distance_to(den) <= profile.home_arrival_radius,
		"having walked there round the trunk (%.1f px from its den)"
		% enemy.global_position.distance_to(den))
	_free(stage)


# === The shared contract ====================================================

## A SECOND creature on the same line goes round too. They share one tick and one stream; one
## taking a way round must not strand the other.
func test_two_creatures_behind_the_same_trunk_both_arrive() -> void:
	var solids: Array[Node] = [_prop(PINE, TRUNK)]
	var far := 44.0
	var stage := await _stage(solids, TRUNK + Vector2(HALF_GAP, 0), PackedVector2Array([
		TRUNK - Vector2(HALF_GAP, 0), TRUNK - Vector2(HALF_GAP + far, 0)]))
	var enemies := stage.runtime.enemies()
	var budget := _budget_frames(enemies[1], 2.0 * HALF_GAP + far, _footprint(PINE))
	var swung := [false, false]
	for _frame in budget:
		stage.runtime.tick_enemies(FRAME)
		for swing in stage.swings:
			swing.advance(FRAME)
		for i in 2:
			if enemies[i].ai_state_name() == "ATTACK" and enemies[i].global_position \
					.distance_to(stage.player.global_position) \
					<= enemies[i].data().engage_distance:
				swung[i] = true
	assert_eq(swung, [true, true], "both reached the player and swung within %d frames" % budget)
	_free(stage)


## A COMPANION follows through the same component and the same seam, so it gets round too: its
## owner on the far side of a trunk is reached, not stared at.
func test_a_companion_follows_its_owner_round_the_trunk() -> void:
	var trunk := _prop(PINE, TRUNK)
	var owner_body := Owner.new()
	add_to_tree(owner_body)
	owner_body.global_position = TRUNK + Vector2(HALF_GAP, 0)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(RngServiceScript.new(WORLD_SEED))
	var pet_data := load(PET_PATH) as PetData
	var pet := PetScene.instantiate() as Pet
	pet.setup(pet_data, &"pet_detour#1", pet_data.stats_at(1))
	add_to_tree(pet)
	pet.global_position = TRUNK - Vector2(HALF_GAP, 0)
	runtime.arm_attacker(pet, pet_data.attack, &"pet_detour#1", CombatRuntime.TEAM_PLAYER)
	assert_true(runtime.arm_ally(pet, pet_data.ai_profile, pet_data.engage_distance,
		pet_data.stats.move_speed, owner_body), "the companion is armed to follow")
	runtime.set_physics_process(false)
	var profile := pet_data.ai_profile
	var foot := _footprint(PINE)
	var body := _body_size(pet)
	var route := 2.0 * HALF_GAP + foot.x + body.x + foot.y + body.y
	var frames := ceili((route / (pet_data.stats.move_speed
		* profile.effective_return_speed_scale()) + 2.0 * profile.decision_interval) / FRAME)
	for _frame in frames:
		runtime.tick_allies(FRAME)
	var gap := pet.global_position.distance_to(owner_body.global_position)
	assert_true(gap <= profile.follow_radius,
		"it is back at its owner's side within %d frames (%.1f px, follow radius %.1f)"
		% [frames, gap, profile.follow_radius])
	runtime.end_session()
	free_node(pet)
	free_node(owner_body)
	free_node(runtime)
	free_node(trunk)


## IN THE OPEN NOTHING CHANGED. No obstacle means no hand and not one look-ahead, and pressing
## against the PLAYER'S OWN BODY is arriving, never "something in the way": a creature that
## tried to walk round its target would circle the player instead of biting.
func test_an_open_fight_takes_no_way_round_and_makes_no_query() -> void:
	var solids: Array[Node] = []
	var stage := await _stage(solids, TRUNK + Vector2(HALF_GAP, 0),
		PackedVector2Array([TRUNK - Vector2(HALF_GAP, 0)]))
	var enemy := stage.runtime.enemies()[0]
	var movement := enemy.get_node("MovementComponent") as MovementComponent
	var trace := _run(stage, 600, 0, false)
	assert_true(trace.first_bite_frame >= 0, "it fought")
	assert_true(stage.player.hp < 100 - enemy.get_attack_power(),
		"for long enough to bite more than once (hp %d)" % stage.player.hp)
	assert_eq(trace.hands, [] as Array[int], "and never took a way round anything")
	assert_eq(movement.detour_probes(), 0, "nor looked ahead once")
	_free(stage)

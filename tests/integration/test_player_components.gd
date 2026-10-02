extends TestCase
## Integration tests for the Player entity + its components working together, and for
## collision-aware movement in the live SceneTree.
##
## Isolation (D-019): these use FRESH instances added to the tree and NEVER mutate a shared
## /root autoload. Player._ready() resolves /root/InputService but only READS it (and only
## in _physics_process, which we don't drive here), so no shared state changes. The runner's
## contamination guard (shared GameState phase) therefore stays green.

const PlayerScene := preload("res://src/gameplay/entities/player.tscn")
const MovementScript := preload("res://src/gameplay/components/movement_component.gd")


func test_player_scene_has_required_components() -> void:
	var player: Node = PlayerScene.instantiate()
	add_to_tree(player)
	await scene_tree.process_frame  # let _ready() run

	assert_true(player is CharacterBody2D, "player root is a CharacterBody2D")
	assert_not_null(player.get_node_or_null("StatsComponent"), "has StatsComponent")
	assert_not_null(player.get_node_or_null("HealthComponent"), "has HealthComponent")
	assert_not_null(player.get_node_or_null("MovementComponent"), "has MovementComponent")

	# Health initialized from stats (player_stats.tres max_hp = 100).
	assert_eq(player.get_max_health(), 100, "max health from StatBlock")
	assert_eq(player.get_current_health(), 100, "starts full")
	assert_false(player.is_dead(), "alive")
	assert_true(player.get_attack_power() > 0, "has attack from stats")

	free_node(player)


func test_player_takes_damage_and_dies_via_health() -> void:
	var player: Node = PlayerScene.instantiate()
	add_to_tree(player)
	await scene_tree.process_frame

	var died := {"n": 0}
	player.died.connect(func() -> void: died["n"] += 1)

	var applied: int = player.take_damage(30)
	assert_eq(applied, 30, "damage applied through player")
	assert_eq(player.get_current_health(), 70)

	player.take_damage(999999)
	assert_true(player.is_dead(), "player dies on lethal damage")
	assert_eq(died["n"], 1, "player died signal fired once")

	free_node(player)


func test_movement_moves_body_in_tree() -> void:
	# A real physics step: a CharacterBody2D driven by MovementComponent.apply_intent must
	# change position (collision-aware motion, not a teleport).
	var body := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	body.add_child(shape)
	var mover: Node = MovementScript.new()
	body.add_child(mover)
	add_to_tree(body)
	await scene_tree.process_frame

	mover.setup(body)
	var start := body.global_position
	# Apply rightward intent across a few physics frames.
	for _i in range(5):
		mover.apply_intent(Vector2.RIGHT, 200.0)
		await scene_tree.physics_frame
	assert_true(body.global_position.x > start.x, "body moved right under intent")

	free_node(body)


func test_zero_intent_keeps_body_still() -> void:
	var body := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	body.add_child(shape)
	var mover: Node = MovementScript.new()
	body.add_child(mover)
	add_to_tree(body)
	await scene_tree.process_frame

	mover.setup(body)
	var start := body.global_position
	for _i in range(5):
		mover.apply_intent(Vector2.ZERO, 200.0)
		await scene_tree.physics_frame
	assert_true(body.global_position.is_equal_approx(start), "no intent => body stays put")

	free_node(body)

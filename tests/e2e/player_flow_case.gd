extends TestCase
## E2E player-flow assertions (Phase 02, D-019). A normal TestCase reusing the shared
## assert_* API. Driven ONLY by the dedicated entrypoint `tests/e2e/run_player_flow.gd` in
## its OWN isolated Godot process (the file name is not `test_*` and `tests/e2e/` is
## excluded from the in-runner discovery), because booting the real app drives the shared
## /root/GameState — which must not happen inside the common runner (the D-019 bug).
##
## It boots the REAL application against the ACTUAL project autoloads, clicks New Game via
## the real MainMenu signal, lands in the real Player Sandbox, then exercises the real
## gameplay: movement changes position, the coordinator's attack resolves bidirectional
## damage, death is deterministic, and teardown leaves no orphan. No duplicate autoloads;
## no gameplay math reimplemented here (it drives the real nodes/coordinator).

const MAIN_SCENE_PATH := "res://main.tscn"


func test_real_player_sandbox_flow() -> void:
	# --- boot the real app, no duplicate autoloads --------------------------------
	for autoload_name in ["EventBus", "GameState", "Localization", "InputService", "SceneRouter"]:
		var count := 0
		for child in scene_tree.root.get_children():
			if child.name == autoload_name:
				count += 1
		assert_eq(count, 1, "exactly one /root/%s (no duplicate autoload)" % autoload_name)

	var gs: Node = scene_tree.root.get_node_or_null("GameState")
	var router: Node = scene_tree.root.get_node_or_null("SceneRouter")
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	assert_not_null(gs)
	assert_not_null(router)
	assert_not_null(input)
	if gs == null or router == null or input == null:
		return

	var packed: PackedScene = load(MAIN_SCENE_PATH)
	var main: Node = packed.instantiate()
	scene_tree.root.add_child(main)
	await scene_tree.process_frame

	# New Game via the REAL menu intent → first gameplay scene (the sandbox).
	var ui: Node = main.get_node_or_null("UI")
	assert_not_null(ui)
	if ui == null or ui.get_child_count() == 0:
		_cleanup(main)
		return
	var menu: Node = ui.get_child(0)
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame

	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "running after New Game")
	assert_eq(router.get_current_key(), "player_sandbox", "sandbox is the first scene")
	var sandbox: Node = router.get_current_scene()
	assert_not_null(sandbox, "sandbox instance exists")
	if sandbox == null:
		_cleanup(main)
		return

	var player: Node = sandbox.get_node_or_null("Player")
	var dummy: Node = sandbox.get_node_or_null("TrainingDummy")
	assert_not_null(player, "sandbox has a Player")
	assert_not_null(dummy, "sandbox has a TrainingDummy")
	if player == null or dummy == null:
		_cleanup(main)
		return

	# The sandbox put input into GAMEPLAY context on enter.
	assert_true(input.call("is_gameplay_active"), "sandbox set GAMEPLAY input context")

	# --- movement: driving the player's movement changes its position -------------
	var move: Node = player.get_node_or_null("MovementComponent")
	assert_not_null(move, "player has MovementComponent")
	if move != null:
		var start: Vector2 = player.global_position
		for _i in range(8):
			move.apply_intent(Vector2.RIGHT, 160.0)
			await scene_tree.physics_frame
		assert_true(player.global_position.x > start.x, "player moved under movement intent")

	# --- attack: the REAL coordinator path resolves bidirectional damage ----------
	var dummy_full: int = dummy.get_current_health()
	var player_full: int = player.get_current_health()
	# Place the player next to the dummy so the sandbox range check passes, then drive the
	# coordinator's own resolution (the same method the attack intent triggers).
	player.global_position = dummy.global_position + Vector2(20, 0)
	sandbox.call("resolve_player_attack")
	assert_true(dummy.get_current_health() < dummy_full, "player attack damaged the dummy")
	assert_true(player.get_current_health() < player_full,
		"dummy retaliated — player took damage (bidirectional)")

	# --- death is deterministic ---------------------------------------------------
	var dummy_died := {"n": 0}
	dummy.died.connect(func() -> void: dummy_died["n"] += 1)
	for _k in range(200):  # bounded; dummy must die well within this
		if dummy.is_dead():
			break
		player.global_position = dummy.global_position + Vector2(20, 0)
		sandbox.call("resolve_player_attack")
	assert_true(dummy.is_dead(), "dummy eventually dies from repeated hits")
	assert_eq(dummy_died["n"], 1, "dummy died signal fired exactly once")
	# A dead dummy ends the exchange: attacking a corpse is a no-op (no player damage).
	var hp_after_death: int = player.get_current_health()
	sandbox.call("resolve_player_attack")
	assert_eq(player.get_current_health(), hp_after_death,
		"no further exchange once the dummy is dead (deterministic terminal state)")

	# --- cleanup: no orphan -------------------------------------------------------
	_cleanup(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(sandbox), "sandbox freed with Main (no orphan)")
	assert_false(is_instance_valid(main), "Main freed (no orphan)")


func _cleanup(main: Node) -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

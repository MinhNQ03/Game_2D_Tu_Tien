extends TestCase
## E2E player-flow assertions (Phase 02, D-019 + hardening). A normal TestCase reusing the
## shared assert_* API. Driven ONLY by the dedicated entrypoint `tests/e2e/run_player_flow.gd`
## in its OWN isolated Godot process (file name is not `test_*`; `tests/e2e/` is excluded
## from the in-runner discovery), because booting the real app drives the shared
## /root/GameState — which must not happen inside the common runner (D-019).
##
## It exercises the REAL semantic-input boundary, not shortcuts:
##   InputMap action → InputService → Player._physics_process (poll get_move_vector /
##   is_gameplay_action_just_pressed) → MovementComponent / attack_requested →
##   PlayerSandbox coordinator → DamageRules → HealthComponent.
## Movement is driven by `Input.action_press("move_right")` (NOT MovementComponent.apply_intent).
## Attack is driven by `Input.action_press("attack")` (NOT a direct resolve_player_attack()).
## Direct positioning is used ONLY as setup to make the fixed-range check deterministic.

const MAIN_SCENE_PATH := "res://main.tscn"

# Semantic actions this test drives (names only — never physical keys).
const MOVE_RIGHT := &"move_right"
const ATTACK := &"attack"


func test_real_player_sandbox_flow() -> void:
	# --- boot the real app, no duplicate autoloads --------------------------------
	for autoload_name in ["EventBus", "GameState", "Localization", "InputService", "SceneRouter"]:
		assert_eq(_count_named(autoload_name), 1,
			"exactly one /root/%s (no duplicate autoload)" % autoload_name)

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
		_teardown(main)
		return
	var menu: Node = ui.get_child(0)
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame

	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "running after New Game")
	assert_eq(router.get_current_key(), "player_sandbox", "sandbox is the first scene")
	var sandbox: Node = router.get_current_scene()
	assert_not_null(sandbox, "sandbox instance exists")
	if sandbox == null:
		_teardown(main)
		return

	var player: Node = sandbox.get_node_or_null("Player")
	var dummy: Node = sandbox.get_node_or_null("TrainingDummy")
	assert_not_null(player, "sandbox has a Player")
	assert_not_null(dummy, "sandbox has a TrainingDummy")
	if player == null or dummy == null:
		_teardown(main)
		return

	# The sandbox put input into GAMEPLAY context on enter.
	assert_true(input.call("is_gameplay_active"), "sandbox set GAMEPLAY input context")

	# --- MOVEMENT via the REAL semantic input path -------------------------------
	# Press the semantic action; the Player polls InputService.get_move_vector() in its own
	# _physics_process and feeds MovementComponent. We never call apply_intent directly here.
	# Start the player at the left side (clear space to the right) so a rightward press
	# demonstrably changes x without immediately hitting the dummy.
	player.global_position = Vector2(60, 150)
	await scene_tree.physics_frame
	var move_start: Vector2 = player.global_position
	Input.action_press(MOVE_RIGHT)
	for _i in range(10):
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	await scene_tree.physics_frame
	assert_true(player.global_position.x > move_start.x,
		"player moved right from a real semantic move_right action (via InputService)")

	# --- INPUT GATING regression: attack must NOT fire outside GAMEPLAY -----------
	# Put the player next to the dummy so range is satisfied; the only thing that should
	# stop the hit is the input context, not distance.
	input.call("set_menu_context")  # not GAMEPLAY
	player.global_position = dummy.global_position + Vector2(40, 0)
	await scene_tree.physics_frame
	var dummy_hp_before_gate: int = dummy.get_current_health()
	await _attack_once(player, dummy)
	assert_eq(dummy.get_current_health(), dummy_hp_before_gate,
		"attack is GATED: a MENU-context attack press does not damage the dummy")

	# --- ATTACK via the REAL semantic input path (now in GAMEPLAY) ----------------
	input.call("set_gameplay_context")
	player.global_position = dummy.global_position + Vector2(40, 0)
	await scene_tree.physics_frame
	var dummy_full: int = dummy.get_current_health()
	var player_full: int = player.get_current_health()
	await _attack_once(player, dummy)
	assert_true(dummy.get_current_health() < dummy_full,
		"semantic attack damaged the dummy (through InputService → Player → sandbox)")
	assert_true(player.get_current_health() < player_full,
		"dummy retaliated — player took damage (bidirectional)")

	# --- death is deterministic (repeated semantic attacks) -----------------------
	var dummy_died := {"n": 0}
	dummy.died.connect(func() -> void: dummy_died["n"] += 1)
	for _k in range(200):  # bounded; dummy must die well within this
		if dummy.is_dead():
			break
		await _attack_once(player, dummy)
	assert_true(dummy.is_dead(), "dummy eventually dies from repeated semantic attacks")
	assert_eq(dummy_died["n"], 1, "dummy died signal fired exactly once (this life)")

	# A dead dummy ends the exchange: another attack is a no-op (no further player damage).
	var hp_after_death: int = player.get_current_health()
	await _attack_once(player, dummy)
	assert_eq(player.get_current_health(), hp_after_death,
		"no further exchange once the dummy is dead (deterministic terminal state)")

	# --- cleanup / isolation ------------------------------------------------------
	_teardown(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(sandbox), "sandbox freed with Main (no orphan)")
	assert_false(is_instance_valid(player), "player freed (no orphan)")
	assert_false(is_instance_valid(dummy), "dummy freed (no orphan)")
	assert_false(is_instance_valid(main), "Main freed (no orphan)")
	# No duplicate autoloads were created by the test.
	for autoload_name in ["EventBus", "GameState", "Localization", "InputService", "SceneRouter"]:
		assert_eq(_count_named(autoload_name), 1,
			"still exactly one /root/%s after teardown" % autoload_name)
	# GameState is not left corrupt: we never ended the session, so it is still RUNNING (a
	# legal phase), not some garbage value. (This isolated process exits right after.)
	assert_eq(gs.get_phase(), gs.Phase.RUNNING,
		"GameState remains in a legal phase (RUNNING) after teardown, not corrupt")
	assert_true(gs.is_session_active(), "session still marked active (no corruption)")


## One semantic attack: keep the player in range (setup positioning), press the attack
## action, let the Player's edge-triggered poll fire on the next physics frame, then
## release. The press PERSISTS across one physics frame so `is_gameplay_action_just_pressed`
## reliably registers before we release.
func _attack_once(player: Node, dummy: Node) -> void:
	# 40px: within SANDBOX_ATTACK_RANGE (64) but outside the combined body half-widths
	# (12 + 14 = 26), so the player/dummy bodies don't overlap and get pushed apart.
	player.global_position = dummy.global_position + Vector2(40, 0)
	Input.action_press(ATTACK)
	await scene_tree.physics_frame  # Player._physics_process sees just_pressed here
	Input.action_release(ATTACK)
	await scene_tree.physics_frame  # let the release settle (fresh edge next time)


func _count_named(node_name: String) -> int:
	var count := 0
	for child in scene_tree.root.get_children():
		if child.name == node_name:
			count += 1
	return count


## Release any still-pressed actions and free Main (and its whole subtree).
func _teardown(main: Node) -> void:
	if Input.is_action_pressed(MOVE_RIGHT):
		Input.action_release(MOVE_RIGHT)
	if Input.is_action_pressed(ATTACK):
		Input.action_release(ATTACK)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

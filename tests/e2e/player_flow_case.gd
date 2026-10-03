extends TestCase
## E2E player-flow assertions (Phase 02 combat sandbox, D-019 + hardening). A normal TestCase
## reusing the shared assert_* API. Driven ONLY by the dedicated entrypoint
## `tests/e2e/run_player_flow.gd` in its OWN isolated Godot process (file name is not
## `test_*`; `tests/e2e/` is excluded from in-runner discovery), because adding the sandbox
## under /root drives the shared /root/InputService (GAMEPLAY context) — which must not
## happen inside the common runner (D-019 / L-010).
##
## PHASE 03 NOTE: New Game no longer loads the player sandbox (it now enters the World/Map
## via WorldRuntime — see run_world_flow.gd). The sandbox is retained as the Phase-02 combat
## validation scene, so this E2E instantiates `player_sandbox.tscn` DIRECTLY against the real
## autoloads instead of reaching it through the menu. That keeps the Phase-02 combat boundary
## covered without a dead New-Game → sandbox path. (D-003 / Phase-03 retention of the
## sandbox.)
##
## It exercises the REAL semantic-input boundary, not shortcuts:
##   InputMap action → InputService → Player._physics_process (poll get_move_vector /
##   is_gameplay_action_just_pressed) → MovementComponent / attack_requested →
##   PlayerSandbox coordinator → DamageRules → HealthComponent.
## Movement is driven by `Input.action_press("move_right")` (NOT MovementComponent.apply_intent).
## Attack is driven by `Input.action_press("attack")` (NOT a direct resolve_player_attack()).
## Direct positioning is used ONLY as setup to make the fixed-range check deterministic.

const SANDBOX_SCENE_PATH := "res://src/gameplay/sandbox/player_sandbox.tscn"

# Semantic actions this test drives (names only — never physical keys).
const MOVE_RIGHT := &"move_right"
const ATTACK := &"attack"


func test_real_player_sandbox_flow() -> void:
	# --- real autoloads present, none duplicated ----------------------------------
	for autoload_name in ["EventBus", "GameState", "Localization", "InputService", "SceneRouter"]:
		assert_eq(_count_named(autoload_name), 1,
			"exactly one /root/%s (no duplicate autoload)" % autoload_name)

	var input: Node = scene_tree.root.get_node_or_null("InputService")
	assert_not_null(input)
	if input == null:
		return

	# Instantiate the Phase-02 combat sandbox DIRECTLY under /root (no Main, no New Game).
	# Its _ready() sets the GAMEPLAY input context — exactly as the real first scene did in
	# Phase 02 — so the semantic-input boundary below is driven for real.
	var packed: PackedScene = load(SANDBOX_SCENE_PATH)
	assert_not_null(packed, "player_sandbox.tscn loads")
	if packed == null:
		return
	var sandbox: Node = packed.instantiate()
	assert_not_null(sandbox, "sandbox instantiates")
	if sandbox == null:
		return
	scene_tree.root.add_child(sandbox)
	await scene_tree.process_frame  # let the sandbox _ready() run

	var player: Node = sandbox.get_node_or_null("Player")
	var dummy: Node = sandbox.get_node_or_null("TrainingDummy")
	assert_not_null(player, "sandbox has a Player")
	assert_not_null(dummy, "sandbox has a TrainingDummy")
	if player == null or dummy == null:
		_teardown(sandbox)
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
	_teardown(sandbox)
	await scene_tree.process_frame
	assert_false(is_instance_valid(sandbox), "sandbox freed (no orphan)")
	assert_false(is_instance_valid(player), "player freed (no orphan)")
	assert_false(is_instance_valid(dummy), "dummy freed (no orphan)")
	# No duplicate autoloads were created by the test.
	for autoload_name in ["EventBus", "GameState", "Localization", "InputService", "SceneRouter"]:
		assert_eq(_count_named(autoload_name), 1,
			"still exactly one /root/%s after teardown" % autoload_name)


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


## Release any still-pressed actions and free the sandbox subtree.
func _teardown(node: Node) -> void:
	if Input.is_action_pressed(MOVE_RIGHT):
		Input.action_release(MOVE_RIGHT)
	if Input.is_action_pressed(ATTACK):
		Input.action_release(ATTACK)
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()

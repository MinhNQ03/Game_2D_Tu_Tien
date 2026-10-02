extends TestCase
## Gameplay smoke test: the Player Sandbox scene is STRUCTURALLY sound.
##
## STRUCTURAL ONLY (D-019): we instantiate the scene but do NOT add it to the tree, because
## PlayerSandbox._ready() calls InputService.set_gameplay_context() — a shared /root autoload
## mutation that must not happen inside the common runner. The scene actually running (input
## context GAMEPLAY, attack resolving, bidirectional damage) is verified in the dedicated,
## isolated E2E process (tests/e2e/run_player_flow.gd). Here we only confirm the sandbox is
## wired with the right pieces, then free the detached instance (no orphan, no mutation).

const SandboxScene := preload("res://src/gameplay/sandbox/player_sandbox.tscn")


func test_sandbox_has_player_dummy_walls_camera_hud() -> void:
	var sandbox: Node = SandboxScene.instantiate()  # NOT added to the tree
	assert_not_null(sandbox, "sandbox instantiates")
	if sandbox == null:
		return

	var player := sandbox.get_node_or_null("Player")
	var dummy := sandbox.get_node_or_null("TrainingDummy")
	assert_not_null(player, "sandbox has a Player")
	assert_not_null(dummy, "sandbox has a TrainingDummy")
	assert_true(player is CharacterBody2D, "player is a CharacterBody2D")
	assert_true(dummy is StaticBody2D, "dummy is a StaticBody2D (no movement)")

	# Static collision boundary present (so the player can't leave the arena).
	var walls := sandbox.get_node_or_null("Walls")
	assert_not_null(walls, "sandbox has a Walls container")
	assert_true(walls.get_child_count() >= 4, "arena has boundary walls on all sides")

	# A camera and a HUD label (placeholder presentation).
	assert_not_null(sandbox.get_node_or_null("Camera2D"), "sandbox has a Camera2D")
	assert_not_null(sandbox.get_node_or_null("HUD/InfoLabel"), "sandbox has a HUD label")

	# The sandbox exposes the first-scene return contract Main wires to.
	assert_true(sandbox.has_signal("return_to_menu_requested"),
		"sandbox exposes return_to_menu_requested (first-scene contract)")

	sandbox.free()


func test_player_and_dummy_within_sandbox_attack_range() -> void:
	# A spawn-placement sanity check: the player and dummy start close enough that an
	# attack intent can land, so the sandbox is actually playable/validatable. Uses the
	# scene's own positions and the coordinator's documented range constant — no magic
	# number duplicated here.
	var sandbox: Node = SandboxScene.instantiate()
	if sandbox == null:
		return
	var player: Node2D = sandbox.get_node_or_null("Player")
	var dummy: Node2D = sandbox.get_node_or_null("TrainingDummy")
	assert_not_null(player)
	assert_not_null(dummy)
	if player != null and dummy != null:
		var dist := player.position.distance_to(dummy.position)
		assert_true(dist <= PlayerSandbox.SANDBOX_ATTACK_RANGE,
			"player spawns within attack range of the dummy (dist=%f)" % dist)
	sandbox.free()

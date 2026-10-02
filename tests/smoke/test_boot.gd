extends TestCase
## Smoke test (STRUCTURAL ONLY — runs inside the shared test runner).
##
## IMPORTANT ISOLATION RULE (D-019): this test runs in the same process as every other
## test, where the project autoloads (GameState, SceneRouter, ...) are LIVE singletons
## under /root. Therefore this test must NEVER boot Main into the SceneTree here, because
## Main._ready() drives the shared /root/GameState lifecycle and would contaminate other
## tests (and be contaminated by them). The REAL application boot — booting main.tscn,
## running Main._ready(), reaching MENU, New Game → prologue → RUNNING — is verified in a
## DEDICATED, isolated Godot process: `tests/e2e/run_app_flow.gd` (its own CI step), plus
## the CI "runtime boot smoke" (`--quit-after 2`). Here we only assert static structure
## that mutates no shared singleton.

const MAIN_SCENE_PATH := "res://main.tscn"


## (1 + 2) The configured main scene exists in the resource system / on disk.
func test_main_scene_exists() -> void:
	assert_true(ResourceLoader.exists(MAIN_SCENE_PATH),
		"main scene should exist at %s" % MAIN_SCENE_PATH)


## (1) project.godot must point run/main_scene at the main scene.
func test_project_declares_main_scene() -> void:
	var declared := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(declared, MAIN_SCENE_PATH,
		"application/run/main_scene should be the main scene")


## Project identity was renamed to Aetheria (D-006).
func test_project_name_is_aetheria() -> void:
	var app_name := String(ProjectSettings.get_setting("application/config/name", ""))
	assert_eq(app_name, "Aetheria", "project name should be Aetheria")


## (3) The main scene loads as a PackedScene.
func test_main_scene_loads() -> void:
	var packed := load(MAIN_SCENE_PATH)
	assert_not_null(packed, "main scene should load as a PackedScene")
	assert_true(packed is PackedScene, "loaded resource should be a PackedScene")


## (4) The main scene instantiates and exposes the Systems/World/UI shell, and its
## bootstrap self-validation passes — WITHOUT entering the SceneTree. We deliberately do
## NOT add it to the tree: that would run Main._ready() and mutate the shared /root
## autoloads (see the isolation note above). The real boot lifecycle is covered by the
## dedicated E2E process. Here we only confirm the static shell is correct, then free the
## detached instance (no orphan, no shared-state mutation).
func test_main_scene_structure_is_valid_without_booting() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	assert_not_null(packed, "main scene should load")
	if packed == null:
		return

	var root := packed.instantiate()  # instantiate only — NOT added to the tree
	assert_not_null(root, "main scene should instantiate")
	if root == null:
		return

	# Children declared in main.tscn exist on the instance even before entering the tree.
	assert_not_null(root.get_node_or_null("Systems"), "Main should have a Systems node")
	assert_not_null(root.get_node_or_null("World"), "Main should have a World node")
	assert_not_null(root.get_node_or_null("UI"), "Main should have a UI node")

	# Bootstrap self-validation reports a valid structure (pure check, no lifecycle).
	if root.has_method("has_required_structure"):
		assert_true(root.call("has_required_structure"),
			"bootstrap should report its structure is valid")
	else:
		assert_true(false, "bootstrap script missing has_required_structure()")

	# It never entered the tree, so _ready()/_boot() never ran: the shared /root/GameState
	# is untouched by this test (the runner's contamination guard asserts this globally).
	root.free()


## (negative) A Main-like node MISSING a required container must be detected as invalid
## — proving the structure check actually fails when the structure is wrong. The node is
## never added to the tree, so no lifecycle/boot runs.
func test_missing_structure_is_detected() -> void:
	var script: Script = load("res://src/bootstrap/main.gd")
	assert_not_null(script, "bootstrap script should load")
	if script == null:
		return
	var node: Node = Node2D.new()
	node.set_script(script)
	var systems := Node.new()
	systems.name = "Systems"
	var world := Node2D.new()
	world.name = "World"
	node.add_child(systems)
	node.add_child(world)
	# Intentionally NO "UI" child.
	if node.has_method("has_required_structure"):
		assert_false(node.call("has_required_structure"),
			"structure check must FAIL when a required container is missing")
	else:
		assert_true(false, "bootstrap script missing has_required_structure()")
	node.free()


## Proves the harness records a failed assertion (so a real regression cannot pass
## silently) WITHOUT failing this test.
func test_runner_detects_failure() -> void:
	var probe := TestCase.new()
	probe.reset_failures()
	probe.assert_true(false, "intentional probe failure")
	assert_false(probe.get_failures().is_empty(),
		"a failed assertion must be recorded by the harness")

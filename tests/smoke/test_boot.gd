extends TestCase
## Smoke test: the project really boots and the main scene is structurally sound.
##
## This is a REAL test. Beyond loading/instantiating, it adds Main to the live
## SceneTree so Godot runs the actual node lifecycle (`_enter_tree` → `_ready`), then
## verifies the bootstrap structure and cleans up with no orphan nodes.

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


## (4 + 5 + 6 + 7 + 8) The main scene instantiates, actually ENTERS the SceneTree so its
## `_ready` runs, exposes Systems/World/UI, and its bootstrap self-validation passes.
## Cleans up afterwards (9: no orphan nodes).
func test_main_scene_enters_tree_and_is_valid() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	assert_not_null(packed, "main scene should load")
	if packed == null:
		return

	var root := packed.instantiate()  # (4) instantiate
	assert_not_null(root, "main scene should instantiate")
	if root == null:
		return

	# (5) Actually enter the SceneTree so Godot runs _enter_tree/_ready.
	var added := add_to_tree(root)
	assert_true(added, "Main should be added to the SceneTree")
	if not added:
		root.free()
		return

	# (6) Give the engine a frame so _ready() has run (awaited by the runner too).
	await scene_tree.process_frame
	assert_true(root.is_inside_tree(), "Main should be inside the SceneTree after add")

	# (7) Required container structure present as live children.
	assert_not_null(root.get_node_or_null("Systems"), "Main should have a Systems node")
	assert_not_null(root.get_node_or_null("World"), "Main should have a World node")
	assert_not_null(root.get_node_or_null("UI"), "Main should have a UI node")

	# (8) Bootstrap self-validation reports a valid structure.
	if root.has_method("has_required_structure"):
		assert_true(root.call("has_required_structure"),
			"bootstrap should report its structure is valid")
	else:
		assert_true(false, "bootstrap script missing has_required_structure()")

	# (9) Cleanup — no orphan nodes left behind.
	free_node(root)


## (negative) A Main-like node MISSING a required container must be detected as invalid
## — proving the structure check actually fails when the structure is wrong.
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
	free_node(node)


## Proves the harness records a failed assertion (so a real regression cannot pass
## silently) WITHOUT failing this test.
func test_runner_detects_failure() -> void:
	var probe := TestCase.new()
	probe.reset_failures()
	probe.assert_true(false, "intentional probe failure")
	assert_false(probe.get_failures().is_empty(),
		"a failed assertion must be recorded by the harness")

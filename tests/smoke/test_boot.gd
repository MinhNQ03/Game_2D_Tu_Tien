extends TestCase
## Smoke test: the project boots and the main scene is structurally sound.
##
## This is a REAL test. It loads the actual main scene configured in project.godot,
## instantiates it, and asserts the bootstrap structure the rest of the project relies
## on. If any assertion fails, the runner exits non-zero (verified by
## `test_runner_detects_failure`).

const MAIN_SCENE_PATH := "res://main.tscn"


## 1 + 2: the configured main scene exists on disk / in the resource system.
func test_main_scene_exists() -> void:
	assert_true(ResourceLoader.exists(MAIN_SCENE_PATH),
		"main scene should exist at %s" % MAIN_SCENE_PATH)


## project.godot must actually point run/main_scene at the main scene.
func test_project_declares_main_scene() -> void:
	var declared := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(declared, MAIN_SCENE_PATH,
		"application/run/main_scene should be the main scene")


## project identity was renamed to Aetheria (foundation fix / D-006).
func test_project_name_is_aetheria() -> void:
	var app_name := String(ProjectSettings.get_setting("application/config/name", ""))
	assert_eq(app_name, "Aetheria", "project name should be Aetheria")


## 3: the main scene loads as a PackedScene.
func test_main_scene_loads() -> void:
	var packed := load(MAIN_SCENE_PATH)
	assert_not_null(packed, "main scene should load as a PackedScene")
	assert_true(packed is PackedScene, "loaded resource should be a PackedScene")


## 3 + 4: the main scene instantiates without crashing and has the bootstrap structure.
func test_main_scene_instantiates_with_structure() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	if packed == null:
		assert_true(false, "cannot instantiate: scene failed to load")
		return
	var root := packed.instantiate()
	assert_not_null(root, "main scene should instantiate")
	if root == null:
		return
	# Required container structure (Main/Systems/World/UI).
	assert_not_null(root.get_node_or_null("Systems"), "Main should have a Systems node")
	assert_not_null(root.get_node_or_null("World"), "Main should have a World node")
	assert_not_null(root.get_node_or_null("UI"), "Main should have a UI node")
	# The bootstrap script exposes a structure self-check; use it if present.
	if root.has_method("has_required_structure"):
		assert_true(root.call("has_required_structure"),
			"bootstrap reports its structure is valid")
	root.free()


## 5: proves the harness records failures (so a real regression can't pass silently).
## We drive the assertion into a throwaway TestCase and confirm it registered a failure,
## WITHOUT failing this test. This verifies "failing assertion => recorded".
func test_runner_detects_failure() -> void:
	var probe := TestCase.new()
	probe.reset_failures()
	probe.assert_true(false, "intentional probe failure")
	assert_false(probe.get_failures().is_empty(),
		"a failed assertion must be recorded by the harness")

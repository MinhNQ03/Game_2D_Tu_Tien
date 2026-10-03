extends TestCase
## E2E application-flow assertions (D-019). This is a normal TestCase — it reuses the
## shared assert_* API and failure recording (no second assertion framework).
##
## It is NOT run by the in-process `tests/run_tests.gd`: the file name is not `test_*.gd`
## (so the runner's discovery skips it) and `tests/e2e/` is in the runner's EXCLUDED_DIRS.
## It is driven ONLY by the dedicated entrypoint `tests/e2e/run_app_flow.gd`, in its own
## isolated Godot process.
##
## Why a separate process: the real boot drives the shared /root/GameState autoload to
## RUNNING. Running it inside the common test runner would contaminate every other test
## (the bug fixed in D-019). Here the process does nothing else, so there is nothing to
## contaminate.
##
## It uses the ACTUAL project autoloads under /root (declared in project.godot [autoload]).
## It must NOT spawn duplicate autoloads, and it drives the REAL player intent
## (MainMenu.new_game_pressed), never calling GameState/SceneRouter directly.

const MAIN_SCENE_PATH := "res://main.tscn"
const REQUIRED_AUTOLOADS := [
	"EventBus", "GameState", "Localization", "InputService", "SceneRouter",
]


## Full boot → menu → New Game → first gameplay scene (the hub map) → RUNNING, on the real
## autoloads, then cleanup. (This app-flow E2E only checks the lifecycle/wiring reaches the
## first scene; the world/map flow itself is exercised by run_world_flow.gd and the player
## sandbox by run_player_flow.gd.)
func test_real_application_flow() -> void:
	# --- 1. all five real autoloads present; none duplicated -------------------
	var autoloads := {}
	for autoload_name in REQUIRED_AUTOLOADS:
		var node: Node = scene_tree.root.get_node_or_null(autoload_name)
		assert_not_null(node, "real autoload /root/%s must exist" % autoload_name)
		autoloads[autoload_name] = node
		# No duplicate: a second node with the same name would be auto-renamed, so a plain
		# per-name child count confirms there is exactly one.
		var count := 0
		for child in scene_tree.root.get_children():
			if child.name == autoload_name:
				count += 1
		assert_eq(count, 1, "exactly one /root/%s (no duplicate autoload)" % autoload_name)

	var gs: Node = autoloads["GameState"]
	var router: Node = autoloads["SceneRouter"]
	if gs == null or router == null:
		return  # cannot proceed without the core singletons

	# The real autoload starts fresh at BOOT (we are the only thing running).
	assert_eq(gs.get_phase(), gs.Phase.BOOT, "fresh GameState autoload starts at BOOT")

	# --- 2. boot the REAL main scene ------------------------------------------
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	assert_not_null(packed, "main.tscn loads")
	if packed == null:
		return
	var main: Node = packed.instantiate()
	assert_not_null(main, "main.tscn instantiates")
	if main == null:
		return

	# Entering the tree runs Main._ready() -> _verify_core_autoloads() -> _boot() -> menu.
	scene_tree.root.add_child(main)
	await scene_tree.process_frame  # let _ready() across Main + the menu run

	# --- 3. boot settled at MENU with the real menu shown ---------------------
	assert_true(main.is_inside_tree(), "Main is inside the tree")
	assert_true(main.call("has_required_structure"), "Main structure valid")
	assert_eq(gs.get_phase(), gs.Phase.MENU, "boot reached MENU before any input")

	var ui: Node = main.get_node_or_null("UI")
	assert_not_null(ui, "Main/UI exists")
	if ui == null:
		_cleanup(main)
		return
	assert_eq(ui.get_child_count(), 1, "exactly one MainMenu under UI")
	var menu: Node = ui.get_child(0)
	assert_true(menu.has_signal("new_game_pressed"), "menu exposes new_game_pressed")

	# --- 4. drive the REAL player intent (menu signal), not the services ------
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame  # let the first gameplay scene's _ready() run

	# --- 5. the whole chain wired itself --------------------------------------
	assert_true(gs.is_session_active(), "session active after New Game")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "lifecycle reached RUNNING")
	assert_eq(router.get_current_key(), "map_hub",
		"router loaded the first gameplay scene (Phase 03: the hub map)")
	var content: Node = router.get_current_scene()
	assert_not_null(content, "a live content scene instance exists")

	var world: Node = main.get_node_or_null("World")
	assert_not_null(world, "Main/World exists")
	if world != null:
		assert_eq(world.get_child_count(), 1, "exactly one content scene under World")

	# --- 13. the first gameplay scene set the input context to GAMEPLAY -------
	var input: Node = autoloads["InputService"]
	if input != null:
		assert_true(input.call("is_gameplay_active"),
			"the first gameplay scene's _ready() set the input context to GAMEPLAY")

	# --- 15. cleanup: no orphan content scene, no leftover menu ---------------
	_cleanup(main)
	await scene_tree.process_frame  # let queue_free complete
	assert_false(is_instance_valid(content),
		"content scene is freed after Main leaves the tree (no orphan)")
	assert_false(is_instance_valid(main), "Main is freed after cleanup (no orphan)")


## Remove Main (and all its children) from the tree and free immediately.
func _cleanup(main: Node) -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

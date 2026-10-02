extends TestCase
## Integration test: BOOT -> MENU -> NEW GAME -> SESSION INIT -> FIRST SCENE.
##
## Exercises GameState + SceneRouter + the real prologue content scene together, driving
## the same sequence the bootstrap/menu would. Uses fresh instances so it is isolated from
## the autoload singletons and order-independent.

const GameStateScript := preload("res://src/infrastructure/game_state.gd")
const RouterScript := preload("res://src/infrastructure/scene_router.gd")
const PROLOGUE_PATH := "res://src/presentation/scenes/prologue_shell.tscn"


func test_boot_to_first_scene_flow() -> void:
	var gs: Node = GameStateScript.new()
	var router: Node = RouterScript.new()
	var world_host := Node2D.new()
	add_to_tree(gs)
	add_to_tree(router)
	add_to_tree(world_host)
	router.set_scene_host(world_host)
	router.register_scene("prologue", PROLOGUE_PATH)

	# BOOT -> INITIALIZING -> READY -> MENU
	assert_true(gs.begin_initialization(), "boot -> initializing")
	assert_true(gs.mark_ready(), "initializing -> ready")
	assert_true(gs.enter_menu(), "ready -> menu")

	# NEW GAME: start session, load first scene, confirm running.
	assert_true(gs.start_new_game(), "menu -> starting_session")
	assert_true(gs.is_session_active(), "session active")
	var loaded: bool = router.request_transition("prologue", &"world_prologue", &"prologue_map")
	assert_true(loaded, "first scene loaded via router")
	assert_true(gs.confirm_session_running(), "starting_session -> running")

	# Verify end state: running session, first scene present, location recorded.
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "phase is RUNNING")
	assert_eq(world_host.get_child_count(), 1, "exactly one content scene under world host")
	assert_eq(router.get_current_key(), "prologue", "router tracks the first scene")

	# Let the first scene's _ready() run (it builds a label + sets input context).
	await scene_tree.process_frame
	assert_not_null(router.get_current_scene(), "first scene instance exists")

	# Return to menu cleanly (ends session, clears scene).
	assert_true(gs.end_session(), "running -> menu on end_session")
	router.clear_current_scene()
	assert_false(gs.is_session_active(), "session ended")
	assert_eq(router.get_current_key(), "", "scene cleared")

	free_node(world_host)
	free_node(router)
	free_node(gs)

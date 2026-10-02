extends TestCase
## Unit tests for GameState lifecycle + session (src/infrastructure/game_state.gd).
##
## Uses a fresh instance per test (not the autoload singleton) so tests are isolated and
## order-independent. GameState is a plain Node, so new() works headless.

const GameStateScript := preload("res://src/infrastructure/game_state.gd")


func _make() -> Node:
	return GameStateScript.new()


func test_initial_phase_is_boot() -> void:
	var gs := _make()
	assert_eq(gs.get_phase(), gs.Phase.BOOT, "fresh GameState starts in BOOT")
	assert_false(gs.is_session_active(), "no session at boot")
	free_node(gs)


func test_valid_boot_sequence() -> void:
	var gs := _make()
	assert_true(gs.begin_initialization(), "BOOT -> INITIALIZING")
	assert_true(gs.mark_ready(), "INITIALIZING -> READY")
	assert_true(gs.enter_menu(), "READY -> MENU")
	assert_eq(gs.get_phase(), gs.Phase.MENU)
	free_node(gs)


func test_invalid_transition_rejected() -> void:
	var gs := _make()
	# BOOT -> RUNNING is illegal; must be rejected and leave phase unchanged.
	assert_false(gs.transition_to(gs.Phase.RUNNING), "illegal transition returns false")
	assert_eq(gs.get_phase(), gs.Phase.BOOT, "phase unchanged after illegal transition")
	free_node(gs)


func test_start_new_game_flow() -> void:
	var gs := _make()
	gs.begin_initialization()
	gs.mark_ready()
	gs.enter_menu()
	assert_true(gs.start_new_game(), "MENU -> STARTING_SESSION")
	assert_true(gs.is_session_active(), "session active after start_new_game")
	assert_ne(gs.get_run_id(), "", "a run_id is minted")
	assert_true(gs.confirm_session_running(), "STARTING_SESSION -> RUNNING")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING)
	free_node(gs)


func test_session_survives_transition() -> void:
	var gs := _make()
	gs.begin_initialization()
	gs.mark_ready()
	gs.enter_menu()
	gs.start_new_game()
	gs.confirm_session_running()
	var run_id: String = gs.get_run_id()
	gs.set_current_location(&"world_01", &"village", "village_scene")
	# Simulate a scene transition round-trip.
	assert_true(gs.begin_transition(), "RUNNING -> TRANSITIONING")
	assert_true(gs.complete_transition(), "TRANSITIONING -> RUNNING")
	assert_true(gs.is_session_active(), "session still active across transition")
	assert_eq(gs.get_run_id(), run_id, "run_id preserved across transition")
	assert_eq(String(gs.get_current_map_id()), "village", "location preserved")
	free_node(gs)


func test_end_session_clears_state() -> void:
	var gs := _make()
	gs.begin_initialization()
	gs.mark_ready()
	gs.enter_menu()
	gs.start_new_game()
	gs.confirm_session_running()
	assert_true(gs.end_session(), "RUNNING -> MENU on end_session")
	assert_false(gs.is_session_active(), "session cleared")
	assert_eq(gs.get_run_id(), "", "run_id cleared")
	free_node(gs)


func test_to_from_dict_round_trip() -> void:
	var gs := _make()
	gs.begin_initialization()
	gs.mark_ready()
	gs.enter_menu()
	gs.start_new_game()
	gs.confirm_session_running()
	gs.set_current_location(&"world_02", &"forest", "forest_scene")
	var snapshot: Dictionary = gs.to_dict()

	var gs2 := _make()
	gs2.from_dict(snapshot)
	assert_eq(gs2.is_session_active(), gs.is_session_active())
	assert_eq(gs2.get_run_id(), gs.get_run_id())
	assert_eq(String(gs2.get_current_world_id()), "world_02")
	assert_eq(String(gs2.get_current_map_id()), "forest")
	assert_eq(gs2.get_current_scene_key(), "forest_scene")
	free_node(gs)
	free_node(gs2)

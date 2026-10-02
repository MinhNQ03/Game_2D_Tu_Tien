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


func _running_session(world: StringName, map: StringName, scene_key: String) -> Node:
	var gs := _make()
	gs.begin_initialization()
	gs.mark_ready()
	gs.enter_menu()
	gs.start_new_game()
	gs.confirm_session_running()
	gs.set_current_location(world, map, scene_key)
	return gs


# --- Persistence invariant (serialize run identity + location; NEVER lifecycle) ---

## A snapshot carries run identity + location, and NEVER the lifecycle phase or a raw
## `session_active` flag (which the old format persisted and could resurrect inconsistently).
func test_to_dict_omits_lifecycle_and_active_flag() -> void:
	var gs := _running_session(&"world_02", &"forest", "forest_scene")
	var snapshot: Dictionary = gs.to_dict()
	assert_false(snapshot.has("session_active"),
		"snapshot must not persist the derived session_active flag")
	assert_false(snapshot.has("phase"), "snapshot must not persist the runtime phase")
	assert_true(snapshot.has("run_id"), "snapshot carries run identity")
	assert_eq(String(snapshot.get("current_map_id", "")), "forest", "location persisted")
	free_node(gs)


## to_dict() on a non-session (no run underway) has nothing to save: returns an empty dict.
func test_to_dict_empty_when_no_session() -> void:
	var gs := _make()
	gs.begin_initialization()
	gs.mark_ready()
	gs.enter_menu()  # at MENU, no session started
	var snapshot: Dictionary = gs.to_dict()
	assert_true(snapshot.is_empty(), "no active session => empty snapshot (nothing to save)")
	free_node(gs)


## Hydrating a saved run restores identity + location and DERIVES session_active, without
## touching the lifecycle phase. The caller drives the phase to RUNNING afterward.
func test_hydrate_restores_run_without_fabricating_phase() -> void:
	var src := _running_session(&"world_02", &"forest", "forest_scene")
	var snapshot: Dictionary = src.to_dict()

	var gs2 := _make()
	gs2.begin_initialization()
	gs2.mark_ready()
	gs2.enter_menu()  # load-safe phase
	assert_true(gs2.hydrate_session(snapshot), "hydrate from a valid snapshot succeeds")
	assert_true(gs2.is_session_active(), "session_active derived from presence of run_id")
	assert_eq(gs2.get_run_id(), src.get_run_id(), "run_id restored")
	assert_eq(String(gs2.get_current_map_id()), "forest", "location restored")
	# Phase was NOT fabricated by hydrate: it remains the load-safe MENU until the caller
	# transitions it. The old bug produced BOOT + session_active=true; prove that's gone.
	assert_eq(gs2.get_phase(), gs2.Phase.MENU, "hydrate does not fabricate a RUNNING phase")
	assert_ne(gs2.get_phase(), gs2.Phase.BOOT, "and never leaves an invalid BOOT+active state")
	free_node(src)
	free_node(gs2)


## hydrate_session refuses an empty / run_id-less snapshot (fail loud, no silent partial load).
func test_hydrate_rejects_invalid_snapshot() -> void:
	var gs := _make()
	gs.begin_initialization()
	gs.mark_ready()
	gs.enter_menu()
	assert_false(gs.hydrate_session({}), "empty snapshot rejected")
	assert_false(gs.hydrate_session({"current_map_id": "forest"}), "no run_id => rejected")
	assert_false(gs.is_session_active(), "no session created from an invalid snapshot")
	free_node(gs)


## hydrate_session refuses to graft a run onto a live (mid-session) lifecycle, so a load
## can't corrupt an in-progress game.
func test_hydrate_rejects_unsafe_phase() -> void:
	var gs := _running_session(&"world_02", &"forest", "forest_scene")  # phase RUNNING
	var ok: bool = gs.hydrate_session({"run_id": "run_x", "current_map_id": "cave"})
	assert_false(ok, "hydrate rejected while RUNNING")
	assert_eq(String(gs.get_current_map_id()), "forest", "live run left untouched")
	free_node(gs)


## from_dict is a thin alias of hydrate_session (symmetry with to_dict) and must behave
## identically — it must NOT fabricate lifecycle state the way the old version did.
func test_from_dict_is_hydrate_alias() -> void:
	var src := _running_session(&"world_03", &"peak", "peak_scene")
	var snapshot: Dictionary = src.to_dict()
	var gs2 := _make()
	gs2.begin_initialization()
	gs2.mark_ready()
	gs2.enter_menu()
	assert_true(gs2.from_dict(snapshot), "from_dict delegates to hydrate_session")
	assert_eq(gs2.get_run_id(), src.get_run_id(), "run restored via from_dict")
	assert_eq(gs2.get_phase(), gs2.Phase.MENU, "from_dict did not fabricate a phase")
	free_node(src)
	free_node(gs2)

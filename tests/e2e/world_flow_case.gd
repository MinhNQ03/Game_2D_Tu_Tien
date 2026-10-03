extends TestCase
## E2E world/map-flow assertions (Phase 03, D-019 isolation pattern). A normal TestCase
## reusing the shared assert_* API. Driven ONLY by the dedicated entrypoint
## `tests/e2e/run_world_flow.gd` in its OWN isolated Godot process (file name is not
## `test_*`; `tests/e2e/` is excluded from in-runner discovery), because booting the real
## app drives the shared /root/GameState + InputService — which must not happen inside the
## common runner (D-019 / L-010).
##
## It exercises the REAL world/map boundary end to end, no shortcuts:
##   MainMenu.new_game_pressed → Main → WorldRuntime.start_session → SceneRouter loads the
##   hub map → persistent Player parented under the map's PlayerHost at the named spawn →
##   a REAL `interact` InputEvent (Input.parse_input_event) → MapBase._unhandled_input →
##   InputService.is_gameplay_action_just_pressed → MapBase.exit_requested → WorldRuntime
##   .request_map_transition → SceneRouter swaps to the field map → the SAME player persists
##   → back again → repeated round trips do not grow orphans → a REAL `open_menu` event
##   returns to the menu → cleanup leaves no orphan and no duplicate autoload.
##
## Setup-only teleport (player.global_position = exit-zone position) is used to put the
## player inside the exit sensor deterministically; the TRANSITION itself is driven by a
## real semantic input event, not a direct WorldRuntime/SceneRouter call.

const MAIN_SCENE_PATH := "res://main.tscn"
const INTERACT := &"interact"
const OPEN_MENU := &"open_menu"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const REQUIRED_AUTOLOADS := [
	"EventBus", "GameState", "Localization", "InputService", "SceneRouter",
]


func test_real_world_map_flow() -> void:
	# --- 1. all five real autoloads present; none duplicated ----------------------
	for autoload_name in REQUIRED_AUTOLOADS:
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

	assert_eq(gs.get_phase(), gs.Phase.BOOT, "fresh GameState autoload starts at BOOT")

	# --- 2. boot the REAL main scene ---------------------------------------------
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	var main: Node = packed.instantiate()
	scene_tree.root.add_child(main)
	await scene_tree.process_frame

	assert_eq(gs.get_phase(), gs.Phase.MENU, "boot reached MENU before any input")

	# --- 3. New Game via the REAL menu intent → hub map --------------------------
	var ui: Node = main.get_node_or_null("UI")
	assert_not_null(ui)
	if ui == null or ui.get_child_count() == 0:
		_teardown(main)
		return
	var menu: Node = ui.get_child(0)
	assert_true(menu.has_signal("new_game_pressed"), "menu exposes new_game_pressed")
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame

	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "running after New Game")
	assert_eq(router.get_current_key(), "map_hub",
		"New Game loads the hub map as the first scene (Phase 03)")
	assert_eq(gs.call("get_current_map_id"), &"map_hub",
		"GameState records the hub as the current map")
	assert_true(input.call("is_gameplay_active"), "entering the map set GAMEPLAY input context")

	# The persistent player exists, is under the hub's PlayerHost, at the default spawn.
	var world_runtime := _find_world_runtime(main)
	assert_not_null(world_runtime, "Main has a WorldRuntime node under Systems")
	if world_runtime == null:
		_teardown(main)
		return
	var player: Node = world_runtime.call("get_player")
	assert_not_null(player, "WorldRuntime owns a persistent player")
	if player == null:
		_teardown(main)
		return
	var hub_map: Node = router.get_current_scene()
	assert_not_null(hub_map, "hub map instance exists")
	assert_true(_player_is_in_map(player, hub_map), "player is parented inside the hub map")

	# --- 4. move to the hub's exit zone and trigger a REAL interact → field ------
	await _interact_to_transition(player, hub_map)

	assert_eq(router.get_current_key(), "map_field",
		"a real interact on the hub exit transitioned to the field map")
	assert_eq(gs.call("get_current_map_id"), &"map_field", "GameState now records the field")
	var field_map: Node = router.get_current_scene()
	assert_not_null(field_map, "field map instance exists")

	# The SAME player persisted across the transition (not re-created, not freed).
	assert_true(is_instance_valid(player), "the persistent player survived the transition")
	assert_eq(world_runtime.call("get_player"), player, "WorldRuntime keeps the same player")
	assert_true(_player_is_in_map(player, field_map), "player re-parented into the field map")

	# --- 5. go back hub ↔ field repeatedly; no orphan growth ---------------------
	# Baseline after settling the first two swaps.
	await scene_tree.process_frame
	var baseline: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for _i in range(5):
		await _interact_to_transition(player, router.get_current_scene())  # field → hub
		await _interact_to_transition(player, router.get_current_scene())  # hub → field
	await scene_tree.process_frame
	await scene_tree.process_frame
	var after: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_true(after <= baseline,
		"repeated map transitions do not leak orphan nodes (%d -> %d)"
		% [int(baseline), int(after)])
	assert_true(is_instance_valid(player), "player still alive after many transitions")

	# --- 6. a REAL open_menu returns to the menu ---------------------------------
	var active_map: Node = router.get_current_scene()
	assert_not_null(active_map, "a map is active before open_menu")
	# Real key event through the engine + direct handler dispatch while held (same headless
	# belt-and-suspenders as interact). `open_menu` is a system action (not GAMEPLAY-gated).
	_press_action_key(OPEN_MENU)
	if is_instance_valid(active_map) and active_map.has_method("_unhandled_input"):
		active_map.call("_unhandled_input", _make_action_event(OPEN_MENU, true))
	await scene_tree.process_frame
	await scene_tree.process_frame
	_release_action_key(OPEN_MENU)
	assert_eq(gs.get_phase(), gs.Phase.MENU, "open_menu ended the session back to MENU")
	assert_false(gs.is_session_active(), "session ended")
	assert_eq(router.get_current_key(), "", "no content scene after returning to menu")
	assert_false(is_instance_valid(player), "the persistent player was freed on session end")

	# --- 7. cleanup / isolation --------------------------------------------------
	_teardown(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(main), "Main freed after cleanup (no orphan)")
	for autoload_name in REQUIRED_AUTOLOADS:
		assert_eq(_count_named(autoload_name), 1,
			"still exactly one /root/%s after teardown (no duplicate autoload)" % autoload_name)
	# GameState is left in a legal phase (MENU — we returned cleanly), not corrupt.
	assert_eq(gs.get_phase(), gs.Phase.MENU, "GameState remains in a legal phase after teardown")


# --- helpers -----------------------------------------------------------------

## Find the WorldRuntime node Main hangs under Systems (by type, not a hard path).
func _find_world_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is WorldRuntime:
			return child
	return null


## True if `player` is somewhere inside `map`'s subtree (re-parented into its PlayerHost).
func _player_is_in_map(player: Node, map: Node) -> bool:
	if player == null or map == null:
		return false
	var p := player.get_parent()
	while p != null:
		if p == map:
			return true
		p = p.get_parent()
	return false


## Find the first MapExitZone in a map (as a Node2D), or null.
func _first_exit(map: Node) -> Node2D:
	if map == null:
		return null
	var exits := map.get_node_or_null("Exits")
	if exits == null:
		return null
	for zone in exits.get_children():
		if zone is MapExitZone and zone is Node2D:
			return zone as Node2D
	return null


## Walk the player into the map's exit zone using REAL movement input, so the Area2D sensor
## fires `body_entered` via genuine physics motion (teleporting a body by setting
## `global_position` does NOT reliably re-trigger overlap detection — Godot forum / headless
## physics). We press `move_left`/`move_right` toward the exit (polled by the Player in its
## own `_physics_process` → MovementComponent → `move_and_slide`) until the player is within
## the zone's horizontal extent, then release. Returns true if the exit was reached.
func _walk_into_exit(player: Node, map: Node) -> bool:
	var zone := _first_exit(map)
	if zone == null or not (player is Node2D):
		return false
	var p := player as Node2D
	var target_x: float = zone.global_position.x
	var action: StringName = MOVE_RIGHT if target_x > p.global_position.x else MOVE_LEFT
	Input.action_press(action)
	var reached := false
	for _i in range(240):  # bounded; the arena is ~400px wide, plenty of frames
		await scene_tree.physics_frame
		if absf(p.global_position.x - target_x) <= 16.0:
			reached = true
			break
	Input.action_release(action)
	# A couple of frames for the Area2D body_entered to register the overlap.
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	return reached


## Drive one full "walk to the exit + press interact" through the REAL boundary and wait for
## the resulting transition to complete.
##
## Real path exercised: real movement input → Player movement → physics overlap fires the
## exit zone's `body_entered` → `MapBase._active_exit` is set → the `interact` action's
## just_pressed state is set on the Input singleton → `MapBase._unhandled_input` is dispatched
## → `InputService.is_gameplay_action_just_pressed` (gated on GAMEPLAY) →
## `MapBase.exit_requested` → `WorldRuntime.request_map_transition` → `SceneRouter`.
##
## `_unhandled_input` is invoked directly (headless has no window to pump viewport input),
## but every downstream link — real movement, the Area2D active-exit detection, the
## InputService gate, the signal, WorldRuntime, and SceneRouter — runs for real.
func _interact_to_transition(player: Node, map: Node) -> void:
	var before_key := ""
	var router := scene_tree.root.get_node_or_null("SceneRouter")
	if router != null:
		before_key = str(router.call("get_current_key"))

	assert_true(await _walk_into_exit(player, map),
		"player walked into the exit zone (from '%s')" % before_key)

	# Drive the `interact` intent through the engine's REAL input dispatch: feed a key event
	# matching the `interact` action. The engine marks the action just_pressed and dispatches
	# `_unhandled_input` to the in-tree map. As a headless belt-and-suspenders (viewport input
	# propagation can be unreliable with no window), ALSO invoke the map's `_unhandled_input`
	# directly WHILE the key is held — so `is_gameplay_action_just_pressed` is genuinely true.
	_press_action_key(INTERACT)
	if map != null and is_instance_valid(map) and map.has_method("_unhandled_input"):
		map.call("_unhandled_input", _make_action_event(INTERACT, true))
	await scene_tree.process_frame
	await scene_tree.process_frame
	_release_action_key(INTERACT)

	# Let the transition (free old scene + load new + re-parent player) settle.
	await scene_tree.process_frame
	await scene_tree.process_frame

	if router != null:
		assert_ne(str(router.call("get_current_key")), before_key,
			"interact actually changed the active map (was '%s')" % before_key)


## Synthesize and feed the FIRST physical key bound to `action` as a real press event, so the
## engine updates the action state (just_pressed) and dispatches `_unhandled_input` to
## in-tree nodes. Falls back to an InputEventAction if the action has no key event.
func _press_action_key(action: StringName) -> void:
	var ev := _make_action_event(action, true)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release_action_key(action: StringName) -> void:
	var ev := _make_action_event(action, false)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _make_action_event(action: StringName, pressed: bool) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := InputEventKey.new()
			k.physical_keycode = (e as InputEventKey).physical_keycode
			k.keycode = (e as InputEventKey).keycode
			k.pressed = pressed
			return k
	var a := InputEventAction.new()
	a.action = action
	a.pressed = pressed
	a.strength = 1.0 if pressed else 0.0
	return a


func _count_named(node_name: String) -> int:
	var count := 0
	for child in scene_tree.root.get_children():
		if child.name == node_name:
			count += 1
	return count


func _teardown(main: Node) -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

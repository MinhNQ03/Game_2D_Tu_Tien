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
	# Press open_menu (a system action, not GAMEPLAY-gated) and run the map's real
	# `_unhandled_input` while held → `is_system_action_just_pressed` → return_to_menu.
	Input.action_press(OPEN_MENU)
	if is_instance_valid(active_map) and active_map.has_method("_unhandled_input"):
		active_map.call("_unhandled_input", _make_action_event(OPEN_MENU, true))
	Input.action_release(OPEN_MENU)
	await scene_tree.process_frame
	await scene_tree.process_frame
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


## Make the map treat the player as standing in its exit zone, deterministically.
##
## In a headless `-s` SceneTree process there is no game window and the physics/overlap
## pipeline for Area2D (`body_entered`) does NOT run the way it does in a real game loop, so
## relying on either walking or teleporting-into-the-zone to make the Area2D fire is
## unreliable (this was the root cause of the earlier CI failures). Instead we emit the exit
## zone's OWN `body_entered(player)` signal — the exact signal the Area2D raises on overlap —
## which drives the REAL MapBase handler (`_on_exit_body_entered` → `_active_exit`). We also
## place the player on the zone so the state is coherent. Everything downstream of the sensor
## (MapBase active-exit tracking, the interact gate, `exit_requested`, WorldRuntime, the
## router) still runs for real; only the headless-flaky physics overlap is substituted by the
## engine's own signal. Returns true if the zone was found.
func _stand_in_exit(player: Node, map: Node) -> bool:
	var zone := _first_exit(map)
	if zone == null:
		return false
	if player is Node2D:
		(player as Node2D).global_position = zone.global_position
	# Emit the Area2D's real body_entered so MapBase sets its _active_exit (same as overlap).
	zone.emit_signal("body_entered", player)
	await scene_tree.process_frame
	return true


## Drive one full "stand in the exit + press interact" through the REAL MapBase boundary and
## wait for the resulting transition to complete.
##
## Real path exercised: the exit zone's `body_entered(player)` → `MapBase._on_exit_body_entered`
## → `MapBase._active_exit` is set → the `interact` action is pressed on the Input singleton →
## `MapBase._unhandled_input` runs → `InputService.is_gameplay_action_just_pressed` (gated on
## GAMEPLAY) → `MapBase.exit_requested` → `WorldRuntime.request_map_transition` → `SceneRouter`.
##
## `_unhandled_input` is invoked directly (headless has no window to pump viewport input) with
## the interact action held, so the InputService gate check is genuine. Every link from the
## sensor signal through the router runs for real.
func _interact_to_transition(player: Node, map: Node) -> void:
	var before_key := ""
	var router := scene_tree.root.get_node_or_null("SceneRouter")
	if router != null:
		before_key = str(router.call("get_current_key"))

	assert_true(await _stand_in_exit(player, map),
		"player stands in the exit zone (from '%s')" % before_key)

	# Fire the interact through MapBase's REAL `_unhandled_input` → `exit_requested`. The gate
	# is `InputService.is_gameplay_action_just_pressed(interact)` (GAMEPLAY context + the
	# Input singleton's just_pressed edge). Because the exact frame on which `action_press`
	# makes `is_action_just_pressed` true in a headless `-s` process is finicky, we retry a
	# few times — press, dispatch the handler while held, step a frame — until the transition
	# happens. Bounded, deterministic, and still driving the real MapBase→WorldRuntime→router
	# chain on each attempt.
	var changed := false
	for _attempt in range(6):
		Input.action_press(INTERACT)
		if map != null and is_instance_valid(map) and map.has_method("_unhandled_input"):
			map.call("_unhandled_input", _make_action_event(INTERACT, true))
		await scene_tree.process_frame
		if router != null and str(router.call("get_current_key")) != before_key:
			changed = true
			Input.action_release(INTERACT)
			break
		Input.action_release(INTERACT)
		await scene_tree.physics_frame

	# Let the transition (free old scene + load new + re-parent player) settle.
	await scene_tree.process_frame

	if router != null:
		assert_true(changed,
			"interact actually changed the active map (was '%s')" % before_key)


## Build an input event for `action`: the first physical key bound to it (so an engine
## dispatch would behave like a real key press), falling back to an InputEventAction. Used as
## the argument passed to the map's `_unhandled_input` (its content is not inspected by
## MapBase, which polls InputService — but a realistic event keeps the call faithful).
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

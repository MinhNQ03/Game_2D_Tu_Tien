extends TestCase
## E2E world/map-flow assertions (Phase 03 reopen, D-019 isolation + D-022 data-driven).
## A normal TestCase reusing the shared assert_* API, driven ONLY by the dedicated entrypoint
## `tests/e2e/run_world_flow.gd` in its OWN isolated Godot process (D-019 / L-010).
##
## It exercises the REAL world/map boundary end to end, through the REAL input pipeline
## (L-016/L-017): it NEVER calls `MapBase._unhandled_input`, `WorldRuntime.request_map_transition`,
## or `SceneRouter.request_transition` directly to drive gameplay. Semantic input is fed via
## `Input.parse_input_event` with real key events (the engine then dispatches `_input`/
## `_unhandled_input` and updates the InputMap action state). The ONLY headless concession is
## the Area2D sensor overlap: a real game-loop raises `body_entered`, which the headless `-s`
## process does not do reliably, so we emit the exit zone's OWN `body_entered(player)` signal
## (the exact signal the sensor raises) — the REAL MapBase handler then runs. A genuine
## semantic MOVEMENT step is also performed so the InputService movement path is exercised.
##
## Flow: real main.tscn → MainMenu.new_game_pressed → WorldRuntime → SceneRouter → hub map →
## persistent player → real movement → stand in exit (teleport setup) + real interact key →
## field → back → repeat >= 20 round trips (per-round + no-leak invariants) → real open_menu
## key → clean return to menu + player freed.

const MAIN_SCENE_PATH := "res://main.tscn"
const INTERACT := &"interact"
const OPEN_MENU := &"open_menu"
const MOVE_RIGHT := &"move_right"
const SECT_PANEL := &"sect_panel"
const ROUND_TRIPS := 20
const REQUIRED_AUTOLOADS := [
	"EventBus", "GameState", "Localization", "InputService", "SceneRouter",
]


func test_real_world_map_flow() -> void:
	# --- 1. real autoloads present; none duplicated -------------------------------
	for autoload_name in REQUIRED_AUTOLOADS:
		assert_eq(_count_named(autoload_name), 1,
			"exactly one /root/%s (no duplicate autoload)" % autoload_name)

	var gs: Node = scene_tree.root.get_node_or_null("GameState")
	var router: Node = scene_tree.root.get_node_or_null("SceneRouter")
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	if gs == null or router == null or input == null:
		assert_true(false, "core autoloads missing")
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
	if ui == null or ui.get_child_count() == 0:
		assert_true(false, "no MainMenu under UI")
		_teardown(main)
		return
	var menu: Node = ui.get_child(0)
	assert_true(menu.has_signal("new_game_pressed"), "menu exposes new_game_pressed")
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame

	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "running after New Game")
	assert_eq(router.get_current_key(), "map_hub", "New Game loads the hub map first (Phase 03)")
	assert_eq(gs.call("get_current_map_id"), &"map_hub", "GameState records the hub")
	assert_true(input.call("is_gameplay_active"), "entering the map set GAMEPLAY input context")

	var world_runtime := _find_world_runtime(main)
	if world_runtime == null:
		assert_true(false, "WorldRuntime missing under Main/Systems")
		_teardown(main)
		return

	# Phase 05 (D-026): a RelationshipRuntime sibling must exist under Main/Systems, be a
	# non-autoload node, and persist (same instance) across every map swap. Capture its id now.
	var relationship_runtime := _find_relationship_runtime(main)
	assert_not_null(relationship_runtime, "RelationshipRuntime exists under Main/Systems")
	var relationship_id := -1
	if relationship_runtime != null:
		relationship_id = relationship_runtime.get_instance_id()
		assert_true(relationship_runtime.call("is_session_active"),
			"RelationshipRuntime session active after New Game")
		assert_eq(_count_named("RelationshipRuntime"), 0,
			"RelationshipRuntime is NOT an autoload (not under /root)")

	# Phase 06 (Sect): a SectRuntime sibling must exist under Main/Systems, be a non-autoload
	# node, run a session, and have enrolled the player into the authored start sect. Capture
	# its id to assert it survives map swaps.
	var sect_runtime := _find_sect_runtime(main)
	assert_not_null(sect_runtime, "SectRuntime exists under Main/Systems")
	var sect_runtime_id := -1
	if sect_runtime != null:
		sect_runtime_id = sect_runtime.get_instance_id()
		assert_true(sect_runtime.call("is_session_active"),
			"SectRuntime session active after New Game")
		assert_eq(_count_named("SectRuntime"), 0,
			"SectRuntime is NOT an autoload (not under /root)")
		assert_eq(sect_runtime.call("get_player_sect_id"), &"sect_azure_cloud",
			"player enrolled in the authored start sect")

	var player: Node = world_runtime.call("get_player")
	assert_not_null(player, "WorldRuntime owns a persistent player")
	if player == null:
		_teardown(main)
		return
	var player_id := player.get_instance_id()  # proven-persistent identity across all maps

	# Phase 04 (D-023): the player is bound to ONE authoritative CharacterState that must NOT
	# be recreated on a map swap. Capture its identity now and assert it persists below.
	var character = world_runtime.call("get_player_character")
	assert_not_null(character, "WorldRuntime built the player's CharacterState")
	var character_id := -1
	if character != null:
		character_id = character.get_instance_id()
		assert_eq(String(character.instance_id), "player", "player state has the stable id")
		assert_true(character.is_alive(), "player starts ALIVE")
		# Phase 06 / D-015: the player's DERIVED cache matches the authoritative sect roster.
		if sect_runtime != null:
			var player_sect: SectState = sect_runtime.call("get_player_sect")
			assert_not_null(player_sect, "player's authoritative SectState resolves")
			if player_sect != null:
				assert_true(player_sect.is_member(character.instance_id),
					"player is on the authoritative sect roster")
				assert_eq(character.sect_id, player_sect.id,
					"CharacterState.sect_id matches the roster sect")
				assert_eq(character.sect_rank, player_sect.rank_of(character.instance_id),
					"CharacterState.sect_rank matches the roster rank")

	var hub_map: Node = router.get_current_scene()
	assert_true(_player_is_in_map(player, hub_map), "player is parented inside the hub map")

	# Camera limits are data-driven from MapData.bounds (Rect2(16,16,960,576) — D-036).
	_assert_camera_limits(hub_map, 16, 16, 976, 592, "hub")

	# --- 3b. Sect is VISIBLE in the HUD + the panel toggles via REAL input (Phase 06) ----
	var hud := _find_gameplay_hud(hub_map)
	assert_not_null(hud, "the hub map owns a GameplayHUD")
	if hud != null:
		# The HUD renders the player's sect: the localized name appears somewhere, and NO raw
		# sect id leaks into any label.
		var hud_text := _all_label_text(hud)
		var loc: Node = scene_tree.root.get_node_or_null("Localization")
		var sect_name := String(loc.call("t", "SECT_AZURE_CLOUD_NAME")) if loc != null else ""
		assert_true(sect_name != "" and (sect_name in hud_text),
			"HUD shows the localized sect name")
		for t in hud_text:
			assert_false(t.contains("sect_azure_cloud"),
				"no raw sect id leaks into the HUD (%s)" % t)
		# Toggle the Sect detail panel via a REAL `sect_panel` key event (bounded retry for
		# input-dispatch frame timing). It starts closed, opens on the key.
		assert_false(hud.call("is_sect_panel_open"), "sect panel starts closed")
		for _attempt in range(8):
			await _fire_action(SECT_PANEL)
			await scene_tree.process_frame
			if bool(hud.call("is_sect_panel_open")):
				break
		assert_true(hud.call("is_sect_panel_open"), "a real sect_panel key opened the panel")

	# --- 4. a REAL semantic MOVEMENT step (proves InputService movement path) -----
	await _prove_movement(player, input, hub_map)

	# --- 5. first transition hub → field via REAL interact input -----------------
	await _interact_to_transition(player, "map_hub")
	assert_eq(router.get_current_key(), "map_field", "real interact transitioned hub → field")
	assert_eq(gs.call("get_current_map_id"), &"map_field", "GameState now records the field")
	var field_map: Node = router.get_current_scene()
	assert_eq(player.get_instance_id(), player_id, "SAME player instance after transition")
	assert_true(_player_is_in_map(player, field_map), "player re-parented into the field map")
	_assert_camera_limits(field_map, 16, 16, 976, 592, "field")

	# --- 6. >= 20 round trips, per-round invariants + no orphan leak -------------
	await scene_tree.process_frame
	var baseline: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for i in range(ROUND_TRIPS):
		var from_key := str(router.call("get_current_key"))
		await _interact_to_transition(player, from_key)
		var now_key := str(router.call("get_current_key"))
		assert_ne(now_key, from_key, "round %d: map changed (%s -> %s)" % [i, from_key, now_key])
		assert_eq(player.get_instance_id(), player_id, "round %d: SAME player instance" % i)
		# The authoritative CharacterState is NOT recreated on a map swap (D-023 invariant):
		# WorldRuntime owns one for the session and the SAME player node keeps carrying it.
		var round_character = world_runtime.call("get_player_character")
		assert_true(round_character != null and round_character.get_instance_id() == character_id,
			"round %d: SAME CharacterState instance (not recreated on map swap)" % i)
		# The RelationshipRuntime (and its graph) is the SAME instance across the map swap too
		# (D-026): it lives under Main/Systems and is never freed/rebuilt by a content swap.
		var round_rel := _find_relationship_runtime(main)
		assert_true(round_rel != null and round_rel.get_instance_id() == relationship_id,
			"round %d: SAME RelationshipRuntime instance (survives map swap)" % i)
		# The SectRuntime (+ the player's SectState membership) is the SAME across the swap
		# (Phase 06): it lives under Main/Systems and is never freed/rebuilt by a content swap.
		var round_sect := _find_sect_runtime(main)
		assert_true(round_sect != null and round_sect.get_instance_id() == sect_runtime_id,
			"round %d: SAME SectRuntime instance (survives map swap)" % i)
		if round_sect != null:
			assert_eq(round_sect.call("get_player_sect_id"), &"sect_azure_cloud",
				"round %d: player's sect membership persists across the swap" % i)
		assert_eq(_count_player_instances(scene_tree.root), 1, "round %d: exactly one Player" % i)
		var active: Node = router.get_current_scene()
		assert_true(_player_is_in_map(player, active), "round %d: player in active map" % i)
		var world: Node = main.get_node_or_null("World")
		if world != null:
			assert_eq(world.get_child_count(), 1, "round %d: one active content scene" % i)
		assert_eq(gs.call("get_current_map_id"), StringName(now_key),
			"round %d: GameState map id matches router" % i)
		assert_false(router.call("is_transitioning"), "round %d: router not stuck" % i)
	await scene_tree.process_frame
	await scene_tree.process_frame
	var after: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_true(after <= baseline + 2.0,
		"no orphan growth across %d round trips (%d -> %d)"
		% [ROUND_TRIPS, int(baseline), int(after)])
	assert_true(is_instance_valid(player), "player still alive after %d transitions" % ROUND_TRIPS)
	assert_eq(player.get_instance_id(), player_id, "still the SAME player after all transitions")

	# --- 7. a REAL open_menu key returns to the menu + frees the player ----------
	await _fire_action(OPEN_MENU)
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.MENU, "open_menu ended the session back to MENU")
	assert_false(gs.is_session_active(), "session ended")
	assert_eq(router.get_current_key(), "", "no content scene after returning to menu")
	assert_false(is_instance_valid(player), "the persistent player was freed on session end")
	# The relationship subsystem persists as a node but ends its session on return to menu.
	if relationship_runtime != null and is_instance_valid(relationship_runtime):
		assert_false(relationship_runtime.call("is_session_active"),
			"RelationshipRuntime session ended on return to menu")
	# The sect subsystem likewise ends its session + clears its state on return to menu.
	if sect_runtime != null and is_instance_valid(sect_runtime):
		assert_false(sect_runtime.call("is_session_active"),
			"SectRuntime session ended on return to menu")
		assert_eq(sect_runtime.call("get_player_sect_id"), &"",
			"SectRuntime cleared the player's sect on session end")

	# --- 8. cleanup / isolation --------------------------------------------------
	_teardown(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(main), "Main freed after cleanup (no orphan)")
	for autoload_name in REQUIRED_AUTOLOADS:
		assert_eq(_count_named(autoload_name), 1,
			"still exactly one /root/%s after teardown" % autoload_name)
	assert_eq(gs.get_phase(), gs.Phase.MENU, "GameState remains in a legal phase after teardown")


# --- helpers -----------------------------------------------------------------

func _find_world_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is WorldRuntime:
			return child
	return null


func _find_relationship_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is RelationshipRuntime:
			return child
	return null


func _find_sect_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is SectRuntime:
			return child
	return null


## The GameplayHUD inside the active map (a CanvasLayer named "GameplayHUD" MapBase adds).
func _find_gameplay_hud(map: Node) -> Node:
	if map == null:
		return null
	return map.get_node_or_null("GameplayHUD")


## Every Label's text anywhere under `node` (recursive) — for asserting rendered UI content.
func _all_label_text(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		out += _all_label_text(child)
	return out


func _player_is_in_map(player: Node, map: Node) -> bool:
	if player == null or not is_instance_valid(player) or map == null:
		return false
	var p := player.get_parent()
	while p != null:
		if p == map:
			return true
		p = p.get_parent()
	return false


## Count Player instances anywhere under root (duplicate-player guard).
func _count_player_instances(node: Node) -> int:
	var n := 0
	if node is Player:
		n += 1
	for child in node.get_children():
		n += _count_player_instances(child)
	return n


func _assert_camera_limits(map: Node, l: int, t: int, r: int, b: int, tag: String) -> void:
	var cam := map.get_node_or_null("Camera2D")
	if cam == null or not (cam is Camera2D):
		assert_true(false, "%s map has no Camera2D" % tag)
		return
	var c := cam as Camera2D
	assert_eq(c.limit_left, l, "%s camera limit_left" % tag)
	assert_eq(c.limit_top, t, "%s camera limit_top" % tag)
	assert_eq(c.limit_right, r, "%s camera limit_right" % tag)
	assert_eq(c.limit_bottom, b, "%s camera limit_bottom" % tag)


## Drive a genuine semantic MOVEMENT: press move_right (real key event + action state), let
## the Player poll InputService.get_move_vector() in its own _physics_process, then release.
##
## Also proves the camera FOLLOWS (D-036): the map's Camera2D is a plain child node, so
## before this it stayed at its authored position and the player simply walked out of frame
## once the view became smaller than the map. Asserting "the camera moved toward the player"
## is the observable contract — not "the camera equals the player", because position
## smoothing eases it over several frames.
func _prove_movement(player: Node, input: Node, map: Node) -> void:
	if not (player is Node2D):
		return
	var p := player as Node2D
	var cam := map.get_node_or_null("Camera2D") as Camera2D

	# Start well left of centre so a correct follow must travel a visible distance right.
	p.global_position = Vector2(120, 304)
	await scene_tree.physics_frame
	var start_x: float = p.global_position.x
	var cam_start_x: float = cam.global_position.x if cam != null else 0.0

	Input.action_press(MOVE_RIGHT)
	for _i in range(12):
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	await scene_tree.physics_frame
	assert_true(p.global_position.x > start_x,
		"player moved right via a real semantic move action (InputService path)")
	assert_true(input.call("is_gameplay_active"), "still GAMEPLAY context after movement")

	assert_not_null(cam, "the map has a Camera2D to follow with")
	if cam != null:
		# Let the smoothing settle so this does not depend on a single frame.
		for _j in range(30):
			await scene_tree.physics_frame
		assert_true(cam.global_position.x > cam_start_x,
			"camera tracked the player instead of staying at its authored position "
			+ "(was %.1f, now %.1f)" % [cam_start_x, cam.global_position.x])
		# And it must never be dragged outside the authored map bounds.
		assert_true(cam.global_position.x >= float(cam.limit_left)
			and cam.global_position.x <= float(cam.limit_right),
			"camera stayed within the horizontal map limits while following")


## Stand the player in the active map's exit zone (teleport setup) and fire the exit via the
## REAL input pipeline: emit the sensor's real `body_entered` (headless Area2D concession,
## L-016) so MapBase sets its active exit, then feed a REAL `interact` key event through
## `Input.parse_input_event` (no direct `_unhandled_input` call). Retries a bounded number of
## frames so input-dispatch frame timing can't cause a false negative. Waits for the swap.
func _interact_to_transition(player: Node, from_key: String) -> void:
	var router := scene_tree.root.get_node_or_null("SceneRouter")
	var active: Node = router.call("get_current_scene") if router != null else null
	var zone := _first_exit_zone(active)
	assert_not_null(zone, "active map '%s' has an exit zone" % from_key)
	if zone == null:
		return
	# Teleport the player onto the zone (setup) and raise the sensor's real signal so the
	# REAL MapBase handler sets _active_exit (headless physics won't raise it on its own).
	if player is Node2D:
		(player as Node2D).global_position = (zone as Node2D).global_position
	zone.emit_signal("body_entered", player)
	await scene_tree.process_frame

	# Fire the interact action via the REAL input pipeline, bounded-retry until the map swaps.
	for _attempt in range(8):
		await _fire_action(INTERACT)
		await scene_tree.process_frame
		if router != null and str(router.call("get_current_key")) != from_key:
			break
	await scene_tree.process_frame


## First MapExitZone (Node2D) in a map's Exits, or null.
func _first_exit_zone(map: Node) -> Node2D:
	if map == null:
		return null
	var exits := map.get_node_or_null("Exits")
	if exits == null:
		return null
	for zone in exits.get_children():
		if zone is MapExitZone and zone is Node2D:
			return zone as Node2D
	return null


## Feed a REAL key press+release for `action` through the engine input pipeline. The engine
## updates the InputMap action state (so is_*_just_pressed is true) AND dispatches
## `_input`/`_unhandled_input` to in-tree nodes on the processed frame. No direct handler call.
func _fire_action(action: StringName) -> void:
	var press := _key_event_for(action, true)
	if press == null:
		# Fallback: action with no key binding — still drive via the action state so the
		# gate check is real (should not happen for interact/open_menu which bind keys).
		Input.action_press(action)
		await scene_tree.process_frame
		Input.action_release(action)
		return
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await scene_tree.process_frame
	var release := _key_event_for(action, false)
	if release != null:
		Input.parse_input_event(release)
		Input.flush_buffered_events()
	await scene_tree.process_frame


## Build an InputEventKey from the first physical key bound to `action`, or null if none.
func _key_event_for(action: StringName, pressed: bool) -> InputEventKey:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := InputEventKey.new()
			k.physical_keycode = (e as InputEventKey).physical_keycode
			k.keycode = (e as InputEventKey).keycode
			k.pressed = pressed
			return k
	return null


func _count_named(node_name: String) -> int:
	var count := 0
	for child in scene_tree.root.get_children():
		if child.name == node_name:
			count += 1
	return count


func _teardown(main: Node) -> void:
	for a in [MOVE_RIGHT, INTERACT, OPEN_MENU]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

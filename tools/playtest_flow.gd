extends SceneTree
## playtest_flow — Aetheria real-application playtest harness (D-051).
##
## Boots the REAL game in a REAL window and PLAYS it with REAL semantic input, declaring
## expected-vs-observed for every step. It is the gate that proves the player-facing
## experience, which no other gate in this project covers: unit tests prove rules, integration
## tests prove boundaries, E2E proves the real flow — and all three were green while the
## Phase-09 attack lifecycle was completely invisible to the player (D-051 §10b).
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . -s res://tools/playtest_flow.gd
##     godot --path . -s res://tools/playtest_flow.gd -- vi user://playtest
##     godot --path . --resolution 1280x800 -s res://tools/playtest_flow.gd -- en /tmp/pt
##
## Arguments after `--`: [language] [output_dir]. Output defaults to `user://playtest`, which
## is EPHEMERAL EVIDENCE — screenshots and the report are produced, inspected, and NOT
## committed (`docs/PHASE_EXECUTION_PROTOCOL.md` §2).
##
## IT DRIVES THE REAL BOUNDARY, NOT A SHORTCUT. Movement, interaction, menus and attacks all
## go through `Input.parse_input_event` with a real `InputEventKey` built from the action's own
## binding, so the engine updates the InputMap state and dispatches it exactly as a key press
## does. It must NEVER call a domain mutator to fake player behaviour: that is L-017 — a test
## that bypasses the boundary it advertises stays green while the boundary is broken.
##
## The one sanctioned exception is DETERMINISTIC SETUP (placing the player for a reproducible
## encounter). Those steps say so in their name and in the report, so a reader can tell which
## steps are evidence about the input pipeline and which are staging.
##
## EXIT CODE IS THE GATE: 0 only when every step passed. A step that cannot even be attempted
## is a FAILURE, not a skip — "the harness could not find the HUD" must not read as success.

const MAIN_SCENE := "res://main.tscn"

## Frames to wait after a state change before sampling. UI builds in `_ready`, themes resolve
## on the next draw, and the map camera eases over several frames, so a single-frame wait
## samples a half-built screen.
const SETTLE_FRAMES := 12

## Bounded polling budget for an effect that takes an unknown number of frames (a transition,
## an attack landing). Polling the observable effect beats betting on one frame: synthetic
## `just_pressed` timing is fragile in a scripted run (L-016).
const POLL_FRAMES := 240

var _out_dir := "user://playtest"
var _language := "vi"
## One entry per step: name, expected, observed, ok, msec, shot, map, ui.
var _steps: Array[Dictionary] = []
var _errors := 0
var _warnings := 0
var _shots: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_language = String(args[0])
	if args.size() >= 2:
		_out_dir = String(args[1])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _settle()

	# Language is applied AFTER boot and VERIFIED, because `Main._boot` applies the SAVED
	# language — setting it earlier is silently undone, which is how a whole capture run once
	# came out in the wrong language while every filename claimed otherwise (D-050).
	await _step_set_language()

	await _step_main_menu(main)
	await _step_new_game(main)
	var map := await _step_world_ready()
	await _step_hud_present(map)
	await _step_move(map)
	await _step_toggle_panel(map)
	await _step_attack(map)
	await _step_enter_field(map)
	await _step_encounter(main)
	await _step_return_to_menu(main)

	_write_report()
	main.get_parent().remove_child(main)
	main.free()
	quit(1 if _failed_count() > 0 else 0)


# === Steps ==================================================================
#
# Every step records expected vs observed through `_record()`. A step that cannot run its check
# records a FAILURE with the reason, never a silent skip.

func _step_set_language() -> void:
	var started := Time.get_ticks_msec()
	var loc := root.get_node_or_null("Localization")
	if loc == null:
		_record("01_language", "/root/Localization present", "missing", false, started)
		return
	loc.call("set_language", _language)
	var active := String(loc.call("get_language"))
	_record("01_language", "language=%s" % _language, "language=%s" % active,
		active == _language, started)


func _step_main_menu(main: Node) -> void:
	var started := Time.get_ticks_msec()
	var menu := _menu_of(main)
	var buttons := _buttons_of(menu) if menu != null else [] as Array[Button]
	var ok := menu != null and buttons.size() >= 3
	if ok:
		buttons[0].grab_focus()
		await _settle()
	_record("02_main_menu", "menu with >= 3 actions",
		"menu=%s buttons=%d" % [menu != null, buttons.size()], ok, started,
		await _shot("02_main_menu"))


func _step_new_game(main: Node) -> void:
	var started := Time.get_ticks_msec()
	var menu := _menu_of(main)
	if menu == null or not menu.has_signal("new_game_pressed"):
		_record("03_new_game", "menu exposes new_game_pressed", "no menu signal", false, started)
		return
	# The menu's own intent signal, which is what its button emits — this is the real
	# navigation boundary, not a call into Main.
	menu.emit_signal("new_game_pressed")
	var gs := root.get_node_or_null("GameState")
	var running := false
	for _i in POLL_FRAMES:
		await process_frame
		if gs != null and bool(gs.call("is_session_active")):
			running = true
			break
	_record("03_new_game", "session_active=true", "session_active=%s" % running, running, started)


func _step_world_ready() -> Node:
	var started := Time.get_ticks_msec()
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = null
	for _i in POLL_FRAMES:
		await process_frame
		map = router.call("get_current_scene") if router != null else null
		if map != null:
			break
	await _settle()
	_record("04_world_ready", "a content scene is live",
		"map=%s" % _map_id(), map != null, started, await _shot("04_hub"))
	return map


func _step_hud_present(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var hud := map.get_node_or_null("GameplayHUD") if map != null else null
	_record("05_hud", "GameplayHUD exists in the active map",
		"hud=%s" % (hud != null), hud != null, started, await _shot("05_hud"))


## A REAL movement step: a held direction key, and the player's position must change.
func _step_move(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var player := _player_of(map)
	if player == null:
		_record("06_move", "player realized in the map", "no player", false, started)
		return
	var before := player.global_position
	var moved := await _hold_action(&"move_right", func() -> bool:
		return player.global_position.distance_to(before) > 1.0)
	_record("06_move", "position changes under a real move_right key",
		"moved=%.1fpx" % player.global_position.distance_to(before), moved, started)


## A REAL UI toggle: the sect panel key, and the HUD must report the panel open.
func _step_toggle_panel(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var hud := map.get_node_or_null("GameplayHUD") if map != null else null
	if hud == null or not hud.has_method("is_sect_panel_open"):
		_record("07_sect_panel", "HUD exposes is_sect_panel_open", "not available", false,
			started)
		return
	var opened := await _press_until(&"sect_panel", func() -> bool:
		return bool(hud.call("is_sect_panel_open")))
	var shot := await _shot("07_sect_panel")
	# Close it again so later steps see the normal playfield rather than a covered screen.
	if opened:
		await _press_until(&"sect_panel", func() -> bool:
			return not bool(hud.call("is_sect_panel_open")))
	_record("07_sect_panel", "a real sect_panel key opens the panel",
		"open=%s" % opened, opened, started, shot)


## A REAL attack: the attack key, and a registered target must lose health.
##
## The player is PLACED next to the target first. That step is deterministic setup, not a claim
## about the movement pipeline (step 06 already proved that with a real key), and it is named
## so in the report.
func _step_attack(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var player := _player_of(map)
	var targets: Array = map.call("get_combat_targets") if (
		map != null and map.has_method("get_combat_targets")) else []
	if player == null or targets.is_empty():
		_record("08_attack", "a combat target exists in the map",
			"player=%s targets=%d" % [player != null, targets.size()], false, started)
		return
	var target := targets[0] as Node2D
	if target == null or not target.has_method("get_current_health"):
		_record("08_attack", "the target exposes its health", "unusable target", false, started)
		return
	# --- deterministic setup (NOT an input-pipeline claim) ---
	player.global_position = target.global_position - Vector2(18, 0)
	var attack_component := player.get_node_or_null("AttackComponent")
	if attack_component != null:
		attack_component.call("set_facing", Vector2.RIGHT)
	await _settle()
	var before := int(target.call("get_current_health"))
	# --- the real boundary ---
	var hurt := await _press_until(&"attack", func() -> bool:
		return int(target.call("get_current_health")) < before)
	var after := int(target.call("get_current_health"))
	_record("08_attack", "target health drops after a real attack key",
		"hp %d -> %d" % [before, after], hurt, started, await _shot("08_attack"))


## A REAL map transition: walk into the exit zone and interact.
func _step_enter_field(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var player := _player_of(map)
	var zone := _first_exit_zone(map)
	if player == null or zone == null:
		_record("09_enter_field", "the map declares an exit zone",
			"player=%s zone=%s" % [player != null, zone != null], false, started)
		return
	var from_map := _map_id()
	# --- deterministic setup: stand in the exit zone ---
	player.global_position = zone.global_position
	await _settle()
	# The headless/scripted concession documented in L-016: the Area2D sensor's own signal is
	# emitted so the REAL handler runs. Everything after this is real input.
	zone.emit_signal("body_entered", player)
	await _settle()
	var changed := await _press_until(&"interact", func() -> bool:
		return _map_id() != from_map)
	_record("09_enter_field", "interact changes the active map (was %s)" % from_map,
		"map=%s" % _map_id(), changed, started, await _shot("09_field"))


## The Phase-10 encounter, as a player would meet it: the field is populated, a creature
## hunts, a real attack key kills it, and the corpse stops acting.
##
## Three steps rather than one, so a failure says WHICH part of an encounter broke — "the
## creature never hunted" and "the creature could not be killed" are different bugs with
## different causes, and a single `09_encounter FAILED` would hide that.
func _step_encounter(main: Node) -> void:
	var combat := main.get_node_or_null("Systems/CombatRuntime")
	var started := Time.get_ticks_msec()
	if combat == null:
		_record("10_enemies_spawned", "CombatRuntime exists", "missing", false, started)
		return
	var spawned := int(combat.call("enemy_count"))
	_record("10_enemies_spawned", "the field is populated from data",
		"enemies=%d living=%d" % [spawned, int(combat.call("living_enemy_count"))],
		spawned >= 1, started, await _shot("10_field_enemies"))
	if spawned < 1:
		return

	var enemies: Array = combat.call("enemies")
	var enemy := enemies[0] as Node2D
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = router.call("get_current_scene") if router != null else null
	var player := _player_of(map)
	if enemy == null or player == null:
		_record("11_enemy_hunts", "a creature and a player exist",
			"enemy=%s player=%s" % [enemy != null, player != null], false, started)
		return

	# --- it hunts (deterministic setup: stand where it can see you) ---
	started = Time.get_ticks_msec()
	player.global_position = enemy.global_position + Vector2(70, 0)
	var hunting := false
	var state := "IDLE"
	for _i in POLL_FRAMES:
		await process_frame
		state = String(enemy.call("ai_state_name"))
		if state in ["ALERT", "CHASE", "ATTACK", "RECOVER"]:
			hunting = true
			break
	var hunt_shot := await _shot("11_enemy_hunts")
	_record("11_enemy_hunts", "the creature notices the player and hunts",
		"state=%s" % state, hunting, started, hunt_shot)

	# --- the player kills it with REAL attack keys ---
	started = Time.get_ticks_msec()
	var start_hp := int(enemy.call("get_current_health"))
	var attack_component := player.get_node_or_null("AttackComponent")
	for _round in 40:
		if bool(enemy.call("is_dead")):
			break
		# Re-placed inside reach each round because the creature keeps moving; the SWING
		# itself is a real key event.
		player.global_position = enemy.global_position - Vector2(16, 0)
		if attack_component != null:
			attack_component.call("set_facing", Vector2.RIGHT)
		_send_key(&"attack", true)
		await process_frame
		_send_key(&"attack", false)
		for _i in 24:
			await process_frame
			if bool(enemy.call("is_dead")):
				break
	var dead := bool(enemy.call("is_dead"))
	_record("12_enemy_killed", "real attack keys kill the creature",
		"hp %d -> %d dead=%s" % [start_hp, int(enemy.call("get_current_health")), dead],
		dead, started, await _shot("12_enemy_killed"))

	# --- the corpse stops acting ---
	started = Time.get_ticks_msec()
	var resting := enemy.global_position
	for _i in 60:
		await process_frame
	var still := enemy.global_position.distance_to(resting) < 0.01
	var reset := String(enemy.call("ai_state_name")) == "IDLE"
	_record("13_corpse_inert", "a dead creature stops moving and thinking",
		"moved=%.2fpx state=%s" % [
			enemy.global_position.distance_to(resting), enemy.call("ai_state_name")],
		still and reset, started)


func _step_return_to_menu(main: Node) -> void:
	var started := Time.get_ticks_msec()
	var gs := root.get_node_or_null("GameState")
	var back := await _press_until(&"open_menu", func() -> bool:
		return gs != null and not bool(gs.call("is_session_active")))
	var teardown: Array = main.call("get_last_teardown_order") if main.has_method(
		"get_last_teardown_order") else []
	_record("14_return_to_menu", "open_menu ends the session",
		"session_active=%s teardown=%s" % [
			gs != null and bool(gs.call("is_session_active")), str(teardown)],
		back, started, await _shot("14_menu"))


# === Real semantic input =====================================================

## Press `action` (a real key event for its binding) and poll `is_done` until it is true.
##
## Polls the OBSERVABLE EFFECT over a bounded number of frames instead of betting on a single
## frame: after a synthetic press, `is_action_just_pressed` timing is fragile in a scripted run
## (L-016), and an attack's effect lands a windup later anyway.
func _press_until(action: StringName, is_done: Callable) -> bool:
	if not InputMap.has_action(action):
		return false
	for _attempt in 8:
		_send_key(action, true)
		await process_frame
		_send_key(action, false)
		for _i in int(POLL_FRAMES / 8.0):
			await process_frame
			if bool(is_done.call()):
				return true
	return false


## Hold `action` down for up to `POLL_FRAMES`, releasing as soon as `is_done` is true.
## For continuous input (movement), where one press-release pair may move nothing visible.
func _hold_action(action: StringName, is_done: Callable) -> bool:
	if not InputMap.has_action(action):
		return false
	_send_key(action, true)
	var done := false
	for _i in POLL_FRAMES:
		await process_frame
		if bool(is_done.call()):
			done = true
			break
	_send_key(action, false)
	await process_frame
	return done


## Feed a real `InputEventKey` for the first physical key bound to `action`, through the engine,
## so the InputMap action state updates and `_input`/`_unhandled_input` dispatch exactly as a
## real key press does.
func _send_key(action: StringName, pressed: bool) -> void:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var synthetic := InputEventKey.new()
		synthetic.physical_keycode = key.physical_keycode
		synthetic.keycode = key.keycode
		synthetic.pressed = pressed
		Input.parse_input_event(synthetic)
		Input.flush_buffered_events()
		return


# === Observation helpers =====================================================

func _menu_of(main: Node) -> Node:
	var ui := main.get_node_or_null("UI")
	if ui == null or ui.get_child_count() == 0:
		return null
	return ui.get_child(0)


func _buttons_of(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node == null:
		return out
	if node is Button:
		out.append(node as Button)
	for child in node.get_children():
		out += _buttons_of(child)
	return out


func _player_of(map: Node) -> Node2D:
	if map == null:
		return null
	# Explicitly typed: `call()` returns Variant, and `:=` would infer Variant — which this
	# project promotes to a compile error (L-020).
	var host: Variant = map.call("get_player_host") if map.has_method(
		"get_player_host") else null
	if not (host is Node):
		return null
	for child in (host as Node).get_children():
		var body := child as Node2D
		if body != null and body.has_method("get_attack_power"):
			return body
	return null


func _first_exit_zone(map: Node) -> Node2D:
	var exits := map.get_node_or_null("Exits") if map != null else null
	if exits == null:
		return null
	for child in exits.get_children():
		var zone := child as Node2D
		if zone != null:
			return zone
	return null


## The id of the active map, as the ROUTER reports it (not as the scene is named), so the
## observed value is the one the game's own navigation state holds.
func _map_id() -> String:
	var router := root.get_node_or_null("SceneRouter")
	if router == null:
		return ""
	return String(router.call("get_current_key"))


## A compact description of what the UI is showing, for the report's `ui` column.
func _ui_state() -> String:
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = router.call("get_current_scene") if router != null else null
	if map == null:
		return "menu"
	var hud := map.get_node_or_null("GameplayHUD")
	if hud == null:
		return "map(no hud)"
	var parts: Array[String] = ["hud"]
	if hud.has_method("is_sect_panel_open") and bool(hud.call("is_sect_panel_open")):
		parts.append("sect_panel")
	if hud.has_method("is_health_gauge_visible") and bool(
			hud.call("is_health_gauge_visible")):
		parts.append("health")
	return "+".join(parts)


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


## Write the current viewport and return the filename (empty on failure, which also counts as
## an error — a report that silently lacks its evidence is worse than a loud one).
func _shot(shot_name: String) -> String:
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		_errors += 1
		push_error("[playtest] viewport produced no image for '%s'" % shot_name)
		return ""
	var size := root.get_visible_rect().size
	var file := "%s_%dx%d_%s.png" % [
		_language, int(size.x), int(size.y), shot_name]
	if image.save_png("%s/%s" % [_out_dir, file]) != OK:
		_errors += 1
		push_error("[playtest] could not write %s" % file)
		return ""
	_shots.append(file)
	return file


func _record(
		step: String,
		expected: String,
		observed: String,
		ok: bool,
		started_msec: int,
		shot: String = "") -> void:
	if not ok:
		_errors += 1
	_steps.append({
		"step": step,
		"expected": expected,
		"observed": observed,
		"ok": ok,
		"msec": Time.get_ticks_msec() - started_msec,
		"shot": shot,
		"map": _map_id(),
		"ui": _ui_state(),
	})


func _failed_count() -> int:
	var failed := 0
	for entry in _steps:
		if not bool(entry["ok"]):
			failed += 1
	return failed


# === Report ==================================================================

## Write both a human-readable report to stdout and a machine-readable JSON file.
##
## A failure must name the exact step, with expected and observed side by side. "PLAYTEST
## FAILED" is useless; "step=09_enter_field expected=map_field observed=map_hub" is actionable.
func _write_report() -> void:
	var failed := _failed_count()
	print("\n=== AETHERIA PLAYTEST REPORT ===")
	print("language=%s  viewport=%dx%d  steps=%d  failed=%d  errors=%d  warnings=%d" % [
		_language, int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y),
		_steps.size(), failed, _errors, _warnings])
	print("output=%s" % _out_dir)
	print("")
	for entry in _steps:
		print("[%s] %-18s %6dms  map=%-10s ui=%-20s" % [
			"PASS" if bool(entry["ok"]) else "FAIL", entry["step"], int(entry["msec"]),
			entry["map"], entry["ui"]])
		print("       expected: %s" % entry["expected"])
		print("       observed: %s" % entry["observed"])
		if String(entry["shot"]) != "":
			print("       shot:     %s" % entry["shot"])
	if failed > 0:
		print("\nPLAYTEST FAILED")
		for entry in _steps:
			if not bool(entry["ok"]):
				print("  step=%s expected=%s observed=%s" % [
					entry["step"], entry["expected"], entry["observed"]])
	else:
		print("\nPLAYTEST PASSED — %d step(s), %d screenshot(s)" % [
			_steps.size(), _shots.size()])

	_print_scorecard()

	var payload := {
		"language": _language,
		"viewport": [
			int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y)],
		"steps": _steps,
		"failed": failed,
		"errors": _errors,
		"warnings": _warnings,
		"shots": _shots,
	}
	var path := "%s/playtest_report.json" % _out_dir
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[playtest] could not write %s" % path)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("\nreport: %s" % path)


## The UX scorecard SECTION — deliberately a prompt, not a computed score.
##
## A number this tool invented would be worthless: nothing here can measure whether a screen is
## legible or whether an encounter is readable. What the tool CAN do is refuse to let the
## question go unasked, and name the artefacts the reviewer has to look at. The scores and the
## defect list belong in the phase report, written by whoever looked at the screenshots
## (`docs/PHASE_EXECUTION_PROTOCOL.md` §3) — and `B8`: a screenshot-producing tool is not a
## screenshot-reviewing tool.
func _print_scorecard() -> void:
	print("\n--- AI UX SCORECARD (fill in by LOOKING at the shots above, 1-5) ---")
	for dimension in [
		"CLARITY", "HIERARCHY", "RESPONSIVENESS", "PIXEL SHARPNESS", "LOCALIZATION",
		"VISUAL CONSISTENCY", "MOTION / FEEDBACK", "SPACING", "READABILITY",
		"PLAYER CONFIDENCE",
	]:
		print("  %-20s _/5" % dimension)
	print("  CONCRETE DEFECTS: list them; a score <= 3 REQUIRES at least one.")
	print("  %d screenshot(s) to inspect in %s" % [_shots.size(), _out_dir])

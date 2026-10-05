extends SceneTree
## capture_ui — Aetheria UI visual-regression capture harness.
##
## Boots the REAL application in a REAL window, drives it to each required UI state, and
## writes a PNG of the actual viewport. Not a mockup, not an editor screenshot — the thing the
## player sees (`docs/UI_UX_BIBLE.md` review discipline, D-050 §B22).
##
## WHY THIS EXISTS: for eight phases every art/layout claim in this repository ended with "the
## on-screen result has not been seen" (D-009's shadow), because the only way to run the engine
## was headless and headless renders nothing. A display is available now, so the gap is a
## tooling gap rather than a hard constraint — and a layout bug is the one class of defect that
## NO assertion catches (D-034's four simultaneous HUD failures were all invisible to tests).
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . --resolution 1920x1080 -s res://tools/capture_ui.gd -- vi out/dir
##     godot --path . --resolution 1280x720  -s res://tools/capture_ui.gd -- en out/dir
##
## It is a BUILD-TIME TOOL: nothing in the game depends on it, and it is excluded from the
## shipped game the same way `gen_prototype_assets.py` is.

const MAIN_SCENE := "res://main.tscn"

## Frames to wait after a state change before sampling. UI builds in `_ready`, themes resolve
## on the next draw, and `position_smoothing` on the map camera eases over several frames — a
## single-frame wait captures a half-built screen and would make every capture a lie.
const SETTLE_FRAMES := 12

var _out_dir := "user://ui_captures"
var _language := "vi"
var _written: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_language = String(args[0])
	if args.size() >= 2:
		_out_dir = String(args[1])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var loc := root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", _language)

	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _settle()

	var ui: Node = main.get_node_or_null("UI")
	var menu: Node = ui.get_child(0) if (ui != null and ui.get_child_count() > 0) else null
	if menu == null:
		push_error("[capture] no main menu under Main/UI")
		quit(1)
		return

	# --- 1-3. Main menu, and its focus states -------------------------------------
	await _shot("01_main_menu")
	# Focus is part of the visual contract (a keyboard player must SEE where they are), so it
	# is captured rather than assumed. Driven through the real buttons the menu built.
	var buttons := _buttons_of(menu)
	if buttons.size() > 0:
		buttons[0].grab_focus()
		await _settle()
		await _shot("02_main_menu_focus_first")
	var disabled := _first_disabled(buttons)
	if disabled != null:
		# A disabled control cannot take focus, so focus its neighbour and capture the pair —
		# the point is that "unavailable" reads as unavailable NEXT TO an available item.
		var idx := buttons.find(disabled)
		var neighbour: Button = buttons[idx + 1] if idx + 1 < buttons.size() else buttons[0]
		neighbour.grab_focus()
		await _settle()
		await _shot("03_main_menu_disabled_load")

	# --- 4. Settings --------------------------------------------------------------
	if menu.has_signal("settings_pressed"):
		menu.emit_signal("settings_pressed")
		await _settle()
		await _shot("04_settings")
		if main.has_method("is_settings_open") and bool(main.call("is_settings_open")):
			var settings: Node = main.get_node("UI").get_child(
				main.get_node("UI").get_child_count() - 1)
			if settings.has_signal("close_requested"):
				settings.emit_signal("close_requested")
				await _settle()

	# --- 5-8. Gameplay: hub, HUD, sect panel, world time --------------------------
	if menu.has_signal("new_game_pressed"):
		menu.emit_signal("new_game_pressed")
		await _settle()
		await _settle()
		await _shot("05_hub_gameplay")

		var router := root.get_node_or_null("SceneRouter")
		var map: Node = router.call("get_current_scene") if router != null else null
		var hud := map.get_node_or_null("GameplayHUD") if map != null else null
		if hud != null:
			await _shot("06_hub_hud")
			# The side panels are the densest UI in the game and the likeliest to clip, so
			# each is captured OPEN rather than trusted.
			if hud.has_method("is_sect_panel_open") and not bool(
					hud.call("is_sect_panel_open")):
				_toggle_panel(hud, "_sect_panel")
			await _settle()
			await _shot("07_sect_panel")
			_toggle_panel(hud, "_faction_panel")
			await _settle()
			await _shot("08_faction_panel")

	print("[capture] wrote %d file(s) to %s" % [_written.size(), _out_dir])
	for name in _written:
		print("[capture]   %s" % name)
	main.get_parent().remove_child(main)
	main.free()
	quit(0)


## Toggle a HUD side panel by property name. The HUD owns its panels privately and exposes
## only `is_*_open()`, so the capture harness flips `visible` directly — acceptable HERE
## because this is a build-time tool whose entire job is to look at presentation, and the
## alternative (feeding real key events) adds input-timing flakiness to a screenshot.
func _toggle_panel(hud: Node, property: String) -> void:
	var panel: Variant = hud.get(property)
	if panel is Control:
		(panel as Control).visible = not (panel as Control).visible


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


## Write the current viewport to `<out>/<language>_<width>x<height>_<name>.png`.
func _shot(shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		push_error("[capture] viewport produced no image for '%s'" % shot_name)
		return
	var size := root.get_visible_rect().size
	var file := "%s/%s_%dx%d_%s.png" % [
		_out_dir, _language, int(size.x), int(size.y), shot_name]
	if image.save_png(file) != OK:
		push_error("[capture] could not write %s" % file)
		return
	_written.append(file.get_file())


## Every Button under `node`, in tree order (the order a keyboard player walks).
func _buttons_of(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node as Button)
	for child in node.get_children():
		out += _buttons_of(child)
	return out


func _first_disabled(buttons: Array[Button]) -> Button:
	for button in buttons:
		if button.disabled:
			return button
	return null

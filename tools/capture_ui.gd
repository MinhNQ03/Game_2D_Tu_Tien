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
##     godot --path . --resolution 1280x720 -s res://tools/capture_ui.gd -- vi out/dir
##     godot --path . --resolution 1280x800 -s res://tools/capture_ui.gd -- en out/dir
##
## VARY THE ASPECT RATIO, NOT JUST THE PIXEL COUNT. The project stretches with
## `canvas_items` + `expand`, so a window at the SAME aspect as the authored 1280x720 is a
## pure uniform scale: the viewport the UI is laid out in stays 1280x720 and every control
## keeps the same relationship to every other one. Capturing 1600x900 next to 1280x720
## therefore proves nothing about layout — it produces two identical images at different
## sizes. A different aspect (e.g. 1280x800, 16:10) genuinely changes the visible rect, which
## is where anchors, reserved strips and bounded boxes can actually break.
##
## The window manager may also refuse a window larger than the desktop, which silently gives
## a different viewport than requested — which is why each filename records the viewport the
## frame was ACTUALLY rendered at, not the resolution that was asked for.
##
## It is a BUILD-TIME TOOL: nothing in the game depends on it, and it is excluded from the
## shipped game the same way `gen_prototype_assets.py` is.

const MAIN_SCENE := "res://main.tscn"

## Frames to wait after a state change before sampling. UI builds in `_ready`, themes resolve
## on the next draw, and `position_smoothing` on the map camera eases over several frames — a
## single-frame wait captures a half-built screen and would make every capture a lie.
const SETTLE_FRAMES := 12

## Upper bound on frames to wait for the main menu to exist (see `_await_menu`). Generous,
## because it only costs time on the slow path; a run that never finds a menu still fails.
const MENU_WAIT_FRAMES := 240

var _out_dir := "user://ui_captures"
var _language := "vi"
var _written: Array[String] = []
var _failed := false


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

	# LANGUAGE IS SET AFTER BOOT, ON PURPOSE, AND VERIFIED.
	#
	# `Main._boot` applies the language saved in `SettingsStore`, so setting it before
	# `add_child` is silently undone — which is how every `vi_*.png` in the first capture run
	# came out in ENGLISH. The filename named a language the screenshot was not in: the same
	# lying-artifact failure as a screenshot named after a panel that never opened, and worse,
	# because a reviewer comparing vi against en would have been comparing en against en.
	# Boot first, then switch, then verify, then let the UI rebuild from `language_changed`.
	if not _apply_language():
		quit(1)
		return
	await _settle()

	var menu := await _await_menu(main)
	if menu == null:
		push_error("[capture] no main menu under Main/UI after %d frames" % MENU_WAIT_FRAMES)
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
			# each is captured OPEN rather than trusted. A failed toggle writes NO file:
			# a missing capture is honest, a closed-panel capture named `07_sect_panel`
			# is not.
			var sect_opened := true
			if hud.has_method("is_sect_panel_open") and not bool(
					hud.call("is_sect_panel_open")):
				sect_opened = _toggle_panel(hud, "_sect_panel")
			if sect_opened:
				await _settle()
				await _shot("07_sect_panel")
			if _toggle_panel(hud, "_faction_panel"):
				await _settle()
				await _shot("08_faction_panel")

	print("[capture] wrote %d file(s) to %s" % [_written.size(), _out_dir])
	for name in _written:
		print("[capture]   %s" % name)
	main.get_parent().remove_child(main)
	main.free()
	# A capture run that skipped a state is a FAILED run, not a partial success — the caller
	# (a human, or a future CI visual gate) must be able to tell from the exit code.
	quit(1 if _failed else 0)


## Switch the live `Localization` to the requested language and CONFIRM it took.
##
## Goes through the owning service (L-003) and checks the observable result rather than the
## return value alone, because `set_language` also returns true when the code was already
## active — so only reading back `get_language()` proves the screenshots about to be written
## are in the language their filenames claim.
func _apply_language() -> bool:
	var loc := root.get_node_or_null("Localization")
	if loc == null:
		push_error("[capture] no /root/Localization — cannot guarantee the capture language")
		_failed = true
		return false
	loc.call("set_language", _language)
	var active := String(loc.call("get_language"))
	if active != _language:
		push_error(("[capture] asked for '%s' but Localization is on '%s' — refusing to "
			+ "write files named after a language they are not in") % [_language, active])
		_failed = true
		return false
	print("[capture] language confirmed: %s" % active)
	return true


## Toggle a HUD side panel by property name. The HUD owns its panels privately and exposes
## only `is_*_open()`, so the capture harness flips `visible` directly — acceptable HERE
## because this is a build-time tool whose entire job is to look at presentation, and the
## alternative (feeding real key events) adds input-timing flakiness to a screenshot.
## Returns false (loud) if the panel could not be found or did not change state.
##
## Failing loudly matters more here than it looks: if the HUD renames the field, a silent
## no-op would still write a file called `07_sect_panel.png` — with the panel CLOSED. A
## capture that quietly lies is worse than a missing capture, because the whole point of these
## files is to be the evidence a human reviews.
func _toggle_panel(hud: Node, property: String) -> bool:
	var panel: Variant = hud.get(property)
	if not (panel is Control):
		push_error(("[capture] HUD has no Control '%s' — the capture would have written a "
			+ "screenshot named after a panel it never opened") % property)
		_failed = true
		return false
	var control := panel as Control
	var before := control.visible
	control.visible = not before
	if control.visible == before:
		push_error("[capture] '%s' did not change visibility" % property)
		_failed = true
		return false
	return true


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


## The live main menu under `Main/UI`, polled for a BOUNDED number of frames.
##
## A single check after `_settle()` failed one run in four (D-056 UI pass, the first run after
## a re-import): the language switch rebuilds the menu, and on a cold shader cache the rebuild
## had not landed within `SETTLE_FRAMES`. Polling with a cap keeps the run fast when it is
## fast and still fails LOUD when there is genuinely no menu. A child already queued for
## deletion is the menu being replaced, not the menu.
func _await_menu(main: Node) -> Node:
	for _i in MENU_WAIT_FRAMES:
		var ui := main.get_node_or_null("UI")
		if ui != null:
			for child in ui.get_children():
				if not child.is_queued_for_deletion():
					return child
		await process_frame
	return null


## Write the current viewport to `<out>/<language>_<width>x<height>_<name>.png`.
func _shot(shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		push_error("[capture] viewport produced no image for '%s'" % shot_name)
		_failed = true
		return
	var size := root.get_visible_rect().size
	var file := "%s/%s_%dx%d_%s.png" % [
		_out_dir, _language, int(size.x), int(size.y), shot_name]
	if image.save_png(file) != OK:
		push_error("[capture] could not write %s" % file)
		_failed = true
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

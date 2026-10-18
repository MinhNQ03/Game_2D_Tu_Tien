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
##     godot --path . --resolution 1280x720 -s res://tools/capture_ui.gd -- vi out/dir \
##         vignette origin_lang_y      # ONLY that Origin's opening scene, step by step
##
## THE FULL RUN CONFIRMS ONE ORIGIN (the screen's default), so it shows one vignette. The other
## four were captured by no tool until Gate VC (B2-01): `vignette <origin_id>` starts a run as
## that Origin and photographs its opening, then quits.
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

## The frame rate the run is paced at, by the tool itself rather than by the display. A vsynced
## window in a LOCKED X session is presented at ~1 Hz (931 ms/frame, D-063 A0): a full run is
## about a thousand frames, so it took fifteen minutes (UI-01: the en run finished in 14 min, the
## vi run was killed at its 900 s budget after shot 15), and every settle let ~0.9 s of world
## run per frame, a wolf closing in between two staged shots. Vsync off and 60 fps is what
## `--disable-vsync --max-fps 60` gives every other real-window tool (`playtest_flow.gd`); here
## no caller can forget it (`tests/unit/tools/test_capture_ui_pacing.gd`).
const PACED_FPS := 60

var _out_dir := "user://ui_captures"
var _language := "vi"
var _written: Array[String] = []
var _failed := false
## Set by `vignette <origin_id>`: capture only that Origin's opening scene.
var _vignette_origin: StringName = &""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_language = String(args[0])
	if args.size() >= 2:
		_out_dir = String(args[1])
	if args.size() >= 4 and String(args[2]) == "vignette":
		_vignette_origin = StringName(String(args[3]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = PACED_FPS
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

	if _vignette_origin != &"":
		await _capture_one_vignette(main, menu)
		print("[capture] wrote %d file(s) to %s" % [_written.size(), _out_dir])
		main.get_parent().remove_child(main)
		main.free()
		quit(1 if _failed or _written.is_empty() else 0)
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
		await _capture_identity_and_opening(main)
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
				_toggle_panel(hud, "_faction_panel")
			if hud.has_method("is_sect_panel_open") and bool(hud.call("is_sect_panel_open")):
				_toggle_panel(hud, "_sect_panel")
			await _capture_satchel_and_equipment(main, hud)
			await _capture_dialogue(hud)
		await _capture_the_night(main)

	print("[capture] wrote %d file(s) to %s" % [_written.size(), _out_dir])
	for name in _written:
		print("[capture]   %s" % name)
	main.get_parent().remove_child(main)
	main.free()
	# A capture run that skipped a state is a FAILED run, not a partial success — the caller
	# (a human, or a future CI visual gate) must be able to tell from the exit code.
	quit(1 if _failed else 0)


## 9-11: the satchel with real items in it, the protagonist WEARING the Thanh Vân robe (the
## equipment visual swap), and the technique dock. SETUP goes through the runtimes' public API —
## the same concession the E2E flows make — because walking to every pickup would turn a
## screenshot into a playthrough. A state that could not be reached writes NO file and fails
## the run: a capture named after a state it is not in is the lie this tool exists to prevent.
## The identity screen (Phase 20) with each look and each Origin chosen, then the run it starts:
## the Origin's vignette, step by step, and the arrival. The LAST Origin and the SECOND look
## are the ones confirmed, so the captures that follow show a non-default run.
func _capture_identity_and_opening(main: Node) -> void:
	var identity := RunKit.identity_of(main)
	if identity == null:
		push_error("[capture] the identity screen did not open")
		return
	await _shot("04a_identity_default")
	var looks := identity.find_children("Look_*", "Button", true, false)
	var origins := identity.find_children("Origin_*", "Button", true, false)
	for i in origins.size():
		(origins[i] as Button).grab_focus()
		await _settle()
		await _shot("04b_identity_origin_%d" % (i + 1))
	for i in looks.size():
		(looks[i] as Button).grab_focus()
		await _settle()
		await _shot("04c_identity_look_%d" % (i + 1))
	(identity.find_child("Begin", true, false) as Button).grab_focus()
	await _settle()
	await _shot("04d_identity_begin_focused")
	identity.emit_signal("confirmed", identity.call("selected_appearance_id"),
		identity.call("selected_origin_id"))
	await _settle()
	var story := RunKit.story_of(main)
	var step := 0
	while story != null and story.is_scene_playing() and step < 12:
		step += 1
		await _settle()
		await _shot("04e_opening_step_%02d" % step)
		story.advance_scene()
	await _settle()


## ONE Origin's opening scene, every step (B2-01: three of the five had never been captured).
## The run is started as that Origin through the identity screen's own `confirmed` signal; an
## Origin the screen does not offer, or a scene that never plays, fails the run.
func _capture_one_vignette(main: Node, menu: Node) -> void:
	menu.emit_signal("new_game_pressed")
	await _settle()
	var identity := RunKit.identity_of(main)
	if identity == null or identity.find_child("Origin_%s" % _vignette_origin, true, false) == null:
		push_error("[capture] the identity screen does not offer '%s'" % _vignette_origin)
		_failed = true
		return
	identity.emit_signal("confirmed", identity.call("selected_appearance_id"), _vignette_origin)
	await _settle()
	var story := RunKit.story_of(main)
	if story == null or not story.get_service().origin_is(_vignette_origin) \
			or not story.is_scene_playing():
		push_error("[capture] no opening scene plays for '%s'" % _vignette_origin)
		_failed = true
		return
	var step := 0
	while story.is_scene_playing() and step < 12:
		step += 1
		await _settle()
		await _shot("vignette_%s_step_%02d" % [_vignette_origin, step])
		story.advance_scene()
	await _settle()


## The Night (Phase 20, beats 7-11) as the window shows it. A CAPTURE, not a proof: the story
## is brought to the Night through its owner (the real-key path is the Story E2E's), and each
## state is photographed where the player would see it.
func _capture_the_night(main: Node) -> void:
	var story := RunKit.story_of(main)
	var world := main.get_node_or_null("Systems/WorldRuntime")
	if story == null or world == null or not story.is_session_active():
		push_error("[capture] no story to capture the Night of")
		_failed = true
		return
	for who: StringName in [&"actor_elder_shen", &"actor_disciple_lin", &"actor_carter_te"]:
		story.meet(who)
	story.set_flag(&"flag_heard_village_business", 1)
	story.choose(&"choice_lam_readings", &"kept")
	await _settle()
	await _shot("20_night_warning_card")
	story.advance_scene()
	await _settle()
	await _shot("21_night_warning_caption")
	RunKit.skip_scenes(main)
	world.call("request_map_transition", &"map_field", &"from_hub")
	await _settle()
	await _settle()
	story.advance_scene()
	story.advance_scene()
	await _settle()
	await _shot("22_night_rupture_caption")
	RunKit.skip_scenes(main)
	await _settle()
	var player := world.call("get_player") as Node2D
	if player != null:
		player.global_position = Vector2(590, 262)  # staging: in sight of the wreck
	await _settle()
	await _shot("23_night_wave_and_wreck")
	world.call("request_map_transition", &"map_hub", &"from_field")  # withdrawing is an answer
	await _settle()
	await _settle()
	await _shot("24_morning_card")
	RunKit.skip_scenes(main)
	player = world.call("get_player") as Node2D
	if player != null:
		player.global_position = Vector2(612, 364)  # staging: at the weighted sheet
	await _settle()
	await _shot("25_morning_sheet_under_the_stele")
	# The Chronicle, page by page, as the run stands this morning.
	var router := root.get_node_or_null("SceneRouter")
	var here: Node = router.call("get_current_scene") if router != null else null
	var hud: Node = here.get_node_or_null("GameplayHUD") if here != null else null
	var book: ChroniclePanel = hud.call("chronicle_panel") if hud != null else null
	if book == null:
		push_error("[capture] no Chronicle to capture")
		_failed = true
		return
	book.reset_page()
	book.visible = true
	await _settle()  # the book packs its pages for the room it is laid out in
	book.reset_page()
	for page in 30:
		await _settle()
		await _shot("26_chronicle_page_%02d_%s" % [page + 1, book.page_id()])
		if not book.advance_page():
			break
	book.visible = false
	await _capture_the_bridge(main)


## The Act-I bridge (D-073) as the window shows it: the sheet shown, where the stake stood, the
## old cart track and the door at its end. A CAPTURE, staged through the owners; the real-key
## path is the Story E2E's (8i, 8j, 12).
func _capture_the_bridge(main: Node) -> void:
	var story := RunKit.story_of(main)
	var world := main.get_node_or_null("Systems/WorldRuntime")
	var knowledge := main.get_node_or_null("Systems/KnowledgeRuntime")
	var dialogue := main.get_node_or_null("Systems/DialogueRuntime")
	if story == null or world == null or knowledge == null or dialogue == null:
		push_error("[capture] no session to capture the bridge of")
		_failed = true
		return
	story.set_flag(&"flag_heard_elder_account", 1)
	story.note_cultivated()
	knowledge.call("grant", &"know_survey_fragment", &"source_survey_sheet")
	story.set_flag(&"flag_heard_road_ahead", 1)
	await _settle()
	await _shot("30_act1_road_ahead_card")
	RunKit.skip_scenes(main)
	var router := root.get_node_or_null("SceneRouter")
	var hub: Node = router.call("get_current_scene")
	var lin := hub.get_node_or_null("Interactables/LinYue") as Node2D
	var player := world.call("get_player") as Node2D
	if lin != null and player != null:
		player.global_position = lin.global_position + Vector2(-22, 0)  # staging: beside her
		await _settle()
		await _shot("31_act1_purpose_ask_who_wrote_it")
		dialogue.call("talk", &"actor_disciple_lin")
		await _settle()
		await _shot("32_act1_whom_to_show")
		dialogue.call("choose", &"lin_trail", &"lin_show")
		await _settle()
		await _shot("33_act1_she_reads_the_hand")
		dialogue.call("leave")
	world.call("request_map_transition", &"map_field", &"from_hub")
	await _settle()
	await _settle()
	var field: Node = router.call("get_current_scene")
	player = world.call("get_player") as Node2D
	var socket := field.get_node_or_null("KnowledgeSources/StakeSocket") as Node2D
	if socket != null and player != null:
		player.global_position = socket.global_position + Vector2(14, 2)  # staging: at the mark
		await _settle()
		await _shot("34_act1_where_the_stake_stood")
		knowledge.call("grant", &"know_stake_socket", &"source_stake_socket")
	var wreck := field.get_node_or_null("Visual/Decor/CartWreck") as Node2D
	if wreck != null and player != null:
		player.global_position = wreck.global_position + Vector2(-44, 30)  # staging: by the wreck
		await _settle()
		await _shot("35_act1_wreck_and_old_track")
	var seal := field.get_node_or_null("KnowledgeSources/ShaftSeal") as Node2D
	if seal != null and player != null:
		player.global_position = seal.global_position + Vector2(0, 6)  # staging: at the sill
		await _settle()
		await _shot("36_act1_the_survey_shaft")
		knowledge.call("grant", &"know_sealed_shaft", &"source_shaft_seal")
		await _settle()
		await _shot("37_act1_shaft_sealed_caption")
		RunKit.skip_scenes(main)
		await _settle()
		await _shot("38_act1_standing_purpose")


func _capture_satchel_and_equipment(main: Node, hud: Node) -> void:
	var inventory := main.get_node_or_null("Systems/InventoryRuntime")
	var equipment := main.get_node_or_null("Systems/EquipmentRuntime")
	var world := main.get_node_or_null("Systems/WorldRuntime")
	if inventory == null or equipment == null or world == null:
		push_error("[capture] the inventory/equipment runtimes are missing under Main/Systems")
		_failed = true
		return
	for item_id in [&"item_bo_huyet_dan", &"item_linh_thach", &"item_kiem_thanh_thiet",
			&"item_dao_bao_thanh_van", &"item_manual_phong", &"item_manual_loi"]:
		inventory.call("give", item_id, 2 if item_id == &"item_bo_huyet_dan" else 1)
	world.call("refresh_active_map_inventory_view")
	hud.call("open_inventory")
	await _settle()
	if not bool(hud.call("is_inventory_open")):
		push_error("[capture] the satchel did not open")
		_failed = true
		return
	await _shot("09_satchel")
	hud.call("close_inventory")
	# The techniques need Hậu Thiên 1 and the breathing method (canon gates, P12/P15): the same
	# setup `capture_motion.gd techniques` uses. Then reading both manuals teaches them through
	# the Knowledge Core, and the dock appears.
	var knowledge := main.get_node_or_null("Systems/KnowledgeRuntime") as KnowledgeRuntime
	var cultivation := main.get_node_or_null("Systems/CultivationRuntime") as CultivationRuntime
	var player := _player(hud)
	if knowledge != null and cultivation != null and player != null:
		var state: CharacterState = player.call("get_character_state")
		knowledge.grant(&"know_dan_khi_quyet", &"capture")
		if state.realm_id == &"realm_pham":
			cultivation.get_service().gather(state, 999)
			cultivation.get_service().breakthrough(state)
			cultivation.realm_advanced.emit(state.realm_id, state.realm_layer, true)
	inventory.call("use", &"item_manual_phong")
	inventory.call("use", &"item_manual_loi")
	var worn := String(equipment.call("equip", &"item_dao_bao_thanh_van"))
	await _settle()
	await _settle()
	if worn != "":
		push_error("[capture] equipping the Thanh Vân robe was refused: %s" % worn)
		_failed = true
		return
	await _shot("10_equipped_and_dock")
	# UI-02: the satchel WITH something worn — both slots of the character card filled, the
	# figure in the robe, the worn rows leading the list. (The card had only been captured
	# filled on the Chronicle's body page.)
	var armed := String(equipment.call("equip", &"item_kiem_thanh_thiet"))
	hud.call("open_inventory")
	await _settle()
	await _settle()
	if armed != "" or not bool(hud.call("is_inventory_open")):
		push_error("[capture] the satchel with the blade and robe worn could not be shown (%s)"
			% armed)
		_failed = true
		return
	await _shot("11_satchel_worn")
	hud.call("close_inventory")
	# ...and the blade goes back in the satchel: every frame after this one was first taken
	# with only the robe worn, and a second worn thing gives the Chronicle's body section
	# another page (the later frames would be renumbered and stop being comparable).
	var unarmed := String(equipment.call("unequip", EquipmentData.Slot.WEAPON))
	await _settle()
	if unarmed != "":
		push_error("[capture] the blade could not be put back: %s" % unarmed)
		_failed = true


## 12-13 (UI-01): an open dialogue at its fullest, in the language of the run — the line whose
## answers take the most room (its largest set that can be offered together, `DialogueOffers`)
## and the longest line said. STAGED through the HUD's own `set_dialogue_view`, the view a talk
## pushes, so no conversation opens and nothing the later frames show is changed; the real-key
## path is the Dialogue E2E's. A box that did not open writes no file and fails the run.
func _capture_dialogue(hud: Node) -> void:
	var catalog := load(DialogueRuntime.CATALOG_PATH) as DialogueCatalogData
	var loc := root.get_node_or_null("Localization")
	if catalog == null or loc == null or not hud.has_method("set_dialogue_view"):
		push_error("[capture] no dialogue catalog, Localization or HUD dialogue seam")
		_failed = true
		return
	var widest: Array = []  # [dialogue, line]
	var widest_rank := Vector2i(-1, -1)  # (answers offered together, their characters)
	var longest: Array = []
	var longest_chars := -1
	for dialogue in catalog.entries:
		for line in dialogue.nodes:
			var offered := DialogueOffers.largest(line)
			var chars := 0
			for option in offered:
				chars += String(loc.call("t", String(option.text_key))).length()
			if Vector2i(offered.size(), chars) > widest_rank:
				widest_rank = Vector2i(offered.size(), chars)
				widest = [dialogue, line]
			var said := String(loc.call("t", String(line.text_key))).length()
			if said > longest_chars:
				longest_chars = said
				longest = [dialogue, line]
	var shots := [["12_dialogue_longest_answers", widest], ["13_dialogue_longest_line", longest]]
	for serial in shots.size():
		var shot: Array = shots[serial]
		var pick: Array = shot[1]
		hud.call("set_dialogue_view", DialogueOffers.view_of(pick[0], pick[1], serial + 1))
		await _settle()
		if not bool(hud.call("is_dialogue_open")):
			push_error("[capture] the dialogue box did not open for %s" % pick[1].id)
			_failed = true
			return
		print("[capture] %s: %s/%s" % [shot[0], pick[0].id, pick[1].id])
		_check_dialogue_band(hud.call("dialogue_panel") as DialoguePanel, shot[0])
		await _shot(shot[0])
	await _capture_dialogue_paged(hud, catalog, loc)
	hud.call("set_dialogue_view", DialogueView.make_closed())
	await _settle()


## 14-16 (UI-01): the states no shipped line reaches yet — a line too long for the box (its
## first page, with the more cue and the answers held back), its last page with an answer too
## long for its column (wrapped under its first word) that makes the set too tall for the band
## (a window of whole answers, the cue below lit), and the window moved down to the last answer
## (the cue above lit). The panel is handed a STAGED localisation that says three real lines as
## one and every offered answer as one, in the language of the run, the way a translation that
## grew would; the real one is restored afterwards. Every shot fails the run if the box is
## taller than its band.
func _capture_dialogue_paged(hud: Node, catalog: DialogueCatalogData, loc: Node) -> void:
	var panel := hud.call("dialogue_panel") as DialoguePanel
	var dialogue := catalog.dialogue_of_speaker(&"actor_scout_ko")
	var line := dialogue.node(&"ko_hub") if dialogue != null else null
	if panel == null or line == null:
		push_error("[capture] no dialogue panel or no ko_hub line to page")
		_failed = true
		return
	var view := DialogueOffers.view_of(dialogue, line, 3)
	var said := " ".join([String(loc.call("t", "DLG_LIN_RIVAL")),
		String(loc.call("t", "DLG_LIN_NOTATION")), String(loc.call("t", "DLG_LIN_SHEET_READ"))])
	# The first answer says every answer offered with it, as one: wider than its column.
	var answer_key := String(view.choices[0]["text_key"])
	var answers: PackedStringArray = []
	for option in view.choices:
		answers.append(String(loc.call("t", String(option["text_key"]))))
	var answer := ", ".join(answers)
	var staged := StagedText.new(loc, {String(line.text_key): said, answer_key: answer})
	panel.set("_loc", staged)
	hud.call("set_dialogue_view", view)
	await _settle()
	if panel.page_count() < 2:
		push_error("[capture] the staged long line did not page (%d)" % panel.page_count())
		_failed = true
	else:
		print("[capture] 14_dialogue_paged: %s/%s, page 1 of %d" % [dialogue.id, line.id,
			panel.page_count()])
		_check_dialogue_band(panel, "14_dialogue_paged")
		await _shot("14_dialogue_paged")
		while panel.next_page():
			pass
		await _settle()
		var wrapped := panel.find_child("Answer", true, false) as Label
		if wrapped == null or wrapped.get_line_count() < 2:
			push_error("[capture] the staged long answer did not wrap")
			_failed = true
		var shown := panel.shown_choice_indices()
		if shown.size() >= view.choices.size():
			push_error("[capture] the staged answer set was not windowed (%s)" % [shown])
			_failed = true
		print("[capture] 15_dialogue_paged_last: page %d of %d, answers %s of %d" % [
			panel.page_index() + 1, panel.page_count(), shown, view.choices.size()])
		_check_dialogue_band(panel, "15_dialogue_paged_last")
		await _shot("15_dialogue_paged_last")
		panel.move_selection(-1)  # wraps round to the last answer
		await _settle()
		shown = panel.shown_choice_indices()
		if not shown.has(view.choices.size() - 1):
			push_error("[capture] the answer window did not follow the selection (%s)" % [shown])
			_failed = true
		print("[capture] 16_dialogue_answers_window: answers %s of %d" % [shown,
			view.choices.size()])
		_check_dialogue_band(panel, "16_dialogue_answers_window")
		await _shot("16_dialogue_answers_window")
	panel.set("_loc", loc)
	staged.free()


## Fail the run if the open box is taller than the band below the playfield clear zone.
func _check_dialogue_band(panel: DialoguePanel, shot: String) -> void:
	if panel == null:
		return
	var allowed := root.get_visible_rect().size.y * (1.0 - UIPalette.PLAYFIELD_CLEAR_ZONE.end.y) \
		- UIPalette.HUD_MARGIN
	if panel.size.y > allowed + 0.5:
		push_error("[capture] %s: the dialogue box is %.0f px tall, the band allows %.0f"
			% [shot, panel.size.y, allowed])
		_failed = true


## The player body under the HUD's map (`PlayerHost`), or null.
func _player(hud: Node) -> Node2D:
	var host := hud.get_parent().get_node_or_null("PlayerHost")
	if host == null:
		return null
	for child in host.get_children():
		if child is CharacterBody2D:
			return child as Node2D
	return null


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


## Localization that says the given texts for the given keys and defers everything else.
class StagedText extends Node:
	var _real: Node
	var _said: Dictionary

	func _init(real: Node, said: Dictionary) -> void:
		_real = real
		_said = said

	func t(key: String) -> String:
		return String(_said[key]) if _said.has(key) else String(_real.call("t", key))

	func t_args(key: String, args: Dictionary) -> String:
		return String(_real.call("t_args", key, args))

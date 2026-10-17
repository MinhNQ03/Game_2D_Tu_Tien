extends TestCase
## The story's first surfaces (Phase 20, D-072): the identity screen, the story-scene band,
## and what the HUD does around them. Autoloads are live in the runner (D-019) and only READ
## or reset to their baseline; every node is freed by the test that made it (L-019).

const IdentityScript := preload("res://src/presentation/menus/identity_screen.gd")
const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")

const APPEARANCES_PATH := "res://data/characters/player_appearances.tres"
const ORIGINS_PATH := "res://data/story/origin_catalog.tres"
const SCENES_PATH := "res://data/story/story_scene_catalog.tres"
const VIEWPORT := Vector2(1280, 720)


func _identity() -> IdentityScreen:
	var screen: IdentityScreen = IdentityScript.new()
	screen.setup(load(APPEARANCES_PATH) as PlayerAppearanceCatalogData,
		load(ORIGINS_PATH) as OriginCatalogData)
	add_to_tree(screen)
	return screen


func _hud() -> GameplayHUD:
	var hud: GameplayHUD = HUDScript.new()
	add_to_tree(hud)
	return hud


func _use_language(code: String) -> void:
	scene_tree.root.get_node("Localization").call("set_language", code)


func _text(key: String) -> String:
	return String(scene_tree.root.get_node("Localization").call("t", key))


func _member_view() -> SectMembershipView:
	var view := SectMembershipView.new()
	view.is_member = true
	view.sect_name_key = &"SECT_AZURE_CLOUD_NAME"
	view.rank_name_key = &"SECT_RANK_OUTER_DISCIPLE"
	return view


func _step_view(scene: StorySceneData, index: int) -> StorySceneView:
	var view := StorySceneView.new()
	view.scene_id = scene.id
	view.step_index = index
	view.step_count = scene.steps.size()
	view.elsewhere = scene.elsewhere
	view.kind = scene.steps[index].kind
	view.text_key = scene.steps[index].text_key
	view.sub_key = scene.steps[index].sub_key
	return view


# === The identity screen ====================================================

func test_the_identity_screen_offers_every_look_and_all_five_origins() -> void:
	_use_language("vi")
	var screen := _identity()
	var looks := screen.find_children("Look_*", "Button", true, false)
	var origins := screen.find_children("Origin_*", "Button", true, false)
	assert_eq(looks.size(),
		(load(APPEARANCES_PATH) as PlayerAppearanceCatalogData).entries.size(),
		"one button per look the catalog offers")
	assert_eq(origins.size(), 5, "and the five Origins of canon")
	assert_eq(screen.selected_origin_id(), &"origin_ho_tieu", "the first Origin is chosen")
	assert_eq(screen.selected_appearance_id(), &"appearance_wanderer_m", "and the first look")
	for button: Button in looks:
		assert_false(button.text.contains("APPEARANCE_"), "no raw key ('%s')" % button.text)
	for origin in (load(ORIGINS_PATH) as OriginCatalogData).entries:
		var card := screen.card_name_text(origin.id)
		assert_true(card != "" and not card.contains("ORIGIN_"),
			"each card names its Origin in words ('%s')" % card)
		var tagline := (screen.find_child("Origin_%s" % origin.id, true, false)
			.find_child("Tagline", true, false) as Label).text
		assert_true(tagline != "" and not tagline.contains("ORIGIN_"),
			"and says its one line ('%s')" % tagline)
		var thumb := screen.find_child("Origin_%s" % origin.id, true, false) \
			.find_child("Thumb", true, false) as TextureRect
		assert_not_null(thumb.texture, "%s: the card shows its picture" % origin.id)
	free_node(screen)
	scene_tree.root.get_node("InputService").call("set_menu_context")


## The cursor LOOKS, accept CHOOSES. Looking shows the option on the stage and describes it;
## only choosing marks it — in words, never by colour alone — and changes the summary.
func test_the_cursor_looks_and_accept_chooses_and_the_choice_is_marked_in_words() -> void:
	_use_language("en")
	var screen := _identity()
	var healer := screen.find_child("Origin_origin_lang_y", true, false) as Button
	var escort := screen.find_child("Origin_origin_ho_tieu", true, false) as Button
	healer.grab_focus()
	assert_eq(screen.shown_origin_id(), &"origin_lang_y", "the cursor is on the healer")
	assert_eq((screen.find_child("OriginName", true, false) as Label).text,
		_text("ORIGIN_LANG_Y_NAME"), "the detail names what is under the cursor")
	assert_eq((screen.find_child("OriginProblem", true, false) as Label).text,
		_text("ORIGIN_LANG_Y_PROBLEM"), "states its problem")
	assert_eq((screen.find_child("OriginEdge", true, false) as Label).text,
		_text("ORIGIN_LANG_Y_EDGE"), "what it gives")
	assert_eq((screen.find_child("OriginCost", true, false) as Label).text,
		_text("ORIGIN_LANG_Y_COST"), "and what it costs")
	assert_eq(screen.selected_origin_id(), &"origin_ho_tieu", "but nothing was chosen by looking")
	assert_true(screen.card_name_text(&"origin_ho_tieu").begins_with(IdentityScreen.CHOSEN_MARK),
		"the mark stays on what IS chosen")
	for key: String in ["ORIGIN_LANG_Y_PAST", "ORIGIN_LANG_Y_GOAL", "ORIGIN_LANG_Y_WHY_HERE",
			"ORIGIN_LANG_Y_LEAD", "ORIGIN_LANG_Y_HORIZON"]:
		var shown := false
		for label: Label in screen.find_child("Detail", true, false).find_children("*", "Label",
				true, false):
			shown = shown or label.text == _text(key)
		assert_true(shown, "the detail tells the whole past: %s" % key)
	healer.pressed.emit()
	assert_eq(screen.selected_origin_id(), &"origin_lang_y", "accept chose the healer")
	assert_true(screen.card_name_text(&"origin_lang_y").begins_with(IdentityScreen.CHOSEN_MARK),
		"and it is marked")
	assert_false(screen.card_name_text(&"origin_ho_tieu").begins_with(IdentityScreen.CHOSEN_MARK),
		"the one left behind is no longer marked")
	assert_true((healer.find_child("ChosenFrame", true, false) as Control).visible
		and not (escort.find_child("ChosenFrame", true, false) as Control).visible,
		"the gold frame moved with the choice")

	var woman := screen.find_child("Look_appearance_wanderer_f", true, false) as Button
	var portrait := screen.find_child("Portrait", true, false) as TextureRect
	woman.grab_focus()
	assert_true(portrait.texture.resource_path.ends_with("medallion_player_f_proto.png"),
		"a look under the cursor is put on the stage (%s)" % portrait.texture.resource_path)
	assert_eq(screen.selected_appearance_id(), &"appearance_wanderer_m", "without being chosen")
	woman.pressed.emit()
	assert_eq(screen.selected_appearance_id(), &"appearance_wanderer_f", "accept chose the look")
	assert_eq(screen.selected_origin_id(), &"origin_lang_y", "and left the Origin alone")
	var summary := (screen.find_child("Summary", true, false) as Label).text
	assert_true(summary.contains(_text("APPEARANCE_WANDERER_F_NAME"))
		and summary.contains(_text("ORIGIN_LANG_Y_NAME")),
		"the summary states the choice in words ('%s')" % summary)
	var preview := screen.find_child("Preview", true, false) as CharacterVisualComponent
	assert_true(preview != null and preview.scale == Vector2(3, 3),
		"with the body itself, at an integer scale")
	free_node(screen)
	scene_tree.root.get_node("InputService").call("set_menu_context")


## THE BUG THE E2E FOUND: reaching "Set out" means walking the cursor down through every
## Origin below the chosen one. That must choose none of them — and once the cursor is on the
## bottom row, the stage and the description go back to what will actually be started.
func test_walking_the_cursor_to_the_buttons_changes_no_choice() -> void:
	_use_language("en")
	var screen := _identity()
	(screen.find_child("Origin_origin_de_tu_bi_loai", true, false) as Button).pressed.emit()
	for origin_id: StringName in [&"origin_lang_y", &"origin_nghe_nhan", &"origin_thu_thu"]:
		(screen.find_child("Origin_%s" % origin_id, true, false) as Button).grab_focus()
	assert_eq(screen.shown_origin_id(), &"origin_thu_thu", "the cursor is on the last Origin")
	assert_eq(screen.selected_origin_id(), &"origin_de_tu_bi_loai", "the choice has not moved")
	(screen.find_child("Begin", true, false) as Button).grab_focus()
	assert_eq(screen.shown_origin_id(), &"origin_de_tu_bi_loai",
		"on the button, the description is of what the button will start")
	assert_eq((screen.find_child("OriginName", true, false) as Label).text,
		_text("ORIGIN_DE_TU_BI_LOAI_NAME"), "by name")
	free_node(screen)
	scene_tree.root.get_node("InputService").call("set_menu_context")


## Crossing from one column to the other lands on what is ALREADY chosen there, so the
## crossing itself can never change a choice.
func test_crossing_columns_lands_on_the_current_choice() -> void:
	var screen := _identity()
	var artisan := screen.find_child("Origin_origin_nghe_nhan", true, false) as Button
	var woman := screen.find_child("Look_appearance_wanderer_f", true, false) as Button
	artisan.pressed.emit()
	woman.pressed.emit()
	assert_eq(woman.get_node(woman.focus_neighbor_right), artisan,
		"right of the looks is the chosen Origin")
	assert_eq(artisan.get_node(artisan.focus_neighbor_left), woman,
		"left of the Origins is the chosen look")
	var begin := screen.find_child("Begin", true, false) as Button
	assert_eq(begin.get_node(begin.focus_neighbor_top), artisan,
		"and up from Begin is the chosen Origin")
	free_node(screen)
	scene_tree.root.get_node("InputService").call("set_menu_context")


## ONE confirmation starts ONE run: the screen locks itself, so a second press — a held key,
## a double tap — emits nothing.
func test_confirming_emits_once_with_what_was_chosen_and_locks_the_screen() -> void:
	var screen := _identity()
	var heard: Array = []
	var cancelled := [0]
	screen.confirmed.connect(func(look: StringName, origin: StringName) -> void:
		heard.append([look, origin]))
	screen.cancelled.connect(func() -> void: cancelled[0] += 1)
	(screen.find_child("Origin_origin_thu_thu", true, false) as Button).pressed.emit()
	(screen.find_child("Look_appearance_wanderer_f", true, false) as Button).pressed.emit()
	var begin := screen.find_child("Begin", true, false) as Button
	begin.pressed.emit()
	begin.pressed.emit()
	(screen.find_child("Back", true, false) as Button).pressed.emit()
	assert_eq(heard, [[&"appearance_wanderer_f", &"origin_thu_thu"]],
		"confirmed once, as chosen")
	assert_eq(cancelled[0], 0, "and Back after confirming does nothing")
	assert_true(screen.is_locked() and begin.disabled, "the screen is locked")
	(screen.find_child("Origin_origin_lang_y", true, false) as Button).pressed.emit()
	assert_eq(screen.selected_origin_id(), &"origin_thu_thu",
		"and what was confirmed cannot be changed afterwards")
	free_node(screen)
	scene_tree.root.get_node("InputService").call("set_menu_context")


func test_backing_out_emits_once_and_confirms_nothing() -> void:
	var screen := _identity()
	var confirmed := [0]
	var cancelled := [0]
	screen.confirmed.connect(func(_l: StringName, _o: StringName) -> void: confirmed[0] += 1)
	screen.cancelled.connect(func() -> void: cancelled[0] += 1)
	var back := screen.find_child("Back", true, false) as Button
	back.pressed.emit()
	back.pressed.emit()
	(screen.find_child("Begin", true, false) as Button).pressed.emit()
	assert_eq([cancelled[0], confirmed[0]], [1, 0], "back once; nothing confirmed after it")
	free_node(screen)
	scene_tree.root.get_node("InputService").call("set_menu_context")


## Measured as LAID OUT at 1280x720, in both languages, with each Origin chosen (the longest
## description is the one that could push the plaque past the screen).
func test_the_identity_screen_fits_the_screen_for_every_origin_in_both_languages() -> void:
	var holder := SubViewport.new()
	holder.size = Vector2i(VIEWPORT)
	add_to_tree(holder)
	for code: String in ["vi", "en"]:
		_use_language(code)
		var screen: IdentityScreen = IdentityScript.new()
		screen.setup(load(APPEARANCES_PATH) as PlayerAppearanceCatalogData,
			load(ORIGINS_PATH) as OriginCatalogData)
		holder.add_child(screen)
		var plaque := screen.find_child("IdentityPlaque", true, false) as Control
		for origin in (load(ORIGINS_PATH) as OriginCatalogData).entries:
			(screen.find_child("Origin_%s" % origin.id, true, false) as Button).grab_focus()
			await scene_tree.process_frame
			await scene_tree.process_frame
			var rect := plaque.get_global_rect()
			assert_true(rect.position.x >= 0.0 and rect.position.y >= 0.0
				and rect.end.x <= VIEWPORT.x and rect.end.y <= VIEWPORT.y,
				"[%s] %s: the plaque (%s) is inside the screen" % [code, origin.id, rect])
			for name: String in ["OriginPast", "OriginProblem", "OriginGoal", "OriginWhyHere",
					"OriginLead", "OriginHorizon", "OriginEdge", "OriginCost", "Summary", "Hint"]:
				var label := screen.find_child(name, true, false) as Label
				var box := label.get_global_rect()
				assert_true(box.end.y <= VIEWPORT.y and box.position.x >= 0.0
					and box.end.x <= VIEWPORT.x,
					"[%s] %s: %s (%s) is on screen, not cut off" % [code, origin.id, name, box])
				assert_true(label.get_line_count() <= label.get_visible_line_count()
					or label.get_visible_line_count() < 0,
					"[%s] %s: every line of %s is visible" % [code, origin.id, name])
			var begin := screen.find_child("Begin", true, false) as Control
			assert_true(begin.get_global_rect().end.y <= VIEWPORT.y,
				"[%s] %s: Set out is on screen" % [code, origin.id])
		holder.remove_child(screen)
		screen.free()
	free_node(holder)
	_use_language("vi")
	scene_tree.root.get_node("InputService").call("set_menu_context")


# === The story-scene band ===================================================

func test_a_scene_step_shows_the_band_modally_and_ending_it_restores_gameplay() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	var hud := _hud()
	var scene := (load(SCENES_PATH) as StorySceneCatalogData).entry(&"scene_arrival")
	assert_false(hud.is_story_scene_open(), "hidden until a step is pushed")
	assert_false(hud.story_scene_panel().is_processing(), "and reading no key")
	hud.set_story_scene_view(_step_view(scene, 0))
	assert_true(hud.is_story_scene_open(), "a step shows the band")
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL),
		"and takes a UI_MODAL context: the player cannot walk under it")
	hud.set_story_scene_view(_step_view(scene, 1))
	hud.set_story_scene_view(_step_view(scene, 2))
	hud.set_story_scene_view(null)
	assert_false(hud.is_story_scene_open(), "no step hides it")
	assert_true(bool(input.call("is_gameplay_active")),
		"three steps took ONE context: ending the scene gives control back")
	assert_false(hud.story_scene_panel().is_processing(), "and it stops reading keys")
	free_node(hud)
	input.call("set_menu_context")


func test_a_scene_stands_the_prompt_strip_down_and_brings_it_back() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	var hud := _hud()
	var strip := hud.find_child("PromptStrip", true, false) as Control
	var scene := (load(SCENES_PATH) as StorySceneCatalogData).entry(&"scene_arrival")
	assert_true(strip.visible, "the strip is shown while walking")
	hud.set_story_scene_view(_step_view(scene, 0))
	assert_false(strip.visible, "none of its keys act during a scene, so it stands down")
	hud.set_story_scene_view(null)
	assert_true(strip.visible, "and is back when the scene ends")
	free_node(hud)
	input.call("set_menu_context")


func test_the_band_shows_a_card_a_caption_and_its_keys_in_words() -> void:
	_use_language("vi")
	var hud := _hud()
	var panel := hud.story_scene_panel()
	var scene := (load(SCENES_PATH) as StorySceneCatalogData).entry(&"scene_arrival")
	hud.set_story_scene_view(_step_view(scene, 0))
	assert_eq(panel.place_text(), _text("STORY_SCENE_ARRIVAL_PLACE"), "the card names the place")
	assert_eq(panel.time_text(), _text("STORY_SCENE_ARRIVAL_TIME"), "and the time")
	assert_eq(panel.body_text(), "", "and no narration yet")
	assert_eq(panel.pips_text(), "1 / 3", "the player can see how long the scene is")
	hud.set_story_scene_view(_step_view(scene, 1))
	assert_eq(panel.body_text(), _text("STORY_SCENE_ARRIVAL_1"), "a caption is narration")
	assert_eq(panel.place_text(), "", "and the card is gone")
	var keys := panel.keys_text()
	assert_false(keys.contains("{") or keys.contains("UI_STORY"), "the keys are resolved")
	var input: Node = scene_tree.root.get_node("InputService")
	assert_true(keys.contains(String(input.call("get_action_display_label", &"interact")))
		and keys.contains(String(input.call("get_action_display_label", &"open_menu"))),
		"and name the REAL keys for 'continue' and 'skip' ('%s')" % keys)
	hud.set_story_scene_view(null)
	free_node(hud)
	scene_tree.root.get_node("InputService").call("set_menu_context")


## A scene that is somewhere else COVERS the map — entirely. (The first build used a 90 %
## veil; in the real window the plaza and the HUD still showed through it.)
func test_a_scene_that_is_elsewhere_covers_the_map_and_one_that_is_here_does_not() -> void:
	var hud := _hud()
	var panel := hud.story_scene_panel()
	var scenes := load(SCENES_PATH) as StorySceneCatalogData
	hud.set_story_scene_view(_step_view(scenes.entry(&"scene_vignette_ho_tieu"), 0))
	assert_true(panel.covers_the_map(), "a memory is shown on the ink ground")
	var ground := panel.find_child("Ground", true, false) as Control
	assert_true(ground.visible and ground.get_child_count() > 0, "which is really drawn")
	var fill := ground.find_child("Background", true, false) as ColorRect
	assert_eq(fill.color.a, 1.0, "and is opaque")
	hud.set_story_scene_view(_step_view(scenes.entry(&"scene_arrival"), 0))
	assert_false(panel.covers_the_map(), "the arrival is HERE: the village shows")
	hud.set_story_scene_view(null)
	free_node(hud)
	scene_tree.root.get_node("InputService").call("set_menu_context")


## Every shipped scene step, in both languages, as LAID OUT at 1280x720: inside the screen,
## and — when the scene is here — below the centre the player is watching.
func test_every_shipped_scene_step_fits_the_screen_in_both_languages() -> void:
	var holder := SubViewport.new()
	holder.size = Vector2i(VIEWPORT)
	add_to_tree(holder)
	var hud: GameplayHUD = HUDScript.new()
	holder.add_child(hud)
	var panel := hud.story_scene_panel()
	var measured := 0
	for code: String in ["vi", "en"]:
		_use_language(code)
		for scene in (load(SCENES_PATH) as StorySceneCatalogData).entries:
			for index in scene.steps.size():
				hud.set_story_scene_view(_step_view(scene, index))
				await scene_tree.process_frame
				await scene_tree.process_frame
				var box := panel.box_rect()
				measured += 1
				assert_true(box.position.x >= 0.0 and box.end.x <= VIEWPORT.x
					and box.position.y >= 0.0 and box.end.y <= VIEWPORT.y,
					"[%s] %s step %d: the band (%s) is inside the screen"
					% [code, scene.id, index, box])
				if not scene.elsewhere:
					assert_true(box.position.y >= VIEWPORT.y * 0.5,
						"[%s] %s step %d: a scene that is here stays out of the centre"
						% [code, scene.id, index])
	assert_true(measured >= 40, "the scan measured the steps (%d)" % measured)
	hud.set_story_scene_view(null)
	holder.remove_child(hud)
	hud.free()
	free_node(holder)
	_use_language("vi")
	scene_tree.root.get_node("InputService").call("set_menu_context")


# === The HUD around a nobody ================================================

## The strip sells "Sect" and "Politics" only to a member (D-072 §3).
func test_the_prompt_strip_advertises_the_sect_only_to_a_member() -> void:
	var hud := _hud()
	var sect_row := hud.find_child("SectPrompt", true, false) as Control
	var politics_row := hud.find_child("PoliticsPrompt", true, false) as Control
	hud.set_sect_view(SectMembershipView.make_empty())
	assert_false(sect_row.visible or politics_row.visible,
		"someone with no sect is offered neither")
	hud.set_sect_view(_member_view())
	assert_true(sect_row.visible and politics_row.visible, "a member is offered both")
	hud.set_sect_view(SectMembershipView.make_empty())
	assert_false(sect_row.visible or politics_row.visible, "and leaving takes them away again")
	free_node(hud)


func test_the_plaque_shows_the_portrait_of_the_look_the_player_chose() -> void:
	var hud := _hud()
	var looks := load(APPEARANCES_PATH) as PlayerAppearanceCatalogData
	for look in looks.entries:
		hud.set_player_portrait(look.template.portrait_ref)
		assert_eq(hud.player_portrait_path(), look.template.portrait_ref,
			"%s: the plaque shows that look's own portrait" % look.id)
	var kept := hud.player_portrait_path()
	hud.set_player_portrait("res://assets/ui/does_not_exist.png")
	assert_eq(hud.player_portrait_path(), kept, "a missing file leaves the plaque as it was")
	free_node(hud)

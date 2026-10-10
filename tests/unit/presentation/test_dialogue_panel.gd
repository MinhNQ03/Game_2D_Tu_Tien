extends TestCase
## Unit tests for the Phase-18 dialogue presentation: `DialoguePanel` and the HUD's modal
## handling of a `DialogueView`. Presentation only — every view here is one the test wrote,
## because the panel must show what it is given and decide nothing.

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const DIALOGUES := "res://data/dialogue/dialogue_catalog.tres"


func _hud() -> GameplayHUD:
	var hud: GameplayHUD = HUDScript.new()
	add_to_tree(hud)
	return hud


func _use_language(code: String) -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", code)


func _t(key: String) -> String:
	return String(scene_tree.root.get_node("Localization").call("t", key))


## Kha Thản's "what do you need" line: four answers.
func _hub_view(serial: int = 1) -> DialogueView:
	var view := DialogueView.new()
	view.open = true
	view.dialogue_id = &"dlg_scout_ko"
	view.node_id = &"ko_hub"
	view.line_serial = serial
	view.speaker_id = &"actor_scout_ko"
	view.speaker_name_key = &"CHARACTER_SCOUT_KO_NAME"
	view.speaker_title_key = &"CHARACTER_SCOUT_KO_TITLE"
	view.portrait_path = "res://assets/ui/aetheria_ink/medallion_merchant_proto.png"
	view.mood = DialogueNodeData.Mood.CALM
	view.text_key = &"DLG_KO_HUB"
	var choices: Array[Dictionary] = [
		{"id": &"ko_trade", "text_key": &"DLG_KO_CHOICE_TRADE"},
		{"id": &"ko_ask_woods", "text_key": &"DLG_KO_CHOICE_WOODS"},
		{"id": &"ko_talk_price", "text_key": &"DLG_KO_CHOICE_PRICE"},
		{"id": &"ko_leave", "text_key": &"DLG_CHOICE_LEAVE"},
	]
	view.choices = choices
	return view


## A line with nothing to answer.
func _line_view(serial: int, continues: bool) -> DialogueView:
	var view := _hub_view(serial)
	view.node_id = &"ko_greet"
	view.text_key = &"DLG_KO_GREET"
	view.mood = DialogueNodeData.Mood.WARY
	view.gestures = true
	view.choices = [] as Array[Dictionary]
	view.continues = continues
	return view


func test_an_open_view_shows_the_box_modally_and_a_closed_one_restores_gameplay() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	var hud := _hud()
	assert_false(hud.is_dialogue_open(), "closed until a view says otherwise")
	assert_false(hud.dialogue_panel().is_processing(), "and the closed panel reads no key")
	hud.set_dialogue_view(_hub_view())
	assert_true(hud.is_dialogue_open(), "an open view shows the box")
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL),
		"and takes a UI_MODAL context")
	assert_true(hud.dialogue_panel().is_processing(), "the open panel reads its keys")
	hud.set_dialogue_view(_hub_view(2))
	hud.set_dialogue_view(_hub_view(3))
	hud.set_dialogue_view(DialogueView.make_closed())
	assert_false(hud.is_dialogue_open(), "a closed view hides it")
	assert_true(bool(input.call("is_gameplay_active")),
		"three open views took ONE context: one pop restores gameplay")
	assert_false(hud.dialogue_panel().is_processing(), "and the panel stops reading keys")
	free_node(hud)
	input.call("set_menu_context")


func test_dialogue_focus_stands_the_other_controls_down_and_brings_them_back() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	var hud := _hud()
	hud.set_interact_available(true, &"UI_HUD_TALK_ACTION", {"name": &"CHARACTER_SCOUT_KO_NAME"})
	var strip := hud.find_child("PromptStrip", true, false) as Control
	var dock := hud.skill_dock()
	var dock_shown := dock.visible
	assert_true(strip.visible, "the prompt strip is shown while walking")
	assert_eq(dock.modulate.a, 1.0, "and the dock is opaque")
	hud.set_dialogue_view(_hub_view())
	assert_false(strip.visible, "the prompt strip stands down: none of its keys act now")
	assert_eq(dock.modulate.a, 0.0, "so does the technique dock")
	hud.set_dialogue_view(DialogueView.make_closed())
	assert_true(strip.visible, "the strip is back when the talk ends")
	assert_eq(dock.modulate.a, 1.0, "and so is the dock")
	assert_eq(dock.visible, dock_shown, "whose own show/hide rule was never touched")
	assert_ne(hud.interact_prompt_text(), "", "with the interact prompt still offered")
	free_node(hud)
	input.call("set_menu_context")


func test_a_shop_opening_never_leaves_two_modal_contexts() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	var hud := _hud()
	hud.set_dialogue_view(_hub_view())
	# The owner closes the conversation, THEN opens the shop (DialogueRuntime's order).
	hud.set_dialogue_view(DialogueView.make_closed())
	var shop := ShopView.new()
	shop.open = true
	shop.shop_id = &"shop_ko_than_packs"
	shop.name_key = &"SHOP_KO_THAN_PACKS_NAME"
	shop.keeper_name_key = &"CHARACTER_SCOUT_KO_NAME"
	shop.currency_name_key = &"ITEM_LINH_THACH_NAME"
	hud.set_shop_view(shop)
	assert_true(hud.is_shop_open() and not hud.is_dialogue_open(), "one panel, the shop")
	hud.set_shop_view(ShopView.make_closed())
	assert_true(bool(input.call("is_gameplay_active")), "one pop and gameplay is back")
	free_node(hud)
	input.call("set_menu_context")


func test_the_panel_shows_who_speaks_how_and_what_can_be_answered() -> void:
	_use_language("vi")
	var hud := _hud()
	hud.set_dialogue_view(_hub_view())
	var panel := hud.dialogue_panel()
	assert_eq(panel.speaker_text(), "Kha Thản", "the speaker, by name")
	assert_eq(panel.line_text(), _t("DLG_KO_HUB"), "the line")
	assert_eq(panel.mood_text(), _t("UI_DIALOGUE_MOOD_CALM"), "how it is said, in words")
	assert_true(panel.has_portrait(), "his portrait")
	assert_eq(panel.choice_texts(), ["Mua bán", "Hỏi về khu rừng", "Bàn chuyện giá cả", "Cáo từ"]
		as Array[String], "the answers, in order")
	assert_eq(panel.selected_choice_id(), &"ko_trade", "the first is selected")
	assert_true(panel.keys_text().contains("E") and panel.keys_text().contains("Esc"),
		"the keys are named ('%s')" % panel.keys_text())
	hud.set_dialogue_view(_line_view(2, true))
	assert_eq(panel.choice_ids(), [] as Array[StringName], "a line with nothing to answer")
	assert_eq(panel.mood_text(), _t("UI_DIALOGUE_MOOD_WARY"), "its own mood")
	assert_false((panel.find_child("Choices", true, false) as Control).visible,
		"gives the answers' column back to the line")
	assert_true(panel.keys_text().contains("Nghe tiếp"), "and offers to continue")
	hud.set_dialogue_view(_line_view(3, false))
	assert_true(panel.keys_text().contains("Kết thúc"), "or, on a last line, to end")
	free_node(hud)


func test_no_shipped_line_or_answer_renders_as_a_raw_key_in_either_language() -> void:
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	for code: String in ["vi", "en"]:
		_use_language(code)
		for dialogue in catalog.entries:
			for line in dialogue.nodes:
				var view := _hub_view(1)
				view.text_key = line.text_key
				view.mood = line.mood
				var choices: Array[Dictionary] = []
				for option in line.choices:
					choices.append({"id": option.id, "text_key": option.text_key})
				view.choices = choices
				hud.set_dialogue_view(view)
				assert_false(panel.line_text().begins_with("DLG_"),
					"[%s] %s renders text, not its key" % [code, line.id])
				for text in panel.choice_texts():
					assert_false(text.begins_with("DLG_"), "[%s] an answer of %s" % [code, line.id])
				assert_false(panel.mood_text().begins_with("UI_"), "[%s] the mood" % code)
	_use_language("vi")
	free_node(hud)


func test_selection_wraps_and_a_request_names_the_line_it_answers() -> void:
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var asked: Array = []
	var on_choice := func(node_id: StringName, id: StringName) -> void:
		asked.append([node_id, id])
	var advanced := [0]
	var on_advance := func() -> void: advanced[0] += 1
	hud.dialogue_choice_requested.connect(on_choice)
	hud.dialogue_advance_requested.connect(on_advance)
	hud.set_dialogue_view(_hub_view())
	panel.move_selection(1)
	assert_eq(panel.selected_choice_id(), &"ko_ask_woods", "down one")
	panel.move_selection(-2)
	assert_eq(panel.selected_choice_id(), &"ko_leave", "up past the top wraps to the last")
	panel.confirm()
	assert_eq(asked, [[&"ko_hub", &"ko_leave"]], "the request names the line AND the answer")
	hud.set_dialogue_view(_hub_view(2))
	assert_eq(panel.selected_index(), 0, "a new line starts at its first answer")
	hud.set_dialogue_view(_line_view(3, true))
	panel.confirm()
	assert_eq(advanced[0], 1, "on a line with nothing to answer, confirm continues")
	assert_eq(asked.size(), 1, "and asks for no choice")
	hud.set_dialogue_view(DialogueView.make_closed())
	panel.confirm()
	assert_eq([asked.size(), advanced[0]], [1, 1], "a closed panel asks for nothing")
	hud.dialogue_choice_requested.disconnect(on_choice)
	hud.dialogue_advance_requested.disconnect(on_advance)
	free_node(hud)


func test_the_box_fits_under_the_clear_zone_in_both_languages() -> void:
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var viewport := Vector2(1280, 720)
	for code: String in ["vi", "en"]:
		_use_language(code)
		for dialogue in catalog.entries:
			for line in dialogue.nodes:
				var view := _hub_view(1)
				view.text_key = line.text_key
				var choices: Array[Dictionary] = []
				for option in line.choices:
					choices.append({"id": option.id, "text_key": option.text_key})
				view.choices = choices
				hud.set_dialogue_view(view)
				# A wrapped line's height is only known once it has been laid out at its
				# real width: measure the box AS SHOWN, not its minimum size.
				await scene_tree.process_frame
				await scene_tree.process_frame
				var shown := panel.size
				assert_true(shown.x <= viewport.x - 2.0 * UIPalette.HUD_MARGIN,
					"[%s] %s: %.0f px wide fits the screen" % [code, line.id, shown.x])
				# The middle half of the screen stays clear: the box, sitting one margin above
				# the bottom edge, must end below 3/4 of the height.
				assert_true(shown.y <= viewport.y * 0.25 - UIPalette.HUD_MARGIN,
					"[%s] %s: %.0f px tall stays below the clear zone"
						% [code, line.id, shown.y])
	_use_language("vi")
	free_node(hud)


## An answer must say what it is about: none may be cut short by the column (the first English
## capture showed "Tell him what the stele reco…").
func test_no_shipped_answer_is_truncated_in_either_language() -> void:
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	for code: String in ["vi", "en"]:
		_use_language(code)
		for dialogue in catalog.entries:
			for line in dialogue.nodes:
				if line.choices.is_empty():
					continue
				var view := _hub_view(1)
				var choices: Array[Dictionary] = []
				for option in line.choices:
					choices.append({"id": option.id, "text_key": option.text_key})
				view.choices = choices
				hud.set_dialogue_view(view)
				await scene_tree.process_frame
				await scene_tree.process_frame
				for row in panel.find_child("ChoiceRows", true, false).get_children():
					if row.is_queued_for_deletion():
						continue
					var label := row.get_child(0) as Label
					var needed := label.get_theme_font("font").get_string_size(label.text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
					assert_true(needed <= label.size.x + 0.5,
						"[%s] '%s' needs %.0f px and has %.0f" % [code, label.text, needed,
							label.size.x])
	_use_language("vi")
	free_node(hud)


func test_the_mood_colours_are_the_kits_own_roles() -> void:
	assert_eq(UITheme.dialogue_mood_color(DialogueNodeData.Mood.CALM), UIPalette.COLOR_TEXT,
		"calm")
	assert_eq(UITheme.dialogue_mood_color(DialogueNodeData.Mood.WARM), UIPalette.COLOR_TITLE,
		"warm")
	assert_eq(UITheme.dialogue_mood_color(DialogueNodeData.Mood.STERN),
		UIPalette.COLOR_CRIMSON_HOVER, "stern")
	assert_eq(UITheme.dialogue_mood_color(DialogueNodeData.Mood.WARY),
		UIPalette.COLOR_TEXT_MUTED, "wary")

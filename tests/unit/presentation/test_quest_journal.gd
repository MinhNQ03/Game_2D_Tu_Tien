extends TestCase
## Unit tests for what the player SEES of their quests (Phase 19): the one purpose line in the
## place plaque and the journal panel. Both render a `QuestJournalView`; neither decides
## anything. Key handling (the journal's own key, Esc, a threat) is driven with real key
## events in the quest E2E flow; here the HUD's own state and layout.

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const QUESTS := "res://data/quests/quest_catalog.tres"

const VEIN := &"quest_unquiet_vein"
const PILLS := &"quest_treeline_pills"


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


func _entry(quest_id: StringName, phase: QuestService.Phase, prefix: String,
		objectives: Array, any: bool, owed: bool = false) -> Dictionary:
	var hint := "%s_LEAD" % prefix
	if phase == QuestService.Phase.ACTIVE:
		hint = "%s_GOAL" % prefix
	elif phase == QuestService.Phase.READY:
		hint = "%s_RETURN" % prefix
	var typed: Array[Dictionary] = []
	for objective: Dictionary in objectives:
		typed.append(objective)
	var reward_items: Array[Dictionary] = [
		{"name_key": &"ITEM_BO_HUYET_DAN_NAME", "count": 2}]
	return {"quest_id": quest_id, "phase": phase, "owed": owed,
		"title_key": StringName("%s_TITLE" % prefix),
		"summary_key": StringName("%s_SUMMARY" % prefix), "hint_key": StringName(hint),
		"giver_name_key": &"CHARACTER_ELDER_SHEN_NAME",
		"receiver_name_key": &"CHARACTER_ELDER_SHEN_NAME", "any": any, "objectives": typed,
		"reward_items": reward_items, "reward_xp": 10,
		"reward_regard_name_key": &"CHARACTER_ELDER_SHEN_NAME",
		"reward_regard_dimension": &"respect", "reward_regard_delta": 10}


## The elder's task under way (two ways, neither done) and the scout's errand ready to hand in.
func _view() -> QuestJournalView:
	var view := QuestJournalView.new()
	view.available = true
	view.purpose_key = &"QUEST_TREELINE_PILLS_RETURN"
	view.purpose_phase = QuestService.Phase.READY
	var entries: Array[Dictionary] = [
		_entry(VEIN, QuestService.Phase.ACTIVE, "QUEST_UNQUIET_VEIN", [
			{"text_key": &"QUEST_UNQUIET_VEIN_OBJ_FIGHT", "value": 0, "required": 1,
				"met": false},
			{"text_key": &"QUEST_UNQUIET_VEIN_OBJ_ASK", "value": 0, "required": 1,
				"met": false}], true),
		_entry(PILLS, QuestService.Phase.READY, "QUEST_TREELINE_PILLS", [
			{"text_key": &"QUEST_TREELINE_PILLS_OBJ_CARRY", "value": 2, "required": 2,
				"met": true}], false),
	]
	view.entries = entries
	return view


# === The purpose line ==============================================================

func test_the_plaque_says_what_the_player_is_about_or_nothing() -> void:
	_use_language("vi")
	var hud := _hud()
	assert_eq(hud.purpose_text(), "", "with no quest view the line is hidden")
	var view := _view()
	hud.set_quest_view(view)
	assert_eq(hud.purpose_text(), "Trao thuốc cho Kha Thản",
		"a quest ready to answer: who to go to")
	var label := hud.find_child("Purpose", true, false) as Label
	assert_eq(label.get_theme_color("font_color"), UIPalette.COLOR_ACCENT,
		"in the accent — and the words say it too, so colour is not the only signal")
	view.purpose_key = &"QUEST_UNQUIET_VEIN_GOAL"
	view.purpose_phase = QuestService.Phase.ACTIVE
	hud.set_quest_view(view)
	assert_eq(hud.purpose_text(), "Xem Vụ Lang có bám mạch rừng", "a quest under way: what to do")
	assert_eq(label.get_theme_color("font_color"), UIPalette.COLOR_TEXT, "in body text")
	_use_language("en")
	assert_eq(hud.purpose_text(), "See if wolves hold the vein", "a language change relabels it")
	view.purpose_key = &""
	hud.set_quest_view(view)
	assert_eq(hud.purpose_text(), "", "nothing on offer and nothing under way: hidden again")
	hud.set_quest_view(QuestJournalView.make_empty())
	assert_eq(hud.purpose_text(), "", "no quest session: hidden")
	_use_language("vi")
	free_node(hud)


## The line is ONE row and may not trim what it says: every purpose line the shipped quests
## can show must fit the plaque, in both languages.
func test_every_shipped_purpose_line_fits_one_row_in_both_languages() -> void:
	var catalog := load(QUESTS) as QuestCatalogData
	var hud := _hud()
	var view := QuestJournalView.new()
	view.available = true
	var label := hud.find_child("Purpose", true, false) as Label
	for code: String in ["vi", "en"]:
		_use_language(code)
		for quest in catalog.entries:
			for key: StringName in [quest.lead_key, quest.goal_key, quest.return_key]:
				view.purpose_key = key
				hud.set_quest_view(view)
				await scene_tree.process_frame
				var needed := label.get_theme_font("font").get_string_size(label.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
				assert_true(needed <= label.size.x + 0.5,
					"[%s] '%s' needs %.0f px and the plaque row has %.0f"
						% [code, label.text, needed, label.size.x])
				assert_eq(label.get_line_count(), 1, "[%s] '%s' is one row" % [code, label.text])
				assert_ne(label.text, String(key), "[%s] %s is translated" % [code, key])
	_use_language("vi")
	free_node(hud)


# === The journal ===================================================================

func test_the_journal_is_a_reading_panel_not_a_modal() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	var hud := _hud()
	var journal := hud.quest_journal_panel()
	assert_false(hud.is_quest_journal_open(), "closed at rest")
	journal.visible = true
	assert_true(hud.is_quest_journal_open(), "open")
	assert_true(bool(input.call("is_gameplay_active")),
		"the journal takes no input context: the player keeps walking with it open")
	assert_true((hud.find_child("PromptStrip", true, false) as Control).visible,
		"so the prompt strip stays: its keys still act")
	assert_false(journal.is_processing(), "and it runs nothing per frame")
	hud.close_reading_panels()
	assert_false(hud.is_quest_journal_open(), "a hostile turning on the player closes it")
	journal.visible = true
	hud.open_inventory()
	hud.show_defeat()
	assert_false(hud.is_quest_journal_open(), "and so does falling")
	free_node(hud)
	assert_true(bool(input.call("is_gameplay_active")), "the HUD gave back every context it took")
	input.call("set_menu_context")


func test_the_journal_lists_the_most_urgent_first_and_says_each_state_in_words() -> void:
	_use_language("vi")
	var hud := _hud()
	var journal := hud.quest_journal_panel()
	hud.set_quest_view(_view())
	assert_eq(journal.shown_quest_ids(), [PILLS, VEIN] as Array[StringName],
		"what is ready to answer comes before what is under way, whatever the authored order")
	var pills := journal.block_text(PILLS)
	assert_true(pills.contains("Thuốc cho người gác bìa rừng"), "its name")
	assert_true(pills.contains("xong, chờ thưa lại"), "its state, as a word")
	assert_true(pills.contains("Trao thuốc cho Kha Thản"), "the next thing to do")
	assert_true(pills.contains("Kha Thản không rời được lối băng rừng"), "why it matters")
	assert_true(pills.contains("Mang Bổ Huyết Đan tới cho Kha Thản (2/2) — xong"),
		"the objective, its count, and that it is met — in words")
	assert_true(pills.contains("Người nhờ: Thẩm Bất Kỳ"), "who asked")
	assert_true(pills.contains("Thưởng: Bổ Huyết Đan ×2 · 10 KN · kính trọng của Thẩm Bất Kỳ"),
		"and what it pays, part by part")
	var vein := journal.block_text(VEIN)
	assert_true(vein.contains("đang làm"), "under way, as a word")
	assert_true(vein.contains("Chỉ cần một trong các cách:"), "two ways are marked as either-or")
	assert_true(vein.contains("· Hạ một con Vụ Lang trong Rừng Vỡ Mạch")
		and vein.contains("· Hỏi Kha Thản về bãi săn của Vụ Lang"), "and both are listed")
	assert_false(vein.contains("(0/1)"), "a count of one is not printed as a fraction")
	_use_language("en")
	assert_true(journal.block_text(PILLS).contains("ready to answer"), "English follows")
	assert_true(journal.block_text(VEIN).contains("Any one of these:"), "in every line")
	_use_language("vi")
	free_node(hud)


func test_offered_owed_done_and_empty_each_read_differently() -> void:
	_use_language("vi")
	var hud := _hud()
	var journal := hud.quest_journal_panel()
	var view := QuestJournalView.new()
	view.available = true
	var entries: Array[Dictionary] = [
		_entry(VEIN, QuestService.Phase.COMPLETED, "QUEST_UNQUIET_VEIN", [], true),
		_entry(PILLS, QuestService.Phase.AVAILABLE, "QUEST_TREELINE_PILLS", [], false),
	]
	view.entries = entries
	hud.set_quest_view(view)
	assert_eq(journal.shown_quest_ids(), [PILLS, VEIN] as Array[StringName],
		"what is on offer comes before what is done")
	var offered := journal.block_text(PILLS)
	assert_true(offered.contains("chờ người nhận"), "on offer, as a word")
	assert_true(offered.contains("Kha Thản chờ thuốc của làng"), "with where to go")
	assert_true(offered.contains("Thưởng:"), "and what it pays, BEFORE it is taken")
	assert_false(offered.contains("Kha Thản không rời được"),
		"but not the whole ask: that is his to say")
	var done := journal.block_text(VEIN)
	assert_eq(done, "Mạch rừng không yên\nđã xong", "a finished quest is one quiet line")
	entries[1] = _entry(PILLS, QuestService.Phase.READY, "QUEST_TREELINE_PILLS", [], false, true)
	view.entries = entries
	hud.set_quest_view(view)
	assert_true(journal.block_text(PILLS).contains("còn thiếu thưởng"),
		"a reward still owed says so instead of 'done'")
	var none := QuestJournalView.new()
	none.available = true
	hud.set_quest_view(none)
	assert_eq(journal.shown_quest_ids(), [] as Array[StringName], "no entries")
	var said_empty := false
	for label: Label in journal.find_children("*", "Label", true, false):
		if label.visible and label.text == "Chưa ai nhờ ngươi việc gì.":
			said_empty = true
	assert_true(said_empty, "an empty journal says so")
	free_node(hud)


func test_no_journal_line_shows_a_raw_key_in_either_language() -> void:
	var hud := _hud()
	var journal := hud.quest_journal_panel()
	hud.set_quest_view(_view())
	for code: String in ["vi", "en"]:
		_use_language(code)
		for label: Label in journal.find_children("*", "Label", true, false):
			assert_false(label.text.contains("QUEST_") or label.text.contains("UI_")
				or label.text.contains("CHARACTER_") or label.text.contains("ITEM_"),
				"[%s] '%s' is not a raw key" % [code, label.text])
			assert_false(label.text.contains("{") or label.text.contains("}"),
				"[%s] '%s' has no unfilled placeholder" % [code, label.text])
	var keys := journal.find_child("Keys", true, false) as Label
	assert_true(keys.text.begins_with("Q "), "the keys line names the journal's own key")
	_use_language("vi")
	free_node(hud)


## The journal's box is the shared bounded side panel: its content scrolls inside it and can
## never push the frame off-screen, at either authored size, however much it holds.
func test_a_full_journal_stays_inside_its_box() -> void:
	_use_language("vi")
	var hud := _hud()
	var journal := hud.quest_journal_panel()
	var view := _view()
	for i in 6:
		view.entries.append(_entry(StringName("quest_extra_%d" % i),
			QuestService.Phase.ACTIVE, "QUEST_UNQUIET_VEIN", [
				{"text_key": &"QUEST_UNQUIET_VEIN_OBJ_FIGHT", "value": 0, "required": 1,
					"met": false}], false))
	hud.set_quest_view(view)
	journal.visible = true
	await scene_tree.process_frame
	await scene_tree.process_frame
	var viewport := journal.get_viewport_rect().size
	assert_eq(int(journal.size.x), UIPalette.SIDE_PANEL_WIDTH,
		"its width is the side panel's, not its content's")
	assert_true(journal.size.y <= viewport.y - UIPalette.HUD_MARGIN * 2.0
		- UIPalette.TOP_PLAQUE_RESERVE - UIPalette.PROMPT_STRIP_RESERVE + 1.0,
		"eight quests do not make it taller than its box (%.0f px)" % journal.size.y)
	var keys := journal.find_child("Keys", true, false) as Label
	assert_true(keys.get_global_rect().end.y <= journal.get_global_rect().end.y + 0.5,
		"and the keys line stays inside the frame")
	free_node(hud)

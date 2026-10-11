extends "res://tests/framework/test_case.gd"
## The Chronicle (Phase 20, D-072 §8): one reading book, four pages, pure presentation.

const HudScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const LOC_PATH := "/root/Localization"


func _hud() -> GameplayHUD:
	var hud: GameplayHUD = HudScript.new()
	add_to_tree(hud)
	return hud


func _use_language(code: String) -> void:
	var loc := scene_tree.root.get_node_or_null(LOC_PATH)
	if loc != null:
		loc.call("set_language", code)


func _view() -> ChronicleView:
	var view := ChronicleView.new()
	view.available = true
	view.chapter_title_key = &"STORY_CHAPTER_PROLOGUE_TITLE"
	view.objective_key = &"STORY_BEAT_SETTLE_OBJECTIVE"
	var records: Array[StringName] = [&"STORY_BEAT_ARRIVAL_RECORD", &"STORY_BEAT_NIGHT_RECORD"]
	view.records = records
	var decisions: Array[StringName] = [&"STORY_CHOICE_LAM_READINGS_KEPT"]
	view.decisions = decisions
	view.origin_name_key = &"ORIGIN_LANG_Y_NAME"
	view.origin_problem_key = &"ORIGIN_LANG_Y_PROBLEM"
	view.origin_edge_key = &"ORIGIN_LANG_Y_EDGE"
	view.origin_cost_key = &"ORIGIN_LANG_Y_COST"
	view.origin_goal_key = &"ORIGIN_LANG_Y_GOAL"
	view.knowledge.append({"name_key": &"KNOW_SURVEY_FRAGMENT_NAME",
		"desc_key": &"KNOW_SURVEY_FRAGMENT_DESC"})
	view.people.append({"name_key": &"CHARACTER_DISCIPLE_LIN_NAME",
		"title_key": &"CHARACTER_DISCIPLE_LIN_TITLE", "affinity": 0, "trust": 15, "respect": 0})
	return view


func test_the_book_has_four_pages_and_each_says_what_its_owner_holds() -> void:
	_use_language("vi")
	var hud := _hud()
	var book := hud.chronicle_panel()
	hud.set_chronicle_view(_view())
	book.reset_page()
	assert_eq(book.page_id(), ChroniclePanel.PAGE_STORY, "it opens on the story")
	var lines := book.page_lines()
	assert_true(lines.has("Trước mắt: Tĩnh tọa ở suối Lạc Hà"),
		"what to do now is on it (%s)" % str(lines))
	assert_true(lines.find("Mạch dưới rừng đã vỡ. Ngươi có mặt ở đó, và ngươi còn sống.")
		< lines.find("Ngươi bước vào Thôn Lạc Hà. Không ai chờ ngươi cả."),
		"the newest record is read first")
	assert_true(lines.has("◆ Ngươi giữ kín việc Lâm Nguyệt tự ý đo mạch."),
		"decisions are marked")
	assert_true(book.advance_page(), "there is a next page")
	assert_true(book.page_lines().has("Lang Y Du Phương"), "who the player was")
	assert_true(book.page_lines().has(
		"Điều ngươi tìm: Tìm ra bệnh nhân của ngươi thật sự chết vì đâu."),
		"and what they came for")
	assert_true(book.advance_page(), "and another")
	assert_eq(book.page_id(), ChroniclePanel.PAGE_KNOWLEDGE, "what is known")
	assert_eq(book.page_lines().size(), 2, "one name and one description per thing known")
	assert_true(book.advance_page(), "and the last")
	assert_true(book.page_lines().has("Lâm Nguyệt — Nội môn đệ tử"), "whom they have met")
	assert_true(book.page_lines().has("Thiện cảm 0 · Tin cậy 15 · Kính trọng 0"),
		"and how that person regards them, in numbers the graph holds")
	assert_false(book.advance_page(), "after the last page there is no next: the HUD closes it")
	free_node(hud)


func test_an_empty_book_says_so_and_never_shows_a_raw_key() -> void:
	var hud := _hud()
	var book := hud.chronicle_panel()
	for code: String in ["vi", "en"]:
		_use_language(code)
		book.refresh_language()
		assert_eq(book.page_lines().size(), 1, "[%s] no view: one line saying so" % code)
		var empty := ChronicleView.new()
		empty.available = true
		hud.set_chronicle_view(empty)
		book.reset_page()
		while true:
			for line in book.page_lines():
				assert_false(line.contains("UI_") or line.contains("STORY_"),
					"[%s] page %s shows no raw key ('%s')" % [code, book.page_id(), line])
			if not book.advance_page():
				break
		hud.set_chronicle_view(null)
		book.reset_page()
	_use_language("vi")
	free_node(hud)


func test_the_world_line_names_who_it_is_about() -> void:
	_use_language("vi")
	var hud := _hud()
	var view := WorldSimView.new()
	view.available = true
	view.last_event_kind_key = &"WORLDSIM_EVENT_RELATIONSHIP_SHIFT"
	view.last_event_magnitude = 5
	hud.set_world_sim_view(view)
	var nameless := (hud.find_child("WorldEvent", true, false) as Label).text
	view.last_event_who_key = &"CHARACTER_DISCIPLE_LIN_NAME"
	hud.set_world_sim_view(view)
	var named := (hud.find_child("WorldEvent", true, false) as Label).text
	assert_true(named.begins_with("Lâm Nguyệt: "), "the subject leads the line ('%s')" % named)
	assert_true(named.ends_with(nameless), "and the rest says what moved ('%s')" % nameless)
	free_node(hud)

extends "res://tests/framework/test_case.gd"
## The Chronicle (Phase 20, D-072 §8; D-073 §4): one reading book, pure presentation —
## what each page says, in words, from its owners; nothing dropped to fit.

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


func _regard(dimension: StringName, value: int, minimum: int = 0,
		maximum: int = 100) -> Dictionary:
	return {"dimension": dimension, "value": value, "minimum": minimum, "maximum": maximum}


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
	var noticed: Array[StringName] = [&"STORY_NOTICED_CARTER_LANG_Y"]
	view.noticed = noticed
	view.stats_available = true
	view.attack = 12
	view.defense = 4
	view.move_speed = 120
	view.knowledge.append({"name_key": &"KNOW_SURVEY_FRAGMENT_NAME",
		"desc_key": &"KNOW_SURVEY_FRAGMENT_DESC"})
	var kept: Array[StringName] = [&"STORY_CHOICE_LAM_READINGS_KEPT"]
	view.people.append({"name_key": &"CHARACTER_DISCIPLE_LIN_NAME",
		"title_key": &"CHARACTER_DISCIPLE_LIN_TITLE",
		"regard": [_regard(&"affinity", 0, -100, 100), _regard(&"trust", 15),
			_regard(&"respect", 0)], "notes": kept})
	var none: Array[StringName] = []
	view.people.append({"name_key": &"CHARACTER_ELDER_SHEN_NAME",
		"title_key": &"CHARACTER_ELDER_SHEN_TITLE",
		"regard": [_regard(&"affinity", -10, -100, 100), _regard(&"trust", 0),
			_regard(&"respect", 0)], "notes": none})
	return view


## Turn to the first page of `section` (asserting the book has one).
func _turn_to(book: ChroniclePanel, section: StringName) -> void:
	book.reset_page()
	for _i in book.page_count():
		if book.page_id() == section:
			return
		book.advance_page()
	assert_eq(book.page_id(), section, "the book has a '%s' page" % section)


## Every line of the section, over however many pages it takes.
func _section_lines(book: ChroniclePanel, section: StringName) -> Array[String]:
	var out: Array[String] = []
	book.reset_page()
	for _i in book.page_count():
		if book.page_id() == section:
			out.append_array(book.page_lines())
		if not book.advance_page():
			break
	return out


func test_the_book_says_what_each_owner_holds_page_by_page() -> void:
	_use_language("vi")
	var hud := _hud()
	var book := hud.chronicle_panel()
	hud.set_chronicle_view(_view())
	book.visible = true
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
	var sections: Array[StringName] = []
	book.reset_page()
	for _i in book.page_count():
		if sections.is_empty() or sections.back() != book.page_id():
			sections.append(book.page_id())
		if not book.advance_page():
			break
	assert_eq(sections, [ChroniclePanel.PAGE_STORY, ChroniclePanel.PAGE_SELF,
		ChroniclePanel.PAGE_BODY, ChroniclePanel.PAGE_KNOWLEDGE, ChroniclePanel.PAGE_PEOPLE]
		as Array[StringName], "story, who you are, body and path, knowledge, people — in order")
	assert_false(book.advance_page(), "after the last page there is no next: the HUD closes it")
	var who := _section_lines(book, ChroniclePanel.PAGE_SELF)
	assert_true(who.has("Lang Y Du Phương"), "who the player was (%s)" % str(who))
	assert_true(who.has("Điều ngươi tìm: Tìm ra bệnh nhân của ngươi thật sự chết vì đâu."),
		"and what they came for")
	assert_true(who.has("◆ Móng tay lão phu xe xám như tro — như người bệnh ngươi không cứu được."),
		"and what only this Origin noticed, kept to be re-read (H21-11)")
	assert_eq(_section_lines(book, ChroniclePanel.PAGE_KNOWLEDGE).size(), 2,
		"one name and one description per thing known")
	free_node(hud)


## H21-07: a number alone means nothing to a newcomer. Each dimension is said by NAME, with a
## word for where it stands and the number; the dimensions are never added together; and the
## decision that moved a person's regard stands under them.
func test_the_people_page_says_each_regard_in_words_and_why() -> void:
	_use_language("vi")
	var hud := _hud()
	var book := hud.chronicle_panel()
	hud.set_chronicle_view(_view())
	book.visible = true
	var lines := _section_lines(book, ChroniclePanel.PAGE_PEOPLE)
	assert_true(lines.has("Lâm Nguyệt — Nội môn đệ tử"), "whom they have met (%s)" % str(lines))
	assert_true(lines.has("Tin cậy: tin đôi chút (+15)"),
		"her trust: its name, a word, the number (%s)" % str(lines))
	assert_true(lines.has("Thiện cảm: dửng dưng (0)"), "her affinity, separately")
	assert_true(lines.has("Kính trọng: chưa nể (0)"), "her respect, separately")
	assert_true(lines.has("Thiện cảm: lạnh nhạt (-10)"),
		"the elder's affinity is below nothing, and says so")
	var lin_at := lines.find("Lâm Nguyệt — Nội môn đệ tử")
	var note_at := lines.find("◆ Ngươi giữ kín việc Lâm Nguyệt tự ý đo mạch.")
	var shen_at := lines.find("Thẩm Bất Kỳ — Trưởng lão Thanh Đài")
	assert_true(note_at > lin_at and note_at < shen_at,
		"the decision that moved her regard stands under HER, not under the elder")
	for line in lines:
		assert_false(line.contains("actor_") or line.contains("UI_") or line.contains("rel_"),
			"no raw id or key ('%s')" % line)
		assert_false(line.to_lower().contains("tổng") or line.to_lower().contains("total"),
			"and no total: the dimensions are never summed ('%s')" % line)
	_use_language("en")
	book.refresh_language()
	var english := _section_lines(book, ChroniclePanel.PAGE_PEOPLE)
	assert_true(english.has("Trust: a little (+15)") and english.has("Affinity: cold (-10)"),
		"in English too (%s)" % str(english))
	_use_language("vi")
	free_node(hud)


## A dimension that is at its default is not news; one that has moved is. A rivalry appears
## only for someone who has one (the rejected candidate and Lâm Nguyệt).
func test_a_dimension_that_was_never_set_is_not_listed() -> void:
	_use_language("en")
	var hud := _hud()
	var book := hud.chronicle_panel()
	var view := _view()
	(view.people[0]["regard"] as Array).append(_regard(&"rivalry", 15))
	hud.set_chronicle_view(view)
	book.visible = true
	var lines := _section_lines(book, ChroniclePanel.PAGE_PEOPLE)
	assert_eq(lines.count("Rivalry: a spark (+15)"), 1, "her rivalry, once (%s)" % str(lines))
	var rivalries := 0
	for line in lines:
		rivalries += int(line.begins_with("Rivalry"))
	assert_eq(rivalries, 1, "and nobody else is given one they do not have")
	_use_language("vi")
	free_node(hud)


## H21-08: one place to read one's own character — every line a number an owner holds, fed by
## the same views the HUD shows, with nothing computed here.
func test_body_and_path_reads_what_the_owners_report() -> void:
	_use_language("vi")
	var hud := _hud()
	var book := hud.chronicle_panel()
	hud.set_chronicle_view(_view())
	hud.set_map_name(&"UI_MAP_HUB_NAME")
	hud.set_health(64, 100)
	var progression := ProgressionView.new()
	progression.available = true
	progression.level = 3
	progression.xp_into_level = 12
	progression.xp_for_next = 40
	hud.set_progression_view(progression)
	var realm := CultivationView.new()
	realm.available = true
	realm.realm_name_key = &"REALM_HAU_THIEN_NAME"
	realm.layer = 1
	realm.progress = 7
	realm.step_cost = 40
	hud.set_cultivation_view(realm)
	var bag := InventoryView.new()
	bag.rows.append({"item_id": &"item_kiem_thanh_thiet",
		"name_key": &"ITEM_KIEM_THANH_THIET_NAME", "desc_key": &"ITEM_KIEM_THANH_THIET_DESC",
		"icon": null, "count": 1, "usable": true, "equipped": true})
	bag.rows.append({"item_id": &"item_bo_huyet_dan", "name_key": &"ITEM_BO_HUYET_DAN_NAME",
		"desc_key": &"ITEM_BO_HUYET_DAN_DESC", "icon": null, "count": 2, "usable": true,
		"equipped": false})
	hud.set_inventory_view(bag)
	var arts := SkillView.new()
	arts.slots.append({"slot": 1, "technique_id": &"tech_thanh_phong_chuong",
		"name_key": &"TECH_THANH_PHONG_CHUONG_NAME", "icon": null, "element": &"phong",
		"cooldown_left": 0.0, "cooldown_total": 1.0, "qi_cost": 12, "ready": true})
	hud.set_skill_view(arts)
	book.visible = true
	var lines := _section_lines(book, ChroniclePanel.PAGE_BODY)
	var loc := scene_tree.root.get_node_or_null(LOC_PATH)
	assert_true(lines.has("Sinh lực 64 / 100"), "health, as the gauge has it (%s)" % str(lines))
	assert_true(lines.has("Cấp 3 · kinh nghiệm 12 / 40"), "level and experience")
	assert_true(lines.has("%s tầng 1 · tu vi 7 / 40" % loc.call("t", "REALM_HAU_THIEN_NAME")),
		"the realm, its layer and how far along")
	assert_true(lines.has("Công 12 · Thủ 4 · Tốc độ 120"), "the stats combat reads, by name")
	assert_true(lines.has(String(loc.call("t", "ITEM_KIEM_THANH_THIET_NAME"))),
		"what is worn")
	assert_true(lines.has(String(loc.call("t", "ITEM_KIEM_THANH_THIET_DESC"))),
		"with the item's own account of what it changes")
	assert_false(lines.has(String(loc.call("t", "ITEM_BO_HUYET_DAN_NAME"))),
		"and NOT the rest of the bag: this is not a second satchel")
	var art_line := ""
	for line in lines:
		if line.begins_with(String(loc.call("t", "TECH_THANH_PHONG_CHUONG_NAME"))):
			art_line = line
	assert_true(art_line.contains("12 khí"), "a technique with its cost ('%s')" % art_line)
	var input := scene_tree.root.get_node_or_null("InputService")
	assert_true(art_line.ends_with(String(input.call("get_action_display_label", &"skill_1"))),
		"and the key InputService reports for its slot ('%s')" % art_line)
	assert_true(lines.has("Chưa có linh thú nào đi cùng ngươi."), "no companion: said plainly")
	assert_true(lines.has("Ngươi đang ở Thôn Lạc Hà."), "and the place")
	# It follows its owners: a blow shows on the open page, with no other call.
	hud.set_health(40, 100)
	assert_true(_section_lines(book, ChroniclePanel.PAGE_BODY).has("Sinh lực 40 / 100"),
		"the open book follows the gauge")
	free_node(hud)


## H21-09: the book used to show the newest six records and drop the rest. Nothing is dropped
## now: the newest fill the first page and every older one is on a later page — the earlier
## road, after everything else — and no page is taller than the room it has, in either language.
func test_a_long_history_is_paged_whole_newest_first_and_every_page_fits() -> void:
	var hud := _hud()
	var book := hud.chronicle_panel()
	var view := _view()
	var long: Array[StringName] = []
	var beats: Array[StringName] = [&"ROAD", &"ARRIVAL", &"CONTACTS", &"BUSINESS", &"CONFIDENCE",
		&"WARNING", &"NIGHT", &"AFTERMATH", &"SETTLE", &"SHEET_TOLD", &"LEAVING",
		&"WHOSE_HAND", &"STAKE_LINE", &"RUTS"]
	for _repeat in 3:  # three times the whole shipped story: 42 records
		for stem in beats:
			long.append(StringName("STORY_BEAT_%s_RECORD" % stem))
	view.records = long
	# ...and everything else a finished bridge leaves in the book: the eight things known by
	# then, four people (one with a rivalry and two decisions on record), two observations.
	for stem: String in ["SURVEYORS_LINE", "NIGHT_WHEELS", "SHAFT_CLAIM", "STAKE_SOCKET",
			"SEALED_SHAFT", "SURVEY_NOTATION", "VEIN_STONE_GRADES"]:
		view.knowledge.append({"name_key": StringName("KNOW_%s_NAME" % stem),
			"desc_key": StringName("KNOW_%s_DESC" % stem)})
	var both: Array[StringName] = [&"STORY_CHOICE_LAM_READINGS_KEPT",
		&"STORY_CHOICE_SHEET_SHOWN_LIN"]
	view.people[0]["notes"] = both
	(view.people[0]["regard"] as Array).append(_regard(&"rivalry", 15))
	var stood: Array[StringName] = [&"STORY_CHOICE_NIGHT_STAND_STOOD"]
	view.people.append({"name_key": &"CHARACTER_SCOUT_KO_NAME",
		"title_key": &"CHARACTER_SCOUT_KO_TITLE", "regard": [_regard(&"affinity", 0, -100, 100),
			_regard(&"trust", 5), _regard(&"respect", 10)], "notes": stood})
	var two: Array[StringName] = [&"STORY_NOTICED_CARTER_LANG_Y", &"STORY_NOTICED_TRAIL_LANG_Y"]
	view.noticed = two
	var loc := scene_tree.root.get_node_or_null(LOC_PATH)
	for code: String in ["vi", "en"]:
		_use_language(code)
		hud.set_chronicle_view(view)
		book.visible = true
		book.refresh_language()
		await scene_tree.process_frame
		await scene_tree.process_frame
		book.reset_page()
		var everything := book.all_lines()
		for key in long:
			assert_eq(everything.count(String(loc.call("t", String(key)))), 3,
				"[%s] every record of '%s' is in the book" % [code, key])
		var first_page := book.page_lines()
		assert_true(first_page.find(String(loc.call("t", "STORY_BEAT_RUTS_RECORD")))
			< first_page.find(String(loc.call("t", "STORY_BEAT_STAKE_LINE_RECORD"))),
			"[%s] the newest record leads the first page, the one before it follows" % code)
		assert_true(first_page.size() < everything.size() / 2,
			"[%s] the first page holds what fits (%d lines of %d), not everything"
			% [code, first_page.size(), everything.size()])
		var sections: Array[StringName] = []
		var history_pages := 0
		for _i in book.page_count():
			sections.append(book.page_id())
			history_pages += int(book.page_id() == ChroniclePanel.PAGE_HISTORY)
			if not book.advance_page():
				break
		assert_true(history_pages >= 2, "[%s] the earlier road takes pages of its own (%d)"
			% [code, history_pages])
		assert_eq(sections.find(ChroniclePanel.PAGE_HISTORY),
			sections.rfind(ChroniclePanel.PAGE_PEOPLE) + 1,
			"[%s] and they come AFTER the pages a player opens the book for" % code)
		assert_eq(book.page_lines().back(), String(loc.call("t", "STORY_BEAT_ROAD_RECORD")),
			"[%s] the very first record is the last line of the book" % code)
		assert_true(book.tallest_page_height() <= book.body_height() + 0.5,
			"[%s] no page is taller than its room: %.0f px of content in %.0f px"
			% [code, book.tallest_page_height(), book.body_height()])
		assert_true(book.body_height() > 150.0, "[%s] measured on a laid-out panel (%.0f px)"
			% [code, book.body_height()])
	# AT THE SMALLEST SUPPORTED WINDOW, and at the second aspect ratio (PX-5): the same book,
	# laid out by the engine at that size, still has no page taller than its room.
	var window := scene_tree.root
	var was := window.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		window.size = size
		for code: String in ["vi", "en"]:
			_use_language(code)
			book.refresh_language()
			for _i in 3:
				await scene_tree.process_frame
			book.reset_page()
			assert_eq(int(book.get_viewport_rect().size.y), size.y, "measured at %s" % size)
			assert_true(book.tallest_page_height() <= book.body_height() + 0.5,
				"[%s %s] %.0f px of content in %.0f px of page"
				% [code, size, book.tallest_page_height(), book.body_height()])
			# ...and AS LAID OUT (PX-5): every page's real labels, measured by the engine, fit
			# the room — the packing estimate is not allowed to be its own witness — and every
			# page's title fits its one line.
			var title := book.find_children("*", "Label", true, false)[0] as Label
			for page in book.page_count():
				await scene_tree.process_frame
				assert_true(book.rendered_height() <= book.body_height() + 0.5,
					"[%s %s] page %d (%s) is laid out %.0f px tall in %.0f px"
					% [code, size, page + 1, book.page_id(), book.rendered_height(),
						book.body_height()])
				assert_true(title.get_theme_default_font().get_string_size(title.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, UIPalette.FONT_SIZE_SUBTITLE).x
					<= title.size.x + 0.5, "[%s %s] the title '%s' fits its line"
					% [code, size, title.text])
				if not book.advance_page():
					break
			book.reset_page()
			assert_true(book.page_count() >= 8,
				"[%s %s] a smaller window means more pages (%d), never smaller type"
				% [code, size, book.page_count()])
			var every_line := book.all_lines()
			for key in long:
				assert_eq(every_line.count(String(loc.call("t", String(key)))), 3,
					"[%s %s] and still every record of '%s'" % [code, size, key])
	window.size = was
	_use_language("vi")
	free_node(hud)


## THE DEFECT THE FIRST REAL CAPTURE SHOWED: the book packed its pages for half the room it
## had (an estimate inflated by a title measured before it had a width), so "Body and path"
## was four lines over a page two-thirds empty, on 14 pages. A page must USE its room: at the
## smallest window an ordinary run's book is one page per section, and the estimate made
## before layout agrees with what the engine then lays out.
func test_a_page_uses_the_room_it_has_at_the_smallest_window() -> void:
	_use_language("vi")
	var window := scene_tree.root
	var was := window.size
	window.size = Vector2i(1280, 720)
	var hud := _hud()
	var book := hud.chronicle_panel()
	hud.set_chronicle_view(_view())
	hud.set_health(100, 100)
	var estimate := book.body_height()
	book.visible = true
	for _i in 4:
		await scene_tree.process_frame
	var laid_out := book.body_height()
	assert_true(laid_out > 220.0, "at 1280x720 a page has real room (%.0f px)" % laid_out)
	assert_true(absf(estimate - laid_out) <= 24.0,
		"the estimate before layout (%.0f) is what the engine lays out (%.0f)"
		% [estimate, laid_out])
	var per_section := {}
	book.reset_page()
	for _i in book.page_count():
		per_section[book.page_id()] = int(per_section.get(book.page_id(), 0)) + 1
		if not book.advance_page():
			break
	for section: StringName in [ChroniclePanel.PAGE_STORY, ChroniclePanel.PAGE_BODY,
			ChroniclePanel.PAGE_KNOWLEDGE]:
		assert_eq(int(per_section.get(section, 0)), 1,
			"an ordinary run's '%s' is ONE page, not a few lines over an empty one" % section)
	for section: StringName in [ChroniclePanel.PAGE_SELF, ChroniclePanel.PAGE_PEOPLE]:
		assert_true(int(per_section.get(section, 0)) in [1, 2],
			"'%s' (long lines, kept together per person) takes one page or two" % section)
	assert_true(book.page_count() <= 7, "seven pages at most, not fourteen (%d)"
		% book.page_count())
	assert_false(per_section.has(ChroniclePanel.PAGE_HISTORY),
		"and two records need no 'earlier road'")
	assert_true(book.tallest_page_height() <= laid_out + 0.5, "and nothing overflows it")
	window.size = was
	free_node(hud)


## A closed book costs nothing: its sources may change any number of times and nothing is
## laid out until it is opened.
func test_a_closed_book_is_not_rebuilt_until_it_is_opened() -> void:
	_use_language("vi")
	var hud := _hud()
	var book := hud.chronicle_panel()
	assert_false(book.visible, "the book starts closed")
	var built := book.page_lines().size()
	hud.set_chronicle_view(_view())
	for hp in [90, 80, 70]:
		hud.set_health(hp, 100)
	assert_eq(book.page_lines().size(), built, "nothing was laid out while it was closed")
	book.visible = true
	assert_true(book.page_lines().size() > built, "opening it lays out the current state")
	assert_true(_section_lines(book, ChroniclePanel.PAGE_BODY).has("Sinh lực 70 / 100"),
		"the LAST state it was told, not a stale one")
	free_node(hud)


func test_an_empty_book_says_so_and_never_shows_a_raw_key() -> void:
	var hud := _hud()
	var book := hud.chronicle_panel()
	book.visible = true
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


## The bands are where a value stands on ITS OWN range: read about the middle on a dimension
## that can go below zero, up from nothing on one that cannot — and every band of every
## dimension the book can show has a word in every language.
func test_regard_bands_follow_each_dimensions_own_range_and_are_all_named() -> void:
	var b := RegardBands
	assert_eq([b.band(-100, -100, 100), b.band(-40, -100, 100), b.band(-10, -100, 100),
		b.band(0, -100, 100), b.band(4, -100, 100), b.band(15, -100, 100),
		b.band(40, -100, 100)], [b.BAND_LOWEST, b.BAND_LOWEST, b.BAND_LOW, b.BAND_MIDDLE,
		b.BAND_MIDDLE, b.BAND_HIGH, b.BAND_HIGHEST],
		"a signed dimension: one impression leaves the middle, a history reaches an end")
	assert_eq([b.band(0, 0, 100), b.band(5, 0, 100), b.band(15, 0, 100), b.band(20, 0, 100),
		b.band(50, 0, 100), b.band(80, 0, 100), b.band(100, 0, 100)], [b.BAND_LOWEST,
		b.BAND_LOW, b.BAND_LOW, b.BAND_MIDDLE, b.BAND_HIGH, b.BAND_HIGHEST, b.BAND_HIGHEST],
		"an unsigned one: nothing is 'none', and it climbs from there")
	var config := load("res://data/relationship/relationship_config.tres") \
		as RelationshipConfigData
	var loc := scene_tree.root.get_node_or_null(LOC_PATH)
	var shown: Array[StringName] = ChronicleView.SHOWN_DIMENSIONS.duplicate()
	shown.append_array(ChronicleView.SHOWN_WHEN_SET)
	for dimension in shown:
		assert_true(config.has_dimension(dimension), "'%s' is a real dimension" % dimension)
		assert_true(bool(loc.call("is_translated", RegardBands.name_key(dimension))),
			"'%s' has a name in every language" % dimension)
		var lowest := config.get_min(dimension)
		var highest := config.get_max(dimension)
		var seen := {}
		for value in range(lowest, highest + 1):
			seen[RegardBands.band(value, lowest, highest)] = true
			if value > lowest:
				assert_true(RegardBands.band(value, lowest, highest)
					>= RegardBands.band(value - 1, lowest, highest),
					"'%s': a higher value is never a lower band (%d)" % [dimension, value])
		assert_eq(seen.size(), RegardBands.BAND_COUNT,
			"'%s': its range reaches all five bands" % dimension)
		for band in RegardBands.BAND_COUNT:
			var key := RegardBands.KEY_FORMAT % [String(dimension).to_upper(), band]
			assert_true(bool(loc.call("is_translated", key)), "'%s' has a word everywhere" % key)


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

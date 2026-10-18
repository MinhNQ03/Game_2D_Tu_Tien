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


## Every line of the section AS SHOWN, over however many pages it takes.
func _section_lines(book: ChroniclePanel, section: StringName) -> Array[String]:
	var out: Array[String] = []
	book.reset_page()
	for _i in book.book_page_count():
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
	assert_eq(book.tab_id(), ChroniclePanel.TAB_JOURNEY, "under the journey tab")
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
	for _i in book.book_page_count():
		if sections.is_empty() or sections.back() != book.page_id():
			sections.append(book.page_id())
		if not book.advance_page():
			break
	assert_eq(sections, [ChroniclePanel.PAGE_STORY, ChroniclePanel.PAGE_KNOWLEDGE,
		ChroniclePanel.PAGE_PEOPLE, ChroniclePanel.PAGE_SELF, ChroniclePanel.PAGE_BODY]
		as Array[StringName], "the journey, what you know, people, then who you are and body "
		+ "and path — tab by tab")
	assert_false(book.advance_page(), "after the last page there is no next")
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
## road, the rest of the journey tab — and no page is taller than its room, in either language.
func test_a_long_history_is_paged_whole_newest_first_and_every_page_fits() -> void:
	var hud := _hud()
	var book := hud.chronicle_panel()
	var view := _view()
	var long: Array[StringName] = []
	var beats: Array[StringName] = [&"ROAD", &"ARRIVAL", &"CONTACTS", &"BUSINESS", &"CONFIDENCE",
		&"WARNING", &"NIGHT", &"AFTERMATH", &"SETTLE", &"SHEET_TOLD", &"LEAVING",
		&"WHOSE_HAND", &"STAKE_LINE", &"RUTS"]
	# Six times the whole shipped story, 84 records: the centred book's page (UI-03) holds about
	# twice what the side panel's did, and the earlier road must still need pages of its own.
	for _repeat in 6:
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
			assert_eq(everything.count(String(loc.call("t", String(key)))), 6,
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
		for _i in book.book_page_count():
			sections.append(book.page_id())
			history_pages += int(book.page_id() == ChroniclePanel.PAGE_HISTORY)
			if not book.advance_page():
				break
		assert_true(history_pages >= 2, "[%s] the earlier road takes pages of its own (%d)"
			% [code, history_pages])
		assert_eq(sections.find(ChroniclePanel.PAGE_HISTORY),
			sections.rfind(ChroniclePanel.PAGE_STORY) + 1,
			"[%s] and they follow the road so far, inside the journey tab" % code)
		assert_eq(sections.rfind(ChroniclePanel.PAGE_HISTORY) + 1,
			sections.find(ChroniclePanel.PAGE_KNOWLEDGE),
			"[%s] before the next tab begins" % code)
		book.select_tab(ChroniclePanel.TAB_JOURNEY)
		while book.next_page():
			pass
		assert_eq(book.page_lines().back(), String(loc.call("t", "STORY_BEAT_ROAD_RECORD")),
			"[%s] the very first record is the journey's last line" % code)
		book.reset_page()
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
			# page's heading fits its one line.
			var captions := book.find_children("Caption", "Label", true, false)
			for page in book.book_page_count():
				await scene_tree.process_frame
				assert_true(book.rendered_height() <= book.body_height() + 0.5,
					"[%s %s] page %d (%s) is laid out %.0f px tall in %.0f px"
					% [code, size, page + 1, book.page_id(), book.rendered_height(),
						book.body_height()])
				var caption := captions[book.current_page()] as Label
				assert_true(caption.get_theme_default_font().get_string_size(caption.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, UIPalette.BOOK_TAB_FONT_SIZE).x
					<= caption.size.x + 0.5, "[%s %s] the heading '%s' fits its line"
					% [code, size, caption.text])
				if not book.advance_page():
					break
			book.reset_page()
			assert_true(book.book_page_count() >= 8,
				"[%s %s] a smaller window means more pages (%d), never smaller type"
				% [code, size, book.book_page_count()])
			var every_line := book.all_lines()
			for key in long:
				assert_eq(every_line.count(String(loc.call("t", String(key)))), 6,
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
	for _i in book.book_page_count():
		per_section[book.page_id()] = int(per_section.get(book.page_id(), 0)) + 1
		if not book.advance_page():
			break
	for section: StringName in [ChroniclePanel.PAGE_STORY, ChroniclePanel.PAGE_KNOWLEDGE]:
		assert_eq(int(per_section.get(section, 0)), 1,
			"an ordinary run's '%s' is ONE page, not a few lines over an empty one" % section)
	# The body page is headed by the character's figure since the UI refresh, which takes the
	# room a few lines did: it may run to two pages. "Not a few lines over an empty one" is
	# held for EVERY page by `test_no_page_but_the_last_is_nearly_empty`.
	for section: StringName in [ChroniclePanel.PAGE_SELF, ChroniclePanel.PAGE_PEOPLE,
			ChroniclePanel.PAGE_BODY]:
		assert_true(int(per_section.get(section, 0)) in [1, 2],
			"'%s' (long lines, kept together per person) takes one page or two" % section)
	assert_true(book.book_page_count() <= 7, "seven pages at most, not fourteen (%d)"
		% book.book_page_count())
	assert_false(per_section.has(ChroniclePanel.PAGE_HISTORY),
		"and two records need no 'earlier road'")
	assert_true(book.tallest_page_height() <= laid_out + 0.5, "and nothing overflows it")
	window.size = was
	free_node(hud)


## H21-20. No page but the book's last reads as empty: at both shipped windows and in both
## languages, every page that is followed by another is at least a third full. (It was 10
## pages at 1280x720 with 3/10 and 5/10 holding two or three lines.)
func test_no_page_but_the_last_is_nearly_empty() -> void:
	var window := scene_tree.root
	var was := window.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		for code: String in ["vi", "en"]:
			_use_language(code)
			window.size = size
			var hud := _hud()
			var book := hud.chronicle_panel()
			hud.set_chronicle_view(_view())
			hud.set_health(100, 100)
			book.visible = true
			for _i in 4:
				await scene_tree.process_frame
			var room := book.body_height()
			book.reset_page()
			var count := book.book_page_count()
			var everything := book.all_lines()
			var per_section := {}
			for _i in count:
				per_section[book.page_id()] = int(per_section.get(book.page_id(), 0)) + 1
				if not book.advance_page():
					break
			book.reset_page()
			var read: Array[String] = []
			for index in count:
				await scene_tree.process_frame   # the page just turned to is laid out
				read.append_array(book.page_lines())
				var filled := book.rendered_height()
				# A LEFTOVER is what H21-20 was: a section that ran a few lines over onto a
				# page of its own. (A section whose one page is short holds little — that is
				# what its owner has to say, not a page turned for nothing.)
				if index < count - 1 and int(per_section[book.page_id()]) > 1:
					assert_true(filled >= room / 3.0 - 0.5,
						"[%s %dx%d] page %d of %d ('%s') is %.0f px of %.0f: it reads as a page"
						% [code, size.x, size.y, index + 1, count, book.page_id(), filled, room])
				assert_true(filled <= room + 0.5, "[%s %dx%d] page %d fits its room"
					% [code, size.x, size.y, index + 1])
				if not book.advance_page():
					break
			assert_eq(read, everything, "[%s %dx%d] evening the pages out dropped and "
				% [code, size.x, size.y] + "reordered nothing")
			free_node(hud)
	window.size = was


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
		var empty_line := String(scene_tree.root.get_node(LOC_PATH).call("t", "UI_CHRONICLE_EMPTY"))
		for tab: StringName in ChroniclePanel.TABS:
			book.select_tab(tab)
			assert_eq(book.page_lines(), [empty_line],
				"[%s] no view: the '%s' tab says so too, never a blank page" % [code, tab])
		book.reset_page()
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


## UI-03 C1: the Chronicle is the centred book's second page set — at most four NAMED tabs,
## each opened by its own key (the key named on the tab), the move keys turning the tabs and
## the pages inside a tab — and through the HUD it opens modal, its own key or Esc closes it.
func test_four_named_tabs_each_opened_by_its_own_key() -> void:
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	var loc: Node = scene_tree.root.get_node_or_null(LOC_PATH)
	if input == null or loc == null:
		return
	input.call("set_gameplay_context")
	var hud := _hud()
	var book := hud.chronicle_panel()
	assert_true(book is UIBookPanel, "the Chronicle IS the centred book (the ui-02 seam)")
	var view := _view()
	var long: Array[StringName] = []
	for _repeat in 60:
		long.append(&"STORY_BEAT_NIGHT_RECORD")
	view.records = long
	hud.set_chronicle_view(view)
	for code: String in ["vi", "en"]:
		_use_language(code)
		book.refresh_language()
		assert_true(book.page_count() <= 4 and book.page_count() == ChroniclePanel.TABS.size(),
			"[%s] at most four tabs (%d)" % [code, book.page_count()])
		var strip := book.find_child("TabRow", true, false) as Node
		var shown: Array[String] = []
		for plate in strip.get_children():
			if plate.is_queued_for_deletion():
				continue
			for label in plate.get_children():
				if label is Label:
					shown.append((label as Label).text)
		for index in ChroniclePanel.TABS.size():
			var name := String(loc.call("t", "UI_CHRONICLE_TAB_%s"
				% String(ChroniclePanel.TABS[index]).to_upper()))
			var key := String(input.call("get_action_display_label",
				ChroniclePanel.TAB_ACTIONS[index]))
			assert_false(name.begins_with("UI_"), "[%s] tab %d has a name ('%s')"
				% [code, index, name])
			assert_eq(shown[index], "%s %s" % [key, name],
				"[%s] tab %d names its key and what it holds" % [code, index])
	_use_language("vi")
	book.refresh_language()
	hud.open_chronicle()
	assert_true(hud.is_chronicle_open(), "the HUD opened the book")
	assert_false(bool(input.call("is_gameplay_active")),
		"and the book holds the keys while it is open")
	assert_eq(book.tab_id(), ChroniclePanel.TAB_JOURNEY, "it opens on the journey")
	assert_true(book.is_processing(), "the open book reads its keys every frame")
	# One key per tab, read as the book reads it (its `_process`, in the modal context) — called
	# here once per press, so a press is read exactly once.
	book.set_process(false)
	for index in [2, 1, 3, 0]:
		await _press(book, ChroniclePanel.TAB_ACTIONS[index])
		assert_eq(book.tab_id(), ChroniclePanel.TABS[index],
			"the key %s opens '%s'" % [ChroniclePanel.TAB_ACTIONS[index],
				ChroniclePanel.TABS[index]])
	assert_true(book.tab_page_count() >= 2, "a long road takes the journey over pages (%d)"
		% book.tab_page_count())
	await _press(book, ChroniclePanel.LEAF_NEXT_ACTION)
	assert_eq([book.tab_id(), book.tab_page_index()], [ChroniclePanel.TAB_JOURNEY, 1],
		"move-down turns the page INSIDE the tab")
	await _press(book, ChroniclePanel.LEAF_PREV_ACTION)
	assert_eq(book.tab_page_index(), 0, "and move-up turns it back")
	await _press(book, UIBookPanel.NEXT_ACTION)
	assert_eq(book.tab_id(), ChroniclePanel.TAB_KNOWLEDGE, "move-right turns to the next tab")
	await _press(book, UIBookPanel.PREV_ACTION)
	assert_eq(book.tab_id(), ChroniclePanel.TAB_JOURNEY, "and move-left back")
	# The Chronicle's own key closes it; Esc closes it and asks nothing about leaving.
	Input.action_press(ChroniclePanel.CHRONICLE_ACTION)
	hud._unhandled_input(InputEventAction.new())
	Input.action_release(ChroniclePanel.CHRONICLE_ACTION)
	assert_false(hud.is_chronicle_open(), "its own key closed it")
	assert_true(bool(input.call("is_gameplay_active")), "and the keys are the world's again")
	await scene_tree.process_frame
	hud.open_chronicle()
	Input.action_press(&"open_menu")
	hud._unhandled_input(InputEventAction.new())
	Input.action_release(&"open_menu")
	assert_false(hud.is_chronicle_open(), "Esc closed it")
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_NONE, "one press, one level")
	# One book at a time: the satchel opening closes the Chronicle, through the one seam.
	hud.open_chronicle()
	hud.open_inventory()
	assert_false(hud.is_chronicle_open(), "the satchel took the middle of the screen")
	assert_true(hud.is_inventory_open(), "and is the one book open")
	hud.close_inventory()
	assert_true(bool(input.call("is_gameplay_active")), "closed, the keys are the world's")
	free_node(hud)
	input.call("set_menu_context")


## Press `action` for one frame and let the open book read it.
func _press(book: ChroniclePanel, action: StringName) -> void:
	Input.action_press(action)
	book._process(0.0)
	Input.action_release(action)
	await scene_tree.process_frame


## UI-03 C1: NOTHING is behind a filter. Read through the tabs alone — each tab's key, then its
## pages — the player meets every line of the book exactly once, every section whole and in
## its old order, at both windows and in both languages.
func test_every_entry_is_reached_through_the_tabs_in_its_old_order() -> void:
	var window := scene_tree.root
	var was := window.size
	var view := _view()
	var long: Array[StringName] = []
	for _repeat in 10:
		long.append(&"STORY_BEAT_ARRIVAL_RECORD")
		long.append(&"STORY_BEAT_NIGHT_RECORD")
	view.records = long
	for stem: String in ["SURVEYORS_LINE", "NIGHT_WHEELS", "SHAFT_CLAIM", "STAKE_SOCKET",
			"SEALED_SHAFT", "SURVEY_NOTATION", "VEIN_STONE_GRADES"]:
		view.knowledge.append({"name_key": StringName("KNOW_%s_NAME" % stem),
			"desc_key": StringName("KNOW_%s_DESC" % stem)})
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		for code: String in ["vi", "en"]:
			_use_language(code)
			window.size = size
			var hud := _hud()
			var book := hud.chronicle_panel()
			hud.set_chronicle_view(view)
			hud.set_health(100, 100)
			book.visible = true
			for _i in 4:
				await scene_tree.process_frame
			var read: Array[String] = []
			var by_section := {}
			for tab in ChroniclePanel.TABS:
				book.select_tab(tab)
				while true:
					await scene_tree.process_frame
					assert_eq(book.tab_id(), tab, "[%s %s] still in '%s'" % [code, size, tab])
					read.append_array(book.page_lines())
					if not by_section.has(book.page_id()):
						by_section[book.page_id()] = [] as Array[String]
					(by_section[book.page_id()] as Array[String]).append_array(book.page_lines())
					if not book.next_page():
						break
			assert_eq(read, book.all_lines(), "[%s %s] the tabs show every line once, in order"
				% [code, size])
			for section: StringName in [ChroniclePanel.PAGE_STORY, ChroniclePanel.PAGE_HISTORY,
					ChroniclePanel.PAGE_KNOWLEDGE, ChroniclePanel.PAGE_PEOPLE,
					ChroniclePanel.PAGE_SELF, ChroniclePanel.PAGE_BODY]:
				assert_eq(by_section.get(section, [] as Array[String]), book.section_lines(section),
					"[%s %s] '%s' is whole and in its order" % [code, size, section])
			var loc := scene_tree.root.get_node_or_null(LOC_PATH)
			var journey: Array[String] = book.section_lines(ChroniclePanel.PAGE_STORY)
			journey.append_array(book.section_lines(ChroniclePanel.PAGE_HISTORY))
			assert_eq(journey.count(String(loc.call("t", "STORY_BEAT_NIGHT_RECORD"))), 10,
				"[%s %s] every record is on the journey" % [code, size])
			assert_eq(book.section_lines(ChroniclePanel.PAGE_KNOWLEDGE).size(), 16,
				"[%s %s] every thing known: a name and what it says, eight times" % [code, size])
			free_node(hud)
	window.size = was
	_use_language("vi")


## UI-03 C1/C4: the learned-knowledge tab is LARGE — names at the book's row size, what they
## say at the body size at least, in the body colour — and nothing on any page of any tab is
## cut: inside the book's frame, every wrapped line shown, at both windows, in both languages.
func test_the_knowledge_tab_is_large_and_nothing_is_clipped() -> void:
	var window := scene_tree.root
	var was := window.size
	var view := _view()
	for stem: String in ["SURVEYORS_LINE", "NIGHT_WHEELS", "SHAFT_CLAIM", "STAKE_SOCKET"]:
		view.knowledge.append({"name_key": StringName("KNOW_%s_NAME" % stem),
			"desc_key": StringName("KNOW_%s_DESC" % stem)})
	var loc := scene_tree.root.get_node_or_null(LOC_PATH)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		for code: String in ["vi", "en"]:
			_use_language(code)
			window.size = size
			var hud := _hud()
			var book := hud.chronicle_panel()
			hud.set_chronicle_view(view)
			hud.set_health(100, 100)
			book.visible = true
			for _i in 4:
				await scene_tree.process_frame
			var frame := book.frame().get_global_rect()
			assert_true(frame.size.x >= float(size.x) * 0.6,
				"[%s %s] the book is large: %.0f px wide" % [code, size, frame.size.x])
			book.select_tab(ChroniclePanel.TAB_KNOWLEDGE)
			await scene_tree.process_frame
			var name_text := String(loc.call("t", "KNOW_SURVEY_FRAGMENT_NAME"))
			var desc_text := String(loc.call("t", "KNOW_SURVEY_FRAGMENT_DESC"))
			var found := 0
			for label in _labels(book.frame()):
				if label.text == name_text:
					found += 1
					assert_eq(label.get_theme_font_size("font_size"), UIPalette.BOOK_ROW_FONT_SIZE,
						"[%s %s] a thing known is named at the book's row size" % [code, size])
				elif label.text == desc_text:
					found += 1
					assert_true(label.get_theme_font_size("font_size") >= UIPalette.FONT_SIZE_BODY,
						"[%s %s] what it says is at the body size at least" % [code, size])
					assert_eq(label.get_theme_color("font_color"), UIPalette.COLOR_TEXT,
						"[%s %s] in the body colour, not muted" % [code, size])
			assert_eq(found, 2, "[%s %s] the knowledge tab shows the sheet" % [code, size])
			book.reset_page()
			for _page in book.book_page_count():
				await scene_tree.process_frame
				var where := "%s %s %s/%d" % [code, size, book.tab_id(), book.tab_page_index()]
				assert_true(book.rendered_height() <= book.body_height() + 0.5,
					"[%s] the page fits its room (%.0f of %.0f px)"
					% [where, book.rendered_height(), book.body_height()])
				for label in _labels(book.frame()):
					assert_true(frame.encloses(label.get_global_rect()),
						"[%s] '%s' lies inside the frame" % [where, label.text.left(40)])
					# The close and turn keycaps are the book's own (`test_book_panel.gd`).
					if not _in_key_prompt(label):
						assert_true(label.get_theme_font_size("font_size")
							>= UIPalette.FONT_SIZE_BODY, "[%s] '%s' is at the body size at least"
							% [where, label.text.left(40)])
					if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
						assert_eq(label.get_visible_line_count(), label.get_line_count(),
							"[%s] every line of '%s' is shown" % [where, label.text.left(40)])
					elif not label.clip_text:
						assert_true(label.get_minimum_size().x <= label.size.x + 0.5,
							"[%s] '%s' is whole on its line" % [where, label.text])
				if not book.advance_page():
					break
			free_node(hud)
	window.size = was
	_use_language("vi")


## Every visible Label under `node` (the book's own and the shown page's).
func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.find_children("*", "Label", true, false):
		if (child as Label).is_visible_in_tree() and not child.is_queued_for_deletion():
			out.append(child as Label)
	return out


func _in_key_prompt(node: Node) -> bool:
	var at := node.get_parent()
	while at != null:
		if at is UIPromptRow:
			return true
		at = at.get_parent()
	return false


## UI-03 C3: the book only READS — it names no owner, no service and no rule; what it shows is
## what the `ChronicleView` (built from the reveal ladder's owners) hands it.
func test_the_book_reads_and_owns_nothing() -> void:
	var source := FileAccess.get_file_as_string(
		"res://src/presentation/chronicle/chronicle_panel.gd")
	assert_true(source.length() > 0, "the panel's source was read")
	for forbidden in ["res://src/gameplay", "res://src/domain", "KnowledgeService",
			"StoryService", "Runtime", "EventBus", "SaveService", ".learn(", ".reveal("]:
		assert_false(source.contains(forbidden),
			"the Chronicle does not mention '%s' — it shows what its owner hands it" % forbidden)
	assert_true(source.begins_with("extends UIBookPanel"),
		"and it extends the ui-02 seam rather than copying it")


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

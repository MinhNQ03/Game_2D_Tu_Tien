extends TestCase
## The centred book (UI-02): the reusable modal page the satchel opens in, and the learned-
## knowledge book after it. Held to what the work item promised: LARGE and CENTRED at both
## aspect ratios the game is captured at, body text at the body size or above, nothing cut, a
## tab strip that turns pages, and while it is open the keys belong to it — Esc closes it and
## asks nothing more.

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const ITEMS := "res://data/items/item_catalog.tres"
const ROBED := "res://data/characters/visual/player_daobao_visual.tres"
const VIEWPORTS: Array[Vector2] = [Vector2(1280, 720), Vector2(1280, 800)]
const MIN_WIDTH_SHARE := 0.6


func _use_language(code: String) -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", code)


func _language() -> String:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	return String(loc.call("get_language")) if loc != null and loc.has_method("get_language") \
		else "en"


func _screen(size: Vector2) -> Control:
	var screen := Control.new()
	screen.size = size
	add_to_tree(screen)
	return screen


func _settle() -> void:
	for i in 3:
		await scene_tree.process_frame


## The fullest satchel the shipped catalog can make: every item, the two wearables WORN (both
## slots of the card filled, their longest names), a big stack of everything else.
func _full_view() -> InventoryView:
	var view := InventoryView.new()
	view.body_profile = load(ROBED) as CharacterVisualProfileData
	var catalog := load(ITEMS) as ItemCatalogData
	for item: ItemData in catalog.entries:
		var worn := item.equipment is EquipmentData
		view.rows.append({"item_id": item.id, "name_key": item.name_key,
			"desc_key": item.desc_key, "icon": item.icon, "count": 1 if worn else 99,
			"usable": true, "equipped": worn,
			"slot": (item.equipment as EquipmentData).slot if worn else -1})
	return view


func _labels(node: Node, out: Array[Label]) -> Array[Label]:
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append(child as Label)
		_labels(child, out)
	return out


func _inside_scroll(node: Node) -> bool:
	var at := node.get_parent()
	while at != null:
		if at is ScrollContainer:
			return true
		at = at.get_parent()
	return false


## C1: centred, at least 60% of the width, every description as long as the catalog's longest,
## in both languages at 16:9 and 16:10 — and NOTHING pushed the frame past the box the screen
## gave it (a frame larger than its anchors means content did not fit and spilled).
func test_the_satchel_book_is_large_centred_and_whole_at_both_aspect_ratios() -> void:
	var original := _language()
	var catalog := load(ITEMS) as ItemCatalogData
	for code in ["vi", "en"]:
		_use_language(code)
		for viewport in VIEWPORTS:
			# Each item's description in turn is the selected one, so the longest is measured.
			for selected in catalog.entries.size():
				var screen := _screen(viewport)
				var panel := InventoryPanel.new()
				screen.add_child(panel)
				panel.set_view(_full_view())
				panel.set_stats(true, 9999, 9999, 9999)
				panel.move_selection(selected)
				await _settle()
				_assert_whole(panel, viewport, "%s %s row %d" % [code, viewport, selected])
				free_node(screen)
	_use_language(original)


func _assert_whole(panel: InventoryPanel, viewport: Vector2, where: String) -> void:
	var frame := panel.frame().get_global_rect()
	var expected := Vector2(viewport.x * UIPalette.BOOK_WIDTH_FRACTION,
		viewport.y - 2.0 * UIPalette.BOOK_SCREEN_INSET)
	assert_true(frame.size.x >= viewport.x * MIN_WIDTH_SHARE,
		"[%s] the book is %.0f px wide, at least %.0f%% of the screen" % [where, frame.size.x,
			MIN_WIDTH_SHARE * 100.0])
	assert_true(absf(frame.size.x - expected.x) <= 1.0 and absf(frame.size.y - expected.y) <= 1.0,
		"[%s] its frame is the box the screen gives it %s, not grown by content: %s"
			% [where, expected, frame.size])
	assert_true(absf(frame.get_center().x - viewport.x * 0.5) <= 1.0
			and absf(frame.get_center().y - viewport.y * 0.5) <= 1.0,
		"[%s] centred both ways: %s" % [where, frame.get_center()])
	assert_true(Rect2(Vector2.ZERO, viewport).encloses(frame), "[%s] on screen" % where)
	var scroll := panel.find_child("ScrollBody", true, false) as ScrollContainer
	var scroll_rect := scroll.get_global_rect()
	for label in _labels(panel.frame(), [] as Array[Label]):
		var rect := label.get_global_rect()
		if _inside_scroll(label):
			# A row may scroll out of sight vertically, never sideways.
			assert_true(rect.position.x >= scroll_rect.position.x - 0.5
					and rect.end.x <= scroll_rect.end.x + 0.5,
				"[%s] row text '%s' stays inside the list's width" % [where, label.text])
		else:
			assert_true(frame.encloses(rect),
				"[%s] '%s' %s lies whole inside the frame %s" % [where, label.text, rect, frame])
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			assert_true(label.get_minimum_size().x <= rect.size.x + 0.5,
				"[%s] '%s' is shown whole on its line" % [where, label.text])
		else:
			assert_eq(label.get_visible_line_count(), label.get_line_count(),
				"[%s] every wrapped line of '%s' is shown" % [where, label.text.left(40)])
	# The body text is at least the UI body size: the rows, the description, the keys, the title,
	# and the whole character sheet beside the list (slot names, stat names and numbers).
	var body: Array[Label] = [panel.find_child("Description", true, false) as Label,
		panel.find_child("Keys", true, false) as Label,
		panel.find_child("Title", true, false) as Label]
	for row in (panel.find_child("ItemRows", true, false) as Node).get_children():
		if not row.is_queued_for_deletion():
			body.append_array(_labels(row, [] as Array[Label]))
	var card := panel.find_child("CharacterCard", true, false) as Node
	assert_not_null(card, "[%s] the character sheet stands beside the list" % where)
	if card != null:
		var sheet := _labels(card, [] as Array[Label])
		assert_true(sheet.size() >= 2 + CharacterCard.STAT_KEYS.size() * 2,
			"[%s] the sheet's slot names and stats were all measured (%d labels)"
				% [where, sheet.size()])
		body.append_array(sheet)
	for label in body:
		assert_true(label.get_theme_font_size("font_size") >= UIPalette.FONT_SIZE_BODY,
			"[%s] '%s' is at least the body size (%d)" % [where, label.text,
				label.get_theme_font_size("font_size")])


## C2: tab support — the strip shows only when there are pages to turn, the move keys' methods
## turn and wrap, only the chosen page is shown, and the book says when it turned.
func test_the_book_turns_between_its_pages() -> void:
	var screen := _screen(VIEWPORTS[0])
	var book := UIBookPanel.new()
	screen.add_child(book)
	book.set_title_key("UI_INVENTORY_TITLE")
	var first := Label.new()
	book.add_page("UI_INVENTORY_TITLE", first)
	await _settle()
	var tabs := book.find_child("Tabs", true, false) as Control
	assert_false(tabs.visible, "one page: no tab strip, nothing to turn")
	book.turn_page(1)
	assert_eq(book.current_page(), 0, "and turning a one-page book does nothing")
	var second := Label.new()
	assert_eq(book.add_page("UI_BOOK_TURN", second), 1, "a second page is added at index 1")
	var turned: Array[int] = []
	book.page_changed.connect(func(index: int) -> void: turned.append(index))
	assert_true(tabs.visible, "two pages: the strip shows")
	assert_eq((book.find_child("TabRow", true, false) as Node).get_child_count(), 2,
		"one tab per page")
	assert_true(first.visible and not second.visible, "only the chosen page is shown")
	book.turn_page(1)
	assert_eq(book.current_page(), 1, "turned to the second page")
	assert_true(second.visible and not first.visible, "and only it is shown")
	book.turn_page(1)
	assert_eq(book.current_page(), 0, "turning past the last wraps to the first")
	book.select_page(9)
	assert_eq(book.current_page(), 1, "a page past the end is the last page")
	assert_eq(turned, [1, 0, 1] as Array[int], "every turn was announced")
	assert_eq(book.page(1), second, "a page is reachable by index")
	free_node(screen)


## The book's own keys (the HUD's prompt count leaves them out): ONE close key in the header and
## the turn key on the tab strip, each glyph resolved from its semantic action through
## `InputService.get_action_display_label` and each word localised — never a literal.
func test_the_book_names_its_keys_from_the_input_service() -> void:
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if input == null or loc == null:
		return
	var original := _language()
	_use_language("en")
	var screen := _screen(VIEWPORTS[0])
	var book := UIBookPanel.new()
	screen.add_child(book)
	book.add_page("UI_INVENTORY_TITLE", Label.new())
	book.add_page("UI_BOOK_TURN", Label.new())
	await _settle()
	var close := book.find_child("CloseKey", true, false) as UIPromptRow
	var turn := book.find_child("TurnKey", true, false) as UIPromptRow
	assert_not_null(close, "the header carries the close key")
	assert_not_null(turn, "the tab strip carries the turn key")
	if close == null or turn == null:
		free_node(screen)
		_use_language(original)
		return
	var close_glyph := String(input.call("get_action_display_label", UIBookPanel.CLOSE_ACTION))
	var turn_glyph := "%s/%s" % [
		String(input.call("get_action_display_label", UIBookPanel.PREV_ACTION)),
		String(input.call("get_action_display_label", UIBookPanel.NEXT_ACTION))]
	assert_true(close_glyph in _texts(close), "the close badge shows '%s': %s"
		% [close_glyph, _texts(close)])
	assert_eq(close.action_text(), String(loc.call("t", "UI_BOOK_CLOSE")),
		"and says what it does in the player's language")
	assert_true(turn_glyph in _texts(turn), "the turn badge shows '%s': %s"
		% [turn_glyph, _texts(turn)])
	assert_eq(turn.action_text(), String(loc.call("t", "UI_BOOK_TURN")),
		"and says what it does in the player's language")
	free_node(screen)
	_use_language(original)


func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for label in _labels(node, [] as Array[Label]):
		out.append(label.text)
	return out


## C2: the book is presentation only — it never reaches into gameplay or the domain.
func test_the_book_owns_no_gameplay() -> void:
	var source := FileAccess.get_file_as_string(
		"res://src/presentation/ui/components/ui_book_panel.gd")
	assert_true(source.length() > 0, "the component's source was read")
	for forbidden in ["res://src/gameplay", "res://src/domain", "Runtime", "EventBus",
			"SaveService"]:
		assert_false(source.contains(forbidden),
			"the book does not mention '%s' — it shows what its owner hands it" % forbidden)


## C3: open, the satchel holds the keys (gameplay suspended, the prompt strip down, every side
## panel closed, the book drawn over the HUD and the notice over the book); Esc closes it and
## asks nothing about leaving; closed, the keys and the layers are back where they were.
func test_the_open_satchel_is_modal_and_esc_closes_one_level() -> void:
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	if input == null:
		return
	input.call("set_gameplay_context")
	var hud: GameplayHUD = HUDScript.new()
	add_to_tree(hud)
	var root := hud.find_child("HudRoot", false, false) as Control
	var notice := hud.find_child("HudNotice", true, false) as Label
	var notice_index := notice.get_index()
	var rest_bottom := notice.offset_bottom
	# Every side panel the HUD can show is open (the left and the right columns both), so each
	# one's close is measured, not only the journal's.
	var side_panels := {
		"sect": hud.get("_sect_panel") as Control,
		"faction": hud.get("_faction_panel") as Control,
		"journal": hud.quest_journal_panel() as Control,
		"chronicle": hud.chronicle_panel() as Control,
	}
	for side: String in side_panels:
		assert_not_null(side_panels[side], "the HUD built its %s panel" % side)
		if side_panels[side] != null:
			(side_panels[side] as Control).visible = true
	hud.open_inventory()
	var book := hud.inventory_panel()
	assert_true(hud.is_inventory_open(), "the satchel opened")
	assert_false(bool(input.call("is_gameplay_active")), "gameplay input is suspended")
	for side: String in side_panels:
		if side_panels[side] != null:
			assert_false((side_panels[side] as Control).visible,
				"the %s panel closed: one reading surface" % side)
	assert_false((hud.find_child("PromptStrip", true, false) as Control).visible,
		"the world's key prompts stand down")
	assert_true(book.get_index() > root.get_child_count() - 3,
		"the book is drawn over the HUD (index %d of %d)" % [book.get_index(),
			root.get_child_count()])
	assert_true(notice.get_index() > book.get_index(), "and the notice over the book")
	assert_eq(notice.offset_bottom, -float(UIPalette.HUD_MARGIN),
		"the notice dropped into the strip under the book")
	Input.action_press(&"open_menu")
	hud._unhandled_input(InputEventAction.new())
	Input.action_release(&"open_menu")
	assert_false(hud.is_inventory_open(), "Esc closed the book")
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_NONE,
		"and asked nothing about leaving — one press, one level")
	assert_true(bool(input.call("is_gameplay_active")), "the keys are the world's again")
	assert_eq(notice.get_index(), notice_index, "the notice is back on its own layer")
	assert_eq(notice.offset_bottom, rest_bottom, "and in its own band")
	free_node(hud)
	input.call("set_menu_context")


## The notice dropped under the open book never touches the book, at either aspect ratio: its
## band (one margin off the bottom, the height of a notice) fits the strip the book leaves.
func test_the_notice_under_the_open_book_clears_it_at_both_aspect_ratios() -> void:
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	if input != null:
		input.call("set_gameplay_context")
	_use_language("vi")
	var hud: GameplayHUD = HUDScript.new()
	add_to_tree(hud)
	hud.open_inventory()
	hud.announce(&"UI_ITEM_FULL_HEALTH")
	await scene_tree.process_frame
	var notice := hud.find_child("HudNotice", true, false) as Label
	var height := notice.get_combined_minimum_size().y
	for viewport in VIEWPORTS:
		var notice_top := viewport.y + notice.offset_bottom - height
		var book_bottom := viewport.y - UIPalette.BOOK_SCREEN_INSET
		assert_true(notice_top >= book_bottom,
			"at %s the notice (top %.0f) sits under the book (bottom %.0f)"
				% [viewport, notice_top, book_bottom])
	free_node(hud)
	if input != null:
		input.call("set_menu_context")

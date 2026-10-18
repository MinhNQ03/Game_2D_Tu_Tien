extends UIBookPanel
class_name ChroniclePanel
## ChroniclePanel — Aetheria presentation (the Chronicle, Phase 20, D-072 §8; D-073 §4; UI-03).
##
## THE ONE BOOK for everything the player may read about their own run that has no other
## home: the road so far, what they know, whom they have met, who they are and their body and
## path. Since UI-03 it is the SECOND page set of the centred book (`UIBookPanel`, UI-02): it
## opens in the middle of the screen through the HUD's one book seam, holds a UI_MODAL context
## while open, and its own key or Esc closes it.
##
## FOUR TABS, ONE KEY EACH. The six sections it always had are read under four named tabs —
## the journey (the road so far, then the earlier road), what you know, the people you met, and
## yourself (who you are, then body and path) — each opened by its own key (the digit keys of
## the dock, which the world does not hear while the book holds the keys) or turned to with the
## book's move-left / move-right. Inside a tab move-up / move-down turn its pages. Nothing hides
## behind a filter: every line of every section is in exactly one tab, in its old order.
##
## PURE PRESENTATION, AND AN OVERVIEW — NOT AN OWNER. It renders a `ChronicleView` (story,
## Origin, knowledge, people, combat stats) and the views the HUD is already handed by their
## owners (health, level, realm, bag, techniques, companion, place). It writes nothing, offers
## no action on anything it shows, and is not a second journal, bag or technique dock: to
## change what it lists the player uses the surface that owns it.
##
## PAGES ARE PACKED, NOT TRUNCATED. Each section's lines are grouped into blocks that stay
## together (a person with their regard, a record) and the blocks are packed into as many
## pages of their tab as the page's height needs, measured with the font the labels are drawn
## in. Nothing is dropped to fit: the newest records fill the journey's first page and the
## older ones follow it ("the earlier road").

const PAGE_STORY := &"story"
const PAGE_SELF := &"self"
const PAGE_BODY := &"body"
const PAGE_KNOWLEDGE := &"knowledge"
const PAGE_PEOPLE := &"people"
## Records that did not fit the first page: the earlier road, after the road so far.
const PAGE_HISTORY := &"history"

const TAB_JOURNEY := &"journey"
const TAB_KNOWLEDGE := &"knowledge"
const TAB_PEOPLE := &"people"
const TAB_SELF := &"self"
## The tabs in the strip's order; the first is the one the book opens on.
const TABS: Array[StringName] = [TAB_JOURNEY, TAB_KNOWLEDGE, TAB_PEOPLE, TAB_SELF]
## The sections each tab holds, in reading order. Every section is in exactly one tab.
const TAB_SECTIONS := {
	TAB_JOURNEY: [PAGE_STORY, PAGE_HISTORY],
	TAB_KNOWLEDGE: [PAGE_KNOWLEDGE],
	TAB_PEOPLE: [PAGE_PEOPLE],
	TAB_SELF: [PAGE_SELF, PAGE_BODY],
}
## The key that opens each tab, in `TABS` order: the dock's digit keys. While the book is open
## the HUD holds a UI_MODAL context, so no technique is cast by them.
const TAB_ACTIONS: Array[StringName] = [&"skill_1", &"skill_2", &"skill_3", &"skill_4"]
## The keys that turn the pages INSIDE a tab (move-left / move-right turn the tabs: the book's).
const LEAF_PREV_ACTION := &"move_up"
const LEAF_NEXT_ACTION := &"move_down"
const CHRONICLE_ACTION := &"chronicle"
## The action a technique in dock slot N is cast with (the dock's own actions).
const SKILL_ACTION_FORMAT := "skill_%d"

const STYLE_HEAD := &"head"
const STYLE_LINE := &"line"
const STYLE_ACCENT := &"accent"
const STYLE_MUTED := &"muted"
## A line with this key is drawn as the `CharacterCard`, at `CARD_HEIGHT`.
const CARD := &"card"
const CARD_HEIGHT := float(CharacterCard.WELL_SIZE.y) + 4.0
## The gap between the lines of ONE block (a person and their regard, a thing known and what
## it says) and between two blocks: lines that belong together sit together, and the eye finds
## where one thing ends. (At one uniform gap a person took a page to themselves.)
const LINE_GAP := 2
const BLOCK_GAP := UIPalette.SPACE_MD
## Rounding room per label: a Label's minimum height is a whole number of pixels.
const LABEL_SLACK := 1.0
## The least room a page is ever packed for, whatever the window (a guard, not a target).
const MIN_BODY_HEIGHT := 120.0
## Under this share of a page's room, a page reads as empty.
const SPARSE_FRACTION := 1.0 / 3.0

## One per tab, in `TABS` order: the page's heading line, its page count, its body and lines.
var _captions: Array[Label] = []
var _counters: Array[Label] = []
var _bodies: Array[Control] = []
var _lists: Array[VBoxContainer] = []
var _view: ChronicleView = null
## The page shown INSIDE the current tab.
var _leaf: int = 0
## Every page of the book right now, tab by tab in `TABS` order:
## `{ tab: StringName, section: StringName, blocks: Array }`, a block being an Array of
## `{ text: String, style: StringName }`.
var _leaves: Array[Dictionary] = []
var _dirty: bool = true
## The body's size as the engine laid it out (zero until it has: a closed book has no size).
var _laid_out_height: float = 0.0
var _laid_out_width: float = 0.0
var _remeasure_queued: bool = false

# What the HUD is told by the owners, handed on (never asked for here).
var _name_key: StringName = &""
var _place_key: StringName = &""
var _health: int = -1
var _health_max: int = 0
var _progression: ProgressionView = null
var _cultivation: CultivationView = null
var _inventory: InventoryView = null
var _skills: SkillView = null
var _pet: PetView = null


func _ready() -> void:
	super()
	if _lists.is_empty():
		_build_tabs()
	page_changed.connect(_on_tab_changed)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _build_tabs() -> void:
	set_title_key("UI_CHRONICLE_TITLE")
	for tab in TABS:
		var page := VBoxContainer.new()
		page.name = "Tab_%s" % String(tab).capitalize()
		page.add_theme_constant_override("separation", UIPalette.SPACE_SM)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The page's heading and where in the tab the reader is, on ONE line that never wraps:
		# a heading that wrapped on some pages would change the room and re-pack the tab.
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", UIPalette.SPACE_LG)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(heading)
		var caption := _label(UIPalette.BOOK_TAB_FONT_SIZE, UIPalette.COLOR_TITLE)
		caption.name = "Caption"
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.clip_text = true
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.add_child(caption)
		var counter := _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT_MUTED)
		counter.name = "PageCount"
		counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		heading.add_child(counter)
		var body := PanelContainer.new()
		body.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(body)
		var list := UITheme.scroll_body(body)
		list.name = "Lines"
		list.add_theme_constant_override("separation", BLOCK_GAP)
		body.resized.connect(_on_body_resized)
		_captions.append(caption)
		_counters.append(counter)
		_bodies.append(body)
		_lists.append(list)
		add_page("UI_CHRONICLE_TAB_%s" % String(tab).to_upper(), page)


## A tab names the key that opens it: "1 Hành trình". The book draws the plate and the lit
## state; only the words are this book's.
func _tab(key: String, selected: bool) -> Control:
	var plate := super(key, selected)
	var index := _tab_keys.find(key)
	if index >= 0 and index < TAB_ACTIONS.size():
		for child in plate.get_children():
			if child is Label:
				(child as Label).text = _t_args("UI_CHRONICLE_TAB_LABEL", {
					"key": _key_label(TAB_ACTIONS[index]), "name": (child as Label).text})
	return plate


# --- What the book is told ---------------------------------------------------------

## Push a fresh view (event-driven from the owners; never polled).
func set_view(view: ChronicleView) -> void:
	_view = view
	_changed()


## Who the player is called and where they stand (the HUD's own identity and place keys).
func set_identity(name_key: StringName, place_key: StringName) -> void:
	if name_key == _name_key and place_key == _place_key:
		return
	_name_key = name_key
	_place_key = place_key
	_changed()


## The health the HUD's gauge shows (a non-positive maximum = not reported yet).
func set_health(current: int, maximum: int) -> void:
	if current == _health and maximum == _health_max:
		return
	_health = current
	_health_max = maximum
	_changed()


func set_progression_view(view: ProgressionView) -> void:
	_progression = view
	_changed()


func set_cultivation_view(view: CultivationView) -> void:
	_cultivation = view
	_changed()


func set_inventory_view(view: InventoryView) -> void:
	_inventory = view
	_changed()


## The dock's view arrives while a cooldown runs; only what this page SAYS about a technique
## (which are learned, their cost) makes the book re-lay itself.
func set_skill_view(view: SkillView) -> void:
	var before := _technique_signature(_skills)
	_skills = view
	if _technique_signature(view) != before:
		_changed()


func set_pet_view(view: PetView) -> void:
	_pet = view
	_changed()


func _technique_signature(view: SkillView) -> String:
	if view == null:
		return ""
	var parts: Array[String] = []
	for slot in view.slots:
		parts.append("%s:%s:%s" % [slot["slot"], slot["name_key"], slot["qi_cost"]])
	return ",".join(parts)


## Something the book shows changed. A CLOSED book lays nothing out: it is rebuilt when it
## is next opened, however many times its sources changed in between.
func _changed() -> void:
	_dirty = true
	if not _lists.is_empty() and visible:
		_refresh()


func _on_visibility_changed() -> void:
	if not visible or _lists.is_empty():
		return
	_take_laid_out_size()
	_refresh()
	# A book shown for the first time is laid out on the NEXT frame: measure again then.
	_queue_remeasure()


## Measure again AFTER the engine has finished laying out — never inside its layout pass.
## (`resized` is emitted while containers are being sorted; rebuilding this panel's labels
## there freed nodes the sort was still walking and crashed the real application.)
func _queue_remeasure() -> void:
	if _remeasure_queued:
		return
	_remeasure_queued = true
	_remeasure.call_deferred()


func _remeasure() -> void:
	_remeasure_queued = false
	if is_inside_tree() and visible and _take_laid_out_size():
		_dirty = true
		_refresh()


## Adopt the shown tab's body size if the engine has given it one. True when the room changed.
## (Every tab's page has the same shape, so one tab's room is every tab's.)
func _take_laid_out_size() -> bool:
	if _bodies.is_empty():
		return false
	var body := _bodies[current_page()]
	var list := _lists[current_page()]
	if body.size.y < MIN_BODY_HEIGHT or absf(body.size.y - _laid_out_height) < 0.5:
		return false
	_laid_out_height = body.size.y
	if list.size.x > 40.0:
		_laid_out_width = list.size.x
	return true


## The engine laid the body out: from now on that is the room, not the estimate.
func _on_body_resized() -> void:
	if visible:
		_queue_remeasure()


# --- Tabs and pages ----------------------------------------------------------------

## The book as it opens: the first tab, its first page.
func reset_page() -> void:
	_leaf = 0
	_dirty = true
	if _lists.is_empty():
		return
	if current_page() != 0:
		select_page(0)  # `_on_tab_changed` lays the tab out
	else:
		_refresh()


## The tab whose key was pressed, from its first page (the same key again goes back to it).
func select_tab(tab: StringName) -> void:
	var index := TABS.find(tab)
	if index < 0:
		return
	_leaf = 0
	if index != current_page():
		select_page(index)
	else:
		_render()


func tab_id() -> StringName:
	return TABS[current_page()] if current_page() < TABS.size() else TAB_JOURNEY


func _on_tab_changed(_index: int) -> void:
	_leaf = 0
	_refresh()
	# The new tab's page has not been laid out while it was hidden: measure it next frame.
	_queue_remeasure()


## Turn to the next page of the shown tab. False on its last page (nothing happens).
func next_page() -> bool:
	_repack_if_needed()
	if _leaf >= tab_page_count() - 1:
		return false
	_leaf += 1
	_render()
	return true


## Turn back one page in the shown tab. False on its first page.
func previous_page() -> bool:
	_repack_if_needed()
	if _leaf <= 0:
		return false
	_leaf -= 1
	_render()
	return true


## Turn to the next page in READING ORDER: the next page of this tab, else the first page of
## the next tab. False after the book's last page — for tests and captures, which read it all.
func advance_page() -> bool:
	if next_page():
		return true
	if current_page() >= TABS.size() - 1:
		return false
	select_page(current_page() + 1)
	return true


## Read the book's keys while open: one key per tab, and the page keys inside a tab (the
## book's own move-left / move-right turn the tabs; the HUD owns its close keys).
func _process(delta: float) -> void:
	super(delta)
	if _input == null or not visible:
		return
	for index in TAB_ACTIONS.size():
		if _input.call("is_modal_action_just_pressed", TAB_ACTIONS[index]):
			select_tab(TABS[index])
			return
	if _input.call("is_modal_action_just_pressed", LEAF_PREV_ACTION):
		previous_page()
	elif _input.call("is_modal_action_just_pressed", LEAF_NEXT_ACTION):
		next_page()


## The section the shown page belongs to (`PAGE_*`).
func page_id() -> StringName:
	var at := _leaf_index()
	return _leaves[at]["section"] if at >= 0 else PAGE_STORY


## How many pages the shown tab has.
func tab_page_count() -> int:
	_repack_if_needed()
	var count := 0
	for leaf in _leaves:
		count += int(leaf["tab"] == tab_id())
	return count


## Which page of the shown tab is shown (from 0).
func tab_page_index() -> int:
	return _leaf


## How many pages the whole book has, every tab together.
func book_page_count() -> int:
	_repack_if_needed()
	return _leaves.size()


## Where the shown page is in `_leaves` (-1 when the book has none).
func _leaf_index() -> int:
	_repack_if_needed()
	var tab := tab_id()
	var seen := 0
	for index in _leaves.size():
		if _leaves[index]["tab"] != tab:
			continue
		if seen == _leaf:
			return index
		seen += 1
	return -1


## Every line the shown page shows, in order — for tests and captures.
func page_lines() -> Array[String]:
	var out: Array[String] = []
	if _lists.is_empty():
		return out
	for block in _lists[current_page()].get_children():
		if block.is_queued_for_deletion():
			continue
		for child in block.get_children():
			if child is Label:
				out.append((child as Label).text)
			elif child is CharacterCard:
				out.append(String(child.get_meta(&"line", "")))
	return out


## Every line of EVERY page, tab by tab in reading order — for tests ("nothing was dropped").
func all_lines() -> Array[String]:
	_repack_if_needed()
	var out: Array[String] = []
	for leaf in _leaves:
		for block: Array in leaf["blocks"]:
			for line: Dictionary in block:
				out.append(String(line["text"]))
	return out


## Every line of one section, over however many pages it takes — for tests.
func section_lines(section: StringName) -> Array[String]:
	_repack_if_needed()
	var out: Array[String] = []
	for leaf in _leaves:
		if leaf["section"] != section:
			continue
		for block: Array in leaf["blocks"]:
			for line: Dictionary in block:
				out.append(String(line["text"]))
	return out


## The tallest page's content against the room it has, in pixels — for layout tests.
func tallest_page_height() -> float:
	_repack_if_needed()
	var tallest := 0.0
	for leaf in _leaves:
		tallest = maxf(tallest, _blocks_height(leaf["blocks"]))
	return tallest


## The room one page has, in pixels: what the engine laid out, or — before it has — what the
## centred book's frame (`UIPalette.BOOK_SCREEN_INSET` above and below) leaves a page in the
## current window once its title, tab strip, dividers, keys and heading line are drawn.
func body_height() -> float:
	if _laid_out_height > 0.0:
		return _laid_out_height
	var window := get_viewport_rect().size.y if is_inside_tree() \
		else float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	var frame_height := window - 2.0 * float(UIPalette.BOOK_SCREEN_INSET)
	var font := get_theme_default_font()
	# The book's column: header, tab strip, divider, pages, divider, keys (five gaps); the
	# keys line is one line of body text (an autowrap label with no width yet reports a
	# column one letter wide, so it is the font that is asked, not the label).
	var chrome := UITheme.panel_stylebox().get_minimum_size().y \
		+ 5.0 * float(UIPalette.SPACE_SM) \
		+ 2.0 * float(UIPalette.ORNAMENT_DIVIDER_HEIGHT) \
		+ font.get_height(UIPalette.FONT_SIZE_BODY)
	var header := find_child("Header", true, false) as Control
	var strip := find_child("Tabs", true, false) as Control
	chrome += header.get_combined_minimum_size().y if header != null else 0.0
	chrome += strip.get_combined_minimum_size().y if strip != null else 0.0
	# The page's own heading line, and the gap under it.
	chrome += maxf(font.get_height(UIPalette.BOOK_TAB_FONT_SIZE),
		font.get_height(UIPalette.FONT_SIZE_BODY)) + float(UIPalette.SPACE_SM)
	return maxf(MIN_BODY_HEIGHT, frame_height - chrome)


func refresh_language() -> void:
	_dirty = true
	refresh_book_text()
	_refresh()


func _refresh() -> void:
	if _lists.is_empty():
		return
	_repack_if_needed()
	_render()


func _repack_if_needed() -> void:
	if not _dirty and not _leaves.is_empty():
		return
	_dirty = false
	_leaves.clear()
	if _view == null or not _view.available:
		# Nothing written yet: every tab says so, so no key opens an empty page.
		for tab in TABS:
			_leaves.append({"tab": tab, "section": (TAB_SECTIONS[tab] as Array)[0],
				"blocks": [[_row(_t("UI_CHRONICLE_EMPTY"), STYLE_MUTED)]]})
		_leaf = 0
		return
	var room := body_height()
	var story := _pack(_story_blocks(), room)
	_leaves.append({"tab": TAB_JOURNEY, "section": PAGE_STORY,
		"blocks": story[0] if not story.is_empty() else []})
	for i in range(1, story.size()):
		_leaves.append({"tab": TAB_JOURNEY, "section": PAGE_HISTORY, "blocks": story[i]})
	for tab in [TAB_KNOWLEDGE, TAB_PEOPLE, TAB_SELF]:
		for section: StringName in TAB_SECTIONS[tab]:
			for blocks: Array in _pack(_section_blocks(section), room):
				_leaves.append({"tab": tab, "section": section, "blocks": blocks})
	_leaf = clampi(_leaf, 0, maxi(0, tab_page_count() - 1))


func _render() -> void:
	for list in _lists:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var at := _leaf_index()
	if at < 0:
		return
	var tab := current_page()
	var leaf: Dictionary = _leaves[at]
	var pages := tab_page_count()
	_captions[tab].text = _t("UI_CHRONICLE_PAGE_%s" % String(leaf["section"]).to_upper())
	_counters[tab].text = _t_args("UI_CHRONICLE_PAGE_OF", {"page": _leaf + 1, "pages": pages}) \
		if pages > 1 else ""
	# The close key is the book's (in its header); this line says what the page's keys do.
	var tab_keys: Array[String] = []
	for action in TAB_ACTIONS:
		tab_keys.append(_key_label(action))
	set_keys_text(_t_args("UI_CHRONICLE_BOOK_KEYS" if pages > 1 else "UI_CHRONICLE_BOOK_KEYS_ONE",
		{"tabs": "/".join(tab_keys),
		"turn": "%s/%s" % [_key_label(LEAF_PREV_ACTION), _key_label(LEAF_NEXT_ACTION)]}))
	for block: Array in leaf["blocks"]:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", LINE_GAP)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for line: Dictionary in block:
			if line.has(CARD):
				group.add_child(_character_card(String(line["text"])))
				continue
			var label := _styled(line["style"])
			label.text = String(line["text"])
			group.add_child(label)
		_lists[tab].add_child(group)


# --- Packing -----------------------------------------------------------------------

## Split `blocks` over as many pages as `room` pixels need. A block is never split; one that
## is taller than a page gets a page to itself (the body scrolls with the wheel as a last
## resort — nothing is cut).
func _pack(blocks: Array, room: float) -> Array:
	var pages: Array = []
	var current: Array = []
	var used := 0.0
	for block: Array in blocks:
		var height := _blocks_height([block])
		var gap := float(BLOCK_GAP) if not current.is_empty() else 0.0
		if not current.is_empty() and used + gap + height > room:
			pages.append(current)
			current = []
			used = 0.0
			gap = 0.0
		current.append(block)
		used += gap + height
	if not current.is_empty():
		pages.append(current)
	return _even_out(pages, room)


## A page that holds two lines at the end of a section is a page turned for nothing (H21-20:
## three such pages in a ten-page book at 1280x720). While the last page is under a third
## full, the block before it comes over to it, as long as that leaves the page it came from
## at least as full as the one it joins — so nothing is split, nothing is dropped, and a
## short tail becomes two pages that both read as pages.
func _even_out(pages: Array, room: float) -> Array:
	for _move in 8:
		if pages.size() < 2:
			break
		var last: Array = pages[-1]
		var before: Array = pages[-2]
		if _blocks_height(last) >= room * SPARSE_FRACTION or before.size() < 2:
			break
		var moved: Array = before[-1]
		var joined: Array = [moved]
		joined.append_array(last)
		var left: Array = before.slice(0, before.size() - 1)
		if _blocks_height(joined) > room or _blocks_height(left) < _blocks_height(last):
			break
		pages[-2] = left
		pages[-1] = joined
	return pages


## The height `blocks` take when laid out in the list, wrapped at the list's width.
func _blocks_height(blocks: Array) -> float:
	var width := _list_width()
	var total := 0.0
	var font := get_theme_default_font()
	# A Label puts its own `line_spacing` between the lines it wraps to. Leaving it out made a
	# page of wrapped records a few pixels taller per line than it was packed for: the first
	# real capture showed a scrollbar and a clipped last line.
	var spacing := float(get_theme_constant(&"line_spacing", &"Label"))
	for block: Array in blocks:
		for line: Dictionary in block:
			if line.has(CARD):
				total += CARD_HEIGHT
				continue
			var font_px := _font_size(line["style"])
			var wrapped := font.get_multiline_string_size(String(line["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, width, font_px).y
			var rows := maxi(1, int(round(wrapped / font.get_height(font_px))))
			total += wrapped + float(rows - 1) * spacing + LABEL_SLACK
		total += float(maxi(0, block.size() - 1) * LINE_GAP)
	return total + float(maxi(0, blocks.size() - 1) * BLOCK_GAP)


## The height the SHOWN page really takes, as the engine laid its labels out — what a layout
## test must compare with the room (the packing estimate cannot check itself).
func rendered_height() -> float:
	return _lists[current_page()].get_combined_minimum_size().y if not _lists.is_empty() \
		else 0.0


## The width a line wraps at: the list's own once the engine has laid it out, or — before it
## has (a list not laid out reports a few pixels, which would wrap every word onto its own
## line) — the book's frame less its padding and the scrollbar's gutter.
func _list_width() -> float:
	if _laid_out_width > 0.0:
		return _laid_out_width
	var window := get_viewport_rect().size.x if is_inside_tree() \
		else float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	return window * UIPalette.BOOK_WIDTH_FRACTION - float(UIPalette.SCROLLBAR_GUTTER) \
		- UITheme.panel_stylebox().get_minimum_size().x


# --- Sections ----------------------------------------------------------------------

func _section_blocks(section: StringName) -> Array:
	match section:
		PAGE_SELF:
			return _self_blocks()
		PAGE_BODY:
			return _body_blocks()
		PAGE_KNOWLEDGE:
			return _knowledge_blocks()
		PAGE_PEOPLE:
			return _people_blocks()
	return []


## The road so far: where the story stands, then every record NEWEST FIRST, each with the
## decision made there. What does not fit the first page becomes the earlier road.
func _story_blocks() -> Array:
	var blocks: Array = []
	var top: Array = [_row(_t(String(_view.chapter_title_key)), STYLE_HEAD)]
	if _view.objective_key != &"":
		top.append(_row("%s %s" % [_t("UI_CHRONICLE_NOW"), _t(String(_view.objective_key))],
			STYLE_ACCENT))
	blocks.append(top)
	for i in range(_view.decisions.size() - 1, -1, -1):
		blocks.append([_row("◆ %s" % _t(String(_view.decisions[i])), STYLE_MUTED)])
	for i in range(_view.records.size() - 1, -1, -1):
		blocks.append([_row(_t(String(_view.records[i])), STYLE_LINE)])
	return blocks


## Who you are: the name you go by, the Origin you chose, what you came for, and what only
## someone who was that person has noticed.
func _self_blocks() -> Array:
	var blocks: Array = []
	var who: Array = []
	if _name_key != &"":
		who.append(_row(_t(String(_name_key)), STYLE_HEAD))
	who.append(_row(_t(String(_view.origin_name_key)), STYLE_HEAD))
	who.append(_row(_t(String(_view.origin_problem_key)), STYLE_LINE))
	blocks.append(who)
	var aims: Array = [_row("%s %s" % [_t("UI_CHRONICLE_GOAL"), _t(String(_view.origin_goal_key))],
		STYLE_ACCENT)]
	if _view.origin_why_here_key != &"":
		aims.append(_row("%s %s" % [_t("UI_CHRONICLE_WHY_HERE"),
			_t(String(_view.origin_why_here_key))], STYLE_LINE))
	if _view.personal_objective_key != &"":
		aims.append(_row("%s %s" % [_t("UI_CHRONICLE_LEAD"),
			_t(String(_view.personal_objective_key))], STYLE_ACCENT))
	blocks.append(aims)
	blocks.append([_row(_t(String(_view.origin_edge_key)), STYLE_MUTED),
		_row(_t(String(_view.origin_cost_key)), STYLE_MUTED)])
	if not _view.noticed.is_empty():
		var seen: Array = [_row(_t("UI_CHRONICLE_NOTICED"), STYLE_HEAD)]
		for key in _view.noticed:
			seen.append(_row("◆ %s" % _t(String(key)), STYLE_LINE))
		blocks.append(seen)
	return blocks


## Body and path: every line is a number its owner holds, said with its name.
func _body_blocks() -> Array:
	var blocks: Array = []
	var vital: Array = []
	if _health_max > 0:
		vital.append(_row(_t_args("UI_CHRONICLE_HEALTH",
			{"current": maxi(0, _health), "max": _health_max}), STYLE_LINE))
	if _progression != null and _progression.available:
		vital.append(_row(_t_args("UI_CHRONICLE_LEVEL_MAX" if _progression.at_ceiling
			else "UI_CHRONICLE_LEVEL", {"level": _progression.level,
			"into": _progression.xp_into_level, "cost": _progression.xp_for_next}), STYLE_LINE))
	if _cultivation != null and _cultivation.available:
		vital.append(_row(_t_args("UI_CHRONICLE_REALM", {
			"realm": _t(String(_cultivation.realm_name_key)), "layer": _cultivation.layer,
			"progress": _cultivation.progress, "cost": _cultivation.step_cost}), STYLE_LINE))
	# The figure and its numbers lead the page: the same card the satchel shows. Its line
	# keeps the sentence (for whoever reads the page as text) and is DRAWN as the card.
	if _view.stats_available:
		var figure := _row(_t_args("UI_CHRONICLE_STATS", {"attack": _view.attack,
			"defense": _view.defense, "speed": _view.move_speed}), STYLE_ACCENT)
		figure[CARD] = true
		blocks.append([figure])
	if not vital.is_empty():
		blocks.append(vital)
	var worn: Array = [_row(_t("UI_CHRONICLE_WORN"), STYLE_HEAD)]
	if _inventory != null:
		for row in _inventory.rows:
			if bool(row.get("equipped", false)):
				worn.append(_row(_t(String(row["name_key"])), STYLE_LINE))
				worn.append(_row(_t(String(row["desc_key"])), STYLE_MUTED))
	if worn.size() == 1:
		worn.append(_row(_t("UI_CHRONICLE_WORN_NONE"), STYLE_MUTED))
	blocks.append(worn)
	var arts: Array = [_row(_t("UI_CHRONICLE_TECHNIQUES"), STYLE_HEAD)]
	if _skills != null:
		for slot in _skills.slots:
			arts.append(_row(_t_args("UI_CHRONICLE_TECHNIQUE", {
				"name": _t(String(slot["name_key"])), "qi": int(slot["qi_cost"]),
				"key": _key_label(StringName(SKILL_ACTION_FORMAT % int(slot["slot"])))}),
				STYLE_LINE))
	if arts.size() == 1:
		arts.append(_row(_t("UI_CHRONICLE_TECHNIQUES_NONE"), STYLE_MUTED))
	blocks.append(arts)
	var rest: Array = []
	if _pet != null and _pet.available:
		rest.append(_row(_t_args("UI_CHRONICLE_COMPANION", {
			"name": _t(String(_pet.name_key)), "level": _pet.level,
			"state": _t("UI_CHRONICLE_COMPANION_RESTING" if _pet.recovering
				else ("UI_CHRONICLE_COMPANION_OUT" if _pet.out
				else "UI_CHRONICLE_COMPANION_AWAY"))}), STYLE_LINE))
	else:
		rest.append(_row(_t("UI_CHRONICLE_COMPANION_NONE"), STYLE_MUTED))
	if _place_key != &"":
		rest.append(_row(_t_args("UI_CHRONICLE_PLACE", {"place": _t(String(_place_key))}),
			STYLE_MUTED))
	blocks.append(rest)
	return blocks


## What you know: each thing's name, and what it says in the body colour — the page a player
## opens this tab to read, so nothing on it is muted.
func _knowledge_blocks() -> Array:
	var blocks: Array = []
	for entry in _view.knowledge:
		blocks.append([_row(_t(String(entry["name_key"])), STYLE_HEAD),
			_row(_t(String(entry["desc_key"])), STYLE_LINE)])
	if blocks.is_empty():
		blocks.append([_row(_t("UI_CHRONICLE_NO_KNOWLEDGE"), STYLE_MUTED)])
	return blocks


## Whom you have met: each dimension of their regard by NAME, with a word for where it stands
## and its number — never summed — and under it the decisions on record that moved it.
func _people_blocks() -> Array:
	var blocks: Array = []
	for entry in _view.people:
		var person: Array = [_row("%s — %s" % [_t(String(entry["name_key"])),
			_t(String(entry["title_key"]))], STYLE_HEAD)]
		for regard: Dictionary in entry.get("regard", []):
			var dimension: StringName = regard["dimension"]
			var value := int(regard["value"])
			person.append(_row(_t_args("UI_CHRONICLE_REGARD_LINE", {
				"dimension": _capitalised(_t(RegardBands.name_key(dimension))),
				"band": _t(RegardBands.key(dimension, value, int(regard["minimum"]),
					int(regard["maximum"]))),
				"value": ("+%d" % value) if value > 0 else str(value)}), STYLE_LINE))
		for key: StringName in entry.get("notes", []):
			person.append(_row("◆ %s" % _t(String(key)), STYLE_MUTED))
		blocks.append(person)
	if blocks.is_empty():
		blocks.append([_row(_t("UI_CHRONICLE_NO_PEOPLE"), STYLE_MUTED)])
	return blocks


# --- Drawing -----------------------------------------------------------------------

## The character as a figure, fed from the views this book already holds.
func _character_card(line: String) -> CharacterCard:
	var card := CharacterCard.new()
	card.name = "CharacterCard"
	card.set_meta(&"line", line)
	card.custom_minimum_size.y = CARD_HEIGHT
	card.set_body(_inventory.body_profile if _inventory != null else null)
	card.set_worn(_inventory.rows if _inventory != null else ([] as Array[Dictionary]))
	card.set_stats(_view.stats_available, _view.attack, _view.defense, _view.move_speed)
	return card


func _row(text: String, style: StringName) -> Dictionary:
	return {"text": text, "style": style}


## The book reads at arm's length (`UI_UX_BIBLE.md` §8d): a heading at the book's row size,
## every other line at the body size at least.
func _font_size(style: StringName) -> int:
	return UIPalette.BOOK_ROW_FONT_SIZE if style == STYLE_HEAD else UIPalette.FONT_SIZE_BODY


func _styled(style: StringName) -> Label:
	var color := UIPalette.COLOR_TEXT
	match style:
		STYLE_HEAD:
			color = UIPalette.COLOR_TITLE
		STYLE_ACCENT:
			color = UIPalette.COLOR_ACCENT
		STYLE_MUTED:
			color = UIPalette.COLOR_TEXT_MUTED
	var label := _label(_font_size(style), color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _capitalised(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text

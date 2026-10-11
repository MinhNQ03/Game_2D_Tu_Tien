extends PanelContainer
class_name ChroniclePanel
## ChroniclePanel — Aetheria presentation (the Chronicle, Phase 20, D-072 §8; D-073 §4).
##
## THE ONE BOOK for everything the player may read about their own run that has no other
## home: the road so far, who they are, their body and path, what they know, whom they have
## met — and, as the story grows, the earlier road. A READING panel in the shared side-panel
## frame, like the quest journal: not modal, takes no input context, closes with every reading
## surface on Esc and when something hostile turns on the player. Its key opens it, turns the
## page, and closes it after the last page.
##
## PURE PRESENTATION, AND AN OVERVIEW — NOT AN OWNER. It renders a `ChronicleView` (story,
## Origin, knowledge, people, combat stats) and the views the HUD is already handed by their
## owners (health, level, realm, bag, techniques, companion, place). It writes nothing, offers
## no action on anything it shows, and is not a second journal, bag or technique dock: to
## change what it lists the player uses the surface that owns it.
##
## PAGES ARE PACKED, NOT TRUNCATED. Each section's lines are grouped into blocks that stay
## together (a person with their regard, a record) and the blocks are packed into as many
## pages as the panel's height needs, measured with the font the labels are drawn in. Nothing
## is dropped to fit: the newest records fill the first page and the older ones follow at the
## END of the book ("earlier on the road"), so the pages a player wants most come first.

const PAGE_STORY := &"story"
const PAGE_SELF := &"self"
const PAGE_BODY := &"body"
const PAGE_KNOWLEDGE := &"knowledge"
const PAGE_PEOPLE := &"people"
## Records that did not fit the first page: the earlier road, after everything else.
const PAGE_HISTORY := &"history"
## The sections in reading order. `PAGE_HISTORY` is filled from the story's overflow.
const SECTIONS: Array[StringName] = [PAGE_STORY, PAGE_SELF, PAGE_BODY, PAGE_KNOWLEDGE,
	PAGE_PEOPLE, PAGE_HISTORY]
const CHRONICLE_ACTION := &"chronicle"
## The action a technique in dock slot N is cast with (the dock's own actions).
const SKILL_ACTION_FORMAT := "skill_%d"

const STYLE_HEAD := &"head"
const STYLE_LINE := &"line"
const STYLE_ACCENT := &"accent"
const STYLE_MUTED := &"muted"
## The gap between the lines of ONE block (a person and their regard, a thing known and what
## it says) and between two blocks: lines that belong together sit together, and the eye finds
## where one thing ends. (At one uniform gap a person took a page to themselves.)
const LINE_GAP := 2
const BLOCK_GAP := UIPalette.SPACE_MD
## Rounding room per label: a Label's minimum height is a whole number of pixels.
const LABEL_SLACK := 1.0
## The least room a page is ever packed for, whatever the window (a guard, not a target).
const MIN_BODY_HEIGHT := 120.0

var _loc: Node = null
var _input: Node = null
var _title: Label
var _list: VBoxContainer
var _body: Control
var _keys: Label
var _view: ChronicleView = null
var _page: int = 0
## Every page of the book right now: `{ section: StringName, blocks: Array }`, a block being
## an Array of `{ text: String, style: StringName }`.
var _pages: Array[Dictionary] = []
var _dirty: bool = true
## The body's height as the engine laid it out (0 until it has: a closed panel has no size).
var _laid_out_height: float = 0.0
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
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title == null:
		_build()
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	add_child(column)
	# ONE line, always (clipped, never wrapped): a title that wrapped on some pages changed
	# the body's height from page to page, which re-packed the book while it was being read.
	_title = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	column.add_child(UITheme.ornament_divider())
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	_body = body
	_list = UITheme.scroll_body(body)
	_list.name = "Lines"
	_list.add_theme_constant_override("separation", BLOCK_GAP)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	_keys.name = "Keys"
	column.add_child(_keys)
	_body.resized.connect(_on_body_resized)


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
	if _title != null and visible:
		_refresh()


func _on_visibility_changed() -> void:
	if not visible or _title == null:
		return
	_take_laid_out_size()
	_refresh()
	# A panel shown for the first time is laid out on the NEXT frame: measure again then.
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


## Adopt the body's size if the engine has given it one. True when the room changed.
func _take_laid_out_size() -> bool:
	if _body == null or _body.size.y < MIN_BODY_HEIGHT \
			or absf(_body.size.y - _laid_out_height) < 0.5:
		return false
	_laid_out_height = _body.size.y
	return true


## The engine laid the body out: from now on that is the room, not the estimate.
func _on_body_resized() -> void:
	if visible:
		_queue_remeasure()


# --- Pages -------------------------------------------------------------------------

func reset_page() -> void:
	_page = 0
	_dirty = true
	if _title != null:
		_refresh()


## Turn to the next page. False when there is none: the caller closes the book.
func advance_page() -> bool:
	_repack_if_needed()
	if _page >= _pages.size() - 1:
		return false
	_page += 1
	_render()
	return true


## The section the current page belongs to (`PAGE_*`).
func page_id() -> StringName:
	_repack_if_needed()
	return _pages[_page]["section"] if _page < _pages.size() else PAGE_STORY


func page_count() -> int:
	_repack_if_needed()
	return _pages.size()


func page_index() -> int:
	return _page


## Every line the page shows, in order — for tests and captures.
func page_lines() -> Array[String]:
	var out: Array[String] = []
	if _list != null:
		for block in _list.get_children():
			if block.is_queued_for_deletion():
				continue
			for child in block.get_children():
				if child is Label:
					out.append((child as Label).text)
	return out


## Every line of EVERY page, in reading order — for tests ("nothing was dropped to fit").
func all_lines() -> Array[String]:
	_repack_if_needed()
	var out: Array[String] = []
	for page in _pages:
		for block: Array in page["blocks"]:
			for line: Dictionary in block:
				out.append(String(line["text"]))
	return out


## The tallest page's content against the room it has, in pixels — for layout tests.
func tallest_page_height() -> float:
	_repack_if_needed()
	var tallest := 0.0
	for page in _pages:
		tallest = maxf(tallest, _blocks_height(page["blocks"]))
	return tallest


## The room one page has, in pixels: what the engine laid out, or — before it has — what the
## side-panel frame will give this panel in the current window, less its own title, divider,
## footer and padding. The same arithmetic `GameplayHUD._bound_side_panel` anchors it by.
func body_height() -> float:
	if _laid_out_height > 0.0:
		return _laid_out_height
	var window := get_viewport_rect().size.y if is_inside_tree() \
		else float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	var frame := window - 2.0 * float(UIPalette.HUD_MARGIN) \
		- float(UIPalette.TOP_PLAQUE_RESERVE + UIPalette.PROMPT_STRIP_RESERVE)
	# Title (one line; a wrapped title is the engine's to measure, not this estimate's — an
	# autowrap label with no width yet reports a column one letter wide), divider, footer.
	var font := get_theme_default_font()
	var chrome := UITheme.panel_stylebox().get_minimum_size().y \
		+ 3.0 * float(UIPalette.SPACE_SM) \
		+ font.get_height(UIPalette.FONT_SIZE_SUBTITLE) \
		+ font.get_height(UIPalette.FONT_SIZE_HINT) \
		+ float(UIPalette.SPACE_MD)
	return maxf(MIN_BODY_HEIGHT, frame - chrome)


func refresh_language() -> void:
	_dirty = true
	_refresh()


func _refresh() -> void:
	if _title == null:
		return
	_repack_if_needed()
	_render()


func _repack_if_needed() -> void:
	if not _dirty and not _pages.is_empty():
		return
	_dirty = false
	_pages.clear()
	if _view == null or not _view.available:
		_pages.append({"section": PAGE_STORY,
			"blocks": [[_row(_t("UI_CHRONICLE_EMPTY"), STYLE_MUTED)]]})
		_page = 0
		return
	var room := body_height()
	var story := _pack(_story_blocks(), room)
	_pages.append({"section": PAGE_STORY, "blocks": story[0] if not story.is_empty() else []})
	for section: StringName in [PAGE_SELF, PAGE_BODY, PAGE_KNOWLEDGE, PAGE_PEOPLE]:
		for blocks: Array in _pack(_section_blocks(section), room):
			_pages.append({"section": section, "blocks": blocks})
	for i in range(1, story.size()):
		_pages.append({"section": PAGE_HISTORY, "blocks": story[i]})
	_page = clampi(_page, 0, _pages.size() - 1)


func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _pages.is_empty():
		return
	var page: Dictionary = _pages[_page]
	_title.text = "%s — %s" % [_t("UI_CHRONICLE_TITLE"),
		_t("UI_CHRONICLE_PAGE_%s" % String(page["section"]).to_upper())]
	# On the last page the key closes the book, and the footer says so.
	_keys.text = _t_args("UI_CHRONICLE_KEYS" if _page < _pages.size() - 1
		else "UI_CHRONICLE_KEYS_LAST", {"key": _key_label(CHRONICLE_ACTION),
		"page": _page + 1, "pages": _pages.size()})
	for block: Array in page["blocks"]:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", LINE_GAP)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for line: Dictionary in block:
			var label := _styled(line["style"])
			label.text = String(line["text"])
			group.add_child(label)
		_list.add_child(group)


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
			var font_px := _font_size(line["style"])
			var wrapped := font.get_multiline_string_size(String(line["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, width, font_px).y
			var rows := maxi(1, int(round(wrapped / font.get_height(font_px))))
			total += wrapped + float(rows - 1) * spacing + LABEL_SLACK
		total += float(maxi(0, block.size() - 1) * LINE_GAP)
	return total + float(maxi(0, blocks.size() - 1) * BLOCK_GAP)


## The height the CURRENT page really takes, as the engine laid its labels out — what a
## layout test must compare with the room (the packing estimate cannot check itself).
func rendered_height() -> float:
	return _list.get_combined_minimum_size().y if _list != null else 0.0


## The width a line wraps at: the list's own once the engine has laid it out (a list that has
## not been laid out reports a few pixels, which would wrap every word onto its own line).
func _list_width() -> float:
	if _laid_out_height > 0.0 and _list != null and _list.size.x > 40.0:
		return _list.size.x
	return float(UIPalette.SIDE_PANEL_WIDTH - UIPalette.SCROLLBAR_GUTTER) \
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
	blocks.append([_row("%s %s" % [_t("UI_CHRONICLE_GOAL"), _t(String(_view.origin_goal_key))],
		STYLE_ACCENT)])
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
	if _view.stats_available:
		vital.append(_row(_t_args("UI_CHRONICLE_STATS", {"attack": _view.attack,
			"defense": _view.defense, "speed": _view.move_speed}), STYLE_ACCENT))
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


func _knowledge_blocks() -> Array:
	var blocks: Array = []
	for entry in _view.knowledge:
		blocks.append([_row(_t(String(entry["name_key"])), STYLE_HEAD),
			_row(_t(String(entry["desc_key"])), STYLE_MUTED)])
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

func _row(text: String, style: StringName) -> Dictionary:
	return {"text": text, "style": style}


func _font_size(style: StringName) -> int:
	return UIPalette.FONT_SIZE_BODY if style == STYLE_HEAD or style == STYLE_ACCENT \
		else UIPalette.FONT_SIZE_HINT


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


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _capitalised(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text


func _key_label(action: StringName) -> String:
	if _input != null and _input.has_method("get_action_display_label"):
		return String(_input.call("get_action_display_label", action))
	return String(action)


func _t(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))


func _t_args(key: String, args: Dictionary) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t_args", key, args))

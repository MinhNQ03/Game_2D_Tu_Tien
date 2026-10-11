extends PanelContainer
class_name ChroniclePanel
## ChroniclePanel — Aetheria presentation (the Chronicle, Phase 20, D-072 §8).
##
## THE ONE BOOK for everything the player may read about their own run that has no other
## home: the story so far, who they are, what they know, whom they have met. A READING panel
## in the shared side-panel frame, like the quest journal: not modal, takes no input context,
## closes with every reading surface on Esc and when something hostile turns on the player.
## Its key opens it, turns the page, and closes it after the last page.
##
## PURE PRESENTATION: it renders a `ChronicleView` and resolves keys. It is not a second
## journal (quests stay in theirs) and not a second bag.

const PAGE_STORY := &"story"
const PAGE_SELF := &"self"
const PAGE_KNOWLEDGE := &"knowledge"
const PAGE_PEOPLE := &"people"
const PAGES: Array[StringName] = [PAGE_STORY, PAGE_SELF, PAGE_KNOWLEDGE, PAGE_PEOPLE]
const CHRONICLE_ACTION := &"chronicle"
## How many past records the story page shows (the newest; the page is bounded by the screen).
const MAX_RECORDS := 6

var _loc: Node = null
var _input: Node = null
var _title: Label
var _list: VBoxContainer
var _keys: Label
var _view: ChronicleView = null
var _page: int = 0


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title == null:
		_build()
	_refresh()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	add_child(column)
	_title = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	column.add_child(_title)
	column.add_child(UITheme.ornament_divider())
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	_list = UITheme.scroll_body(body)
	_list.name = "Lines"
	_list.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	_keys.name = "Keys"
	column.add_child(_keys)


## Push a fresh view (event-driven from the owners; never polled).
func set_view(view: ChronicleView) -> void:
	_view = view
	if _title != null:
		_refresh()


func reset_page() -> void:
	_page = 0
	if _title != null:
		_refresh()


## Turn to the next page. False when there is none: the caller closes the book.
func advance_page() -> bool:
	if _page >= PAGES.size() - 1:
		return false
	_page += 1
	_refresh()
	return true


func page_id() -> StringName:
	return PAGES[_page]


## Every line the page shows, in order — for tests and captures.
func page_lines() -> Array[String]:
	var out: Array[String] = []
	if _list != null:
		for child in _list.get_children():
			if child is Label and not child.is_queued_for_deletion():
				out.append((child as Label).text)
	return out


func refresh_language() -> void:
	_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_title.text = "%s — %s" % [_t("UI_CHRONICLE_TITLE"),
		_t("UI_CHRONICLE_PAGE_%s" % String(PAGES[_page]).to_upper())]
	# On the last page the key closes the book, and the footer says so.
	_keys.text = _t_args("UI_CHRONICLE_KEYS" if _page < PAGES.size() - 1
		else "UI_CHRONICLE_KEYS_LAST", {"key": _key_label(CHRONICLE_ACTION),
		"page": _page + 1, "pages": PAGES.size()})
	if _view == null or not _view.available:
		_muted("UI_CHRONICLE_EMPTY")
		return
	match PAGES[_page]:
		PAGE_STORY:
			_story_page()
		PAGE_SELF:
			_self_page()
		PAGE_KNOWLEDGE:
			_knowledge_page()
		PAGE_PEOPLE:
			_people_page()


func _story_page() -> void:
	_head(String(_view.chapter_title_key))
	if _view.objective_key != &"":
		_accent("%s %s" % [_t("UI_CHRONICLE_NOW"), _t(String(_view.objective_key))])
	var from := maxi(0, _view.records.size() - MAX_RECORDS)
	for i in range(_view.records.size() - 1, from - 1, -1):
		_line(_t(String(_view.records[i])))
	for key in _view.decisions:
		_muted_text("◆ %s" % _t(String(key)))


func _self_page() -> void:
	_head(String(_view.origin_name_key))
	_line(_t(String(_view.origin_problem_key)))
	_accent("%s %s" % [_t("UI_CHRONICLE_GOAL"), _t(String(_view.origin_goal_key))])
	_muted_text(_t(String(_view.origin_edge_key)))
	_muted_text(_t(String(_view.origin_cost_key)))


func _knowledge_page() -> void:
	if _view.knowledge.is_empty():
		_muted("UI_CHRONICLE_NO_KNOWLEDGE")
	for entry in _view.knowledge:
		_head(String(entry["name_key"]))
		_muted_text(_t(String(entry["desc_key"])))


func _people_page() -> void:
	if _view.people.is_empty():
		_muted("UI_CHRONICLE_NO_PEOPLE")
	for entry in _view.people:
		_line("%s — %s" % [_t(String(entry["name_key"])), _t(String(entry["title_key"]))])
		_muted_text(_t_args("UI_CHRONICLE_REGARD", {"affinity": int(entry["affinity"]),
			"trust": int(entry["trust"]), "respect": int(entry["respect"])}))


func _head(key: String) -> void:
	var label := _wrapped(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	label.text = _t(key)
	_list.add_child(label)


func _line(text: String) -> void:
	var label := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	label.text = text
	_list.add_child(label)


func _accent(text: String) -> void:
	var label := _wrapped(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_ACCENT)
	label.text = text
	_list.add_child(label)


func _muted(key: String) -> void:
	_muted_text(_t(key))


func _muted_text(text: String) -> void:
	var label := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	label.text = text
	_list.add_child(label)


func _wrapped(size: int, color: Color) -> Label:
	var label := _label(size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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

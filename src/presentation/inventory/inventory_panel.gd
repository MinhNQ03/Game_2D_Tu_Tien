extends PanelContainer
class_name InventoryPanel
## InventoryPanel — Aetheria presentation (the bag, opened with the `inventory` key, Phase 13).
##
## A bounded side panel like the sect panel (same frame, same scroll body, same hierarchy:
## title → rows → the selected item's description → the keys). KEYBOARD FIRST: the semantic
## move_up / move_down actions choose a row, `interact` uses it, `inventory` closes — read through
## `InputService.is_modal_action_just_pressed` while the HUD holds a UI_MODAL context, so the
## player does not walk while choosing a pill. It decides nothing: a use is REQUESTED
## (`use_requested`) and the `InventoryRuntime` decides; the outcome comes back as a new view and
## a HUD notice.

## `equipped`: the row was something worn (WorldRuntime takes it off instead of using it).
signal use_requested(item_id: StringName, equipped: bool)

const PANEL_MIN_WIDTH := 300

var _loc: Node = null
var _input: Node = null
var _title: Label
var _list: VBoxContainer
var _empty: Label
var _desc: Label
var _keys: Label
var _view: InventoryView = null
var _selected: int = 0


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UITheme.scroll_body(self)
	_title = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	box.add_child(_title)
	box.add_child(UITheme.ornament_divider())
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	box.add_child(_list)
	_empty = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_empty)
	box.add_child(UITheme.ornament_divider())
	_desc = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desc)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	box.add_child(_keys)
	set_process(false)
	refresh()


func set_view(view: InventoryView) -> void:
	_view = view
	refresh()


func selected_index() -> int:
	return _selected


## True when the selected row is something WORN (using it takes it off).
func selected_is_equipped() -> bool:
	if _view == null or _view.rows.is_empty():
		return false
	return bool(_view.rows[clampi(_selected, 0, _view.rows.size() - 1)].get("equipped", false))


func selected_item_id() -> StringName:
	if _view == null or _view.rows.is_empty():
		return &""
	return _view.rows[clampi(_selected, 0, _view.rows.size() - 1)]["item_id"]


func row_count() -> int:
	return _view.rows.size() if _view != null else 0


## Move the selection by `step` rows (wraps), as the move keys do.
func move_selection(step: int) -> void:
	var n := row_count()
	if n == 0:
		return
	_selected = posmod(_selected + step, n)
	refresh()


func request_use() -> void:
	var item_id := selected_item_id()
	if item_id != &"":
		use_requested.emit(item_id, selected_is_equipped())


## Read the modal keys while open (the HUD turns processing on and off with visibility).
func _process(_delta: float) -> void:
	if _input == null or not visible:
		return
	if _input.call("is_modal_action_just_pressed", &"move_up"):
		move_selection(-1)
	elif _input.call("is_modal_action_just_pressed", &"move_down"):
		move_selection(1)
	elif _input.call("is_modal_action_just_pressed", &"interact"):
		request_use()


func refresh() -> void:
	if _title == null:
		return
	_title.text = _t("UI_INVENTORY_TITLE")
	for child in _list.get_children():
		child.queue_free()
	var rows: Array[Dictionary] = _view.rows if _view != null else ([] as Array[Dictionary])
	_selected = clampi(_selected, 0, maxi(0, rows.size() - 1))
	_empty.visible = rows.is_empty()
	_empty.text = _t("UI_INVENTORY_EMPTY")
	for i in rows.size():
		_list.add_child(_row(rows[i], i == _selected))
	if rows.is_empty():
		_desc.text = ""
	else:
		_desc.text = _t(String(rows[_selected]["desc_key"]))
	var use_key: String = String(_input.call("get_action_display_label", &"interact")) \
		if _input != null else "E"
	var close_key: String = String(_input.call("get_action_display_label", &"inventory")) \
		if _input != null else "I"
	_keys.text = _t_args("UI_INVENTORY_KEYS", {"use": use_key, "close": close_key})


func _row(row: Dictionary, selected: bool) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIPalette.COLOR_ACCENT, 0.22) if selected else Color(0, 0, 0, 0)
	style.border_color = UIPalette.COLOR_ACCENT if selected else Color(0, 0, 0, 0)
	style.set_border_width_all(1 if selected else 0)
	style.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	frame.add_child(line)
	# The item in the kit's slot — the same family as the technique dock (D-062).
	line.add_child(UITheme.icon_slot(row["icon"]))
	var name_label := _label(UIPalette.FONT_SIZE_BODY,
		UIPalette.COLOR_TEXT if row["usable"] else UIPalette.COLOR_TEXT_MUTED)
	name_label.text = _t(String(row["name_key"]))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name_label)
	var count := _label(UIPalette.FONT_SIZE_BODY, UIPalette.GOLD_PRIMARY)
	count.text = _t("UI_INVENTORY_WORN") if bool(row.get("equipped", false)) \
		else "×%d" % int(row["count"])
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(count)
	return frame


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key


func _t_args(key: String, args: Dictionary) -> String:
	return String(_loc.call("t_args", key, args)) if _loc != null else key

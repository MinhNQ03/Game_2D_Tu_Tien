extends PanelContainer
class_name SessionPrompt
## SessionPrompt — Aetheria presentation (a question or a verdict about the SESSION itself).
##
## The one centred box the game uses when the session as a whole is at stake: leaving it
## (nothing is saved before Phase 23, so leaving asks first) and being defeated (the run is
## over and says so). It is the modal box of the kit: the lacquer frame, a title, one sentence,
## the keys. It reads no input and decides nothing — the HUD owns the keys while it is shown
## and reports what was asked for.

var _loc: Node = null
var _title: Label
var _body: Label
var _keys: Label
var _title_key: StringName = &""
var _body_key: StringName = &""
var _keys_key: StringName = &""
var _keys_args: Dictionary = {}


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UIPalette.SESSION_PROMPT_WIDTH, 0)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	column.add_child(UITheme.ornament_divider())
	_body = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	_body.name = "Body"
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_body)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	_keys.name = "Keys"
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_keys)
	refresh()


## What the box says. `keys_args` values are already-resolved key labels ("E", "Esc").
func set_prompt(title_key: StringName, body_key: StringName, keys_key: StringName,
		keys_args: Dictionary) -> void:
	_title_key = title_key
	_body_key = body_key
	_keys_key = keys_key
	_keys_args = keys_args
	refresh()


func title_text() -> String:
	return _title.text if _title != null else ""


func body_text() -> String:
	return _body.text if _body != null else ""


func keys_text() -> String:
	return _keys.text if _keys != null else ""


func refresh() -> void:
	if _title == null:
		return
	_title.text = _t(String(_title_key)) if _title_key != &"" else ""
	_body.text = _t(String(_body_key)) if _body_key != &"" else ""
	_keys.text = String(_loc.call("t_args", String(_keys_key), _keys_args)) \
		if _loc != null and _keys_key != &"" else ""


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key

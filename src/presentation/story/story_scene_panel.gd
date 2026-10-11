extends Control
class_name StoryScenePanel
## StoryScenePanel — Aetheria presentation (a story scene on screen, Phase 20, D-072 §6).
##
## One band in the same lacquer frame as the conversation box, showing ONE step of a scene at
## a time: where and when (a card), a line of narration (a caption), or something a named
## person says (a line).
##
## A scene that is HERE sits across the lower third over the live map, under a light veil. A
## scene that is SOMEWHERE ELSE (a memory, another place) is shown on the menu's own ink
## ground, fully opaque, with the band at the centre of the screen: the village must not be
## visible behind "forty days ago, in the record hall" — not even faintly. (The first build
## used a 90 % veil; in the real window the plaza and the HUD still showed through it.)
##
## It decides nothing and changes nothing: `interact` REQUESTS the next step, and the HUD
## turns Esc into a request to skip. What a scene is about was committed before it started.
##
## Keyboard through `InputService.is_modal_action_just_pressed` while the HUD holds a UI_MODAL
## context. Nothing here runs per frame while hidden.

signal advance_requested()

## How dark the veil is over the map while a scene is HERE.
const VEIL_HERE := 0.35
## Seconds a new step takes to settle.
const STEP_SECONDS := 0.16

var _loc: Node = null
var _input: Node = null
var _veil: ColorRect
## The opaque ink ground of a scene that is somewhere else (the menu's backdrop gradient).
var _ground: Control
var _box: PanelContainer
var _place: Label
var _time: Label
var _speaker: Label
var _text: Label
var _pips: Label
var _keys: Label
var _view: StorySceneView = null
var _tween: Tween = null


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)

	_ground = Control.new()
	_ground.name = "Ground"
	_ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.visible = false
	add_child(_ground)
	UITheme.build_backdrop(_ground)

	_box = PanelContainer.new()
	_box.name = "Box"
	_box.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.custom_minimum_size = Vector2(UIPalette.DIALOGUE_BOX_WIDTH, 0)
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_box)
	_place_box(false)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(column)

	_place = _label(UIPalette.FONT_SIZE_BUTTON, UIPalette.COLOR_TITLE)
	_place.name = "Place"
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_place)
	_time = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_time.name = "Time"
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_time)
	_speaker = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	_speaker.name = "Speaker"
	column.add_child(_speaker)
	_text = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	_text.name = "Text"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.custom_minimum_size = Vector2(UIPalette.DIALOGUE_BOX_WIDTH - 2 * UIPalette.SPACE_LG, 0)
	column.add_child(_text)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)
	_pips = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_pips.name = "Pips"
	footer.add_child(_pips)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_keys.name = "Keys"
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_keys)

	visible = false
	set_process(false)


## Show `view` (a step), or hide when null.
func set_view(view: StorySceneView) -> void:
	var was_scene := _view.scene_id if _view != null else &""
	var was_step := _view.step_index if _view != null else -1
	_view = view
	if view == null:
		return
	refresh()
	if view.scene_id != was_scene or view.step_index != was_step:
		_settle()


func place_text() -> String:
	return _place.text if _place != null and _place.visible else ""


func time_text() -> String:
	return _time.text if _time != null and _time.visible else ""


func body_text() -> String:
	return _text.text if _text != null and _text.visible else ""


func speaker_text() -> String:
	return _speaker.text if _speaker != null and _speaker.visible else ""


func keys_text() -> String:
	return _keys.text if _keys != null else ""


func pips_text() -> String:
	return _pips.text if _pips != null else ""


## The rectangle the box occupies, for layout tests.
func box_rect() -> Rect2:
	return _box.get_global_rect() if _box != null else Rect2()


func _process(_delta: float) -> void:
	if _view != null and _input != null \
			and _input.call("is_modal_action_just_pressed", &"interact"):
		advance_requested.emit()


func refresh() -> void:
	if _view == null or _text == null:
		return
	var is_card := _view.kind == StorySceneStepData.Kind.CARD
	var is_line := _view.kind == StorySceneStepData.Kind.LINE
	_place.visible = is_card
	_time.visible = is_card
	_speaker.visible = is_line and _view.speaker_name_key != &""
	_text.visible = not is_card
	_place.text = _t(String(_view.text_key)) if is_card else ""
	_time.text = _t(String(_view.sub_key)) if is_card else ""
	_speaker.text = _t(String(_view.speaker_name_key)) if _speaker.visible else ""
	_text.text = "" if is_card else _t(String(_view.text_key))
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if is_line \
		else HORIZONTAL_ALIGNMENT_CENTER
	_pips.text = "%d / %d" % [_view.step_index + 1, _view.step_count]
	_keys.text = _t_args("UI_STORY_SCENE_KEYS",
		{"next": _key(&"interact"), "skip": _key(&"open_menu")})
	_veil.color = Color(UIPalette.COLOR_BACKGROUND, VEIL_HERE)
	_veil.visible = not _view.elsewhere
	_ground.visible = _view.elsewhere
	_place_box(_view.elsewhere)


## Is the map behind the scene fully covered (a scene that is somewhere else)?
func covers_the_map() -> bool:
	return _ground != null and _ground.visible


## Where the band sits: across the lower third over the map, or at the centre of the ground.
func _place_box(centred: bool) -> void:
	var anchor := 0.5 if centred else 1.0
	_box.anchor_top = anchor
	_box.anchor_bottom = anchor
	_box.grow_vertical = Control.GROW_DIRECTION_BOTH if centred \
		else Control.GROW_DIRECTION_BEGIN
	_box.offset_top = 0.0
	_box.offset_bottom = 0.0 if centred else -float(UIPalette.HUD_MARGIN)


## A new step settles in (cosmetic; nothing reads it back).
func _settle() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_box.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_box, "modulate:a", 1.0, STEP_SECONDS)


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _key(action: StringName) -> String:
	return String(_input.call("get_action_display_label", action)) if _input != null else ""


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key


func _t_args(key: String, args: Dictionary) -> String:
	return String(_loc.call("t_args", key, args)) if _loc != null else key

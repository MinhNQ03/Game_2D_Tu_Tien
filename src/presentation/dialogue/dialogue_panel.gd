extends PanelContainer
class_name DialoguePanel
## DialoguePanel — Aetheria presentation (talking with someone, Phase 18).
##
## One bounded box at the bottom of the screen, in the same lacquer frame as every panel:
## the speaker's PORTRAIT (their own pipeline medallion) · who they are and HOW they say this
## line (the mood, in words and in the name plate's colour — never an icon that judges the
## player) · the line · the answers offered · the keys.
##
## KEYBOARD FIRST, through `InputService.is_modal_action_just_pressed` while the HUD holds a
## UI_MODAL context: move_up / move_down choose an answer, `interact` says it (or acknowledges
## a line that offers none). Leaving (Esc) is the HUD's.
##
## It decides nothing. The answers listed are the ones `DialogueService` offered into the
## `DialogueView`; a press REQUESTS one, naming the line it answers, and what happens comes
## back as a new view. REACTION and TRANSITION are cosmetic tweens started when the line
## changes — nothing reads them back, and nothing here runs per frame while closed.

signal choice_requested(node_id: StringName, choice_id: StringName)
signal advance_requested()

## Seconds the box takes to appear, and a new line to settle.
const OPEN_SECONDS := 0.14
const LINE_SECONDS := 0.12
## How far the portrait dips when the speaker gestures with a line, in pixels.
const NOD_PX := 3.0

var _loc: Node = null
var _input: Node = null
var _portrait: TextureRect
var _name: Label
var _title: Label
var _mood: Label
var _text: Label
var _keys: Label
var _choices_column: VBoxContainer
var _choices_rule: ColorRect
var _choice_list: VBoxContainer
var _view: DialogueView = null
var _selected: int = 0
## The process frame the current line appeared on. The press that brought it up — `interact`
## on the speaker, or the answer that led here — is still "just pressed" for the rest of that
## frame; reading it here too would answer the new line with the old press.
var _line_frame: int = -1
var _tween: Tween = null


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UIPalette.DIALOGUE_BOX_WIDTH, 0)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	# The speaker's medallion at 1x, NEAREST: it is pixel art (D-062). A plain Control well so
	# the reaction can move the portrait without a container snapping it back.
	var well := Control.new()
	well.name = "PortraitWell"
	well.custom_minimum_size = Vector2(UIPalette.MEDALLION_PX, UIPalette.MEDALLION_PX)
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(well)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.size = Vector2(UIPalette.MEDALLION_PX, UIPalette.MEDALLION_PX)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(_portrait)
	var speech := VBoxContainer.new()
	speech.name = "Speech"
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speech.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	row.add_child(speech)
	var who := HBoxContainer.new()
	who.name = "Who"
	who.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	speech.add_child(who)
	_name = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	_name.name = "SpeakerName"
	who.add_child(_name)
	_title = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_title.name = "SpeakerTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(_title)
	_mood = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_mood.name = "Mood"
	who.add_child(_mood)
	_text = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	_text.name = "Line"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, UIPalette.DIALOGUE_LINE_MIN_HEIGHT)
	speech.add_child(_text)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	_keys.name = "Keys"
	speech.add_child(_keys)
	# A hairline between what is SAID and what may be ANSWERED: without it the mood word at the
	# end of the name row read as a label on the first answer (seen in the first capture).
	_choices_rule = ColorRect.new()
	_choices_rule.name = "ChoicesRule"
	_choices_rule.color = Color(UIPalette.COLOR_TEXT_DISABLED, 0.6)
	_choices_rule.custom_minimum_size = Vector2(1, 0)
	_choices_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_choices_rule)
	_choices_column = VBoxContainer.new()
	_choices_column.name = "Choices"
	_choices_column.custom_minimum_size = Vector2(UIPalette.DIALOGUE_CHOICE_WIDTH, 0)
	_choices_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_choices_column)
	_choice_list = VBoxContainer.new()
	_choice_list.name = "ChoiceRows"
	_choice_list.add_theme_constant_override("separation", 0)
	_choices_column.add_child(_choice_list)
	set_process(false)
	refresh()


func set_view(view: DialogueView) -> void:
	var was_open := _view != null and _view.open
	var new_line := view != null and view.open \
		and (not was_open or _view.line_serial != view.line_serial)
	_view = view
	if new_line:
		_selected = 0
		_line_frame = Engine.get_process_frames()
	refresh()
	if new_line:
		_react(not was_open)


func choice_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if _view != null:
		for option in _view.choices:
			ids.append(option["id"])
	return ids


func selected_index() -> int:
	return _selected


func selected_choice_id() -> StringName:
	var ids := choice_ids()
	if ids.is_empty():
		return &""
	return ids[clampi(_selected, 0, ids.size() - 1)]


## What the panel shows, as shown (for tests and the E2E).
func line_text() -> String:
	return _text.text if _text != null else ""


func speaker_text() -> String:
	return _name.text if _name != null else ""


func mood_text() -> String:
	return _mood.text if _mood != null else ""


func keys_text() -> String:
	return _keys.text if _keys != null else ""


func choice_texts() -> Array[String]:
	var texts: Array[String] = []
	if _view != null:
		for option in _view.choices:
			texts.append(_t(String(option["text_key"])))
	return texts


func has_portrait() -> bool:
	return _portrait != null and _portrait.texture != null


## Move the selection by `step` answers (wraps), as the move keys do.
func move_selection(step: int) -> void:
	var n := choice_ids().size()
	if n == 0:
		return
	_selected = posmod(_selected + step, n)
	refresh()


## Say the selected answer — or, on a line that offers none, acknowledge it.
func confirm() -> void:
	if _view == null or not _view.open:
		return
	var choice_id := selected_choice_id()
	if choice_id == &"":
		advance_requested.emit()
	else:
		choice_requested.emit(_view.node_id, choice_id)


## Read the modal keys while open (the HUD turns processing on and off with visibility).
func _process(_delta: float) -> void:
	if _input == null or not visible or Engine.get_process_frames() <= _line_frame:
		return
	if _input.call("is_modal_action_just_pressed", &"move_up"):
		move_selection(-1)
	elif _input.call("is_modal_action_just_pressed", &"move_down"):
		move_selection(1)
	elif _input.call("is_modal_action_just_pressed", &"interact"):
		confirm()


func refresh() -> void:
	if _text == null:
		return
	for child in _choice_list.get_children():
		child.queue_free()
	if _view == null or not _view.open:
		_text.text = ""
		return
	_name.text = _t(String(_view.speaker_name_key))
	_title.text = _t(String(_view.speaker_title_key)) if _view.speaker_title_key != &"" else ""
	var mood_name: String = DialogueNodeData.Mood.keys()[clampi(_view.mood, 0,
		DialogueNodeData.Mood.size() - 1)]
	_mood.text = _t("UI_DIALOGUE_MOOD_%s" % mood_name)
	var mood_colour := UITheme.dialogue_mood_color(_view.mood)
	_mood.add_theme_color_override("font_color", mood_colour)
	_name.add_theme_color_override("font_color", mood_colour)
	_portrait.texture = load(_view.portrait_path) as Texture2D \
		if _view.portrait_path != "" and ResourceLoader.exists(_view.portrait_path) else null
	_portrait.get_parent().visible = _portrait.texture != null
	_text.text = _t(String(_view.text_key))
	_selected = clampi(_selected, 0, maxi(0, _view.choices.size() - 1))
	_choices_column.visible = not _view.choices.is_empty()
	_choices_rule.visible = _choices_column.visible
	for i in _view.choices.size():
		_choice_list.add_child(_row(_t(String(_view.choices[i]["text_key"])), i == _selected))
	var keys_key := "UI_DIALOGUE_KEYS_CHOOSE"
	if _view.choices.is_empty():
		keys_key = "UI_DIALOGUE_KEYS_CONTINUE" if _view.continues else "UI_DIALOGUE_KEYS_END"
	_keys.text = _t_args(keys_key, {"confirm": _key(&"interact"), "close": _key(&"open_menu")})


## The cosmetic answer to a new line: the box fades in when it opens, a new line settles in,
## and the portrait dips once when the speaker gestures. Never awaited, never read back.
func _react(opening: bool) -> void:
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_portrait.position = Vector2.ZERO
	_tween = create_tween().set_parallel(true)
	if opening:
		modulate.a = 0.0
		_tween.tween_property(self, "modulate:a", 1.0, OPEN_SECONDS)
	else:
		modulate.a = 1.0
		_text.modulate.a = 0.0
		_tween.tween_property(_text, "modulate:a", 1.0, LINE_SECONDS)
	if _view != null and _view.gestures:
		_tween.tween_property(_portrait, "position:y", NOD_PX, LINE_SECONDS)
		_tween.chain().tween_property(_portrait, "position:y", 0.0, LINE_SECONDS)


func _row(text: String, selected: bool) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIPalette.COLOR_ACCENT, 0.22) if selected else Color(0, 0, 0, 0)
	style.border_color = UIPalette.COLOR_ACCENT if selected else Color(0, 0, 0, 0)
	style.set_border_width_all(1 if selected else 0)
	# One pixel of air around the text: four answers must fit beside the 96 px medallion, or
	# the box grows and pushes the announcement band into the playfield's clear zone.
	style.set_content_margin_all(1)
	style.content_margin_left = UIPalette.SPACE_SM
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _label(UIPalette.FONT_SIZE_BODY,
		UIPalette.COLOR_TEXT if selected else UIPalette.COLOR_TEXT_MUTED)
	label.text = ("▸ %s" if selected else "  %s") % text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	frame.add_child(label)
	return frame


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _key(action: StringName) -> String:
	return String(_input.call("get_action_display_label", action)) if _input != null else "?"


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key


func _t_args(key: String, args: Dictionary) -> String:
	return String(_loc.call("t_args", key, args)) if _loc != null else key

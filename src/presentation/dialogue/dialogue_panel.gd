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
## NOTHING SAID IS CUT (UI-01): no label here clips or trims. The title and the answers wrap in
## their column; a line longer than `UIPalette.DIALOGUE_LINE_MAX_LINES` wrapped lines pages —
## the keys row opens with the more-cue, `interact` turns the page, and the answers appear on
## the last page (until then the move keys choose nothing and confirm answers nothing).
##
## THE BOX NEVER LEAVES ITS BAND. Both of its columns are held to the height the band below the
## playfield clear zone leaves (`max_height`, from the viewport at run time). The answers: a set
## that would not fit together is shown as a WINDOW of whole answers that follows the selection,
## a more-cue above or below saying answers are hidden that way. The speech: a name row that
## wraps (a long title) takes its height out of the line's page, which then shows fewer wrapped
## lines and pages sooner. No answer and no line is cut, and the keys behave exactly as before.
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
## The selection marker before an answer, and the air around an answer's text in its row.
const ANSWER_MARKER := "▸"
const ROW_AIR_PX := 1

var _loc: Node = null
var _input: Node = null
var _portrait: TextureRect
var _name: Label
var _title: Label
var _who: HBoxContainer
var _mood: Label
var _text: Label
var _keys: Label
var _choices_column: VBoxContainer
var _choices_rule: ColorRect
var _choice_list: VBoxContainer
## The rows of the current answers (old ones may still be children, queued for freeing), the
## more-cues at either end of a window of them, and the first answer the window shows.
var _rows: Array[Control] = []
var _choices_above: Label
var _choices_below: Label
var _choice_top: int = 0
var _windowed := false
var _view: DialogueView = null
var _selected: int = 0
## The page of the current line being shown, of `_pages` (a line that fits is one page).
var _page: int = 0
var _pages: int = 1
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
	_who = HBoxContainer.new()
	_who.name = "Who"
	_who.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	speech.add_child(_who)
	_name = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	_name.name = "SpeakerName"
	_who.add_child(_name)
	_title = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_title.name = "SpeakerTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A title that wraps to another row takes that row out of the line's page (`_repage`).
	_title.resized.connect(_repage, CONNECT_DEFERRED)
	_who.add_child(_title)
	_mood = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_mood.name = "Mood"
	_who.add_child(_mood)
	_text = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	_text.name = "Line"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, UIPalette.DIALOGUE_LINE_MIN_HEIGHT)
	_text.max_lines_visible = UIPalette.DIALOGUE_LINE_MAX_LINES
	# How many pages a line takes is only known at the width it is laid out at — counted once
	# the layout pass that gave it that width is over (deferred), not in the middle of it.
	_text.resized.connect(_repage, CONNECT_DEFERRED)
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
	_choices_column.add_theme_constant_override("separation", 0)
	row.add_child(_choices_column)
	_choices_above = _more_cue("ChoicesAbove")
	_choice_list = VBoxContainer.new()
	_choice_list.name = "ChoiceRows"
	_choice_list.add_theme_constant_override("separation", 0)
	_choices_column.add_child(_choice_list)
	_choices_below = _more_cue("ChoicesBelow")
	# The band is a share of the screen: a window resized mid-conversation re-fits the answers.
	get_viewport().size_changed.connect(refresh)
	set_process(false)
	refresh()


func set_view(view: DialogueView) -> void:
	var was_open := _view != null and _view.open
	var new_line := view != null and view.open \
		and (not was_open or _view.line_serial != view.line_serial)
	_view = view
	if new_line:
		_selected = 0
		_page = 0
		_choice_top = 0
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


## How many pages the current line takes, and which one is shown (0-based).
func page_count() -> int:
	return _pages


func page_index() -> int:
	return _page


## The tallest the box may be: the band the playfield clear zone leaves below it, less the
## margin the HUD holds the box above the screen's edge (UI_UX_BIBLE §3c). 162 px at 1280x720.
func max_height() -> float:
	var screen := get_viewport_rect().size.y if is_inside_tree() \
		else float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	return screen * (1.0 - UIPalette.PLAYFIELD_CLEAR_ZONE.end.y) - UIPalette.HUD_MARGIN


## The answers the box shows now, as indices into `choice_ids()`: all of them, unless the set
## is too tall for the band and is shown as a window that follows the selection.
func shown_choice_indices() -> Array[int]:
	var shown: Array[int] = []
	for i in _rows.size():
		if _rows[i].visible:
			shown.append(i)
	return shown


## Show the next page of a line that pages. False (and nothing changes) on its last page.
func next_page() -> bool:
	if _page >= _pages - 1:
		return false
	_page += 1
	_repage()
	_settle_line()
	return true


## Back to the line's first page (a new line always starts there).
func reset_page() -> void:
	_page = 0
	_repage()


## Move the selection by `step` answers (wraps), as the move keys do. Nothing is chosen while
## the line still has a page to read: its answers are not on screen yet.
func move_selection(step: int) -> void:
	var n := choice_ids().size()
	if n == 0 or _page < _pages - 1:
		return
	_selected = posmod(_selected + step, n)
	refresh()


## Say the selected answer — or, on a line that offers none, acknowledge it. On a page that is
## not the line's last, turn the page instead.
func confirm() -> void:
	if _view == null or not _view.open:
		return
	if next_page():
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
	_rows.clear()
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
		_rows.append(_row(_t(String(_view.choices[i]["text_key"])), i == _selected))
		_choice_list.add_child(_rows[i])
	_window_choices()
	_repage()


## Hold the answers' column inside the band: if the whole set is taller than the box may be,
## show the run of whole answers around the selection that fits, a more-cue at each end (lit
## only on the side that hides answers, so the box keeps its height as the selection moves).
## Measured from the text and the font, not read back from a layout pass: a wrapped label's
## height settles frames later, and the box must never be drawn too tall in between.
func _window_choices() -> void:
	var heights: Array[float] = []
	var total := 0.0
	for i in _rows.size():
		heights.append(_answer_height(_t(String(_view.choices[i]["text_key"]))))
		total += heights[i]
	var budget := max_height() - get_theme_stylebox("panel").get_minimum_size().y
	_windowed = total > budget
	if not _windowed:
		_choice_top = 0
		for row in _rows:
			row.visible = true
		return
	budget -= _choices_above.get_minimum_size().y + _choices_below.get_minimum_size().y
	var n := _rows.size()
	var top := mini(_choice_top, _selected)
	var end := _window_end(heights, top, budget)
	if _selected > end:
		# Moving down past the window: the selection becomes its last answer.
		top = _selected
		while top > 0 and _sum(heights, top - 1, _selected) <= budget:
			top -= 1
		end = _window_end(heights, top, budget)
	_choice_top = top
	for i in n:
		_rows[i].visible = i >= top and i <= end
	_choices_above.modulate.a = 1.0 if top > 0 else 0.0
	_choices_below.modulate.a = 1.0 if end < n - 1 else 0.0


## The last answer of a window that starts at `top` and fits in `budget` (at least `top`).
func _window_end(heights: Array[float], top: int, budget: float) -> int:
	var end := top
	while end + 1 < heights.size() and _sum(heights, top, end + 1) <= budget:
		end += 1
	return end


func _sum(heights: Array[float], first: int, last: int) -> float:
	var total := 0.0
	for i in range(first, last + 1):
		total += heights[i]
	return total


## How tall an answer's row lays out: its text wrapped at the answer label's width in the
## column the way the label wraps it (AUTOWRAP_WORD_SMART) and the marker beside it, plus the
## row's air above and below. Shaped, as the labels are, so a glyph from a fallback font counts.
func _answer_height(text: String) -> float:
	var font := _text.get_theme_font("font")
	var font_size := UIPalette.FONT_SIZE_BODY
	var marker := TextLine.new()
	marker.add_string(ANSWER_MARKER, font, font_size)
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND \
		| TextServer.BREAK_ADAPTIVE
	paragraph.width = UIPalette.DIALOGUE_CHOICE_WIDTH - UIPalette.SPACE_SM - ROW_AIR_PX \
		- UIPalette.ROW_GAP - marker.get_size().x
	paragraph.add_string(text, font, font_size)
	var answer := 0.0
	for i in paragraph.get_line_count():
		answer += paragraph.get_line_size(i).y
	answer += maxi(0, paragraph.get_line_count() - 1) * _text.get_theme_constant("line_spacing")
	return maxf(answer, marker.get_size().y) + 2 * ROW_AIR_PX


## Page the line at the width it was laid out at: show this page's wrapped lines, the answers
## only on the last page, and keys that say what confirm does here.
func _repage() -> void:
	if _view == null or not _view.open:
		return
	# The speech column is held to the band: what the name row and the keys row leave of it is
	# the line's page, at most `DIALOGUE_LINE_MAX_LINES` wrapped lines and never less than one.
	var line_px := _text.get_line_height() + _text.get_theme_constant("line_spacing")
	var room := max_height() - get_theme_stylebox("panel").get_minimum_size().y \
		- _who.get_combined_minimum_size().y - _keys.get_combined_minimum_size().y \
		- 2 * UIPalette.ROW_GAP
	var per_page := clampi(floori(room / line_px), 1, UIPalette.DIALOGUE_LINE_MAX_LINES)
	_text.max_lines_visible = per_page
	# Before its first layout a wrapping label is one pixel wide, and "every letter on its own
	# line" is not a page count: the line is one page until `resized` says otherwise.
	_pages = 1 if _text.size.x <= 1.0 \
		else maxi(1, ceili(float(_text.get_line_count()) / per_page))
	_page = clampi(_page, 0, _pages - 1)
	_text.lines_skipped = _page * per_page
	# A paged line keeps a full page's height on its shorter last page: the box must not jump.
	var least := minf(UIPalette.DIALOGUE_LINE_MIN_HEIGHT, maxf(room, line_px))
	_text.custom_minimum_size.y = least if _pages == 1 else maxf(least, line_px * per_page)
	var last := _page == _pages - 1
	_choice_list.visible = last
	_choices_above.visible = last and _windowed
	_choices_below.visible = last and _windowed
	var keys := {"confirm": _key(&"interact"), "close": _key(&"open_menu")}
	if not last:
		_keys.text = "%s %s" % [UIPalette.DIALOGUE_MORE_CUE,
			_t_args("UI_DIALOGUE_KEYS_CONTINUE", keys)]
		return
	var keys_key := "UI_DIALOGUE_KEYS_CHOOSE"
	if _view.choices.is_empty():
		keys_key = "UI_DIALOGUE_KEYS_CONTINUE" if _view.continues else "UI_DIALOGUE_KEYS_END"
	_keys.text = _t_args(keys_key, keys)


## A new page settles in the way a new line does. A page turn can land while the box is still
## fading open or the portrait is mid-nod (a doubled press), so restore what the killed tween
## was animating, as _react's non-opening branch does.
func _settle_line() -> void:
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	_portrait.position = Vector2.ZERO
	_tween = create_tween()
	_text.modulate.a = 0.0
	_tween.tween_property(_text, "modulate:a", 1.0, LINE_SECONDS)


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
	style.set_content_margin_all(ROW_AIR_PX)
	style.content_margin_left = UIPalette.SPACE_SM
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colour := UIPalette.COLOR_TEXT if selected else UIPalette.COLOR_TEXT_MUTED
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(line)
	# The marker is always laid out (hidden by alpha) so a wrapped answer hangs under its own
	# first word, and selecting one never moves the text.
	var marker := _label(UIPalette.FONT_SIZE_BODY, colour)
	marker.name = "Marker"
	marker.text = ANSWER_MARKER
	marker.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	marker.modulate.a = 1.0 if selected else 0.0
	line.add_child(marker)
	var label := _label(UIPalette.FONT_SIZE_BODY, colour)
	label.name = "Answer"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	return frame


## A more-cue at one end of the answers' column, shown only while the answers are windowed.
func _more_cue(cue_name: String) -> Label:
	var cue := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	cue.name = cue_name
	cue.text = UIPalette.DIALOGUE_MORE_CUE
	cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cue.visible = false
	_choices_column.add_child(cue)
	return cue


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

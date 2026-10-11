extends Control
class_name IdentityScreen
## IdentityScreen — Aetheria presentation (who the player is; Phase 20, D-072 §2).
##
## Beat 1 of the prologue (`NARRATIVE_MASTER_PLAN.md` §5): a look and an Origin, chosen before
## a run exists. Opened by New Game; it is MENU UI, exactly as settings is — nothing about a
## run is created until `confirmed` is emitted, so backing out has nothing to undo.
##
## IT OFFERS ONLY WHAT IS REAL. The looks are the catalog's (each one a body and a portrait the
## game can draw — shown here, moving, before the player commits); the Origins are the five of
## canon, with the short spoiler-safe lines their data carries: the problem, what it is good
## for, what it costs. Every Origin is open to every look.
##
## IT DECIDES NOTHING. It emits which look and which Origin; `Main` starts the run. All text is
## resolved from localization keys.
##
## KEYS. Arrows move a CURSOR; `ui_accept` on a look or an Origin CHOOSES it (marked ◆). The
## stage and the description follow the cursor while it is on an option — so everything can be
## looked at before anything is chosen — and return to what is chosen when the cursor leaves.
## One line above the buttons always states the current choice in words, which is what "Set
## out" will start. `ui_cancel` (Esc) goes back from anywhere. Confirming locks the screen, so
## a repeated key cannot start two runs.
##
## The first build chose by moving the cursor. Reaching "Set out" from the Origin column then
## meant walking down THROUGH the Origins below, silently changing the choice to the last one
## — found by the story E2E, whose second run started as the wrong person.

signal confirmed(appearance_id: StringName, origin_id: StringName)
signal cancelled()

const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

## The plaque is wide: two columns of choices beside a column of what the choice means.
const PLAQUE_WIDTH := 1080
const CHOICE_COLUMN_WIDTH := 300
const DETAIL_COLUMN_WIDTH := 380
## The chosen body, drawn at an integer scale (pixel art is never resampled).
const PREVIEW_SCALE := 3
const PREVIEW_WELL := Vector2(132, 168)
const CHOICE_BUTTON_HEIGHT := 40
## Drawn before the chosen look and the chosen Origin.
const CHOSEN_MARK := "◆"

var _appearances: PlayerAppearanceCatalogData = null
var _origins: OriginCatalogData = null
var _appearance_id: StringName = &""
var _origin_id: StringName = &""
## True once `confirmed` was emitted: every later key is ignored.
var _locked := false

var _title: Label
var _look_heading: Label
var _origin_heading: Label
var _look_buttons: Dictionary = {}    # appearance_id -> Button
var _origin_buttons: Dictionary = {}  # origin_id -> Button
var _preview: CharacterVisualComponent = null
var _portrait: TextureRect
var _detail_name: Label
var _detail_problem: Label
var _detail_edge_heading: Label
var _detail_edge: Label
var _detail_cost_heading: Label
var _detail_cost: Label
var _hint: Label
## "Chosen: <look> · <Origin>" — what Set out will start, in words.
var _summary: Label
## The option under the cursor (empty while the cursor is on the bottom row).
var _cursor_look: StringName = &""
var _cursor_origin: StringName = &""
var _begin_button: Button
var _back_button: Button
var _bus: Node = null


## Give the screen what it offers. Call BEFORE adding it to the tree.
func setup(appearances: PlayerAppearanceCatalogData, origins: OriginCatalogData) -> void:
	_appearances = appearances
	_origins = origins


func _ready() -> void:
	# See `MainMenu._ready` for why this is the offsets preset and not the anchors preset.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build()
	if _appearances == null or _origins == null or _appearances.entries.is_empty() \
			or _origins.entries.is_empty():
		push_error("[identity] nothing to choose from; the screen was opened without catalogs")
		return
	_appearance_id = _appearances.entries[0].id
	_origin_id = _origins.entries[0].id
	_build_ui()
	_refresh_text()
	_show_appearance()
	_show_origin()

	var input := get_node_or_null("/root/InputService")
	if input != null:
		input.call("set_menu_context")
	_bus = get_node_or_null("/root/EventBus")
	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)
	(_origin_buttons[_origin_id] as Button).grab_focus()


func _exit_tree() -> void:
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)


## Esc backs out from anywhere on the screen.
func _unhandled_input(event: InputEvent) -> void:
	if _locked or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back()


# --- What is chosen (for Main, tests and captures) ---------------------------

func selected_appearance_id() -> StringName:
	return _appearance_id


func selected_origin_id() -> StringName:
	return _origin_id


func is_locked() -> bool:
	return _locked


# --- Building ----------------------------------------------------------------

func _build_ui() -> void:
	UITheme.build_backdrop(self)

	var center := CenterContainer.new()
	center.name = "IdentityCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "IdentityPlaque"
	panel.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	panel.custom_minimum_size = Vector2(PLAQUE_WIDTH, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	panel.add_child(box)

	_title = _label(UIPalette.FONT_SIZE_BUTTON + UIPalette.SPACE_SM, UIPalette.COLOR_TITLE)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	box.add_child(UITheme.ornament_divider())

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	box.add_child(columns)
	columns.add_child(_build_look_column())
	columns.add_child(_build_origin_column())
	columns.add_child(_build_detail_column())

	_hint = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	_summary = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	_summary.name = "Summary"
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_summary)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	box.add_child(actions)
	_back_button = UITheme.menu_button(UITheme.ROLE_SECONDARY)
	_back_button.name = "Back"
	_back_button.pressed.connect(_on_back)
	_back_button.focus_entered.connect(_on_cursor_left_the_options)
	actions.add_child(_back_button)
	_begin_button = UITheme.menu_button(UITheme.ROLE_PRIMARY)
	_begin_button.name = "Begin"
	_begin_button.pressed.connect(_on_begin)
	_begin_button.focus_entered.connect(_on_cursor_left_the_options)
	actions.add_child(_begin_button)
	_wire_focus()


func _build_look_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "LookColumn"
	column.custom_minimum_size = Vector2(CHOICE_COLUMN_WIDTH, 0)
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_look_heading = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	column.add_child(_look_heading)

	var stage := HBoxContainer.new()
	stage.name = "Stage"
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	column.add_child(stage)

	# The body itself, standing: what the player will actually walk around as.
	var well := PanelContainer.new()
	well.name = "PreviewWell"
	well.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	well.custom_minimum_size = PREVIEW_WELL
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(well)
	var anchor := Control.new()
	anchor.name = "PreviewAnchor"
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(anchor)
	_preview = VisualComponentScript.new() as CharacterVisualComponent
	_preview.name = "Preview"
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	anchor.add_child(_preview)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_portrait.custom_minimum_size = Vector2(UIPalette.MEDALLION_PX, UIPalette.MEDALLION_PX)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_portrait)

	for look in _appearances.entries:
		var button := _choice_button()
		button.name = "Look_%s" % look.id
		button.focus_entered.connect(_on_look_focused.bind(look.id))
		button.pressed.connect(_on_look_chosen.bind(look.id))
		column.add_child(button)
		_look_buttons[look.id] = button
	return column


func _build_origin_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "OriginColumn"
	column.custom_minimum_size = Vector2(CHOICE_COLUMN_WIDTH, 0)
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_origin_heading = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	column.add_child(_origin_heading)
	for origin in _origins.entries:
		var button := _choice_button()
		button.name = "Origin_%s" % origin.id
		button.focus_entered.connect(_on_origin_focused.bind(origin.id))
		button.pressed.connect(_on_origin_chosen.bind(origin.id))
		column.add_child(button)
		_origin_buttons[origin.id] = button
	return column


func _build_detail_column() -> Control:
	var well := PanelContainer.new()
	well.name = "DetailWell"
	well.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	well.custom_minimum_size = Vector2(DETAIL_COLUMN_WIDTH, 0)
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.name = "Detail"
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	well.add_child(column)
	_detail_name = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	_detail_name.name = "OriginName"
	column.add_child(_detail_name)
	_detail_problem = _wrapped(UIPalette.COLOR_TEXT)
	_detail_problem.name = "OriginProblem"
	column.add_child(_detail_problem)
	column.add_child(UITheme.ornament_divider())
	_detail_edge_heading = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	column.add_child(_detail_edge_heading)
	_detail_edge = _wrapped(UIPalette.COLOR_TEXT)
	_detail_edge.name = "OriginEdge"
	column.add_child(_detail_edge)
	_detail_cost_heading = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	column.add_child(_detail_cost_heading)
	_detail_cost = _wrapped(UIPalette.COLOR_TEXT)
	_detail_cost.name = "OriginCost"
	column.add_child(_detail_cost)
	return well


## Up/down inside a column; left/right between columns lands on that column's CHOSEN option,
## so the cursor always arrives on something the player already knows.
func _wire_focus() -> void:
	var looks: Array = _look_buttons.values()
	var origins: Array = _origin_buttons.values()
	for i in looks.size():
		var button := looks[i] as Button
		button.focus_neighbor_top = button.get_path_to(looks[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(
			looks[i + 1] if i + 1 < looks.size() else _back_button)
		button.focus_neighbor_left = button.get_path()
	for i in origins.size():
		var button := origins[i] as Button
		button.focus_neighbor_top = button.get_path_to(origins[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(
			origins[i + 1] if i + 1 < origins.size() else _begin_button)
		button.focus_neighbor_right = button.get_path()
	_back_button.focus_neighbor_right = _back_button.get_path_to(_begin_button)
	_begin_button.focus_neighbor_left = _begin_button.get_path_to(_back_button)
	_back_button.focus_neighbor_bottom = _back_button.get_path()
	_begin_button.focus_neighbor_bottom = _begin_button.get_path()
	_refresh_cross_focus()


func _refresh_cross_focus() -> void:
	var look := _look_buttons[_appearance_id] as Button
	var origin := _origin_buttons[_origin_id] as Button
	for button: Button in _look_buttons.values():
		button.focus_neighbor_right = button.get_path_to(origin)
	for button: Button in _origin_buttons.values():
		button.focus_neighbor_left = button.get_path_to(look)
	_back_button.focus_neighbor_top = _back_button.get_path_to(look)
	_begin_button.focus_neighbor_top = _begin_button.get_path_to(origin)


func _choice_button() -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, CHOICE_BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_BODY)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _wrapped(color: Color) -> Label:
	var label := _label(UIPalette.FONT_SIZE_BODY, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(DETAIL_COLUMN_WIDTH - UIPalette.SPACE_LG, 0)
	return label


# --- Looking and choosing ----------------------------------------------------

## The cursor is on a look: put it on the stage. Nothing is chosen by looking.
func _on_look_focused(appearance_id: StringName) -> void:
	if _locked:
		return
	_cursor_look = appearance_id
	_cursor_origin = &""
	_show_stage()
	_refresh_detail()


func _on_origin_focused(origin_id: StringName) -> void:
	if _locked:
		return
	_cursor_origin = origin_id
	_cursor_look = &""
	_show_stage()
	_refresh_detail()


## The cursor went to the bottom row: the stage and the description show what is CHOSEN,
## which is what the button under the cursor will act on.
func _on_cursor_left_the_options() -> void:
	_cursor_look = &""
	_cursor_origin = &""
	_show_stage()
	_refresh_detail()


func _on_look_chosen(appearance_id: StringName) -> void:
	if _locked:
		return
	_appearance_id = appearance_id
	_show_appearance()


func _on_origin_chosen(origin_id: StringName) -> void:
	if _locked:
		return
	_origin_id = origin_id
	_show_origin()


## The look on the stage: the one under the cursor, else the chosen one.
func shown_appearance_id() -> StringName:
	return _cursor_look if _cursor_look != &"" else _appearance_id


## The Origin described: the one under the cursor, else the chosen one.
func shown_origin_id() -> StringName:
	return _cursor_origin if _cursor_origin != &"" else _origin_id


## Mark the chosen look and redraw the stage.
func _show_appearance() -> void:
	_mark_choices()
	_show_stage()
	_refresh_cross_focus()


func _show_origin() -> void:
	_mark_choices()
	_refresh_detail()
	_refresh_cross_focus()


## A chosen option is held down AND marked in words (`_refresh_choice_text`).
func _mark_choices() -> void:
	for id: StringName in _look_buttons:
		(_look_buttons[id] as Button).set_pressed_no_signal(id == _appearance_id)
	for id: StringName in _origin_buttons:
		(_origin_buttons[id] as Button).set_pressed_no_signal(id == _origin_id)
	if _title != null and _title.text != "":
		_refresh_choice_text()


## Put the shown look's real body and portrait on the stage.
func _show_stage() -> void:
	var look := _appearances.entry(shown_appearance_id())
	if look == null or look.template == null or _preview == null:
		return
	var profile := load(look.template.sprite_set_ref) as CharacterVisualProfileData
	if profile != null:
		_preview.setup(profile)
		# Feet on the well's floor, centred: the sprite's origin is its feet.
		_preview.position = Vector2(PREVIEW_WELL.x * 0.5, PREVIEW_WELL.y - UIPalette.SPACE_MD)
	_portrait.texture = load(look.template.portrait_ref) as Texture2D \
		if ResourceLoader.exists(look.template.portrait_ref) else null


func _on_begin() -> void:
	if _locked:
		return
	_locked = true
	_begin_button.disabled = true
	_back_button.disabled = true
	confirmed.emit(_appearance_id, _origin_id)


func _on_back() -> void:
	if _locked:
		return
	_locked = true
	cancelled.emit()


# --- Text --------------------------------------------------------------------

func _refresh_text() -> void:
	_title.text = _t("UI_IDENTITY_TITLE")
	_look_heading.text = _t("UI_IDENTITY_LOOK")
	_origin_heading.text = _t("UI_IDENTITY_ORIGIN")
	_detail_edge_heading.text = _t("UI_IDENTITY_EDGE")
	_detail_cost_heading.text = _t("UI_IDENTITY_COST")
	_hint.text = _t("UI_IDENTITY_HINT")
	_begin_button.text = _t("UI_IDENTITY_BEGIN")
	_back_button.text = _t("UI_IDENTITY_BACK")
	_refresh_choice_text()
	_refresh_detail()


## A chosen look or Origin is MARKED, not only coloured: state is never carried by colour
## alone (`UI_UX_BIBLE.md`), and the focus frame moves away from a choice the moment the
## player crosses to the other column.
func _refresh_choice_text() -> void:
	for look in _appearances.entries:
		(_look_buttons[look.id] as Button).text = _marked(look.id == _appearance_id,
			_t(String(look.name_key)))
	for origin in _origins.entries:
		(_origin_buttons[origin.id] as Button).text = _marked(origin.id == _origin_id,
			_t(String(origin.name_key)))
	var chosen_look := _appearances.entry(_appearance_id)
	var chosen_origin := _origins.entry(_origin_id)
	if _summary != null and chosen_look != null and chosen_origin != null:
		_summary.text = _t_args("UI_IDENTITY_SUMMARY", {
			"look": _t(String(chosen_look.name_key)),
			"origin": _t(String(chosen_origin.name_key))})


func _marked(chosen: bool, text: String) -> String:
	return ("%s %s" % [CHOSEN_MARK, text]) if chosen else ("    %s" % text)


func _refresh_detail() -> void:
	var origin := _origins.entry(shown_origin_id())
	if origin == null or _detail_name == null:
		return
	_detail_name.text = _t(String(origin.name_key))
	_detail_problem.text = _t(String(origin.problem_key))
	_detail_edge.text = _t(String(origin.edge_key))
	_detail_cost.text = _t(String(origin.cost_key))


func _t(key: String) -> String:
	var loc := get_node_or_null("/root/Localization")
	return String(loc.call("t", key)) if loc != null else key


func _t_args(key: String, args: Dictionary) -> String:
	var loc := get_node_or_null("/root/Localization")
	return String(loc.call("t_args", key, args)) if loc != null else key


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()

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
## canon, with the short spoiler-safe lines their data carries: the problem, the personal goal,
## what it is good for, what it costs. Every Origin is open to every look.
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

## The plaque is wide: the person on the left, the choice ledger on the right.
const PLAQUE_WIDTH := 1080
## The choice ledger: one column, the looks above the Origins, uniform rows.
const LEDGER_WIDTH := 320
## The person band: the figure's stage, its portrait, and whose past this is.
const PERSON_BAND_HEIGHT := 196.0
const STAGE_WIDTH := 152.0
## The chosen body, drawn at an integer scale (pixel art is never resampled).
const PREVIEW_SCALE := 3
## 40: the shared button plates carry 12px of vertical padding each side, so a smaller
## minimum here would be a lie the stylebox overrules — the rows are 40px tall.
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
## The stage the figure stands on: its draw callback lays the shared dais under the feet.
var _stage_anchor: Control = null
var _portrait: TextureRect
var _detail_name: Label
var _detail_problem: Label
var _detail_edge_heading: Label
var _detail_edge: Label
var _detail_goal_heading: Label
var _detail_goal: Label
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

	# The person under consideration on the left, the choice ledger on the right: the
	# screen is ABOUT someone (the band), and the ledger is the instrument that changes
	# them. The band and the terms follow the cursor; the ledger moves it.
	var main_row := HBoxContainer.new()
	main_row.name = "MainRow"
	main_row.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	box.add_child(main_row)

	var person := VBoxContainer.new()
	person.name = "Person"
	person.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	person.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	main_row.add_child(person)
	person.add_child(_build_person_band())
	person.add_child(_build_terms_well())

	main_row.add_child(_build_ledger())

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


func _build_person_band() -> Control:
	var band := PanelContainer.new()
	band.name = "PersonBand"
	band.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(row)

	# The body itself, standing: what the player will actually walk around as.
	_stage_anchor = Control.new()
	_stage_anchor.name = "Stage"
	_stage_anchor.custom_minimum_size = Vector2(STAGE_WIDTH, PERSON_BAND_HEIGHT)
	_stage_anchor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stage_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_anchor.draw.connect(_draw_stage_dais.bind(_stage_anchor))
	_stage_anchor.resized.connect(_place_preview)
	row.add_child(_stage_anchor)
	_preview = VisualComponentScript.new() as CharacterVisualComponent
	_preview.name = "Preview"
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_stage_anchor.add_child(_preview)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_portrait.custom_minimum_size = Vector2(UIPalette.MEDALLION_PX, UIPalette.MEDALLION_PX)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait)

	var who := VBoxContainer.new()
	who.name = "Who"
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(who)
	_detail_name = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	_detail_name.name = "OriginName"
	who.add_child(_detail_name)
	_detail_problem = _wrapped(UIPalette.COLOR_TEXT)
	_detail_problem.name = "OriginProblem"
	who.add_child(_detail_problem)
	# The personal goal the Chronicle keeps in view for the whole run: what this past is
	# walking toward. It belongs to the person, not to the terms.
	_detail_goal_heading = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_detail_goal_heading.name = "GoalHeading"
	who.add_child(_detail_goal_heading)
	_detail_goal = _wrapped(UIPalette.COLOR_TEXT)
	_detail_goal.name = "OriginGoal"
	who.add_child(_detail_goal)
	return band


## What the past gives and what it costs, set against each other: two rows in one well, so
## the give and the take read as one decision rather than two paragraphs.
func _build_terms_well() -> Control:
	var well := PanelContainer.new()
	well.name = "TermsWell"
	well.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(row)
	var edge := VBoxContainer.new()
	edge.name = "Edge"
	edge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edge.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(edge)
	_detail_edge_heading = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	edge.add_child(_detail_edge_heading)
	_detail_edge = _wrapped(UIPalette.COLOR_TEXT)
	_detail_edge.name = "OriginEdge"
	edge.add_child(_detail_edge)
	var cost := VBoxContainer.new()
	cost.name = "Cost"
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cost)
	# A burden is the one thing the crimson reservation means: "careful". One 14px heading,
	# never body text — the words still carry the meaning, the colour only its weight.
	_detail_cost_heading = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_CRIMSON)
	cost.add_child(_detail_cost_heading)
	_detail_cost = _wrapped(UIPalette.COLOR_TEXT)
	_detail_cost.name = "OriginCost"
	cost.add_child(_detail_cost)
	return well


## The choice ledger: the looks above the Origins, one column of uniform rows. The five
## Origins are peers — no numbers, no ranks — so the rows differ only in their words and in
## which one is chosen.
func _build_ledger() -> Control:
	var ledger := VBoxContainer.new()
	ledger.name = "Ledger"
	ledger.custom_minimum_size = Vector2(LEDGER_WIDTH, 0)
	ledger.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_look_heading = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	ledger.add_child(_look_heading)
	for look in _appearances.entries:
		var button := _choice_button()
		button.name = "Look_%s" % look.id
		button.focus_entered.connect(_on_look_focused.bind(look.id))
		button.pressed.connect(_on_look_chosen.bind(look.id))
		ledger.add_child(button)
		_look_buttons[look.id] = button
	_origin_heading = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	ledger.add_child(_origin_heading)
	for origin in _origins.entries:
		var button := _choice_button()
		button.name = "Origin_%s" % origin.id
		button.focus_entered.connect(_on_origin_focused.bind(origin.id))
		button.pressed.connect(_on_origin_chosen.bind(origin.id))
		ledger.add_child(button)
		_origin_buttons[origin.id] = button
	return ledger


## Up/down through the one ledger column, looks above Origins. Left/right JUMPS between
## the two kinds, landing on the CHOSEN option of the other kind; coming back up from the
## bottom row lands on the chosen option too. The cursor always arrives on something the
## player already knows, so crossing can never change a choice.
func _wire_focus() -> void:
	var order: Array = []
	order.append_array(_look_buttons.values())
	order.append_array(_origin_buttons.values())
	for i in order.size():
		var button := order[i] as Button
		button.focus_neighbor_top = button.get_path_to(order[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(
			order[i + 1] if i + 1 < order.size() else _begin_button)
	_back_button.focus_neighbor_right = _back_button.get_path_to(_begin_button)
	_begin_button.focus_neighbor_left = _begin_button.get_path_to(_back_button)
	_back_button.focus_neighbor_bottom = _back_button.get_path()
	_begin_button.focus_neighbor_bottom = _begin_button.get_path()
	_refresh_cross_focus()


func _refresh_cross_focus() -> void:
	var look := _look_buttons[_appearance_id] as Button
	var origin := _origin_buttons[_origin_id] as Button
	for button: Button in _look_buttons.values():
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path_to(origin)
	for button: Button in _origin_buttons.values():
		button.focus_neighbor_left = button.get_path_to(look)
		button.focus_neighbor_right = button.get_path()
	_back_button.focus_neighbor_top = _back_button.get_path_to(look)
	_begin_button.focus_neighbor_top = _begin_button.get_path_to(origin)


func _choice_button() -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, CHOICE_BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_BODY)
	# CHOSEN is gold (structure: what is decided); the cursor's ring stays jade
	# (interaction: where you are). Two states, two colours — never one colour for two
	# meanings (`docs/VISUAL_CRAFT_WORKFLOW.md` brief I1).
	button.add_theme_color_override("font_pressed_color", UIPalette.GOLD_PRIMARY)
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
		_place_preview()
	_portrait.texture = load(look.template.portrait_ref) as Texture2D \
		if ResourceLoader.exists(look.template.portrait_ref) else null


## Feet on the stage floor, centred: the sprite's origin is its feet. Re-run on resize, so
## the figure never floats if the band grows under a long problem line.
func _place_preview() -> void:
	if _preview == null or _stage_anchor == null:
		return
	_preview.position = Vector2(
		_stage_anchor.size.x * 0.5, _stage_anchor.size.y - UIPalette.SPACE_MD)
	_stage_anchor.queue_redraw()


## The shared dais under the figure's feet: the lightest ground in the plaque, so the body
## reads as standing IN the stage and not pasted on it (`FigureDais`, one drawing for the
## satchel's stage and this one).
func _draw_stage_dais(anchor: Control) -> void:
	if _preview == null:
		return
	FigureDais.draw_on(anchor, _preview.position, float(PREVIEW_SCALE))


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
	_detail_goal_heading.text = _t("UI_IDENTITY_GOAL")
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
	_detail_goal.text = _t(String(origin.goal_key))
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

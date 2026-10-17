extends Control
class_name IdentityScreen
## IdentityScreen — Aetheria presentation (who the player is; Phase 20, D-072 §2; reworked in
## the experience upgrade).
##
## Beat 1 of the prologue (`NARRATIVE_MASTER_PLAN.md` §5): a look and an Origin, chosen before
## a run exists. Opened by New Game; it is MENU UI, exactly as settings is — nothing about a
## run is created until `confirmed` is emitted, so backing out has nothing to undo.
##
## WHAT IT MUST TELL (experience upgrade). An Origin is a PAST, not a class: the screen says
## so in its subtitle, and for the Origin under the cursor it tells the whole of it — who they
## were, what happened, what they want now, why the road leads to Lạc Hà, the first lead worth
## following there, what they bring and what it costs, and a spoiler-safe question about where
## it may go. The five are CARDS (a picture, a name, one line) so they can be compared at a
## glance; the chosen past is told under its own picture. Everything is the Origin's data
## (`OriginData`); nothing here names an Origin.
##
## IT OFFERS ONLY WHAT IS REAL. The looks are the catalog's (each one a body and a portrait the
## game can draw — shown here, moving, before the player commits); every Origin is open to
## every look. IT DECIDES NOTHING: it emits which look and which Origin; `Main` starts the run.
##
## KEYS. Arrows move a CURSOR; `ui_accept` on a look or an Origin CHOOSES it (marked ◆ in
## words). The picture and the story follow the cursor while it is on an Origin — so all five
## can be read before anything is chosen — and return to what is chosen when the cursor
## leaves. ↑/↓ walk a column, ←/→ cross to the other column's CHOSEN option, ↓ from the last
## Origin is "Set out". One line above the buttons states the choice in words. `ui_cancel`
## (Esc) goes back from anywhere. Confirming locks the screen, so a repeated key cannot start
## two runs.
##
## The first build chose by moving the cursor. Reaching "Set out" from the Origin column then
## meant walking down THROUGH the Origins below, silently changing the choice to the last one
## — found by the story E2E, whose second run started as the wrong person.

signal confirmed(appearance_id: StringName, origin_id: StringName)
signal cancelled()

const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

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
var _subtitle: Label
var _look_heading: Label
var _origin_heading: Label
var _look_buttons: Dictionary = {}    # appearance_id -> Button
var _origin_buttons: Dictionary = {}  # origin_id -> Button (the card)
var _card_names: Dictionary = {}      # origin_id -> Label
var _card_taglines: Dictionary = {}   # origin_id -> Label
var _card_pictures: Dictionary = {}   # origin_id -> TextureRect
var _card_frames: Dictionary = {}     # origin_id -> NinePatchRect (the chosen card's gold)
var _preview: CharacterVisualComponent = null
var _portrait: TextureRect
var _banner: TextureRect
var _detail_name: Label
var _detail_tagline: Label
## heading key -> [heading Label, body Label]; the body's node name is what tests read.
var _sections: Dictionary = {}
var _hint: Label
## "Chosen: <look> · <Origin>" — what Set out will start, in words.
var _summary: Label
## The option under the cursor (empty while the cursor is on the bottom row).
var _cursor_look: StringName = &""
var _cursor_origin: StringName = &""
var _begin_button: Button
var _back_button: Button
var _bus: Node = null

## The detail's sections: [heading key, node name, the OriginData field it shows]. Left column
## first, then right; `bring_cost` is drawn as one row under both.
const LEFT_SECTIONS := [
	["UI_IDENTITY_PAST", "OriginPast", "past_key"],
	["UI_IDENTITY_HAPPENED", "OriginProblem", "problem_key"],
	["UI_IDENTITY_WANT", "OriginGoal", "goal_key"],
]
const RIGHT_SECTIONS := [
	["UI_IDENTITY_WHY_HERE", "OriginWhyHere", "why_here_key"],
	["UI_IDENTITY_LEAD", "OriginLead", "lead_key"],
	["UI_IDENTITY_HORIZON", "OriginHorizon", "horizon_key"],
]
const COST_SECTIONS := [
	["UI_IDENTITY_EDGE", "OriginEdge", "edge_key"],
	["UI_IDENTITY_COST", "OriginCost", "cost_key"],
]


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

	var margin := MarginContainer.new()
	margin.name = "IdentityMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, UIPalette.SPACE_LG)
	margin.add_theme_constant_override("margin_top", UIPalette.SPACE_MD)
	margin.add_theme_constant_override("margin_bottom", UIPalette.SPACE_MD)
	add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	# The plaque is the whole composition: everything the screen says is inside it.
	var plaque := VBoxContainer.new()
	plaque.name = "IdentityPlaque"
	plaque.custom_minimum_size = Vector2(UIPalette.IDENTITY_WIDTH, 0)
	plaque.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	center.add_child(plaque)

	_title = _label(UIPalette.FONT_SIZE_BUTTON + 4, UIPalette.COLOR_TITLE)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plaque.add_child(_title)
	_subtitle = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_subtitle.name = "Subtitle"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plaque.add_child(_subtitle)
	plaque.add_child(UITheme.ornament_divider())

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	plaque.add_child(columns)
	columns.add_child(_build_look_column())
	columns.add_child(_build_origin_column())
	columns.add_child(_build_detail_column())

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	plaque.add_child(footer)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	footer.add_child(words)
	_summary = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	_summary.name = "Summary"
	words.add_child(_summary)
	_hint = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(UIPalette.IDENTITY_WIDTH * 0.4, 0)
	words.add_child(_hint)
	_back_button = UITheme.menu_button(UITheme.ROLE_SECONDARY)
	_back_button.name = "Back"
	_back_button.pressed.connect(_on_back)
	_back_button.focus_entered.connect(_on_cursor_left_the_options)
	footer.add_child(_back_button)
	_begin_button = UITheme.menu_button(UITheme.ROLE_PRIMARY)
	_begin_button.name = "Begin"
	_begin_button.pressed.connect(_on_begin)
	_begin_button.focus_entered.connect(_on_cursor_left_the_options)
	footer.add_child(_begin_button)
	_wire_focus()


func _build_look_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "LookColumn"
	column.custom_minimum_size = Vector2(UIPalette.IDENTITY_LOOK_COLUMN_WIDTH, 0)
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_look_heading = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	column.add_child(_look_heading)

	# The body itself, standing: what the player will actually walk around as.
	var well := PanelContainer.new()
	well.name = "PreviewWell"
	well.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	well.custom_minimum_size = PREVIEW_WELL
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(well)
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
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_portrait)

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
	column.custom_minimum_size = Vector2(UIPalette.IDENTITY_CARD_SIZE.x, 0)
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_origin_heading = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	column.add_child(_origin_heading)
	for origin in _origins.entries:
		var card := _origin_card(origin)
		column.add_child(card)
		_origin_buttons[origin.id] = card
	return column


## One Origin as a card: a button (so focus, hover, the keyboard and the mouse all work as for
## any choice) carrying its picture's thumbnail, its name and its one line. The chosen card
## wears the gold frame AND the mark in words.
func _origin_card(origin: OriginData) -> Button:
	var card := Button.new()
	card.name = "Origin_%s" % origin.id
	card.toggle_mode = true
	card.custom_minimum_size = UIPalette.IDENTITY_CARD_SIZE
	card.focus_entered.connect(_on_origin_focused.bind(origin.id))
	card.mouse_entered.connect(_on_card_hovered.bind(card))
	card.pressed.connect(_on_origin_chosen.bind(origin.id))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UIPalette.SPACE_SM
	row.offset_right = -UIPalette.SPACE_SM
	row.offset_top = UIPalette.SPACE_SM
	row.offset_bottom = -UIPalette.SPACE_SM
	row.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var picture := UITheme.story_picture(origin.art_ref, UIPalette.IDENTITY_CARD_REGION)
	picture.name = "Thumb"
	picture.custom_minimum_size = UIPalette.IDENTITY_CARD_THUMB
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(picture)
	_card_pictures[origin.id] = picture
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var name_label := _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	name_label.name = "Name"
	words.add_child(name_label)
	_card_names[origin.id] = name_label
	var tagline := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	tagline.name = "Tagline"
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(UIPalette.IDENTITY_CARD_SIZE.x
		- UIPalette.IDENTITY_CARD_THUMB.x - 3 * UIPalette.SPACE_MD, 0)
	words.add_child(tagline)
	_card_taglines[origin.id] = tagline
	var frame := UITheme.ornament_frame()
	frame.name = "ChosenFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(frame)
	_card_frames[origin.id] = frame
	return card


func _build_detail_column() -> Control:
	var well := PanelContainer.new()
	well.name = "DetailWell"
	well.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	well.custom_minimum_size = Vector2(UIPalette.IDENTITY_DETAIL_WIDTH, 0)
	var column := VBoxContainer.new()
	column.name = "Detail"
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	well.add_child(column)

	# The past as a picture: the banner, with the name and the line over its faded foot.
	var banner := Control.new()
	banner.name = "Banner"
	banner.custom_minimum_size = Vector2(0, UIPalette.IDENTITY_BANNER_HEIGHT)
	banner.clip_contents = true
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(banner)
	_banner = UITheme.story_picture("")
	_banner.name = "OriginArt"
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.add_child(_banner)
	var fade := UITheme.story_fade()
	fade.name = "BannerFade"
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.add_child(fade)
	var frame := UITheme.ornament_frame()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.add_child(frame)
	var caption := VBoxContainer.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = UIPalette.SPACE_MD
	caption.offset_right = -UIPalette.SPACE_MD
	caption.offset_bottom = -UIPalette.SPACE_SM
	caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	caption.add_theme_constant_override("separation", 0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(caption)
	_detail_name = _label(UIPalette.FONT_SIZE_BUTTON + 2, UIPalette.COLOR_TITLE)
	_detail_name.name = "OriginName"
	_outline(_detail_name)
	caption.add_child(_detail_name)
	_detail_tagline = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	_detail_tagline.name = "OriginTagline"
	_outline(_detail_tagline)
	caption.add_child(_detail_tagline)

	var story := HBoxContainer.new()
	story.name = "Story"
	story.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	column.add_child(story)
	var half := int((UIPalette.IDENTITY_DETAIL_WIDTH - UIPalette.SPACE_LG) * 0.5) \
		- UIPalette.SPACE_MD
	story.add_child(_section_column("StoryLeft", LEFT_SECTIONS, half))
	story.add_child(_section_column("StoryRight", RIGHT_SECTIONS, half))
	column.add_child(UITheme.ornament_divider())
	var costs := HBoxContainer.new()
	costs.name = "BringCost"
	costs.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	column.add_child(costs)
	for entry: Array in COST_SECTIONS:
		costs.add_child(_section_column("Cost_%s" % entry[1], [entry], half))
	return well


func _section_column(column_name: String, sections: Array, width: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = column_name
	column.custom_minimum_size = Vector2(width, 0)
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	for entry: Array in sections:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 0)
		column.add_child(block)
		var heading := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
		block.add_child(heading)
		var body := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
		body.name = String(entry[1])
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(width, 0)
		block.add_child(body)
		_sections[String(entry[0])] = [heading, body, String(entry[2])]
	return column


## ↑/↓ inside a column; ←/→ between columns lands on that column's CHOSEN option, so the
## cursor always arrives on something the player already knows.
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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Text drawn over a picture carries the ink outline (`UIPalette.COLOR_TEXT_OUTLINE`).
func _outline(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", UIPalette.COLOR_TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", 4)


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


## The mouse over a card is the cursor on it: the same as the keyboard reaching it.
func _on_card_hovered(card: Button) -> void:
	if not _locked:
		card.grab_focus()


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


## A chosen option is held down, framed in gold (a card) AND marked in words.
func _mark_choices() -> void:
	for id: StringName in _look_buttons:
		(_look_buttons[id] as Button).set_pressed_no_signal(id == _appearance_id)
	for id: StringName in _origin_buttons:
		(_origin_buttons[id] as Button).set_pressed_no_signal(id == _origin_id)
		(_card_frames[id] as Control).visible = id == _origin_id
	if _title != null and _title.text != "":
		_refresh_choice_text()
	_refresh_card_light()


## The card that is chosen or under the cursor shows its picture in full; the others step
## back. A brightness, never the only sign (the mark and the frame carry the state).
func _refresh_card_light() -> void:
	for id: StringName in _card_pictures:
		var lit := id == _origin_id or id == _cursor_origin
		(_card_pictures[id] as TextureRect).modulate = Color.WHITE if lit \
			else UIPalette.COLOR_CARD_RESTING


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
	_refresh_card_light()


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
	_subtitle.text = _t("UI_IDENTITY_SUBTITLE")
	_look_heading.text = _t("UI_IDENTITY_LOOK")
	_origin_heading.text = _t("UI_IDENTITY_ORIGIN")
	for key: String in _sections:
		(_sections[key][0] as Label).text = _t(key)
	# The subtitle already says what an Origin does NOT decide; the footer says only the keys.
	_hint.text = _t("UI_IDENTITY_KEYS")
	_begin_button.text = _t("UI_IDENTITY_BEGIN")
	_back_button.text = _t("UI_IDENTITY_BACK")
	for origin in _origins.entries:
		(_card_taglines[origin.id] as Label).text = _t(String(origin.tagline_key))
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
		(_card_names[origin.id] as Label).text = _marked(origin.id == _origin_id,
			_t(String(origin.name_key)))
	var chosen_look := _appearances.entry(_appearance_id)
	var chosen_origin := _origins.entry(_origin_id)
	if _summary != null and chosen_look != null and chosen_origin != null:
		_summary.text = _t_args("UI_IDENTITY_SUMMARY", {
			"look": _t(String(chosen_look.name_key)),
			"origin": _t(String(chosen_origin.name_key))})


func _marked(chosen: bool, text: String) -> String:
	return ("%s %s" % [CHOSEN_MARK, text]) if chosen else text


## The text of the card under the cursor (or of the chosen one), as its name: a test and a
## capture read what the card SAYS, not how it is drawn.
func card_name_text(origin_id: StringName) -> String:
	var label := _card_names.get(origin_id) as Label
	return label.text if label != null else ""


func _refresh_detail() -> void:
	var origin := _origins.entry(shown_origin_id())
	if origin == null or _detail_name == null:
		return
	_detail_name.text = _t(String(origin.name_key))
	_detail_tagline.text = _t(String(origin.tagline_key))
	for key: String in _sections:
		var field: String = _sections[key][2]
		(_sections[key][1] as Label).text = _t(String(origin.get(field)))
	UITheme.set_story_picture(_banner, origin.art_ref)


func _t(key: String) -> String:
	var loc := get_node_or_null("/root/Localization")
	return String(loc.call("t", key)) if loc != null else key


func _t_args(key: String, args: Dictionary) -> String:
	var loc := get_node_or_null("/root/Localization")
	return String(loc.call("t_args", key, args)) if loc != null else key


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()

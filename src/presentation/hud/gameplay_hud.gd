extends CanvasLayer
class_name GameplayHUD
## GameplayHUD — Aetheria presentation (in-map heads-up display, asset-backed pass).
##
## A screen-space (`CanvasLayer`) overlay that RENDERS a view of the running session inside
## framed pixel-art panels (shared `UITheme`/`UIPalette` 9-slice assets):
##   - top-left   : an identity panel (portrait-frame slot + character name/title),
##   - top-right  : a map-name panel,
##   - bottom-left: a control-prompt panel with graphic key badges ([E] Interact / [Esc] Menu).
##
## It OWNS no truth. The owner (MapBase) pushes data in via `set_character()`, `set_map_name()`
## and `set_interact_available()`; the HUD only formats + displays. Key glyphs come from
## `InputService.get_action_display_label` (never raw keycodes, L-003). It refreshes on demand
## (owner call) and on language change — never per frame (`05-performance-testing.md`). This is
## the FOUNDATION HUD (identity/map/prompts); HP/mana/cultivation bars are intentionally NOT
## shown (no gameplay semantics yet) — a later phase adds them to the reserved panels.

const PromptRowScript := preload("res://src/presentation/ui/components/ui_prompt_row.gd")

const INTERACT_ACTION := &"interact"
const OPEN_MENU_ACTION := &"open_menu"

var _loc: Node = null
var _input: Node = null
var _bus: Node = null

# Pushed-in view state (presentation copies; the HUD never mutates the source).
var _name_key: StringName = &""
var _title_key: StringName = &""
var _map_name_key: StringName = &""
var _interact_available: bool = false

var _name_label: Label
var _title_label: Label
var _map_label: Label
var _interact_row: UIPromptRow
var _menu_row: UIPromptRow


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	_bus = get_node_or_null("/root/EventBus")
	_build_ui()
	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)
	_refresh()


func _exit_tree() -> void:
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Top-left: identity panel (portrait slot + name/title) --------------------
	var identity_panel := _panel()
	identity_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	identity_panel.position = Vector2(UIPalette.SPACE_MD, UIPalette.SPACE_MD)
	root.add_child(identity_panel)

	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	identity_panel.add_child(identity_row)

	# Portrait frame slot (empty well for now; a portrait texture drops in later).
	var portrait := TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(40, 40)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(UIPalette.TEX_PORTRAIT_FRAME):
		portrait.texture = load(UIPalette.TEX_PORTRAIT_FRAME)
	identity_row.add_child(portrait)

	var identity_text := VBoxContainer.new()
	identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_text.add_theme_constant_override("separation", 2)
	identity_row.add_child(identity_text)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	identity_text.add_child(_name_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_title_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	identity_text.add_child(_title_label)

	# --- Top-right: map-name panel ------------------------------------------------
	var map_panel := _panel()
	map_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_panel.position = Vector2(-UIPalette.SPACE_MD, UIPalette.SPACE_MD)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(map_panel)

	_map_label = Label.new()
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_map_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	map_panel.add_child(_map_label)

	# --- Bottom-left: control-prompt panel (graphic key badges) -------------------
	var prompt_panel := _panel()
	prompt_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	prompt_panel.position = Vector2(UIPalette.SPACE_MD, -UIPalette.SPACE_MD)
	prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(prompt_panel)

	var prompt_box := HBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	prompt_panel.add_child(prompt_box)

	_interact_row = PromptRowScript.new() as UIPromptRow
	prompt_box.add_child(_interact_row)

	_menu_row = PromptRowScript.new() as UIPromptRow
	prompt_box.add_child(_menu_row)


## A framed HUD panel wearing the shared 9-slice panel style.
func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# --- Owner-pushed view state -------------------------------------------------

## Set the character identity to display (name + optional title localization keys). Pass the
## authoritative CharacterState's keys; the HUD resolves them through Localization. A null
## state clears the plate (e.g. before the player exists).
func set_character(state: CharacterState) -> void:
	if state == null:
		_name_key = &""
		_title_key = &""
	else:
		_name_key = state.name_key
		_title_key = state.title_key
	_refresh()


## Set the current map's name localization key.
func set_map_name(name_key: StringName) -> void:
	_map_name_key = name_key
	_refresh()


## Whether the player can currently interact with an exit (drives the interact prompt).
func set_interact_available(available: bool) -> void:
	if _interact_available == available:
		return
	_interact_available = available
	_refresh()


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	if _name_label == null:
		return  # not built yet
	_name_label.text = _resolve(_name_key)
	_title_label.text = _resolve(_title_key)
	_title_label.visible = _title_key != &""
	_map_label.text = _resolve(_map_name_key)
	_refresh_prompts()


## Resolve a localization key to text (empty key -> empty string, no warning spam).
func _resolve(key: StringName) -> String:
	if key == &"" or _loc == null:
		return ""
	return String(_loc.call("t", key))


## Fill the two prompt rows from InputService display labels (never raw keycodes). The
## interact row is hidden until the player is standing in an exit; the menu row is always on.
func _refresh_prompts() -> void:
	if _menu_row == null:
		return
	var menu_key := _display_label(OPEN_MENU_ACTION)
	_menu_row.set_prompt(menu_key, _text("UI_HUD_MENU_ACTION"))
	_interact_row.visible = _interact_available
	if _interact_available:
		var interact_key := _display_label(INTERACT_ACTION)
		_interact_row.set_prompt(interact_key, _text("UI_HUD_INTERACT_ACTION"))


func _display_label(action: StringName) -> String:
	if _input == null:
		return "?"
	return String(_input.call("get_action_display_label", action))


func _text(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))


func _on_language_changed(_language_code: String) -> void:
	_refresh()

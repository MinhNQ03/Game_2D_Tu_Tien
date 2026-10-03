extends CanvasLayer
class_name GameplayHUD
## GameplayHUD — Aetheria presentation (in-map heads-up display, foundation pass).
##
## A presentation-only overlay that RENDERS a view of the running session: the player
## character's identity (name + title, from the authoritative `CharacterState`), the current
## map name (localized), and the contextual control hints (interact / menu) expressed through
## `InputService`'s display-label API — never raw keycodes (`07-localization.md`, L-003).
##
## It OWNS no truth. The owner (MapBase) pushes data in via `set_character()`, `set_map_name()`
## and `set_interact_available()`; the HUD only formats + displays. It refreshes on demand
## (owner call) and on language change — never per frame (`05-performance-testing.md`). This is
## the FOUNDATION HUD (name/map/hints), not the final combat HUD (health bars, resources, …).

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
var _hint_label: Label


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

	# Top-left identity plate (name + title).
	var identity := VBoxContainer.new()
	identity.position = Vector2(UIPalette.SPACE_LG, UIPalette.SPACE_LG)
	identity.add_theme_constant_override("separation", 2)
	root.add_child(identity)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	identity.add_child(_name_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_title_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	identity.add_child(_title_label)

	# Top-right map name.
	_map_label = Label.new()
	_map_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_map_label.position = Vector2(-UIPalette.SPACE_LG, UIPalette.SPACE_LG)
	_map_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_map_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	root.add_child(_map_label)

	# Bottom control hints.
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.position = Vector2(UIPalette.SPACE_LG, -UIPalette.SPACE_XL)
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_hint_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	root.add_child(_hint_label)


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


## Whether the player can currently interact with an exit (drives which hint shows).
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
	_hint_label.text = _build_hint()


## Resolve a localization key to text (empty key -> empty string, no warning spam).
func _resolve(key: StringName) -> String:
	if key == &"" or _loc == null:
		return ""
	return String(_loc.call("t", key))


## Build the contextual control hint using InputService display labels (never raw keycodes).
## Shows the interact hint when an exit is in reach, plus the always-available menu hint.
func _build_hint() -> String:
	if _loc == null or _input == null:
		return ""
	var menu_key := String(_input.call("get_action_display_label", OPEN_MENU_ACTION))
	var menu_hint := String(_loc.call("t_args", "UI_HUD_MENU_HINT", {"key": menu_key}))
	if not _interact_available:
		return menu_hint
	var interact_key := String(_input.call("get_action_display_label", INTERACT_ACTION))
	var interact_hint := String(_loc.call("t_args", "UI_HUD_INTERACT_HINT", {"key": interact_key}))
	return "%s     %s" % [interact_hint, menu_hint]


func _on_language_changed(_language_code: String) -> void:
	_refresh()

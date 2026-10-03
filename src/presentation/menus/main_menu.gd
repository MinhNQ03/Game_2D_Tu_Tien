extends Control
## MainMenu — Aetheria presentation (main-menu shell, foundation presentation pass).
##
## Offers a route to New Game and Quit; Load Game is a disabled placeholder (no save system
## yet, Phase 23). This is the FOUNDATION look (shared `UITheme`/`UIPalette`), not final art.
##
## The menu does not know *why* a new game starts or *how* scenes load — it emits intent
## signals and the coordinator (Main) drives GameState + SceneRouter. All text is resolved
## from localization keys; no literal user-facing strings here (`07-localization.md`). Input
## context ownership (MENU) stays with this menu while shown (§12). Behaviour (signals,
## localization, context) is unchanged from the shell; only the presentation is dressed.

signal new_game_pressed()
signal quit_pressed()

var _background: ColorRect
var _title: Label
var _subtitle: Label
var _new_game_button: Button
var _load_game_button: Button
var _quit_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build()
	_build_ui()
	_refresh_text()

	# Menu owns the MENU input context while shown (input gating ownership, §12).
	var input := get_node_or_null("/root/InputService")
	if input != null:
		input.call("set_menu_context")

	var bus := get_node_or_null("/root/EventBus")
	if bus != null and not bus.is_connected("language_changed", _on_language_changed):
		bus.connect("language_changed", _on_language_changed)

	# Keyboard/gamepad users land on the primary action without a mouse.
	_new_game_button.grab_focus()


func _exit_tree() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.is_connected("language_changed", _on_language_changed):
		bus.disconnect("language_changed", _on_language_changed)


func _build_ui() -> void:
	# Full-rect background behind everything (so the menu is not on transparent black).
	_background = ColorRect.new()
	_background.color = UIPalette.COLOR_BACKGROUND
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	# Center the VBox on its own pivot so PRESET_CENTER anchors the middle, not the corner.
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_TITLE)
	_title.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_subtitle.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_subtitle)

	# A little breathing room between the title block and the buttons.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, UIPalette.SPACE_LG)
	box.add_child(spacer)

	_new_game_button = _make_menu_button()
	_new_game_button.pressed.connect(_on_new_game)
	box.add_child(_new_game_button)

	_load_game_button = _make_menu_button()
	_load_game_button.disabled = true  # No save system yet (Phase 23).
	box.add_child(_load_game_button)

	_quit_button = _make_menu_button()
	_quit_button.pressed.connect(_on_quit)
	box.add_child(_quit_button)


## A uniformly sized menu button (so the three line up as a tidy column).
func _make_menu_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 0)
	return button


func _refresh_text() -> void:
	var loc := get_node_or_null("/root/Localization")
	if loc == null:
		return
	_title.text = String(loc.call("t", "UI_MENU_TITLE"))
	_subtitle.text = String(loc.call("t", "UI_MENU_SUBTITLE"))
	_new_game_button.text = String(loc.call("t", "UI_MENU_NEW_GAME"))
	_load_game_button.text = String(loc.call("t", "UI_MENU_LOAD_GAME"))
	_quit_button.text = String(loc.call("t", "UI_MENU_QUIT"))


func _on_new_game() -> void:
	new_game_pressed.emit()


func _on_quit() -> void:
	quit_pressed.emit()


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()

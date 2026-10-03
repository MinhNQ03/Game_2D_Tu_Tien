extends Control
## MainMenu — Aetheria presentation (main-menu, asset-backed pixel-art pass).
##
## A framed pixel-art menu (shared `UITheme`/`UIPalette` + 9-slice panel assets): a dark
## textured background, a centered framed panel holding the title treatment (title + subtitle
## + ornamental divider) and the action buttons with real normal/hover/pressed/focus/disabled
## states. New Game and Quit are live; Load Game and Settings are disabled placeholders (no
## save/settings system yet).
##
## The menu does not know *why* a new game starts or *how* scenes load — it emits intent
## signals and the coordinator (Main) drives GameState + SceneRouter. All text is resolved
## from localization keys; no literal user-facing strings here (`07-localization.md`). Input
## context ownership (MENU) stays with this menu while shown (§12). Behaviour (signals,
## localization, context) is unchanged from the shell; only the presentation is dressed.

signal new_game_pressed()
signal quit_pressed()

var _title: Label
var _subtitle: Label
var _divider: TextureRect
var _new_game_button: Button
var _load_game_button: Button
var _settings_button: Button
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
	# --- Background: a dark tiled pixel surface (not a flat ColorRect) -------------
	# A deep ink fill behind the framed panel (D-028). The xianxia inset texture is a FRAMED
	# panel, not a seamless tile, so we no longer tile it as a backdrop (that would repeat its
	# border); a flat deep-ink base reads as the "dark lacquer" ground the jade panel sits on.
	var fill := ColorRect.new()
	fill.name = "Background"
	fill.color = UIPalette.COLOR_BACKGROUND
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	# --- Centered framed panel -----------------------------------------------------
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	panel.add_child(box)

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

	# Ornamental divider under the title treatment.
	_divider = TextureRect.new()
	_divider.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_divider.stretch_mode = TextureRect.STRETCH_SCALE
	_divider.custom_minimum_size = Vector2(0, 10)
	_divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(UIPalette.TEX_TITLE_DIVIDER):
		_divider.texture = load(UIPalette.TEX_TITLE_DIVIDER)
	box.add_child(_divider)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, UIPalette.SPACE_SM)
	box.add_child(spacer)

	_new_game_button = _make_menu_button()
	_new_game_button.pressed.connect(_on_new_game)
	box.add_child(_new_game_button)

	_load_game_button = _make_menu_button()
	_load_game_button.disabled = true  # No save system yet (Phase 23).
	box.add_child(_load_game_button)

	_settings_button = _make_menu_button()
	_settings_button.disabled = true  # No settings system yet (placeholder slot).
	box.add_child(_settings_button)

	_quit_button = _make_menu_button()
	_quit_button.pressed.connect(_on_quit)
	box.add_child(_quit_button)


## A uniformly sized menu button (so the column lines up) wearing the shared theme.
func _make_menu_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(300, 0)
	button.focus_mode = Control.FOCUS_ALL
	return button


func _refresh_text() -> void:
	var loc := get_node_or_null("/root/Localization")
	if loc == null:
		return
	_title.text = String(loc.call("t", "UI_MENU_TITLE"))
	_subtitle.text = String(loc.call("t", "UI_MENU_SUBTITLE"))
	_new_game_button.text = String(loc.call("t", "UI_MENU_NEW_GAME"))
	_load_game_button.text = String(loc.call("t", "UI_MENU_LOAD_GAME"))
	_settings_button.text = String(loc.call("t", "UI_MENU_SETTINGS"))
	_quit_button.text = String(loc.call("t", "UI_MENU_QUIT"))


func _on_new_game() -> void:
	new_game_pressed.emit()


func _on_quit() -> void:
	quit_pressed.emit()


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()

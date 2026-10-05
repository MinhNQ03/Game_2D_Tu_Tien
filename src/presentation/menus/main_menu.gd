extends Control
## MainMenu — Aetheria presentation (main-menu, asset-backed pixel-art pass).
##
## A framed pixel-art menu (shared `UITheme`/`UIPalette` + 9-slice panel assets) composed as
## a SCENE rather than a widget stack (D-041): a deep ink ground with a gradient horizon, a
## restrained vignette and four corner ornaments behind a centered framed plaque that holds
## the title treatment (title + subtitle + ornamental divider) and a column of action buttons
## carrying a semantic role hierarchy (one PRIMARY, two SECONDARY, one DANGER) with real
## normal/hover/pressed/focus/disabled states. New Game, Settings and Quit are live; Load Game
## stays a disabled placeholder until the save system lands (Phase 23).
##
## The menu does not know *why* a new game starts or *how* scenes load — it emits intent
## signals and the coordinator (Main) drives GameState + SceneRouter. All text is resolved
## from localization keys; no literal user-facing strings here (`07-localization.md`). Input
## context ownership (MENU) stays with this menu while shown (§12). Behaviour (signals,
## localization, context) is unchanged from the shell; only the presentation is dressed.

signal new_game_pressed()
signal settings_pressed()
signal quit_pressed()

var _title: Label
var _subtitle: Label
var _divider: TextureRect
var _new_game_button: Button
var _load_game_button: Button
var _settings_button: Button
var _quit_button: Button


func _ready() -> void:
	# `set_anchors_and_offsets_preset`, NOT `set_anchors_preset` — and this is the whole reason
	# the menu used to render crammed into the top-left corner at a few hundred px.
	#
	# `set_anchors_preset(p, keep_offsets = false)` does not zero the offsets. It RECOMPUTES
	# them to PRESERVE the control's current on-screen rect (`offset_right += parent_width *
	# (old_anchor - new_anchor)`). `main_menu.tscn` authors this root Control with no size at
	# all, so the current rect was 0x0 — and the call faithfully kept it 0x0 while setting the
	# anchors to full-rect. The `CenterContainer` then centred the plaque inside a 0x0 box at
	# the origin, and the four screen-corner ornaments collapsed onto that box, which is
	# exactly what the broken screenshot showed. The HUD never hit this because it calls the
	# preset BEFORE `add_child`, where the parent range is 0 so the offsets stay 0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_build_backdrop()

	# --- Centered framed plaque ----------------------------------------------------
	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "MenuPlaque"
	panel.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	panel.custom_minimum_size = Vector2(UIPalette.MENU_PANEL_WIDTH, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_TITLE)
	# Muted antique gold for the title plaque (D-030 polish) — a clear warm step above the
	# off-white body/subtitle, reading as a tu-tiên seal rather than flat default text.
	_title.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_subtitle.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_subtitle)

	# Ornamental divider under the title treatment — from the ONE theme factory (D-050).
	# This screen used to build its own, and so did the HUD; the duplicated construction had
	# already produced a visible bug (the stretched jade divider rendered as a flat saturated
	# bar and read as a PROGRESS BAR directly under the subtitle).
	_divider = UITheme.ornament_divider()
	box.add_child(_divider)

	# One deliberate gap between the title treatment and the action column, so the plaque
	# reads as two blocks (identity, then actions) rather than one undifferentiated list.
	var spacer := Control.new()
	spacer.name = "TitleGap"
	spacer.custom_minimum_size = Vector2(0, UIPalette.TITLE_GAP)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	var actions := VBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	box.add_child(actions)

	# Semantic hierarchy (A4): one PRIMARY action, two SECONDARY, one DANGER/exit. The roles
	# live in `UITheme`; this screen never names a colour.
	_new_game_button = _make_menu_button(UITheme.ROLE_PRIMARY)
	_new_game_button.pressed.connect(_on_new_game)
	actions.add_child(_new_game_button)

	_load_game_button = _make_menu_button(UITheme.ROLE_SECONDARY)
	_load_game_button.disabled = true  # No save system yet (Phase 23).
	actions.add_child(_load_game_button)

	# Settings is LIVE as of D-035: it carries the language switch (vi/en) that per-phase
	# beta builds are play-tested with. Load Game stays disabled until save lands (Phase 23).
	_settings_button = _make_menu_button(UITheme.ROLE_SECONDARY)
	_settings_button.pressed.connect(_on_settings)
	actions.add_child(_settings_button)

	_quit_button = _make_menu_button(UITheme.ROLE_DANGER)
	_quit_button.pressed.connect(_on_quit)
	actions.add_child(_quit_button)


## The presentation-only menu backdrop (D-041, A2/A7).
##
## Before this, the menu was a small plaque on a flat near-black `ColorRect`, which read as a
## Godot Control floating in a void. The fix is composition, not content: a deep ink ground,
## a vertical gradient that gives the screen a horizon, a restrained radial vignette, and
## four corner ornaments.
##
## Deliberately built from code-generated gradients plus ONE existing texture: no new asset,
## so no provenance question (`06-art-assets.md`), and no per-frame cost — a
## `GradientTexture2D` rasterises once and is then a static draw. It carries no gameplay: no
## collision, no player, no WorldRuntime, no state (A7).
func _build_backdrop() -> void:
	var fill := ColorRect.new()
	fill.name = "Background"
	fill.color = UIPalette.COLOR_BACKGROUND_DEEP
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	var sky := TextureRect.new()
	sky.name = "BackdropGradient"
	sky.texture = UITheme.backdrop_gradient()
	# The gradient is a smooth ramp, so it is the one UI texture that must NOT be nearest-
	# filtered: at 16x256 stretched full-screen, nearest would show visible banding steps.
	sky.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	# The painted scene (D-044) — what finally makes this a composed screen rather than a
	# plaque on a gradient.
	#
	# It is CENTRED and aspect-preserved at ~88% of the screen height, NOT stretched to cover
	# the viewport. Stretching a 310x330 painting to fill 1280x720+ is a 4x+ upscale and goes
	# visibly soft; centring it is only ~1.9x. The reason that works seamlessly is measured:
	# the artwork's own background navy is deliberately close to COLOR_BACKGROUND_DEEP, so the
	# surrounding fill reads as a continuation of the painting instead of as a border around it.
	var scene := TextureRect.new()
	scene.name = "BackdropScene"
	scene.texture = UITheme.menu_backdrop()
	# LINEAR, not nearest: this is PAINTED art, not pixel art. Nearest would stair-step the
	# soft cloud gradients and the fine gold detail (`UIPalette` painted-tier note).
	scene.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# COVERED, not CENTERED (D-050). The painted backdrop is 310x330 — portrait-ish — so
	# centring it on a 16:9 screen left hard black bars down both sides across roughly 40% of
	# the width, which read as an unfinished application. COVERED fills the screen and crops
	# the overflow, which is what a backdrop is for. Found by looking at a real capture; no
	# assertion could see it.
	scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.visible = scene.texture != null
	add_child(scene)

	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = UITheme.vignette_gradient()
	vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	_build_corner_ornaments()


## Four corner ornaments framing the screen. Uses `key_badge.png` for what D-034 measured it
## to actually be — a hollow CORNER ORNAMENT (centre alpha 0), not the keycap Phase 06 had
## pressed it into service as. Each copy is flipped so the piece points outward.
func _build_corner_ornaments() -> void:
	var tex := UITheme.corner_ornament()
	if tex == null:
		return
	var corners := [
		{"name": "OrnamentTL", "preset": Control.PRESET_TOP_LEFT, "h": false, "v": false},
		{"name": "OrnamentTR", "preset": Control.PRESET_TOP_RIGHT, "h": true, "v": false},
		{"name": "OrnamentBL", "preset": Control.PRESET_BOTTOM_LEFT, "h": false, "v": true},
		{"name": "OrnamentBR", "preset": Control.PRESET_BOTTOM_RIGHT, "h": true, "v": true},
	]
	for corner in corners:
		var piece := TextureRect.new()
		piece.name = String(corner["name"])
		piece.texture = tex
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# EXPAND_IGNORE_SIZE or the rect reports the whole 61x61 texture as its minimum and
		# `custom_minimum_size` silently does nothing (D-034 / L-021).
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		piece.custom_minimum_size = Vector2(UIPalette.ORNAMENT_PX, UIPalette.ORNAMENT_PX)
		piece.size = Vector2(UIPalette.ORNAMENT_PX, UIPalette.ORNAMENT_PX)
		piece.flip_h = bool(corner["h"])
		piece.flip_v = bool(corner["v"])
		piece.modulate = UIPalette.COLOR_ORNAMENT
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.set_anchors_preset(int(corner["preset"]) as Control.LayoutPreset)
		piece.offset_left = UIPalette.HUD_MARGIN if not bool(corner["h"]) \
			else -(UIPalette.ORNAMENT_PX + UIPalette.HUD_MARGIN)
		piece.offset_top = UIPalette.HUD_MARGIN if not bool(corner["v"]) \
			else -(UIPalette.ORNAMENT_PX + UIPalette.HUD_MARGIN)
		piece.offset_right = piece.offset_left + UIPalette.ORNAMENT_PX
		piece.offset_bottom = piece.offset_top + UIPalette.ORNAMENT_PX
		add_child(piece)


## A uniformly sized menu button (so the column lines up) wearing the shared theme, with its
## semantic ROLE applied centrally (`UITheme.role_*`) — this screen names no colour.
func _make_menu_button(role: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(
		UIPalette.MENU_BUTTON_WIDTH, UIPalette.BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	# The button plate is PAINTED art (D-044), so it is filtered LINEAR like the backdrop —
	# nearest would stair-step its gold filigree at this non-integer scale.
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.add_theme_color_override("font_color", UITheme.role_font_color(role))
	button.self_modulate = UITheme.role_modulate(role)
	# Hover lifts the role tint rather than swapping the texture, so the authored pixel art
	# is never replaced — only modulated (A14).
	button.mouse_entered.connect(_on_button_hover.bind(button, role, true))
	button.mouse_exited.connect(_on_button_hover.bind(button, role, false))
	button.focus_entered.connect(_on_button_hover.bind(button, role, true))
	button.focus_exited.connect(_on_button_hover.bind(button, role, false))
	return button


func _on_button_hover(button: Button, role: String, active: bool) -> void:
	if not is_instance_valid(button):
		return
	button.self_modulate = UITheme.role_modulate(role, active)


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


func _on_settings() -> void:
	settings_pressed.emit()


func _on_quit() -> void:
	quit_pressed.emit()


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()

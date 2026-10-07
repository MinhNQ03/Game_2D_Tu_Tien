extends RefCounted
class_name UITheme
## UITheme — Aetheria presentation (asset-backed foundation theme builder).
##
## Builds a Godot `Theme` from the ORIGINAL ink-lacquer UI kit (`UIPalette.TEX_*`, D-062 —
## generated from the Visual DNA by `tools/aetheria_art_pipeline/ui/ui_kit.py`) so every screen
## shares ONE look: a designed 9-slice plate per button state, the lacquer plaque, the quiet
## band, the keycap, material meters, icon slots and tintable ornament masks. The theme is built
## in CODE (not a hand-authored `.tres`) to match the project's code-built UI convention and stay
## unit-testable headless.
##
## Presentation-only: it reads tokens + textures and returns resources. It owns no gameplay
## state. A restyle re-runs the kit generator (or swaps `UIPalette.UI_ASSET_DIR`) without
## touching any call site. If a texture fails to load (e.g. a stripped build), each builder
## FALLS BACK to a flat `StyleBoxFlat` so the UI degrades gracefully rather than crashing — the
## asset-contract test guards that the real textures exist.

# --- Semantic button roles (D-041) -------------------------------------------
#
# Not every action deserves the same weight. The roles are declared HERE, centrally, so a
# screen asks for a role and never tints a button itself — `main_menu.gd` must not contain a
# colour (`04-coding-standards.md` no magic numbers; A4).

## The principal action on a screen (New Game). Warm gold lift.
const ROLE_PRIMARY := "primary"
## Ordinary actions (Load, Settings). The plate exactly as drawn.
const ROLE_SECONDARY := "secondary"
## Leaving / destroying (Quit). Crimson label — reserved, never decorative.
const ROLE_DANGER := "danger"

## Metadata key the role is stored under on a button built by `menu_button`.
const ROLE_META := &"ui_role"

## The button plate for each state: five DESIGNED textures, not one plate tinted five ways.
const BUTTON_TEXTURES := {
	"normal": UIPalette.TEX_BUTTON_NORMAL,
	"hover": UIPalette.TEX_BUTTON_HOVER,
	"focus": UIPalette.TEX_BUTTON_FOCUS,
	"pressed": UIPalette.TEX_BUTTON_PRESSED,
	"disabled": UIPalette.TEX_BUTTON_DISABLED,
}

## A meter's value text: the smallest size it may shrink to, and its inset from the ends.
const METER_TEXT_MIN_SIZE := 11
const METER_TEXT_PAD := 4

## Per-role modulation applied to the button plate. `Color(1,1,1)` means "leave the art
## exactly as drawn", which is why SECONDARY is the untinted baseline.
##
## The tints are RESTRAINED: the plate is dark lacquer under a gold hairline, and a strong tint
## would turn lacquer into coloured plastic. PRIMARY warms the gold a little, DANGER darkens and
## warms slightly, and the real danger signal is the crimson LABEL (`role_font_color`) plus the
## word itself — colour is never the only carrier of meaning (`UI_UX_BIBLE.md` §4).
static func role_modulate(role: String, hovered: bool = false) -> Color:
	match role:
		ROLE_PRIMARY:
			return Color(1.12, 1.06, 0.92) if hovered else Color(1.06, 1.02, 0.92)
		ROLE_DANGER:
			return Color(1.0, 0.88, 0.86) if hovered else Color(0.92, 0.82, 0.80)
		_:
			return Color(1.08, 1.08, 1.08) if hovered else Color(1.0, 1.0, 1.0)


## Font colour for a role's label, so the primary action also reads strongest in text.
static func role_font_color(role: String) -> Color:
	match role:
		ROLE_PRIMARY:
			return UIPalette.COLOR_TITLE
		ROLE_DANGER:
			return UIPalette.COLOR_CRIMSON_HOVER
		_:
			return UIPalette.COLOR_TEXT


## THE composed screen backdrop, built into `parent` (D-041 A2/A7, centralised in D-050).
##
## A deep ink ground, a vertical gradient that gives the screen a horizon, the painted scene,
## a restrained radial vignette, and four corner frets. Before the composition existed a screen
## was a small plaque on a flat near-black fill, which read as a Godot Control floating in a
## void. It lives HERE so the settings screen and the menu cannot diverge (B6/B7).
##
## Built from code-generated gradients plus existing textures; no per-frame cost — a
## `GradientTexture2D` rasterises once and is then a static draw. It carries no gameplay (A7).
## Every layer ignores the mouse so none of them can eat a click meant for the screen.
static func build_backdrop(parent: Control) -> void:
	var fill := ColorRect.new()
	fill.name = "Background"
	fill.color = UIPalette.COLOR_BACKGROUND_DEEP
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fill)

	var sky := TextureRect.new()
	sky.name = "BackdropGradient"
	sky.texture = backdrop_gradient()
	# A smooth ramp: the one UI texture that must NOT be nearest-filtered (banding).
	sky.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sky)

	# The painted scene — COVERED, not CENTERED (D-050): centring a portrait-ish painting on a
	# 16:9 screen left hard black bars down both sides. `menu_backdrop()` also crops the
	# painting's own flat dead left margin, which COVERED would stretch into a dark bar.
	var scene := TextureRect.new()
	scene.name = "BackdropScene"
	scene.texture = menu_backdrop()
	# LINEAR: this is PAINTED art, not pixel art.
	scene.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.visible = scene.texture != null
	parent.add_child(scene)

	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = vignette_gradient()
	vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vignette)

	_build_corner_ornaments(parent)


## Four corner frets framing a full screen: the kit's hollow fretwork corner (a white mask
## tinted with `COLOR_ORNAMENT`), each copy flipped so the hook points outward.
static func _build_corner_ornaments(parent: Control) -> void:
	var tex := corner_ornament()
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
		# EXPAND_IGNORE_SIZE or the rect reports its whole texture as its minimum and
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
		parent.add_child(piece)


## THE vitals gauge (Phase 09). A styled `ProgressBar` with a centred value Label inside it.
##
## One shared seam so the next gauge (a boss bar) inherits the same look instead of being
## styled again by whoever adds it (C18). THE NUMBER IS ALWAYS WRITTEN, not only drawn
## (`docs/UI_UX_BIBLE.md` §4): colour is never the only carrier of meaning.
static func vitals_gauge() -> ProgressBar:
	return _meter("VitalsGauge", UIPalette.GAUGE_HEIGHT, UIPalette.GAUGE_FILL)


## THE XP meter (Phase 11): the same construction as the vitals gauge, deliberately
## UNMISTAKABLE from it — gold instead of jade. What differs is only hue and weight, and both
## are palette tokens.
static func xp_meter() -> ProgressBar:
	return _meter("XpMeter", UIPalette.XP_METER_HEIGHT, UIPalette.XP_METER_FILL)


## The linh khí bar of the skill dock (Phase 15): thin, unlabelled (the dock is read at a glance;
## the slots dim when a cast is unaffordable), the qi hue.
static func qi_bar(height: int, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "QiBar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _gauge_well_stylebox())
	bar.add_theme_stylebox_override("fill", _gauge_fill_stylebox(fill))
	return bar


## The tu vi meter (Phase 12): the same construction as the XP meter, its own hue.
static func cultivation_meter() -> ProgressBar:
	return _meter("CultivationMeter", UIPalette.XP_METER_HEIGHT, UIPalette.CULTIVATION_METER_FILL)


## Push a value into a meter built by `cultivation_meter()`: the bar, its text and its fill (gold
## when a breakthrough is ready), in ONE call so they cannot disagree.
static func set_cultivation_meter_value(
		bar: ProgressBar, into: int, cost: int, ready: bool, text: String) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	var label := bar.get_node_or_null("Value") as Label
	if label != null:
		label.text = text
		fit_meter_text(bar)
	bar.max_value = float(maxi(1, cost))
	bar.value = float(clampi(into, 0, maxi(1, cost))) if cost > 0 else 1.0
	bar.add_theme_stylebox_override("fill", _gauge_fill_stylebox(
		UIPalette.CULTIVATION_METER_FILL_READY if ready else UIPalette.CULTIVATION_METER_FILL))


## Shared meter construction: a styled `ProgressBar` with a centred value Label inside it.
static func _meter(meter_name: String, height: int, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = meter_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.add_theme_stylebox_override("background", _gauge_well_stylebox())
	bar.add_theme_stylebox_override("fill", _gauge_fill_stylebox(fill))

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	value_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A `ProgressBar` is not a container, so the label is anchored over it rather than laid
	# out by it. FULL_RECT with offsets, not `set_anchors_preset` (L-028).
	value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The text never leaves its gauge: clipped as a last guard, and shrunk to fit first (a
	# long realm name in one language spilled over the plaque's edge — capture review, D-062).
	value_label.clip_text = true
	bar.add_child(value_label)
	bar.resized.connect(func() -> void: fit_meter_text(bar))
	return bar


## Fit a meter's value text to the meter: the hint size if it fits, one step smaller at a time
## down to METER_TEXT_MIN_SIZE. Measured with the label's own font, so it holds per language.
static func fit_meter_text(bar: ProgressBar) -> void:
	var label := bar.get_node_or_null("Value") as Label if is_instance_valid(bar) else null
	if label == null or bar.size.x <= 0.0:
		return
	var font := label.get_theme_font("font")
	var room := bar.size.x - float(METER_TEXT_PAD * 2)
	var size := UIPalette.FONT_SIZE_HINT
	while size > METER_TEXT_MIN_SIZE and font != null \
			and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	label.add_theme_font_size_override("font_size", size)


## Push a value into a gauge built by `vitals_gauge()`: the bar, the text, and the critical
## fill colour, together — ONE call, because a gauge whose bar and number disagree is worse than
## either alone.
static func set_gauge_value(bar: ProgressBar, current: int, maximum: int) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	var safe_max: int = maxi(1, maximum)
	var safe_current: int = clampi(current, 0, safe_max)
	bar.max_value = float(safe_max)
	bar.value = float(safe_current)
	var label := bar.get_node_or_null("Value") as Label
	if label != null:
		label.text = "%d / %d" % [safe_current, safe_max]
		fit_meter_text(bar)
	var fraction := float(safe_current) / float(safe_max)
	var fill: Color = UIPalette.GAUGE_FILL_LOW if fraction <= UIPalette.GAUGE_LOW_FRACTION \
		else UIPalette.GAUGE_FILL
	bar.add_theme_stylebox_override("fill", _gauge_fill_stylebox(fill))


## The semantic colour a meter's fill shows, whatever box draws it (the kit's material mask is
## tinted by `modulate_color`; the flat fallback carries `bg_color`). The one way a test or a
## screen asks "what colour is this bar", so neither depends on how the bar is drawn.
static func fill_color(box: StyleBox) -> Color:
	if box is StyleBoxTexture:
		return (box as StyleBoxTexture).modulate_color
	if box is StyleBoxFlat:
		return (box as StyleBoxFlat).bg_color
	return Color(0, 0, 0, 0)


## The gauge's empty well: the kit's inset ink channel (a shadow under the rim, a lit lower
## lip, a gold-in-shadow edge), so an empty gauge reads as a carved channel in its plaque.
static func _gauge_well_stylebox() -> StyleBox:
	var box := _texture_box(UIPalette.TEX_GAUGE_WELL, UIPalette.GAUGE_WELL_SLICE, 0, 0)
	if box != null:
		return box
	var flat := StyleBoxFlat.new()
	flat.bg_color = UIPalette.COLOR_BACKGROUND_DEEP
	flat.border_color = UIPalette.COLOR_ORNAMENT
	flat.set_border_width_all(1)
	return flat


## A meter's fill: the kit's WHITE material mask multiplied by the meter's semantic colour, so
## every meter shares one material (catch-light, body, darker base) and differs only in hue —
## a palette token, never new art.
static func _gauge_fill_stylebox(fill: Color) -> StyleBox:
	var box := _texture_box(UIPalette.TEX_GAUGE_FILL, UIPalette.GAUGE_FILL_SLICE, 0, 0)
	if box != null:
		box.modulate_color = fill
		return box
	var flat := StyleBoxFlat.new()
	flat.bg_color = fill
	return flat


## Push a value into an XP meter built by `xp_meter()`: the bar, the text and the ceiling
## colour, together. `at_ceiling` is explicit because at the top of the authored curve BOTH
## numbers are 0; a maxed meter shows FULL in the jade "nothing left to earn" fill. `text`
## arrives ALREADY LOCALIZED — string resolution stays with the screen (`07-localization.md`).
static func set_xp_meter_value(
		bar: ProgressBar, into: int, cost: int, at_ceiling: bool, text: String = "") -> void:
	if bar == null or not is_instance_valid(bar):
		return
	var label := bar.get_node_or_null("Value") as Label
	if label != null:
		label.text = text
		fit_meter_text(bar)
	if at_ceiling or cost <= 0:
		bar.max_value = 1.0
		bar.value = 1.0
		bar.add_theme_stylebox_override(
			"fill", _gauge_fill_stylebox(UIPalette.XP_METER_FILL_COMPLETE))
		return
	var safe_into: int = clampi(into, 0, cost)
	bar.max_value = float(cost)
	bar.value = float(safe_into)
	bar.add_theme_stylebox_override("fill", _gauge_fill_stylebox(UIPalette.XP_METER_FILL))


## THE scrolling body of a bounded side panel. Returns the `VBoxContainer` rows go into.
##
## One factory because both side panels built this identically — and had the same defect: the
## vertical scrollbar drawn OVER the content. The gutter below reserves its width once.
static func scroll_body(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollBody"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Explicit STOP: the ONE node in the subtree that must receive input (L-028).
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(scroll)

	var gutter := MarginContainer.new()
	gutter.name = "ScrollGutter"
	gutter.add_theme_constant_override("margin_right", UIPalette.SCROLLBAR_GUTTER)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(gutter)

	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(box)
	return box


## THE menu button. One factory for every full-width menu action, in any screen (D-050). The
## hover/focus lift is wired HERE, so a new screen gets the interaction states for free (A14).
static func menu_button(role: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(
		UIPalette.MENU_BUTTON_WIDTH, UIPalette.BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	# The plate is PIXEL art (the ink kit): nearest, so the hairline stays one crisp pixel.
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	apply_button_role(button, role)
	# The role is read from the button at hover time, NOT bound into the callable: a role can
	# change after construction (the settings screen promotes the active language).
	for signal_name in ["mouse_entered", "focus_entered"]:
		button.connect(signal_name, _on_role_button_lift.bind(button, true))
	for signal_name in ["mouse_exited", "focus_exited"]:
		button.connect(signal_name, _on_role_button_lift.bind(button, false))
	return button


## Re-apply a role to an existing button, and remember it on the button.
static func apply_button_role(button: Button, role: String) -> void:
	button.set_meta(ROLE_META, role)
	button.add_theme_color_override("font_color", role_font_color(role))
	button.self_modulate = role_modulate(role)


## The role a `menu_button` is currently wearing (SECONDARY for anything not built here).
static func button_role(button: Button) -> String:
	return String(button.get_meta(ROLE_META, ROLE_SECONDARY))


static func _on_role_button_lift(button: Button, active: bool) -> void:
	if not is_instance_valid(button):
		return
	button.self_modulate = role_modulate(button_role(button), active)


## Build the shared foundation Theme. Styles base `Button` + `Label` + `PanelContainer` so any
## control under a node with this theme inherits the asset-backed look.
static func build() -> Theme:
	var theme := Theme.new()

	# --- Button: one DESIGNED 9-slice texture per state ----------------------
	for state in BUTTON_TEXTURES:
		theme.set_stylebox(state, "Button", button_stylebox(state))
	theme.set_color("font_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_color("font_pressed_color", "Button", UIPalette.COLOR_ACCENT)
	theme.set_color("font_disabled_color", "Button", UIPalette.COLOR_TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_font_size("font_size", "Button", UIPalette.FONT_SIZE_BUTTON)
	theme.set_constant("h_separation", "Button", UIPalette.SPACE_SM)

	# --- Label --------------------------------------------------------------
	# The outline is what makes the light text tokens survive a busy background (map art).
	theme.set_color("font_color", "Label", UIPalette.COLOR_TEXT)
	theme.set_font_size("font_size", "Label", UIPalette.FONT_SIZE_BODY)
	theme.set_color("font_outline_color", "Label", UIPalette.COLOR_TEXT_OUTLINE)
	theme.set_constant("outline_size", "Label", UIPalette.TEXT_OUTLINE_SIZE)
	theme.set_color("font_outline_color", "Button", UIPalette.COLOR_TEXT_OUTLINE)
	theme.set_constant("outline_size", "Button", UIPalette.TEXT_OUTLINE_SIZE)

	# --- PanelContainer: the lacquer plaque ---------------------------------
	theme.set_stylebox("panel", "PanelContainer", panel_stylebox())

	return theme


## Button StyleBox for a given state ("normal"/"hover"/"pressed"/"disabled"/"focus").
##
## FIVE DESIGNED PLATES (D-062, aetheria_style.yaml `ui.states`). Hover lifts the lacquer,
## brightens the gold and draws a jade underline ("this will act"); focus is a jade inner ring
## with corner ticks drawn OVER the normal plate, so it reads with the keyboard alone; pressed
## SINKS (an inner shadow, gold in shadow, the label 1px down); disabled desaturates the plate
## and greys the line while the label stays legible. Every plate measures DARK at its centre,
## so the light text palette stays legal on it (pinned by the theme test).
static func button_stylebox(state: String) -> StyleBox:
	var path: String = BUTTON_TEXTURES.get(state, UIPalette.TEX_BUTTON_NORMAL)
	var pad_h := UIPalette.BUTTON_PAD_H
	var pad_v := UIPalette.BUTTON_PAD_V
	if state == "focus":
		# The focus box sits over the normal one, so it must not add padding of its own.
		pad_h = UIPalette.BUTTON_SLICE_H
		pad_v = UIPalette.BUTTON_SLICE_V
	var box := _texture_box(path, UIPalette.BUTTON_SLICE_H, pad_h, pad_v)
	if box == null:
		return _fallback_button_flat(state)
	box.texture_margin_top = UIPalette.BUTTON_SLICE_V
	box.texture_margin_bottom = UIPalette.BUTTON_SLICE_V
	if state == "pressed":
		box.content_margin_top = pad_v + 1
		box.content_margin_bottom = pad_v - 1
	box.modulate_color = state_modulate(state)
	return box


## Per-state modulation. The five states are DRAWN differently, so no state needs a tint to be
## told apart; the only one left is the disabled plate's reduced presence. Never above 1, so no
## state can brighten a plate past the light-surface limit.
static func state_modulate(state: String) -> Color:
	if state == "disabled":
		return Color(1.0, 1.0, 1.0, 0.85)
	return Color(1.0, 1.0, 1.0)


## The framed panel StyleBox — the surface that CARRIES TEXT (menu panel, HUD plaques, side
## panels): the kit's lacquer plaque. Its centre measures dark (light text is legal on it) and
## its content margins clear the 9-slice band, so text never sits on the gold hairline.
static func panel_stylebox() -> StyleBox:
	var box := _texture_box(UIPalette.TEX_PLAQUE, UIPalette.PLAQUE_MARGIN,
		UIPalette.PLAQUE_MARGIN + 2, UIPalette.PLAQUE_MARGIN)
	if box != null:
		return box
	return _fallback_surface_flat(UIPalette.COLOR_SURFACE)


## The quiet HINT BAND behind passive prompts (D-057 — the HUD weight ladder): the kit's band,
## a lacquer wash with NO frame that fades toward the playfield, a faint gold line above and
## below fading with it.
##
## Ornament is how this UI says "this matters": the plaque marks who the player is, where they
## are and what they are fighting. A row of key hints is the least important text on screen, so
## it gets the least weight that still keeps it legible: its solid end sits under the text and
## the fade hands the rest back to the world. `fade_right`: the band hangs off the LEFT edge.
static func hint_band_stylebox(fade_right: bool = true) -> StyleBox:
	var path := UIPalette.TEX_BAND_RIGHT if fade_right else UIPalette.TEX_BAND_LEFT
	var box := _texture_box(path, UIPalette.BAND_V_MARGIN, UIPalette.SPACE_MD, UIPalette.SPACE_SM)
	if box == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = UIPalette.HINT_BAND_COLOR
		flat.content_margin_left = UIPalette.SPACE_MD
		flat.content_margin_right = UIPalette.SPACE_MD
		flat.content_margin_top = UIPalette.SPACE_SM
		flat.content_margin_bottom = UIPalette.SPACE_SM
		return flat
	var solid := UIPalette.BAND_SOLID_MARGIN
	var fade := UIPalette.BAND_FADE_MARGIN
	box.texture_margin_left = solid if fade_right else fade
	box.texture_margin_right = fade if fade_right else solid
	# The text keeps to the SOLID part: the fade is where the band hands back to the world.
	var half_fade := fade * 0.5
	box.content_margin_left = float(UIPalette.SPACE_MD) if fade_right else half_fade
	box.content_margin_right = half_fade if fade_right else float(UIPalette.SPACE_MD)
	return box


## A darker nested well inside a panel (secondary surface, e.g. a settings option list): the
## same plaque, sunk one step.
static func inset_stylebox() -> StyleBox:
	var box := _texture_box(UIPalette.TEX_PLAQUE, UIPalette.PLAQUE_MARGIN,
		UIPalette.PLAQUE_MARGIN, UIPalette.SPACE_MD)
	if box != null:
		box.modulate_color = Color(0.78, 0.80, 0.84)
		return box
	return _fallback_surface_flat(UIPalette.COLOR_SURFACE_PRESSED)


## StyleBox for the key badge (the "E"/"Esc" keycap): the kit's raised lacquer cap with a jade
## edge. Opaque under the glyph (a keycap needs a solid face); the lip is never stretched.
## `compact`: the keycap that sits ON something (a dock slot's corner) — the same cap, tighter
## padding, so it marks the corner instead of covering the icon.
static func badge_stylebox(compact: bool = false) -> StyleBox:
	var pad_h := 4 if compact else UIPalette.SPACE_SM
	var pad_v := 0 if compact else 2
	var box := _texture_box(UIPalette.TEX_KEYCAP, UIPalette.KEYCAP_SLICE, pad_h, pad_v)
	if box == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = UIPalette.COLOR_BADGE
		flat.border_color = UIPalette.COLOR_BADGE_BORDER
		flat.set_border_width_all(1)
		return flat
	box.texture_margin_bottom = UIPalette.KEYCAP_LIP
	box.content_margin_bottom = UIPalette.KEYCAP_LIP - (5 if compact else 2)
	return box


## An icon slot (skill, item, equipment — one family, aetheria_style.yaml §7): the element's
## ring when the thing in it has an element, the plain slot otherwise.
static func slot_texture(element: StringName = &"") -> Texture2D:
	var path: String = UIPalette.TEX_SLOT_BY_ELEMENT.get(element, UIPalette.TEX_SLOT)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## THE icon slot: the kit's slot frame with the icon centred in its well, drawn 1:1. One
## factory for every icon in the UI — the satchel's items, the dock's techniques, a worn piece —
## so they are one family by construction (aetheria_style.yaml §7). The children are NAMED
## ("Frame", "Icon") so a screen can re-skin them (`set_icon_slot`) without rebuilding.
static func icon_slot(icon: Texture2D = null, element: StringName = &"") -> Control:
	var slot := Control.new()
	slot.name = "IconSlot"
	slot.custom_minimum_size = Vector2(UIPalette.SLOT_PX, UIPalette.SLOT_PX)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := TextureRect.new()
	frame.name = "Frame"
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(frame)
	var image := TextureRect.new()
	image.name = "Icon"
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(image)
	set_icon_slot(slot, icon, element)
	return slot


## Re-skin a slot built by `icon_slot`: its icon and its element ring.
static func set_icon_slot(slot: Control, icon: Texture2D, element: StringName = &"") -> void:
	(slot.get_node("Frame") as TextureRect).texture = slot_texture(element)
	(slot.get_node("Icon") as TextureRect).texture = icon


# --- Menu backdrop (D-041) ---------------------------------------------------

## Vertical ink gradient for the menu ground: a lifted blue band above, sinking to the deep
## ground below. This single texture is what gives the composition a horizon.
static func backdrop_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, UIPalette.COLOR_BACKDROP_HIGH)
	gradient.set_color(1, UIPalette.COLOR_BACKDROP_LOW)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 16
	tex.height = 256
	return tex


## Radial vignette drawn over the backdrop: transparent at the centre, ink at the edges.
static func vignette_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	gradient.set_color(1, UIPalette.COLOR_VIGNETTE)
	# A late ramp: the darkening should only bite near the edge.
	gradient.add_point(0.62, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


## The decorative corner fret texture (a hollow white mask), or null if absent.
static func corner_ornament() -> Texture2D:
	if not ResourceLoader.exists(UIPalette.TEX_CORNER_FRET):
		return null
	return load(UIPalette.TEX_CORNER_FRET) as Texture2D


## THE ornamental divider. One factory, consumed by every screen that needs a rule (D-050):
## the kit's white mask (a 1px rule fading at both ends, a diamond knot at the centre) tinted
## with `GOLD_SECONDARY`, so changing every divider in the game is one constant here.
##
## `width_fills` makes the rule span its parent (a panel header); false keeps its natural width.
static func ornament_divider(width_fills: bool = true) -> TextureRect:
	var strip := TextureRect.new()
	strip.name = "OrnamentDivider"
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.custom_minimum_size = Vector2(0, UIPalette.ORNAMENT_DIVIDER_HEIGHT)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width_fills \
		else Control.SIZE_SHRINK_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.modulate = UIPalette.GOLD_SECONDARY
	if ResourceLoader.exists(UIPalette.TEX_ORNAMENT_DIVIDER):
		strip.texture = load(UIPalette.TEX_ORNAMENT_DIVIDER)
	return strip


## The hollow 9-slice frame (notched corners, centre alpha 0) drawn AROUND something — never a
## text surface of its own. Tinted gold from one constant.
static func ornament_frame() -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.name = "OrnamentFrame"
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var margin := UIPalette.ORNAMENT_FRAME_MARGIN
	frame.patch_margin_left = margin
	frame.patch_margin_right = margin
	frame.patch_margin_top = margin
	frame.patch_margin_bottom = margin
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.modulate = UIPalette.GOLD_PRIMARY
	if ResourceLoader.exists(UIPalette.TEX_ORNAMENT_FRAME):
		frame.texture = load(UIPalette.TEX_ORNAMENT_FRAME)
	return frame


## The painted menu backdrop scene, cropped past its flat dead left margin, or null if absent.
static func menu_backdrop() -> Texture2D:
	if not ResourceLoader.exists(UIPalette.TEX_MENU_BACKDROP):
		return null
	var source := load(UIPalette.TEX_MENU_BACKDROP) as Texture2D
	if source == null:
		return null
	# An `AtlasTexture`: a view onto the same texture, not a second copy in memory.
	var dead := float(UIPalette.MENU_BACKDROP_DEAD_LEFT_PX)
	if dead <= 0.0 or dead >= float(source.get_width()):
		return source
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(
		dead, 0.0, float(source.get_width()) - dead, float(source.get_height()))
	return atlas


## The identity medallion: the actor's pixel portrait in its lacquer disc under the gold ring
## (D-062). Rendered by the art pipeline from the SAME model as the sprite, so the face in the
## HUD is the figure on the map. `female` picks Lâm Nguyệt's. Null when the art is missing, so
## the HUD keeps an empty well instead of a broken texture.
static func portrait_texture(female: bool = false) -> Texture2D:
	var path := UIPalette.TEX_MEDALLION_FEMALE if female else UIPalette.TEX_MEDALLION_PLAYER
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## True once every UI texture resolves (used by the asset-contract test + a startup guard).
static func textures_present() -> bool:
	for path in UIPalette.UI_TEXTURES:
		if not ResourceLoader.exists(path):
			return false
	return true


# --- Builders ----------------------------------------------------------------

## Load `tex_path` into a `StyleBoxTexture` with a uniform 9-slice `margin` (so corners stay
## crisp) and content margins (`pad_h`/`pad_v`, the text inset). Returns null if the texture
## can't be loaded, so the caller can fall back.
static func _texture_box(tex_path: String, margin: int, pad_h: int, pad_v: int) -> StyleBoxTexture:
	if not ResourceLoader.exists(tex_path):
		return null
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return null
	var box := StyleBoxTexture.new()
	box.texture = tex
	box.texture_margin_left = margin
	box.texture_margin_right = margin
	box.texture_margin_top = margin
	box.texture_margin_bottom = margin
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	return box


## Flat fallback for a button state (texture missing) — keeps distinct states.
static func _fallback_button_flat(state: String) -> StyleBoxFlat:
	var fill := UIPalette.COLOR_SURFACE
	match state:
		"hover":
			fill = UIPalette.COLOR_SURFACE_HOVER
		"pressed":
			fill = UIPalette.COLOR_SURFACE_PRESSED
		"disabled":
			fill = UIPalette.COLOR_SURFACE_DISABLED
		"focus":
			var ring := StyleBoxFlat.new()
			ring.bg_color = Color(0, 0, 0, 0)
			ring.border_width_left = UIPalette.FOCUS_BORDER
			ring.border_width_right = UIPalette.FOCUS_BORDER
			ring.border_width_top = UIPalette.FOCUS_BORDER
			ring.border_width_bottom = UIPalette.FOCUS_BORDER
			ring.border_color = UIPalette.COLOR_ACCENT
			return ring
	return _fallback_surface_flat(fill)


static func _fallback_surface_flat(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.corner_radius_top_left = UIPalette.CORNER_RADIUS
	box.corner_radius_top_right = UIPalette.CORNER_RADIUS
	box.corner_radius_bottom_left = UIPalette.CORNER_RADIUS
	box.corner_radius_bottom_right = UIPalette.CORNER_RADIUS
	box.content_margin_left = UIPalette.BUTTON_PAD_H
	box.content_margin_right = UIPalette.BUTTON_PAD_H
	box.content_margin_top = UIPalette.BUTTON_PAD_V
	box.content_margin_bottom = UIPalette.BUTTON_PAD_V
	return box

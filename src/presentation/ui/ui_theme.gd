extends RefCounted
class_name UITheme
## UITheme — Aetheria presentation (asset-backed foundation theme builder).
##
## Builds a Godot `Theme` from the CC0 Xianxia Pixel Pack UI textures (`UIPalette.TEX_*`,
## D-028; recorded in `docs/ASSET_LICENSES.md`) so the main menu and HUD share ONE consistent
## look — 9-slice framed buttons with distinct normal/hover/pressed/focus/disabled states,
## framed panels, and a key-badge chip. The theme is built in CODE (not a hand-authored
## `.tres`) to match the project's code-built UI convention and stay unit-testable headless.
##
## Presentation-only: it reads tokens + textures and returns resources. It owns no gameplay
## state. A later art pass swaps the texture files (or the whole `UIPalette.UI_ASSET_DIR`)
## without touching any call site. If a texture fails to load (e.g. a stripped build), each
## builder FALLS BACK to a flat `StyleBoxFlat` so the UI degrades gracefully rather than
## crashing — the asset-contract test guards that the real textures exist.

# --- Semantic button roles (D-041) -------------------------------------------
#
# Not every action deserves the same weight. The roles are declared HERE, centrally, so a
# screen asks for a role and never tints a button itself — `main_menu.gd` must not contain a
# colour (`04-coding-standards.md` no magic numbers; A4).
#
# The roles reuse the SAME xianxia textures and differ only by a central modulation, so the
# pixel art is never replaced or distorted — only tinted (A1/A14).

## The principal action on a screen (New Game). Warm gold lift.
const ROLE_PRIMARY := "primary"
## Ordinary actions (Load, Settings). The texture's own jade tone, untinted.
const ROLE_SECONDARY := "secondary"
## Leaving / destroying (Quit). Crimson — reserved, never decorative.
const ROLE_DANGER := "danger"

## Metadata key the role is stored under on a button built by `menu_button`.
const ROLE_META := &"ui_role"

## Per-role modulation applied to the button plate. `Color(1,1,1)` means "leave the art
## exactly as authored", which is why SECONDARY is the untinted baseline.
##
## The tints are RESTRAINED on purpose since D-044 put a painted teal plate underneath: a
## strong red DANGER tint multiplied against teal produces muddy brown, not "careful". So
## DANGER only darkens and warms slightly, and the actual danger signal is carried by the
## crimson LABEL (`role_font_color`) plus the word itself — which also satisfies the rule that
## colour is never the only carrier of meaning (`UI_UX_BIBLE.md` §4).
static func role_modulate(role: String, hovered: bool = false) -> Color:
	match role:
		ROLE_PRIMARY:
			return Color(1.16, 1.06, 0.84) if hovered else Color(1.06, 0.99, 0.82)
		ROLE_DANGER:
			return Color(1.02, 0.86, 0.84) if hovered else Color(0.92, 0.78, 0.76)
		_:
			return Color(1.10, 1.10, 1.10) if hovered else Color(1.0, 1.0, 1.0)


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
## a restrained radial vignette, and four corner ornaments. Before the composition existed a
## screen was a small plaque on a flat near-black fill, which read as a Godot Control floating
## in a void.
##
## It lives HERE, not in `main_menu.gd`, because it was in `main_menu.gd`: the settings screen
## is the only other full screen in the game and it had a flat `ColorRect` instead, since the
## composition was reachable only by copying sixty lines. The same reason the divider and the
## menu button are single factories (B6/B7).
##
## Built from code-generated gradients plus existing textures: no new asset, so no provenance
## question (`06-art-assets.md`), and no per-frame cost — a `GradientTexture2D` rasterises
## once and is then a static draw. It carries no gameplay: no collision, no player, no
## runtime, no state (A7). Every layer ignores the mouse so none of them can eat a click
## meant for the screen's controls.
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
	# The gradient is a smooth ramp, so it is the one UI texture that must NOT be nearest-
	# filtered: at 16x256 stretched full-screen, nearest would show visible banding steps.
	sky.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sky)

	# The painted scene (D-044) — what makes this a composed screen rather than a gradient.
	#
	# COVERED, not CENTERED (D-050). The painting is 310x330 — portrait-ish — so centring it
	# on a 16:9 screen left hard black bars down both sides across roughly 40% of the width,
	# which read as an unfinished application. COVERED fills the screen and crops the
	# overflow, which is what a backdrop is for. Found by looking at a real capture; no
	# assertion could see it. `menu_backdrop()` also crops the painting's own flat dead left
	# margin, which COVERED would otherwise stretch into an ~87px bar of near-black.
	var scene := TextureRect.new()
	scene.name = "BackdropScene"
	scene.texture = menu_backdrop()
	# LINEAR, not nearest: this is PAINTED art, not pixel art. Nearest would stair-step the
	# soft cloud gradients and the fine gold detail (`UIPalette` painted-tier note).
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


## Four corner ornaments framing the screen. Uses `key_badge.png` for what D-034 measured it
## to actually be — a hollow CORNER ORNAMENT (centre alpha 0), not the keycap Phase 06 had
## pressed it into service as. Each copy is flipped so the piece points outward.
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
		parent.add_child(piece)


## THE vitals gauge (Phase 09). A styled `ProgressBar` with a centred value Label inside it.
##
## The fifth shared seam, built for the same reason as the other four: the HUD must not style
## a gauge itself, or the next gauge (mana, cultivation progress, a boss bar) will be styled
## differently by whoever adds it — and C18 is explicit that combat UI uses this foundation
## rather than ad-hoc styling.
##
## THE NUMBER IS ALWAYS WRITTEN, not only drawn. `docs/UI_UX_BIBLE.md` §4: colour is never the
## only carrier of meaning, so a gauge carries its value as TEXT as well as a bar — which also
## covers the case where the bar is too short at low values to be read at all.
##
## `show_percentage` is off because a percentage is not what a player tracks in a fight; the
## absolute pair ("18 / 60") is, and it is what the label says.
static func vitals_gauge() -> ProgressBar:
	return _meter("VitalsGauge", UIPalette.GAUGE_HEIGHT, UIPalette.GAUGE_FILL)


## THE XP meter (Phase 11). The same construction as the vitals gauge, deliberately styled to
## be UNMISTAKABLE from it: gold instead of jade, and thinner.
##
## It shares `_meter()` rather than re-building a `ProgressBar` of its own, because duplicated
## styling is precisely how this project previously ended up with four hand-rolled dividers
## and one of them reading as a progress bar (D-050). What differs between the two meters is
## only what SHOULD differ — hue and weight — and both differences are palette tokens, so the
## distinction is one edit away rather than scattered through the HUD.
static func xp_meter() -> ProgressBar:
	return _meter("XpMeter", UIPalette.XP_METER_HEIGHT, UIPalette.XP_METER_FILL)


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
	# out by it. FULL_RECT with offsets, not `set_anchors_preset`, which preserves the current
	# 0x0 rect and would leave the label invisible (L-028).
	value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(value_label)
	return bar


## Push a value into a gauge built by `vitals_gauge()`: the bar, the text, and the critical
## fill colour, together.
##
## It is ONE call on purpose. Three separate updates is three chances to update two of them,
## and a gauge whose bar and number disagree is worse than either alone — the player cannot
## tell which one is lying.
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
	var fraction := float(safe_current) / float(safe_max)
	var fill: Color = UIPalette.GAUGE_FILL_LOW if fraction <= UIPalette.GAUGE_LOW_FRACTION \
		else UIPalette.GAUGE_FILL
	bar.add_theme_stylebox_override("fill", _gauge_fill_stylebox(fill))


## The gauge's empty well: the same dark ink the text surfaces use, so an empty gauge reads as
## part of its plaque rather than as a hole in it.
static func _gauge_well_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UIPalette.COLOR_BACKGROUND_DEEP
	box.border_color = UIPalette.COLOR_ORNAMENT
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	return box


static func _gauge_fill_stylebox(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(2)
	return box


## Push a value into an XP meter built by `xp_meter()`: the bar, the text and the ceiling
## colour, together — one call, for the same reason `set_gauge_value` is one call.
##
## `at_ceiling` is handled explicitly rather than inferred from `into >= cost`, because at the
## top of the authored curve BOTH numbers are 0 and the raw pair would render as "0 / 0" on a
## character who has earned everything there is. A maxed meter shows FULL and switches to the
## jade "nothing left to earn" fill, so it is visibly a different state from nearly-full.
##
## `text` arrives ALREADY LOCALIZED and already formatted. The theme writes it and does not
## build it: resolving a key here would put `Localization` behind a static style helper, and
## `07-localization.md` keeps string resolution with the screen that owns the strings. It is
## also what lets the label read "XP 20 / 45" in English and "KN 20 / 45" in Vietnamese
## without this function knowing either language exists.
static func set_xp_meter_value(
		bar: ProgressBar, into: int, cost: int, at_ceiling: bool, text: String = "") -> void:
	if bar == null or not is_instance_valid(bar):
		return
	var label := bar.get_node_or_null("Value") as Label
	if label != null:
		label.text = text
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
## One factory because both side panels built this identically — scroll mode, `follow_focus`,
## the `MOUSE_FILTER_STOP` that L-028 had to learn the hard way — and because they both had
## the same defect: the vertical scrollbar is drawn OVER the content, so a right-aligned value
## column ran underneath it and the last character of every number was obscured. The gutter
## below reserves the scrollbar's width once, for every panel that will ever have one.
static func scroll_body(parent: Control) -> VBoxContainer:
	# A bounded box means content must scroll rather than stretch the frame: content that
	# outgrows its frame pushes the 9-slice border off-screen, which is what made a side
	# panel render with no visible plate at all (L-028). `follow_focus` so keyboard
	# navigation cannot select a row that is scrolled out of sight.
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollBody"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Explicit STOP: a panel and its labels are MOUSE_FILTER_IGNORE for click-through, and
	# this is the ONE node in the subtree that must receive input — otherwise the wheel passes
	# straight through and clipped content becomes unreachable (L-028).
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(scroll)

	# The gutter that keeps the scrollbar off the text.
	var gutter := MarginContainer.new()
	gutter.name = "ScrollGutter"
	gutter.add_theme_constant_override("margin_right", UIPalette.SCROLLBAR_GUTTER)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(gutter)

	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	# Fill the scroll viewport's width so value rows and dividers span the panel instead of
	# shrink-wrapping their text.
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(box)
	return box


## THE menu button. One factory for every full-width menu action, in any screen (D-050).
##
## It replaces two divergent copies: `main_menu.gd` built a role-styled, palette-sized,
## LINEAR-filtered button with hover/focus lift, while `settings_menu.gd` built a bare
## `Button` at a hand-typed `Vector2(340, 0)` with no role at all — so the settings screen's
## three actions rendered as three identical untinted plates and the player could not tell the
## active language, the inactive one and "Back" apart by anything but their words. Same class
## of defect as the four hand-rolled dividers: duplicated construction let one screen quietly
## miss the design language.
##
## The hover/focus lift is wired HERE rather than in each screen, so a screen never has to
## remember the four signals, and a new screen gets the interaction states for free (A14).
static func menu_button(role: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(
		UIPalette.MENU_BUTTON_WIDTH, UIPalette.BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	# The plate is PAINTED art (D-044), so LINEAR — nearest would stair-step its gold
	# filigree at this non-integer scale.
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	apply_button_role(button, role)
	# The role is read from the button at hover time, NOT bound into the callable. A role can
	# change after construction (the settings screen promotes the active language to PRIMARY),
	# and a bound role would leave the hover lift tinting with the role the button used to
	# have — the hover state and the resting state would disagree.
	for signal_name in ["mouse_entered", "focus_entered"]:
		button.connect(signal_name, _on_role_button_lift.bind(button, true))
	for signal_name in ["mouse_exited", "focus_exited"]:
		button.connect(signal_name, _on_role_button_lift.bind(button, false))
	return button


## Re-apply a role to an existing button, and remember it on the button.
##
## Exists because a role can legitimately CHANGE at runtime: the settings screen promotes
## whichever language is active to PRIMARY, which is how "this is the one in use" is carried
## visually as well as in words.
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


## Build the shared foundation Theme. Styles base `Button` + `Label` so any Button/Label
## under a node with this theme inherits the asset-backed look.
static func build() -> Theme:
	var theme := Theme.new()

	# --- Button: a 9-slice texture per state (real visual distinction, not alpha tweaks) --
	theme.set_stylebox("normal", "Button", button_stylebox("normal"))
	theme.set_stylebox("hover", "Button", button_stylebox("hover"))
	theme.set_stylebox("pressed", "Button", button_stylebox("pressed"))
	theme.set_stylebox("disabled", "Button", button_stylebox("disabled"))
	theme.set_stylebox("focus", "Button", button_stylebox("focus"))
	theme.set_color("font_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_color("font_pressed_color", "Button", UIPalette.COLOR_ACCENT)
	theme.set_color("font_disabled_color", "Button", UIPalette.COLOR_TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_font_size("font_size", "Button", UIPalette.FONT_SIZE_BUTTON)
	theme.set_constant("h_separation", "Button", UIPalette.SPACE_SM)

	# --- Label --------------------------------------------------------------
	# The outline is what makes the light text tokens survive a busy background (map art,
	# a lighter plate). Call sites that override `font_color` still inherit it, so adding it
	# here fixes every existing label at once (D-034).
	theme.set_color("font_color", "Label", UIPalette.COLOR_TEXT)
	theme.set_font_size("font_size", "Label", UIPalette.FONT_SIZE_BODY)
	theme.set_color("font_outline_color", "Label", UIPalette.COLOR_TEXT_OUTLINE)
	theme.set_constant("outline_size", "Label", UIPalette.TEXT_OUTLINE_SIZE)

	# Buttons sit on the LIGHT jade button texture (measured brightness 193), so their text
	# needs the same outline treatment to stay readable.
	theme.set_color("font_outline_color", "Button", UIPalette.COLOR_TEXT_OUTLINE)
	theme.set_constant("outline_size", "Button", UIPalette.TEXT_OUTLINE_SIZE)

	# --- PanelContainer: the framed window/HUD panel ------------------------
	theme.set_stylebox("panel", "PanelContainer", panel_stylebox())

	return theme


## Button StyleBox for a given state name ("normal"/"hover"/"pressed"/"disabled"/"focus"),
## asset-backed with the 9-slice border margin + button inner padding.
## Button StyleBox for a given state name ("normal"/"hover"/"pressed"/"disabled"/"focus").
##
## Backed by the PAINTED jade plate (D-044), not the xianxia pixel-art button, and the reason
## is measured rather than aesthetic: `button_normal.png` has a centre brightness of **202**
## and `button_hover.png` **217**, against this project's own measured
## `SURFACE_LIGHT_BRIGHTNESS_LIMIT` of **120** — the threshold above which a surface must not
## carry the light-only text palette. D-034 found exactly this defect for panels and fixed it
## there (`panel.png` 231 -> the dark `panel_inset.png` at 15) but left the BUTTONS on the
## light plate, where only the text outline was holding legibility together. The painted plate
## measures **32** (29 as the raw crop, before the D-056 re-derivation), so this swap makes
## the button surface legal for the first time and removes the "bright plastic" read in one
## change.
##
## All five states come from ONE texture, differentiated by modulation in `role_modulate` and
## by the per-state tints here. Five separate painted files would have to stay in sync with
## each other through every future art pass; one plate plus arithmetic cannot drift.
static func button_stylebox(state: String) -> StyleBox:
	var box := _painted_button_box(state)
	if box != null:
		return box
	# Fallback (texture missing): a flat state box so the button still works.
	return _fallback_button_flat(state)


## The painted plate as a 9-slice box, or null if the art is absent.
##
## The ornate ENDS — the qi-swirl emblem on the left, the cloud motif and gold cap on the
## right — sit wholly inside asymmetric side bands, so they are never stretched; only the
## flat well between them absorbs the resize. The plate ships at `BUTTON_HEIGHT`, so at the
## authored height nothing is stretched vertically either.
static func _painted_button_box(state: String) -> StyleBoxTexture:
	var tex_path := UIPalette.TEX_BUTTON_PAINTED
	if not ResourceLoader.exists(tex_path):
		return null
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return null
	var pad_left := UIPalette.PAINTED_BUTTON_PAD_LEFT
	var pad_right := UIPalette.PAINTED_BUTTON_PAD_RIGHT
	var pad_v := UIPalette.PAINTED_BUTTON_PAD_V
	# The focus ring overlays the normal box, so it must not add padding of its own.
	if state == "focus":
		pad_left = UIPalette.PAINTED_BUTTON_SLICE_LEFT
		pad_right = UIPalette.PAINTED_BUTTON_SLICE_RIGHT
		pad_v = UIPalette.PAINTED_BUTTON_MARGIN_V
	var box := StyleBoxTexture.new()
	box.texture = tex
	box.texture_margin_left = UIPalette.PAINTED_BUTTON_SLICE_LEFT
	box.texture_margin_right = UIPalette.PAINTED_BUTTON_SLICE_RIGHT
	box.texture_margin_top = UIPalette.PAINTED_BUTTON_MARGIN_V
	box.texture_margin_bottom = UIPalette.PAINTED_BUTTON_MARGIN_V
	box.content_margin_left = pad_left
	box.content_margin_right = pad_right
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.modulate_color = state_modulate(state)
	return box


## Per-state tint of the single painted plate. Multiplicative, so the plate only ever gets
## DARKER or slightly brighter — it can never cross back over the brightness limit the swap
## above exists to respect.
static func state_modulate(state: String) -> Color:
	match state:
		"hover":
			return Color(1.22, 1.22, 1.20)
		"pressed":
			return Color(0.78, 0.80, 0.82)
		"disabled":
			return Color(0.52, 0.55, 0.58, 0.80)
		"focus":
			# The focus box sits ON TOP of the normal one, so it only adds a lift.
			return Color(1.0, 1.0, 1.0, 0.45)
		_:
			return Color(1.0, 1.0, 1.0)


## The framed panel StyleBox - the surface that CARRIES TEXT (menu panel, HUD plates).
##
## It uses the INK INSET texture, not `panel.png`. Measured (D-034): `panel.png` has a
## centre brightness of 230 while every text token in `UIPalette` is light, so the old
## pairing rendered near-white text on a near-white plate - the unreadable Phase-06 HUD.
## `panel_inset.png` measures 19 (dark ink), which is what the light palette was designed
## for. Content margins are >= the 9-slice border so text can never sit on the frame band.
static func panel_stylebox() -> StyleBox:
	var box := _texture_box(UIPalette.TEX_PANEL_INSET, UIPalette.INSET_MARGIN,
		UIPalette.INSET_MARGIN, UIPalette.INSET_MARGIN)
	if box != null:
		return box
	return _fallback_surface_flat(UIPalette.COLOR_SURFACE)


## The LIGHT jade plate (`panel.png`) - for decorative/accent surfaces that carry NO light
## text. Kept available (the art is good) but deliberately not the text surface; anything
## placed on it would need dark text, which this palette does not define.
static func accent_panel_stylebox() -> StyleBox:
	var box := _texture_box(UIPalette.TEX_PANEL, UIPalette.PANEL_MARGIN,
		UIPalette.PANEL_MARGIN, UIPalette.PANEL_MARGIN)
	if box != null:
		return box
	return _fallback_surface_flat(UIPalette.COLOR_SURFACE_HOVER)


## The quiet HINT BAND behind passive prompts (D-057 — the HUD weight ladder): a flat,
## translucent ink fill with no frame and no ornament.
##
## Ornament is how this UI says "this matters": the gold-cornered plaque marks who the player
## is, where they are and what they are fighting. A row of key hints is the least important
## text on screen, so it gets the least weight that still keeps it legible — the band's alpha
## is the legibility bound (see `UIPalette.HINT_BAND_ALPHA`), not a decoration. FLAT on purpose:
## a band has no corners to protect, so there is no texture to 9-slice and no margin to measure.
static func hint_band_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UIPalette.HINT_BAND_COLOR
	box.content_margin_left = UIPalette.SPACE_MD
	box.content_margin_right = UIPalette.SPACE_MD
	box.content_margin_top = UIPalette.SPACE_SM
	box.content_margin_bottom = UIPalette.SPACE_SM
	return box


## A darker nested well inside a panel (secondary surface, e.g. a settings option list).
static func inset_stylebox() -> StyleBox:
	var box := _texture_box(UIPalette.TEX_PANEL_INSET, UIPalette.INSET_MARGIN,
		UIPalette.INSET_MARGIN, UIPalette.SPACE_MD)
	if box != null:
		return box
	return _fallback_surface_flat(UIPalette.COLOR_SURFACE_PRESSED)


## StyleBox for the key-badge chip (the "E"/"Esc" keycap).
##
## Deliberately FLAT, not asset-backed. Measured (D-034): `key_badge.png` is a 61x61 corner
## ornament whose CENTRE PIXEL IS FULLY TRANSPARENT (alpha 0) - it has no fill to put a
## glyph on, and 9-slicing it down to keycap size collapsed its 18px border bands into each
## other, which is why the Phase-06 prompts rendered as unreadable smudges. A keycap needs a
## solid contrasting chip and the pack ships none, so we draw one: dark fill + jade edge.
## Swap this back to `_texture_box` the day a real keycap texture lands.
static func badge_stylebox() -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = UIPalette.COLOR_BADGE
	box.border_color = UIPalette.COLOR_BADGE_BORDER
	box.border_width_left = 1
	box.border_width_right = 1
	box.border_width_top = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	box.content_margin_left = UIPalette.SPACE_SM
	box.content_margin_right = UIPalette.SPACE_SM
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


# --- Menu backdrop (D-041) ---------------------------------------------------
#
# The menu used to be a small plaque on a flat `ColorRect` of near-black, which read as a
# Godot Control floating in a void (A2). These three builders compose a backdrop with depth
# out of NOTHING but code-built gradients and one existing texture — so there is no new asset
# dependency, no license question (`06-art-assets.md` provenance), and no per-frame cost: a
# `GradientTexture2D` is rasterised once and then drawn as a static texture.

## Vertical ink gradient for the menu ground: a lifted blue band above, sinking to the deep
## ground below. This single texture is what gives the composition a horizon.
static func backdrop_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, UIPalette.COLOR_BACKDROP_HIGH)
	gradient.set_color(1, UIPalette.COLOR_BACKDROP_LOW)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	# Top-to-bottom in normalised texture space.
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 16
	tex.height = 256
	return tex


## Radial vignette drawn over the backdrop: transparent at the centre, ink at the edges, so
## the eye is pulled to the menu plaque without the screen looking dirty.
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


## The decorative corner ornament texture, or null if absent.
##
## This is `key_badge.png` used for **what it actually is**. D-034 measured it: a 61x61 piece
## whose centre pixel is fully transparent — a hollow CORNER ORNAMENT that Phase 06 had
## mistakenly pressed into service as a keycap (where, having no fill, it rendered glyphs as
## smudges). Framing the menu corners is its real job, so D-041 puts it there and the keycap
## stays the deliberate drawn chip from `badge_stylebox()`.
static func corner_ornament() -> Texture2D:
	if not ResourceLoader.exists(UIPalette.TEX_KEY_BADGE):
		return null
	return load(UIPalette.TEX_KEY_BADGE) as Texture2D


## THE ornamental divider. One factory, consumed by every screen that needs a rule (D-050).
##
## It replaces duplicated construction in `main_menu.gd` and `gameplay_hud.gd`, which each
## built their own `TextureRect` with their own filter/stretch/size choices — a B6/B7
## violation that had already produced a visible bug: both stretched the jade
## `title_divider.png` to panel width, where it rendered as a flat saturated bar and read as a
## PROGRESS BAR sitting under the menu subtitle. The source is now a monochrome MASK tinted
## with `GOLD_SECONDARY`, so the divider is gold structure rather than a jade fill, and
## changing every divider in the game is one constant here.
##
## `width_fills` makes the rule span its parent (a panel header); passing false keeps it at
## its natural width (a centred ornament under a title).
static func ornament_divider(width_fills: bool = true) -> TextureRect:
	var strip := TextureRect.new()
	strip.name = "OrnamentDivider"
	# Pixel-art mask: NEAREST, and it is scaled on one axis only (`06-art-assets.md`).
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.custom_minimum_size = Vector2(0, UIPalette.ORNAMENT_DIVIDER_HEIGHT)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width_fills \
		else Control.SIZE_SHRINK_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The tint IS the design decision: a white mask becomes antique-gold ornament.
	strip.modulate = UIPalette.GOLD_SECONDARY
	if ResourceLoader.exists(UIPalette.TEX_ORNAMENT_DIVIDER):
		strip.texture = load(UIPalette.TEX_ORNAMENT_DIVIDER)
	return strip


## The ornate 9-slice frame drawn AROUND a dark well (never instead of it — the frame's centre
## alpha is 0, so it carries no text surface of its own). Tinted gold from one constant.
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


## The painted menu backdrop scene, or null if absent.
static func menu_backdrop() -> Texture2D:
	if not ResourceLoader.exists(UIPalette.TEX_MENU_BACKDROP):
		return null
	var source := load(UIPalette.TEX_MENU_BACKDROP) as Texture2D
	if source == null:
		return null
	# The painting carries a FLAT DEAD MARGIN down its left edge, so it is cropped before it
	# is used — `MENU_BACKDROP_DEAD_LEFT_PX`, measured, not estimated. Uncropped and scaled to
	# cover a 16:9 screen that margin becomes a ~90px bar of flat near-black down the left of
	# the menu, which reads as the backdrop failing to load. Like the portrait crop below this
	# is an `AtlasTexture`: a view onto the same texture, not a second copy in memory.
	var dead := float(UIPalette.MENU_BACKDROP_DEAD_LEFT_PX)
	if dead <= 0.0 or dead >= float(source.get_width()):
		return source
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(
		dead, 0.0, float(source.get_width()) - dead, float(source.get_height()))
	return atlas


## A head-and-shoulders crop of a painted standing portrait, as an `AtlasTexture`.
##
## The source art is a full standing figure (310x560), so dropping it straight into a 56px
## square well would show the character's midriff. An `AtlasTexture` region over the TOP
## SQUARE of the image yields head + shoulders — and it costs nothing at runtime, because an
## atlas is a view onto the same texture rather than a second copy in memory.
##
## `female` picks the alternate portrait. Returns null when the art is missing, so the HUD
## keeps its empty well instead of rendering a broken texture.
static func portrait_texture(female: bool = false) -> Texture2D:
	var path := UIPalette.TEX_PORTRAIT_FEMALE if female else UIPalette.TEX_PORTRAIT_MALE
	if not ResourceLoader.exists(path):
		return null
	var source := load(path) as Texture2D
	if source == null:
		return null
	var side := float(source.get_width()) * UIPalette.PORTRAIT_HEAD_CROP_RATIO
	side = minf(side, float(source.get_height()))
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	# Centred horizontally, flush to the top — where a standing figure's head is.
	atlas.region = Rect2(
		(float(source.get_width()) - side) * 0.5, 0.0, side, side)
	return atlas


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

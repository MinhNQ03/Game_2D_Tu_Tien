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

## Per-role modulation applied to the button texture. `Color(1,1,1)` means "leave the art
## exactly as authored", which is why SECONDARY is the untinted baseline.
static func role_modulate(role: String, hovered: bool = false) -> Color:
	match role:
		ROLE_PRIMARY:
			return Color(1.14, 1.04, 0.80) if hovered else Color(1.06, 0.97, 0.76)
		ROLE_DANGER:
			return Color(1.18, 0.72, 0.70) if hovered else Color(1.08, 0.66, 0.64)
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
static func button_stylebox(state: String) -> StyleBox:
	var tex_path := ""
	match state:
		"hover":
			tex_path = UIPalette.TEX_BUTTON_HOVER
		"pressed":
			tex_path = UIPalette.TEX_BUTTON_PRESSED
		"disabled":
			tex_path = UIPalette.TEX_BUTTON_DISABLED
		"focus":
			tex_path = UIPalette.TEX_BUTTON_FOCUS
		_:
			tex_path = UIPalette.TEX_BUTTON_NORMAL
	var pad_h := UIPalette.BUTTON_PAD_H
	var pad_v := UIPalette.BUTTON_PAD_V
	# The focus ring should not add padding (it overlays the normal box), so keep its content
	# margins at the border only.
	if state == "focus":
		pad_h = UIPalette.BUTTON_MARGIN
		pad_v = UIPalette.BUTTON_MARGIN
	var box := _texture_box(tex_path, UIPalette.BUTTON_MARGIN, pad_h, pad_v)
	if box != null:
		return box
	# Fallback (texture missing): a flat state box so the button still works.
	return _fallback_button_flat(state)


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

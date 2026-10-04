extends TestCase
## Unit tests for the asset-backed UI theme (`UITheme`/`UIPalette`). Structural: the built
## Theme carries the button-state styleboxes + label styling the menu/HUD rely on; the panel
## and key-badge styleboxes build; and (asset contract) every declared UI texture exists on
## disk. Pure resources: no tree, no autoloads.

const UIThemeScript := preload("res://src/presentation/ui/ui_theme.gd")
const UIPaletteScript := preload("res://src/presentation/ui/ui_palette.gd")


func test_theme_has_button_state_styleboxes() -> void:
	var theme: Theme = UIThemeScript.build()
	assert_not_null(theme, "theme builds")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		assert_true(theme.has_stylebox(state, "Button"),
			"Button has a '%s' stylebox" % state)
	assert_true(theme.has_color("font_color", "Button"), "Button has font color")
	assert_true(theme.has_font_size("font_size", "Button"), "Button has a font size")


## The button states must be DISTINCT resources (not the same box reused), so hover/pressed/
## disabled read differently — the "visual distinction, not alpha tweak" requirement.
func test_button_states_are_distinct() -> void:
	var normal := UIThemeScript.button_stylebox("normal")
	var hover := UIThemeScript.button_stylebox("hover")
	var pressed := UIThemeScript.button_stylebox("pressed")
	var disabled := UIThemeScript.button_stylebox("disabled")
	assert_not_null(normal, "normal builds")
	assert_true(normal != hover and normal != pressed and normal != disabled,
		"each button state is its own stylebox")


## The framed panel + inset + badge styleboxes build (asset-backed when textures present,
## flat fallback otherwise) — the menu/HUD panels and key badges depend on them.
func test_panel_and_badge_styleboxes_build() -> void:
	assert_not_null(UIThemeScript.panel_stylebox(), "panel stylebox builds")
	assert_not_null(UIThemeScript.inset_stylebox(), "inset stylebox builds")
	assert_not_null(UIThemeScript.badge_stylebox(), "badge stylebox builds")
	theme_has_panel()


func theme_has_panel() -> void:
	var theme: Theme = UIThemeScript.build()
	assert_true(theme.has_stylebox("panel", "PanelContainer"),
		"PanelContainer has the framed panel stylebox")


## ASSET CONTRACT (prompt §20): every runtime UI texture the theme/components reference must
## exist on disk. A missing/renamed/un-tracked asset fails here instead of showing a blank UI.
func test_all_ui_textures_exist() -> void:
	for path in UIPaletteScript.UI_TEXTURES:
		assert_true(ResourceLoader.exists(path), "UI texture exists: %s" % path)
	assert_true(UIThemeScript.textures_present(), "UITheme reports all textures present")


## When the textures are present the panel/button must actually be asset-backed
## (StyleBoxTexture), not the flat fallback — proving the UI uses REAL pixel-art assets.
## The key badge is deliberately NOT asset-backed; see the dedicated test below.
func test_theme_is_asset_backed_when_textures_present() -> void:
	if not UIThemeScript.textures_present():
		return  # textures not imported (shouldn't happen in CI); asset-contract test covers it
	assert_true(UIThemeScript.panel_stylebox() is StyleBoxTexture,
		"panel uses an asset-backed StyleBoxTexture")
	assert_true(UIThemeScript.button_stylebox("normal") is StyleBoxTexture,
		"button uses an asset-backed StyleBoxTexture")
	assert_true(UIThemeScript.accent_panel_stylebox() is StyleBoxTexture,
		"the light accent plate uses an asset-backed StyleBoxTexture")


## REGRESSION GUARD (D-034): the text-bearing panel must use the DARK ink texture.
##
## `panel.png` was measured at centre brightness 230 (near white) while every text token in
## UIPalette is light, so pairing them rendered near-white text on a near-white plate — the
## unreadable Phase-06 HUD. If someone points `panel_stylebox()` back at `TEX_PANEL`, this
## fails instead of shipping an invisible HUD again.
func test_text_panel_uses_the_dark_surface() -> void:
	if not UIThemeScript.textures_present():
		return
	var box := UIThemeScript.panel_stylebox() as StyleBoxTexture
	assert_not_null(box, "panel stylebox is texture-backed")
	assert_not_null(box.texture, "panel stylebox carries a texture")
	assert_eq(box.texture.resource_path, UIPaletteScript.TEX_PANEL_INSET,
		"the panel that carries light text uses the DARK inset texture, not the light plate")


## REGRESSION GUARD (D-034): text must never be drawn on top of the 9-slice border band.
## The border band does not stretch, so a content margin SMALLER than the texture margin
## pushes glyphs onto the frame art (what made the Phase-06 panels look clipped).
func test_panel_content_margin_clears_the_frame_border() -> void:
	if not UIThemeScript.textures_present():
		return
	var box := UIThemeScript.panel_stylebox() as StyleBoxTexture
	assert_true(box.content_margin_left >= box.texture_margin_left,
		"left content margin clears the 9-slice border")
	assert_true(box.content_margin_top >= box.texture_margin_top,
		"top content margin clears the 9-slice border")
	assert_true(box.content_margin_right >= box.texture_margin_right,
		"right content margin clears the 9-slice border")
	assert_true(box.content_margin_bottom >= box.texture_margin_bottom,
		"bottom content margin clears the 9-slice border")


## REGRESSION GUARD (D-034): the key badge is a deliberate FLAT chip, not the pack texture.
## `key_badge.png` is a 61x61 corner ornament whose centre pixel is fully TRANSPARENT, so it
## cannot back a key glyph; 9-slicing it to keycap size collapsed its border bands and the
## prompts rendered as smudges. A keycap needs a solid contrasting fill.
func test_key_badge_is_a_solid_chip_not_the_hollow_ornament() -> void:
	var badge := UIThemeScript.badge_stylebox()
	assert_true(badge is StyleBoxFlat,
		"the keycap is a solid flat chip (key_badge.png has a transparent centre)")
	var flat := badge as StyleBoxFlat
	assert_true(flat.bg_color.a > 0.5, "the keycap has an opaque fill behind the glyph")


## The light text tokens rely on an outline to stay readable over map art / lighter plates.
func test_theme_gives_text_a_readable_outline() -> void:
	var theme: Theme = UIThemeScript.build()
	assert_true(theme.has_color("font_outline_color", "Label"), "Label has an outline colour")
	assert_true(theme.has_constant("outline_size", "Label"), "Label has an outline size")
	assert_true(theme.get_constant("outline_size", "Label") > 0, "the outline is visible")


## The palette tokens the menu/HUD read must be present and sane.
func test_palette_tokens_are_sane() -> void:
	assert_true(UIPaletteScript.FONT_SIZE_TITLE > UIPaletteScript.FONT_SIZE_BODY,
		"title font is larger than body")
	assert_true(UIPaletteScript.SPACE_LG > 0, "spacing tokens are positive")
	assert_true(UIPaletteScript.NINE_PATCH_MARGIN > 0, "nine-patch margin is positive")
	assert_eq(UIPaletteScript.UI_TEXTURES.size(), 10, "all UI textures are registered")


# --- D-041 production-foundation visual pass ---------------------------------

## Semantic button roles must be VISUALLY distinct, or the hierarchy exists only in the
## design doc. The roles tint the same authored texture, so the test asserts the tints
## differ rather than asserting a specific colour (the values are tunable).
func test_button_roles_are_visually_distinct() -> void:
	var primary := UIThemeScript.role_modulate(UIThemeScript.ROLE_PRIMARY)
	var secondary := UIThemeScript.role_modulate(UIThemeScript.ROLE_SECONDARY)
	var danger := UIThemeScript.role_modulate(UIThemeScript.ROLE_DANGER)
	assert_ne(primary, secondary, "PRIMARY is tinted differently from SECONDARY")
	assert_ne(danger, secondary, "DANGER is tinted differently from SECONDARY")
	assert_ne(primary, danger, "PRIMARY and DANGER are not the same tint")
	# SECONDARY is the untinted baseline: it must leave the authored pixel art alone.
	assert_eq(secondary, Color(1.0, 1.0, 1.0), "SECONDARY does not modulate the art at all")
	# Hover must lift every role, so focus/hover is perceivable on all of them.
	for role in [
		UIThemeScript.ROLE_PRIMARY, UIThemeScript.ROLE_SECONDARY, UIThemeScript.ROLE_DANGER,
	]:
		assert_ne(UIThemeScript.role_modulate(role, true),
			UIThemeScript.role_modulate(role, false),
			"role '%s' changes on hover/focus" % role)


## Role font colours must differ too, and DANGER must use the reserved crimson token rather
## than a locally invented colour.
func test_role_font_colors_use_reserved_tokens() -> void:
	assert_eq(UIThemeScript.role_font_color(UIThemeScript.ROLE_PRIMARY),
		UIPaletteScript.COLOR_TITLE, "PRIMARY label uses the gold title token")
	assert_eq(UIThemeScript.role_font_color(UIThemeScript.ROLE_SECONDARY),
		UIPaletteScript.COLOR_TEXT, "SECONDARY label uses the primary text token")
	assert_eq(UIThemeScript.role_font_color(UIThemeScript.ROLE_DANGER),
		UIPaletteScript.COLOR_CRIMSON_HOVER, "DANGER label uses the reserved crimson token")


## The menu backdrop must be buildable with NO new asset: both layers are code-generated
## gradients, which is what keeps provenance clean (`06-art-assets.md`) and the cost static.
func test_backdrop_layers_are_code_built_not_assets() -> void:
	var sky := UIThemeScript.backdrop_gradient()
	assert_not_null(sky, "the backdrop gradient builds")
	assert_true(sky is GradientTexture2D, "it is a code-built gradient, not a loaded file")
	assert_true(sky.width > 0 and sky.height > 0, "it has a real size")
	var vignette := UIThemeScript.vignette_gradient()
	assert_not_null(vignette, "the vignette builds")
	assert_true(vignette is GradientTexture2D, "the vignette is code-built too")
	assert_eq(vignette.fill, GradientTexture2D.FILL_RADIAL, "the vignette is radial")
	# The vignette must be transparent in the middle, or it would dim the menu itself.
	var centre: Color = vignette.gradient.sample(0.0)
	assert_true(centre.a <= 0.01, "the vignette centre is fully transparent (a=%.2f)" % centre.a)
	var edge: Color = vignette.gradient.sample(1.0)
	assert_true(edge.a > centre.a, "the vignette darkens toward the edge")


## The corner ornament reuses `key_badge.png` for what D-034 MEASURED it to be — a hollow
## corner piece. This pins the decision so a future pass does not put it back under a glyph.
func test_corner_ornament_resolves_to_the_hollow_badge_art() -> void:
	assert_true(ResourceLoader.exists(UIPaletteScript.TEX_KEY_BADGE),
		"the ornament source texture is present")
	assert_not_null(UIThemeScript.corner_ornament(), "the ornament texture loads")
	# And the keycap must still be the DRAWN chip, never this hollow art (D-034 regression).
	var badge := UIThemeScript.badge_stylebox()
	assert_true(badge is StyleBoxFlat,
		"the key badge is still a drawn flat chip, not the hollow ornament texture")


## Layout tokens must be internally consistent, or the menu plaque clips its own buttons.
func test_layout_tokens_are_coherent() -> void:
	assert_true(UIPaletteScript.MENU_BUTTON_WIDTH < UIPaletteScript.MENU_PANEL_WIDTH,
		"the action button fits inside the plaque (%d < %d)"
		% [UIPaletteScript.MENU_BUTTON_WIDTH, UIPaletteScript.MENU_PANEL_WIDTH])
	# The plaque must leave room for the 9-slice border band on BOTH sides, or the button
	# would be drawn over the frame art (the D-034 content-margin lesson, applied to layout).
	var border_room := UIPaletteScript.MENU_PANEL_WIDTH - UIPaletteScript.MENU_BUTTON_WIDTH
	assert_true(border_room >= UIPaletteScript.INSET_MARGIN * 2,
		"the plaque clears its own border band on both sides (%d >= %d)"
		% [border_room, UIPaletteScript.INSET_MARGIN * 2])
	for token in [
		UIPaletteScript.BUTTON_HEIGHT, UIPaletteScript.TITLE_GAP, UIPaletteScript.SECTION_GAP,
		UIPaletteScript.ROW_GAP, UIPaletteScript.PANEL_GUTTER, UIPaletteScript.HUD_MARGIN,
		UIPaletteScript.ORNAMENT_PX, UIPaletteScript.IDENTITY_PORTRAIT_PX,
	]:
		assert_true(int(token) > 0, "every layout token is positive (got %d)" % int(token))
	# Section gaps must be bigger than row gaps, or the hierarchy flattens (A12).
	assert_true(UIPaletteScript.SECTION_GAP > UIPaletteScript.ROW_GAP,
		"sections are separated more than the rows inside them")


## Crimson is RESERVED for danger. If it drifts to equal the jade accent or the body text,
## the "be careful" signal is gone (D-041 A1).
func test_crimson_stays_reserved_and_distinct() -> void:
	assert_ne(UIPaletteScript.COLOR_CRIMSON, UIPaletteScript.COLOR_ACCENT,
		"crimson is not the jade interaction accent")
	assert_ne(UIPaletteScript.COLOR_CRIMSON, UIPaletteScript.COLOR_TEXT,
		"crimson is not the body text colour")
	assert_true(UIPaletteScript.COLOR_CRIMSON.r > UIPaletteScript.COLOR_CRIMSON.g
		and UIPaletteScript.COLOR_CRIMSON.r > UIPaletteScript.COLOR_CRIMSON.b,
		"crimson is actually red-dominant")


## The deep backdrop must be DARK, because every text token in the palette is light — the
## same pairing rule D-034 had to learn the hard way, now applied to the backdrop.
func test_backdrop_ground_is_dark_enough_for_light_text() -> void:
	var deep := UIPaletteScript.COLOR_BACKGROUND_DEEP
	var brightness := (deep.r + deep.g + deep.b) / 3.0 * 255.0
	assert_true(brightness < float(UIPaletteScript.SURFACE_LIGHT_BRIGHTNESS_LIMIT),
		"the deep backdrop (%.0f) is below the light-surface limit (%d)"
		% [brightness, UIPaletteScript.SURFACE_LIGHT_BRIGHTNESS_LIMIT])
	# It should read as ink-BLUE, not neutral black: that is what makes the gold read warm.
	assert_true(deep.b > deep.r, "the ground is blue-leaning, not neutral grey")

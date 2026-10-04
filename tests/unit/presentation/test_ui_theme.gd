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

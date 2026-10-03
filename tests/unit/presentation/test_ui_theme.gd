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


## When the textures are present the theme must actually be asset-backed (StyleBoxTexture),
## not the flat fallback — proving the UI uses REAL pixel-art assets, not programmatic boxes.
func test_theme_is_asset_backed_when_textures_present() -> void:
	if not UIThemeScript.textures_present():
		return  # textures not imported (shouldn't happen in CI); asset-contract test covers it
	assert_true(UIThemeScript.panel_stylebox() is StyleBoxTexture,
		"panel uses an asset-backed StyleBoxTexture")
	assert_true(UIThemeScript.button_stylebox("normal") is StyleBoxTexture,
		"button uses an asset-backed StyleBoxTexture")
	assert_true(UIThemeScript.badge_stylebox() is StyleBoxTexture,
		"key badge uses an asset-backed StyleBoxTexture")


## The palette tokens the menu/HUD read must be present and sane.
func test_palette_tokens_are_sane() -> void:
	assert_true(UIPaletteScript.FONT_SIZE_TITLE > UIPaletteScript.FONT_SIZE_BODY,
		"title font is larger than body")
	assert_true(UIPaletteScript.SPACE_LG > 0, "spacing tokens are positive")
	assert_true(UIPaletteScript.NINE_PATCH_MARGIN > 0, "nine-patch margin is positive")
	assert_eq(UIPaletteScript.UI_TEXTURES.size(), 10, "all UI textures are registered")

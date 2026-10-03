extends TestCase
## Unit tests for the foundation UI theme builder (`UITheme`/`UIPalette`). Structural: a built
## Theme must carry the button state styleboxes + label styling the menu/HUD rely on, and the
## key-badge stylebox must exist. Pure resources: no tree, no autoloads.

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


func test_theme_styles_label() -> void:
	var theme: Theme = UIThemeScript.build()
	assert_true(theme.has_color("font_color", "Label"), "Label has font color")
	assert_true(theme.has_font_size("font_size", "Label"), "Label has a font size")


func test_badge_stylebox_builds() -> void:
	var box: StyleBoxFlat = UIThemeScript.badge_stylebox()
	assert_not_null(box, "badge stylebox builds")
	assert_true(box.border_width_left > 0, "badge has a visible border")


## The palette tokens the menu/HUD read must be present and sane (a title bigger than body,
## positive spacing). This guards against an accidental token deletion/rename.
func test_palette_tokens_are_sane() -> void:
	assert_true(UIPaletteScript.FONT_SIZE_TITLE > UIPaletteScript.FONT_SIZE_BODY,
		"title font is larger than body")
	assert_true(UIPaletteScript.SPACE_LG > 0, "spacing tokens are positive")
	assert_true(UIPaletteScript.CORNER_RADIUS >= 0, "corner radius is non-negative")

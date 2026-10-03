extends RefCounted
class_name UITheme
## UITheme — Aetheria presentation (foundation theme builder).
##
## Builds a Godot `Theme` from the `UIPalette` design tokens so the main menu and HUD share
## ONE consistent look (buttons, labels, focus/hover/disabled states) instead of each node
## styling itself ad hoc. The theme is built in CODE (not a hand-authored `.tres`) to match
## this project's code-built UI convention (`src/presentation/menus/main_menu.gd`) and so it
## is deterministically constructible + unit-testable headless (`docs/TEST_PLAN.md`), with no
## editor-only sub-resource wiring.
##
## Presentation-only: it reads tokens and returns a Theme. It owns no gameplay/domain state.
## A later real art pass can replace `build()` (or swap in a designer `.tres`) without any
## call-site change — menu/HUD just call `theme = UITheme.build()`.

## Build the shared foundation Theme. Styles the base `Button` and `Label` types so any
## Button/Label under a node with this theme inherits the look; the HUD key-badge uses a
## dedicated StyleBox from `badge_stylebox()`.
static func build() -> Theme:
	var theme := Theme.new()

	# --- Button -------------------------------------------------------------
	theme.set_stylebox("normal", "Button", _surface_box(UIPalette.COLOR_SURFACE))
	theme.set_stylebox("hover", "Button", _surface_box(UIPalette.COLOR_SURFACE_HOVER))
	theme.set_stylebox("pressed", "Button", _surface_box(UIPalette.COLOR_SURFACE_PRESSED))
	theme.set_stylebox("disabled", "Button", _surface_box(UIPalette.COLOR_SURFACE_DISABLED))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_color("font_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_color("font_pressed_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_color("font_disabled_color", "Button", UIPalette.COLOR_TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", UIPalette.COLOR_TEXT)
	theme.set_font_size("font_size", "Button", UIPalette.FONT_SIZE_BUTTON)

	# --- Label --------------------------------------------------------------
	theme.set_color("font_color", "Label", UIPalette.COLOR_TEXT)
	theme.set_font_size("font_size", "Label", UIPalette.FONT_SIZE_BODY)

	return theme


## StyleBox for the key-badge chip (the "E"/"Esc" in a HUD hint). Separate from the Button
## styles because a badge is a static decorated Label background, not an interactive control.
static func badge_stylebox() -> StyleBoxFlat:
	var box := _surface_box(UIPalette.COLOR_BADGE)
	box.border_width_left = 1
	box.border_width_right = 1
	box.border_width_top = 1
	box.border_width_bottom = 1
	box.border_color = UIPalette.COLOR_ACCENT
	box.content_margin_left = UIPalette.SPACE_SM
	box.content_margin_right = UIPalette.SPACE_SM
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


# --- Builders ----------------------------------------------------------------

## A filled, rounded surface with the standard button padding.
static func _surface_box(fill: Color) -> StyleBoxFlat:
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


## A transparent box with an accent border — the keyboard-focus ring.
static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_width_left = UIPalette.FOCUS_BORDER
	box.border_width_right = UIPalette.FOCUS_BORDER
	box.border_width_top = UIPalette.FOCUS_BORDER
	box.border_width_bottom = UIPalette.FOCUS_BORDER
	box.border_color = UIPalette.COLOR_ACCENT
	box.corner_radius_top_left = UIPalette.CORNER_RADIUS
	box.corner_radius_top_right = UIPalette.CORNER_RADIUS
	box.corner_radius_bottom_left = UIPalette.CORNER_RADIUS
	box.corner_radius_bottom_right = UIPalette.CORNER_RADIUS
	return box

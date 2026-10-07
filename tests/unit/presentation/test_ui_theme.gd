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


## When the textures are present every surface must actually be asset-backed (StyleBoxTexture),
## not the flat fallback — proving the UI uses the REAL kit (D-062), keycap included.
func test_theme_is_asset_backed_when_textures_present() -> void:
	if not UIThemeScript.textures_present():
		return  # textures not imported (shouldn't happen in CI); asset-contract test covers it
	assert_true(UIThemeScript.panel_stylebox() is StyleBoxTexture,
		"panel uses an asset-backed StyleBoxTexture")
	for state in UIThemeScript.BUTTON_TEXTURES:
		assert_true(UIThemeScript.button_stylebox(state) is StyleBoxTexture,
			"the '%s' button uses an asset-backed StyleBoxTexture" % state)
	assert_true(UIThemeScript.badge_stylebox() is StyleBoxTexture, "the keycap is the kit's")
	assert_true(UIThemeScript.hint_band_stylebox() is StyleBoxTexture, "the band is the kit's")


## REGRESSION GUARD (D-034, re-pinned D-062): the text-bearing panel is the kit's PLAQUE, and
## its centre MEASURES dark — every text token is light, and a light plate behind light text
## is the unreadable Phase-06 HUD. Measured, not trusted: a regenerated kit that brightened the
## lacquer fails here.
func test_text_panel_uses_the_dark_surface() -> void:
	if not UIThemeScript.textures_present():
		return
	var box := UIThemeScript.panel_stylebox() as StyleBoxTexture
	assert_not_null(box, "panel stylebox is texture-backed")
	assert_eq(box.texture.resource_path, UIPaletteScript.TEX_PLAQUE,
		"the panel that carries light text is the kit's lacquer plaque")
	var brightness := _centre_brightness(UIPaletteScript.TEX_PLAQUE)
	assert_true(brightness >= 0.0 and brightness < UIPaletteScript.SURFACE_LIGHT_BRIGHTNESS_LIMIT,
		"the plaque's measured centre (%.0f) is DARK, under the %d limit"
			% [brightness, UIPaletteScript.SURFACE_LIGHT_BRIGHTNESS_LIMIT])


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


## REGRESSION GUARD (D-034, re-pinned D-062): a keycap needs a SOLID face under its glyph. The
## Phase-06 badge was a hollow ornament and rendered key glyphs as smudges; the kit's keycap is
## measured opaque at its centre, and its lip band is never stretched.
func test_key_badge_is_a_solid_keycap_not_a_hollow_ornament() -> void:
	var badge := UIThemeScript.badge_stylebox() as StyleBoxTexture
	assert_not_null(badge, "the keycap is the kit's texture")
	if badge == null:
		return
	assert_eq(badge.texture.resource_path, UIPaletteScript.TEX_KEYCAP, "the keycap texture")
	var image := _image(UIPaletteScript.TEX_KEYCAP)
	assert_true(image.get_pixel(image.get_width() / 2, image.get_height() / 2 - 2).a > 0.99,
		"the keycap's face under the glyph is opaque")
	assert_eq(int(badge.texture_margin_bottom), UIPaletteScript.KEYCAP_LIP,
		"the lip is its own 9-slice band, so the cap keeps its depth at any width")


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
	assert_true(UIPaletteScript.PLAQUE_MARGIN > 0, "the plaque's nine-slice margin is positive")
	# 17 kit textures (plaque, 2 bands, 5 button plates, keycap, gauge well + fill, slot,
	# divider, frame, corner fret, 2 medallions) + the painted menu backdrop (D-062).
	assert_eq(UIPaletteScript.UI_TEXTURES.size(), 18, "all UI textures are registered")


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


## The two GRADIENT layers stay code-generated, so the backdrop still has a working
## composition if the painted scene is ever missing, and their cost stays static (a
## `GradientTexture2D` rasterises once). D-044 added a painted scene layer ON TOP of these —
## it did not replace them, and this guards the fallback.
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


## The full-screen corner ornament is the kit's HOLLOW fret mask (measured: transparent at its
## centre, so it frames and never covers), and the keycap is still its own solid cap.
func test_corner_ornament_is_the_hollow_fret() -> void:
	assert_true(ResourceLoader.exists(UIPaletteScript.TEX_CORNER_FRET),
		"the corner fret texture is present")
	assert_not_null(UIThemeScript.corner_ornament(), "the ornament texture loads")
	var image := _image(UIPaletteScript.TEX_CORNER_FRET)
	assert_true(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a < 0.01,
		"the fret is hollow at its centre")
	assert_ne(UIPaletteScript.TEX_CORNER_FRET, UIPaletteScript.TEX_KEYCAP,
		"and the keycap is never this ornament")


## Layout tokens must be internally consistent, or the menu plaque clips its own buttons.
func test_layout_tokens_are_coherent() -> void:
	assert_true(UIPaletteScript.MENU_BUTTON_WIDTH < UIPaletteScript.MENU_PANEL_WIDTH,
		"the action button fits inside the plaque (%d < %d)"
		% [UIPaletteScript.MENU_BUTTON_WIDTH, UIPaletteScript.MENU_PANEL_WIDTH])
	# The plaque must leave room for the 9-slice border band on BOTH sides, or the button
	# would be drawn over the frame art (the D-034 content-margin lesson, applied to layout).
	var border_room := UIPaletteScript.MENU_PANEL_WIDTH - UIPaletteScript.MENU_BUTTON_WIDTH
	assert_true(border_room >= UIPaletteScript.PLAQUE_MARGIN * 2,
		"the plaque clears its own border band on both sides (%d >= %d)"
		% [border_room, UIPaletteScript.PLAQUE_MARGIN * 2])
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


# --- D-044 painted UI tier ---------------------------------------------------

## THE GUARD THIS PROJECT WAS MISSING (D-044, re-pinned D-062): every button plate a label sits
## on must MEASURE dark at its centre, or the light-only text palette is illegal on it. The
## focus plate is the exception by design — it is drawn OVER the normal one and must be HOLLOW.
func test_button_surface_is_dark_enough_for_light_text() -> void:
	if not UIThemeScript.textures_present():
		return
	for state in UIThemeScript.BUTTON_TEXTURES:
		var box := UIThemeScript.button_stylebox(state) as StyleBoxTexture
		assert_not_null(box, "the '%s' button is texture-backed" % state)
		if box == null:
			continue
		assert_eq(box.texture.resource_path, String(UIThemeScript.BUTTON_TEXTURES[state]),
			"the '%s' button wears its own designed plate" % state)
		var path := String(UIThemeScript.BUTTON_TEXTURES[state])
		if state == "focus":
			var image := _image(path)
			assert_true(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a < 0.01,
				"the focus plate is hollow: it rings the normal plate, never covers the label")
			continue
		var brightness := _centre_brightness(path)
		assert_true(brightness < UIPaletteScript.SURFACE_LIGHT_BRIGHTNESS_LIMIT,
			"the '%s' plate's measured centre (%.0f) is under the %d limit"
				% [state, brightness, UIPaletteScript.SURFACE_LIGHT_BRIGHTNESS_LIMIT])


## Every per-state tint keeps every plate dark: a tint never exceeds 1 on any channel, so no
## state can lift a measured-dark plate past the limit the text palette depends on.
func test_button_state_tints_cannot_brighten_past_the_limit() -> void:
	for state in UIThemeScript.BUTTON_TEXTURES:
		var tint := UIThemeScript.state_modulate(state)
		assert_true(maxf(maxf(tint.r, tint.g), tint.b) <= 1.0,
			"the '%s' tint (%s) never brightens its plate" % [state, str(tint)])
	# The states must be DRAWN apart, not tinted apart: five distinct plates.
	var seen: Array[String] = []
	for state in UIThemeScript.BUTTON_TEXTURES:
		var path := String(UIThemeScript.BUTTON_TEXTURES[state])
		assert_false(seen.has(path), "the '%s' state has its own plate" % state)
		seen.append(path)


## A label never lies on the gold hairline or its knots: every state's content margins clear
## the 9-slice bands that hold them, and the vertical bands fit inside the authored height.
func test_button_label_clears_the_hairline() -> void:
	if not UIThemeScript.textures_present():
		return
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := UIThemeScript.button_stylebox(state) as StyleBoxTexture
		assert_true(box.content_margin_left >= box.texture_margin_left
				and box.content_margin_right >= box.texture_margin_right,
			"the '%s' label clears the side bands (knots and hairline)" % state)
		assert_true(box.content_margin_top >= box.texture_margin_top - 1
				and box.content_margin_bottom >= box.texture_margin_bottom - 1,
			"and the top/bottom bands (pressed may sink the label by one pixel)")
		assert_true(box.texture_margin_top + box.texture_margin_bottom
				< UIPaletteScript.BUTTON_HEIGHT,
			"the unstretched vertical bands fit inside BUTTON_HEIGHT")


## The plate is drawn UNDISTORTED at any authored size: the 9-slice bands leave a stretchable
## centre inside the plate and inside the menu button's width, so only the flat lacquer run
## between the knots ever stretches (D-056's lesson: an ornament in a stretched band distorts).
func test_button_plate_slices_leave_a_stretchable_centre() -> void:
	var image := _image(UIPaletteScript.TEX_BUTTON_NORMAL)
	assert_not_null(image, "the plate yields an image to measure")
	if image == null:
		return
	var slices_h := UIPaletteScript.BUTTON_SLICE_H * 2
	var slices_v := UIPaletteScript.BUTTON_SLICE_V * 2
	assert_true(slices_h < image.get_width() and slices_v < image.get_height(),
		"the bands (%d x %d) leave a stretchable centre in the %dx%d plate"
			% [slices_h, slices_v, image.get_width(), image.get_height()])
	assert_true(slices_h < UIPaletteScript.MENU_BUTTON_WIDTH,
		"and fit inside MENU_BUTTON_WIDTH (%d)" % UIPaletteScript.MENU_BUTTON_WIDTH)


## The plate has no opaque background around its chamfered silhouette: the four corners are
## transparent (a dark RECTANGLE behind the button read as a box, not a button), and the well
## the label sits on is solid.
func test_button_plate_background_is_transparent() -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var image := _image(String(UIThemeScript.BUTTON_TEXTURES[state]))
		var w := image.get_width() - 1
		var h := image.get_height() - 1
		for corner in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
			assert_true(image.get_pixelv(corner).a < 0.05,
				"the '%s' plate's corner %s is transparent" % [state, str(corner)])
		assert_true(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a > 0.6,
			"and its well is solid enough to carry a label")


func _image(path: String) -> Image:
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	return image


## Perceived brightness (0-255) of a texture's centre pixel, composited over black.
func _centre_brightness(path: String) -> float:
	var image := _image(path)
	if image == null:
		return -1.0
	var c := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	return 255.0 * c.a * (0.299 * c.r + 0.587 * c.g + 0.114 * c.b)


## The painted backdrop and the identity medallion must resolve. The medallion is the actor's
## own pipeline portrait (D-062): square, at the size the HUD draws it 1:1, and the female
## variant is different art.
func test_painted_backdrop_and_portrait_resolve() -> void:
	assert_not_null(UIThemeScript.menu_backdrop(), "the painted menu backdrop loads")
	var portrait := UIThemeScript.portrait_texture()
	assert_not_null(portrait, "the identity medallion loads")
	if portrait == null:
		return
	assert_eq(portrait.get_width(), portrait.get_height(), "the medallion is square")
	assert_eq(portrait.get_width(), UIPaletteScript.MEDALLION_PX,
		"and exactly the size the HUD draws it, so it is never resampled")
	var female := UIThemeScript.portrait_texture(true)
	assert_not_null(female, "the female medallion loads")
	if female != null:
		assert_ne(female.resource_path, portrait.resource_path,
			"the two medallions are different art")


# === D-050: the ornament seam is CENTRAL, and the chosen assets are what was measured ===

## The divider must come from ONE factory, and EVERY screen must use it.
##
## This is the regression for a defect that was VISIBLE and untested: four screens
## (`main_menu`, `gameplay_hud`, `sect_panel`, `faction_panel`) each built their own divider
## `TextureRect` with their own filter, stretch and size, and all of them stretched the jade
## `title_divider.png` to panel width — where it rendered as a flat saturated bar and read as
## a PROGRESS BAR under the menu subtitle and in every panel header. Duplicated styling is
## what allowed one wrong decision to appear four times, so the guard is structural: assert
## that no screen constructs a divider itself.
func test_d050_the_divider_comes_from_one_central_factory() -> void:
	var divider := UITheme.ornament_divider()
	assert_not_null(divider, "the theme exposes an ornament divider factory")
	assert_true(divider is TextureRect, "it is a TextureRect")
	assert_eq(divider.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
		"pixel-art ornament is NEAREST filtered (06-art-assets)")
	# The tint IS the design decision: a white mask becomes antique-gold ornament, so a
	# semantic colour change is one palette constant rather than new art.
	assert_eq(divider.modulate, UIPalette.GOLD_SECONDARY,
		"it is tinted from the palette's gold token, not left white")
	assert_not_null(divider.texture, "and it actually carries the ornament texture")
	assert_eq(divider.custom_minimum_size.y, float(UIPalette.ORNAMENT_DIVIDER_HEIGHT),
		"its height comes from the palette")
	divider.free()

	# STRUCTURAL GUARD: no screen may build its own divider. Reading the source is the only
	# way to assert this — a rendered divider looks the same whoever constructed it, which is
	# precisely why the duplication survived until somebody looked at a screenshot.
	#
	# IT SCANS THE WHOLE PRESENTATION LAYER RATHER THAN LISTING FILES. The first version
	# listed `main_menu.gd` and `gameplay_hud.gd` — and PASSED while `sect_panel.gd` and
	# `faction_panel.gd` were still building their own dividers, so the defect the test
	# existed to catch was live in two of the four screens that had it. A guard with a
	# hard-coded inventory only protects the files somebody remembered; a guard that walks the
	# directory protects the ones they did not.
	#
	# It watches the LIVE token, not the retired one. Writing it against `TEX_TITLE_DIVIDER`
	# would have been a guard that can only ever catch the mistake already made: the realistic
	# regression is a new panel copying the factory BODY, which references the current
	# ornament texture. Both source filenames are matched too, so hardcoding the path instead
	# of the constant does not slip past. The palette (which declares the paths) and the theme
	# (the one factory) are the only files allowed to name them.
	var divider_tokens: Array[String] = [
		"TEX_ORNAMENT_DIVIDER", "divider.png", "divider_rule.png", "title_divider.png",
	]
	var seam_owners: Array[String] = ["ui_palette.gd", "ui_theme.gd"]
	var offenders: Array[String] = []
	for path in _presentation_scripts("res://src/presentation"):
		if seam_owners.has(path.get_file()):
			continue
		var source := _read_source(path)
		assert_ne(source, "", "%s is readable" % path)
		for token in divider_tokens:
			if source.contains(token):
				offenders.append("%s (%s)" % [path.get_file(), token])
	assert_eq(str(offenders), str([]),
		("no screen may name a divider TEXTURE — every one asks UITheme.ornament_divider(), "
			+ "so one edit restyles every divider in the game. Offenders: %s") % str(offenders))


## Every `.gd` under `root`, recursively. Used by the structural guards above so they cover
## the layer rather than a remembered subset of it.
func _presentation_scripts(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full := "%s/%s" % [dir_path, entry]
				if dir.current_is_dir():
					pending.append(full)
				elif entry.ends_with(".gd"):
					out.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## The other three shared seams — the composed backdrop, the role-styled menu button and the
## scrolling panel body — must also come from the theme, and no screen may re-roll any of them.
##
## Same guard shape as the divider, for the same reason and with the same history. The backdrop
## and the button lived inside `main_menu.gd`, and the consequence was not hypothetical: the
## settings screen had a flat `ColorRect` where the menu had a painted composition, and three
## bare untinted `Button`s where the menu had role-styled plates, so the game's two full
## screens did not look like the same product. The scroll body lived in both side panels, which
## meant both of them also had its defect — the scrollbar drawn over the value column.
## Construction that lives in one screen is construction the next screen will either copy
## (defects included) or do without.
func test_d050_the_backdrop_button_and_scroll_body_come_from_the_theme() -> void:
	var probe := Control.new()
	UITheme.build_backdrop(probe)
	for layer_name in ["Background", "BackdropGradient", "BackdropScene", "Vignette"]:
		assert_not_null(probe.get_node_or_null(layer_name),
			"the backdrop builder adds the %s layer" % layer_name)
	probe.free()

	var button := UITheme.menu_button(UITheme.ROLE_PRIMARY)
	assert_not_null(button, "the theme exposes a menu-button factory")
	assert_eq(button.custom_minimum_size,
		Vector2(UIPalette.MENU_BUTTON_WIDTH, UIPalette.BUTTON_HEIGHT),
		"its size comes from the palette, not from a hand-typed Vector2")
	assert_eq(UITheme.button_role(button), UITheme.ROLE_PRIMARY,
		"it remembers its role, so a hover lift tints with the CURRENT role")
	# A role can change after construction (the settings screen promotes the active
	# language), so re-applying must move both carriers, not just the colour.
	UITheme.apply_button_role(button, UITheme.ROLE_SECONDARY)
	assert_eq(UITheme.button_role(button), UITheme.ROLE_SECONDARY,
		"re-applying a role updates what the button reports")
	assert_eq(button.self_modulate, UITheme.role_modulate(UITheme.ROLE_SECONDARY),
		"and re-tints the plate to the new role")
	button.free()

	# The scrolling panel body is the third seam both side panels had built identically — and
	# both had inherited the same defect from it, a scrollbar drawn over the value column.
	var probe_panel := Control.new()
	var rows := UITheme.scroll_body(probe_panel)
	assert_not_null(rows, "the scroll-body factory returns the row container")
	var scroll := probe_panel.get_node_or_null("ScrollBody") as ScrollContainer
	assert_not_null(scroll, "it adds a ScrollContainer")
	if scroll != null:
		# The one node in the subtree that must receive input, or the wheel passes through
		# and clipped content is unreachable (L-028).
		assert_eq(scroll.mouse_filter, Control.MOUSE_FILTER_STOP,
			"the scroll container accepts input even though its panel ignores it")
		assert_true(scroll.follow_focus,
			"keyboard focus cannot land on a row scrolled out of sight")
	var gutter := probe_panel.get_node_or_null("ScrollBody/ScrollGutter") as MarginContainer
	assert_not_null(gutter, "and a gutter container")
	if gutter != null:
		assert_eq(gutter.get_theme_constant("margin_right"), UIPalette.SCROLLBAR_GUTTER,
			("the gutter reserves the scrollbar's width, so a right-aligned value column "
				+ "is never drawn underneath it"))
	probe_panel.free()

	# STRUCTURAL: no screen constructs any of these seams itself.
	#
	# `ProgressBar.new()` is in the list because of a documentation claim that turned out to be
	# false: `UI_UX_BIBLE.md` §8b says a screen that builds its own seam fails a structural
	# test, and that was true of the divider, backdrop, button and scroll body but NOT of the
	# gauge, which was only covered by a COUNT assertion in the HUD test. Writing the claim
	# down is what exposed the gap; the token closes it rather than softening the sentence.
	var tokens: Array[String] = [
		"BackdropGradient", "Vignette", "MENU_BUTTON_WIDTH", "ScrollContainer.new()",
		"ProgressBar.new()",
	]
	var offenders: Array[String] = []
	for path in _presentation_scripts("res://src/presentation"):
		if path.get_file() == "ui_theme.gd" or path.get_file() == "ui_palette.gd":
			continue
		var source := _read_source(path)
		for token in tokens:
			if source.contains(token):
				offenders.append("%s (%s)" % [path.get_file(), token])
	assert_eq(str(offenders), str([]),
		("a screen must ask UITheme.build_backdrop()/menu_button() rather than assembling "
			+ "either itself. Offenders: %s") % str(offenders))


## The promoted ornament assets must exist and must still be the MASKS the audit chose them
## for. A pack update that replaced them with pre-coloured art would silently break the tint
## seam: the frame would stop responding to `UIPalette`, and nothing else would notice.
func test_d050_the_promoted_ornament_assets_are_present() -> void:
	for path in [
		UIPalette.TEX_ORNAMENT_DIVIDER,
		UIPalette.TEX_ORNAMENT_FRAME,
	]:
		assert_true(ResourceLoader.exists(String(path)),
			"the promoted ornament asset '%s' exists in runtime assets" % String(path))
	# The frame's 9-slice margin must be >= its border band (the notched corner reaches 5px in),
	# or the corners stretch — the `content_margin >= texture_margin` rule for a NinePatch.
	assert_true(UIPalette.ORNAMENT_FRAME_MARGIN >= 8,
		"the frame's patch margin (%d) is at least its measured 8px border band"
			% UIPalette.ORNAMENT_FRAME_MARGIN)
	var frame := UITheme.ornament_frame()
	assert_not_null(frame, "the theme exposes an ornament frame factory")
	assert_eq(frame.patch_margin_left, UIPalette.ORNAMENT_FRAME_MARGIN,
		"and nine-patches it from the palette constant on every side")
	assert_eq(frame.modulate, UIPalette.GOLD_PRIMARY, "tinted gold from the palette")
	frame.free()


## A full-height side panel must start BELOW the strip the top plaques own, or it covers them
## — which both panels were doing until a capture showed it. This is the STRUCTURAL half:
## the HUD must consume the token rather than typing an inset. The token's VALUE is a
## different question and this test cannot answer it; `test_gameplay_hud.gd`'s
## `test_the_reserved_top_strip_is_tall_enough_for_the_plaques_it_reserves_for` measures the
## plaques and asserts the number clears them. Both halves are needed: this one passed for a
## reserve of 104 that was 70px too small (L-034).
func test_d050_side_panels_clear_the_top_plaque_strip() -> void:
	assert_true(UIPalette.TOP_PLAQUE_RESERVE > 0,
		"a reserved top strip exists for the identity + map/world plaques")
	var source := _read_source("res://src/presentation/hud/gameplay_hud.gd")
	assert_true(source.contains("TOP_PLAQUE_RESERVE"),
		("the HUD's side-panel bounds must consume TOP_PLAQUE_RESERVE, so 'a panel must not "
			+ "cover the plaque' is arithmetic rather than something to spot in a screenshot"))


## The semantic token aliases the UI bible uses must resolve, and DANGER must stay distinct
## from interaction — colour is never the only carrier of meaning, but when it carries any, it
## must not collide.
func test_d050_semantic_tokens_are_distinct() -> void:
	assert_ne(UIPalette.CRIMSON_DANGER, UIPalette.JADE_ACCENT,
		"danger and interaction are different colours")
	assert_ne(UIPalette.GOLD_PRIMARY, UIPalette.JADE_ACCENT,
		"structure and interaction are different colours")
	assert_ne(UIPalette.TEXT_PRIMARY, UIPalette.TEXT_SECONDARY,
		"primary and secondary text differ")
	# Every text token is LIGHT, which is why a text-bearing surface must measure dark.
	for token in [UIPalette.TEXT_PRIMARY, UIPalette.TEXT_SECONDARY]:
		var luminance: float = 0.299 * token.r + 0.587 * token.g + 0.114 * token.b
		assert_true(luminance > 0.4,
			"the text palette is light (luma %.2f), which is the premise the surface "
				% luminance + "brightness limit protects")


## The menu backdrop must be cropped past the painting's flat dead margin.
##
## The constant is not taken on trust: this MEASURES the art the same way the audit did and
## asserts the constant still matches it, so a re-export of the painting with a different
## margin fails here instead of putting a ~90px bar of flat near-black down the left of the
## main menu — which is what shipped, and which reads as the backdrop having failed to load.
## Deriving the number from the pixels is the L-029 rule: never author a count beside the
## data it counts.
func test_d050_the_menu_backdrop_is_cropped_past_its_dead_margin() -> void:
	var source := load(UIPalette.TEX_MENU_BACKDROP) as Texture2D
	assert_not_null(source, "the painted backdrop loads")
	if source == null:
		return
	var image := source.get_image()
	assert_not_null(image, "and yields an image to measure")
	if image == null:
		return
	if image.is_compressed():
		image.decompress()
	var flat_columns := _flat_left_columns(image)
	assert_true(flat_columns > 0,
		"the measurement works at all (found %d flat columns)" % flat_columns)
	assert_eq(UIPalette.MENU_BACKDROP_DEAD_LEFT_PX, flat_columns,
		("MENU_BACKDROP_DEAD_LEFT_PX (%d) must equal the painting's MEASURED flat left "
			+ "margin (%d). If the art changed, change the constant to the measurement.") % [
				UIPalette.MENU_BACKDROP_DEAD_LEFT_PX, flat_columns])

	# And the theme must actually apply it: an atlas view starting past the margin.
	var backdrop := UITheme.menu_backdrop()
	assert_not_null(backdrop, "the theme exposes a backdrop texture")
	var atlas := backdrop as AtlasTexture
	assert_not_null(atlas,
		"it is an AtlasTexture (a view onto the same texture), not the raw painting")
	if atlas == null:
		return
	assert_eq(int(atlas.region.position.x), UIPalette.MENU_BACKDROP_DEAD_LEFT_PX,
		"the crop starts exactly past the dead margin")
	assert_eq(int(atlas.region.size.x),
		image.get_width() - UIPalette.MENU_BACKDROP_DEAD_LEFT_PX,
		"and keeps every remaining column of painted content")
	assert_eq(int(atlas.region.size.y), image.get_height(),
		"the crop is horizontal only — the top and bottom edges carry real content")


## Number of leading columns that are a FLAT fill (uniform to within `FLAT_LUMA_RANGE`), i.e.
## painted dead margin rather than art. Stops at the first column with real variation.
func _flat_left_columns(image: Image) -> int:
	# A painted column of real art varies by 100+ levels over the height; a dead margin
	# measured <= 5. The threshold sits far from both, so it is not a knife edge.
	const FLAT_LUMA_RANGE := 8.0
	var height := image.get_height()
	for x in image.get_width():
		var lowest := 2.0
		var highest := -1.0
		for y in height:
			var luma := image.get_pixel(x, y).get_luminance()
			lowest = minf(lowest, luma)
			highest = maxf(highest, luma)
		if (highest - lowest) * 255.0 > FLAT_LUMA_RANGE:
			return x
	return 0


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

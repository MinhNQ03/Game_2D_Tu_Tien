extends TestCase
## Structural tests for the MainMenu (Phase 04 UI hardening; Settings enabled in D-035). The
## menu must wear the shared asset-backed theme, build the title treatment + four action
## buttons, keep Load Game disabled until save exists, resolve all text through Localization
## (no raw keys shown), and emit intent signals WITHOUT owning gameplay. It reads /root
## autoloads (live in the runner, D-019) read-only; `set_menu_context()` resets InputService
## to its baseline (MENU) so no cross-test contamination (the GameState guard stays green).

const MenuScript := preload("res://src/presentation/menus/main_menu.gd")


func _menu() -> Control:
	var menu: Control = MenuScript.new()
	add_to_tree(menu)
	return menu


func test_menu_uses_shared_asset_theme() -> void:
	var menu := _menu()
	assert_not_null(menu.theme, "menu has a theme applied")
	assert_true(menu.theme.has_stylebox("normal", "Button"),
		"menu theme carries the shared button style")
	free_node(menu)


func test_menu_has_four_action_buttons() -> void:
	var menu := _menu()
	var buttons := _collect_buttons(menu)
	assert_true(buttons.size() >= 4,
		"menu builds New Game / Load Game / Settings / Quit (got %d)" % buttons.size())
	free_node(menu)


## Load Game stays disabled until the save system lands (Phase 23); Settings is LIVE as of
## D-035 because it carries the vi/en language switch the beta builds are tested with.
func test_only_load_game_is_disabled() -> void:
	var menu := _menu()
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "en")
	var buttons := _collect_buttons(menu)
	var disabled_texts: Array = []
	var enabled_texts: Array = []
	for b in buttons:
		if b.disabled:
			disabled_texts.append(b.text)
		else:
			enabled_texts.append(b.text)
	assert_true("Load Game" in disabled_texts, "Load Game is disabled (no save yet)")
	assert_true("Settings" in enabled_texts, "Settings is enabled (language switch, D-035)")
	assert_true("New Game" in enabled_texts, "New Game is enabled")
	assert_true("Quit" in enabled_texts, "Quit is enabled")
	free_node(menu)


func test_menu_emits_intents_without_owning_gameplay() -> void:
	var menu := _menu()
	var fired := {"new_game": 0, "settings": 0, "quit": 0}
	menu.new_game_pressed.connect(func() -> void: fired["new_game"] += 1)
	menu.settings_pressed.connect(func() -> void: fired["settings"] += 1)
	menu.quit_pressed.connect(func() -> void: fired["quit"] += 1)
	# Fire the buttons' own `pressed` signal (the real path the menu listens to) so we drive
	# the public behaviour, not a private handler. The menu only EMITS its intent signals; it
	# does not touch GameState/SceneRouter/Localization (that wiring lives in Main).
	for b in _collect_buttons(menu):
		if not b.disabled:
			b.pressed.emit()
	assert_eq(fired["new_game"], 1, "new_game_pressed emitted")
	assert_eq(fired["settings"], 1, "settings_pressed emitted (D-035)")
	assert_eq(fired["quit"], 1, "quit_pressed emitted")
	free_node(menu)


func test_menu_text_is_localized_not_raw_keys() -> void:
	var menu := _menu()
	# Switch language via Localization; it emits `language_changed` on the EventBus, which the
	# menu listens to and re-resolves its text — the real localization path (no private call).
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "vi")
		loc.call("set_language", "en")
	await scene_tree.process_frame
	for b in _collect_buttons(menu):
		assert_false(b.text.begins_with("UI_MENU_"), "button shows localized text, not a key")
		assert_ne(b.text, "", "button text resolved")
	free_node(menu)


func _collect_buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out += _collect_buttons(child)
	return out


# --- D-041 production-foundation visual pass ---------------------------------

## The menu must no longer be a plaque floating on a flat fill (D-041 A2). It must compose a
## real backdrop: a deep ground, a gradient that gives the screen a horizon, and a vignette.
func test_menu_builds_a_composed_backdrop_not_a_flat_void() -> void:
	var menu := _menu()
	var fill := menu.get_node_or_null("Background") as ColorRect
	assert_not_null(fill, "a deep ink ground exists")
	if fill != null:
		assert_eq(fill.color, UIPalette.COLOR_BACKGROUND_DEEP,
			"the ground uses the deep night-blue token, not neutral black")
	var sky := menu.get_node_or_null("BackdropGradient") as TextureRect
	assert_not_null(sky, "the backdrop gradient layer exists (the horizon)")
	if sky != null:
		assert_not_null(sky.texture, "the gradient layer actually carries a texture")
		# A smooth ramp stretched full-screen must be LINEAR-filtered or it bands.
		assert_eq(sky.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR,
			"the gradient is linear-filtered so it does not band")
	var vignette := menu.get_node_or_null("Vignette") as TextureRect
	assert_not_null(vignette, "the vignette layer exists")
	# Backdrop layers must never eat input meant for the buttons.
	for layer_name in ["Background", "BackdropGradient", "Vignette"]:
		var layer := menu.get_node_or_null(layer_name) as Control
		if layer != null:
			assert_eq(layer.mouse_filter, Control.MOUSE_FILTER_IGNORE,
				"%s ignores mouse input" % layer_name)
	free_node(menu)


## Four corner ornaments frame the composition, each pointing outward.
func test_menu_frames_the_screen_with_four_corner_ornaments() -> void:
	var menu := _menu()
	var expected := {
		"OrnamentTL": [false, false], "OrnamentTR": [true, false],
		"OrnamentBL": [false, true], "OrnamentBR": [true, true],
	}
	for ornament_name in expected:
		var piece := menu.get_node_or_null(String(ornament_name)) as TextureRect
		assert_not_null(piece, "%s exists" % ornament_name)
		if piece == null:
			continue
		var flips: Array = expected[ornament_name]
		assert_eq(piece.flip_h, bool(flips[0]), "%s horizontal flip" % ornament_name)
		assert_eq(piece.flip_v, bool(flips[1]), "%s vertical flip" % ornament_name)
		# Without EXPAND_IGNORE_SIZE the 61x61 texture becomes the minimum size and
		# `custom_minimum_size` silently does nothing (D-034 / L-021).
		assert_eq(piece.expand_mode, TextureRect.EXPAND_IGNORE_SIZE,
			"%s can actually be sized" % ornament_name)
		assert_eq(piece.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"%s stays crisp pixel art" % ornament_name)
		assert_true(piece.modulate.a < 1.0,
			"%s is a restrained accent, not a solid graphic" % ornament_name)
	free_node(menu)


## Button hierarchy must be real at runtime, not just available in the theme (A4): the
## primary action and the exit action must not look like the two ordinary ones.
func test_menu_buttons_carry_semantic_role_hierarchy() -> void:
	var menu := _menu()
	var buttons := _collect_buttons(menu)
	assert_eq(buttons.size(), 4, "four action buttons")
	if buttons.size() < 4:
		free_node(menu)
		return
	var new_game: Button = buttons[0]
	var load_game: Button = buttons[1]
	var settings: Button = buttons[2]
	var quit: Button = buttons[3]

	assert_ne(new_game.self_modulate, settings.self_modulate,
		"the PRIMARY action is tinted differently from an ordinary one")
	assert_ne(quit.self_modulate, settings.self_modulate,
		"the EXIT action is tinted differently from an ordinary one")
	assert_eq(load_game.self_modulate, settings.self_modulate,
		"the two ordinary actions share one treatment")
	assert_eq(new_game.get_theme_color("font_color"), UIPalette.COLOR_TITLE,
		"the primary label reads in gold")
	assert_eq(quit.get_theme_color("font_color"), UIPalette.COLOR_CRIMSON_HOVER,
		"the exit label reads in the reserved crimson")
	# Uniform size: the column must read as one engraved stack.
	for button in buttons:
		assert_eq((button as Button).custom_minimum_size.x,
			float(UIPalette.MENU_BUTTON_WIDTH), "every button shares the token width")
		assert_eq((button as Button).custom_minimum_size.y,
			float(UIPalette.BUTTON_HEIGHT), "every button shares the token height")
	free_node(menu)


## Hover/focus must visibly change the button, on every role — keyboard focus included,
## because this project is keyboard-first (`UI_UX_BIBLE.md` §4).
##
## It is driven on SETTINGS, not on New Game: `_ready()` deliberately grabs focus for the
## primary action so a keyboard player lands on it, which means New Game is ALREADY in its
## lifted focus state at build time. Reading an "at rest" baseline off it captures the lifted
## tint and every later comparison comes out backwards — the first version of this test did
## exactly that and failed in CI. Settings is live, focusable and unfocused, so it is the
## honest subject; the primary button's lifted-on-entry state is pinned separately below.
func test_menu_button_hover_and_focus_change_appearance() -> void:
	var menu := _menu()
	var buttons := _collect_buttons(menu)
	if buttons.size() < 4:
		free_node(menu)
		return
	var settings: Button = buttons[2]
	assert_false(settings.has_focus(), "the subject starts unfocused (test precondition)")
	var at_rest := settings.self_modulate
	settings.mouse_entered.emit()
	assert_ne(settings.self_modulate, at_rest, "hover lifts the button")
	settings.mouse_exited.emit()
	assert_eq(settings.self_modulate, at_rest, "leaving restores it")
	settings.focus_entered.emit()
	assert_ne(settings.self_modulate, at_rest,
		"KEYBOARD focus is as visible as mouse hover")
	settings.focus_exited.emit()
	assert_eq(settings.self_modulate, at_rest, "losing focus restores it")
	free_node(menu)


## The primary action must be VISIBLY the focused one the moment the menu opens, because a
## keyboard player gets no mouse cursor to tell them where they are. `_ready()` grabs focus
## for New Game, and the role tint must reflect that rather than leaving the button looking
## identical to the two secondary actions it sits above.
func test_primary_action_opens_already_focused_and_looks_it() -> void:
	var menu := _menu()
	var buttons := _collect_buttons(menu)
	if buttons.is_empty():
		free_node(menu)
		return
	var primary: Button = buttons[0]
	assert_eq(primary.self_modulate, UITheme.role_modulate(UITheme.ROLE_PRIMARY, true),
		"New Game wears its FOCUSED role tint on entry, not the at-rest one")
	assert_ne(primary.self_modulate, UITheme.role_modulate(UITheme.ROLE_PRIMARY, false),
		"the focused tint is actually distinguishable from the at-rest tint")
	free_node(menu)


## The visual pass must not have changed behaviour: the signals, the disabled Load state and
## the localized labels are the contract the coordinator depends on (A20).
func test_menu_behaviour_survived_the_visual_pass() -> void:
	var menu := _menu()
	for signal_name in ["new_game_pressed", "settings_pressed", "quit_pressed"]:
		assert_true(menu.has_signal(signal_name), "%s still exists" % signal_name)
	var buttons := _collect_buttons(menu)
	assert_eq(buttons.size(), 4, "still four actions")
	if buttons.size() == 4:
		assert_false((buttons[0] as Button).disabled, "New Game is live")
		assert_true((buttons[1] as Button).disabled, "Load Game stays disabled until Phase 23")
		assert_false((buttons[2] as Button).disabled, "Settings is live (D-035)")
		assert_false((buttons[3] as Button).disabled, "Quit is live")
		for button in buttons:
			assert_ne((button as Button).text, "", "every button has localized text")
			assert_eq((button as Button).focus_mode, Control.FOCUS_ALL,
				"every button is keyboard reachable")
	free_node(menu)


## The menu root must actually FILL the screen.
##
## This is the regression guard for the defect that made the whole menu render crammed into
## the top-left corner at a few hundred pixels. `set_anchors_preset(p, keep_offsets = false)`
## does NOT zero the offsets — it recomputes them to PRESERVE the control's current rect. The
## menu is instantiated from `main_menu.tscn`, whose root Control has no authored size, so the
## current rect was 0x0 and the call faithfully kept it 0x0 while setting full-rect anchors.
## The `CenterContainer` then centred the plaque inside a 0x0 box at the origin and the four
## screen-corner ornaments collapsed onto it.
##
## Asserting the ANCHORS alone would have passed on the broken build — they were already
## full-rect. The offsets are what was wrong, so the offsets are what this pins.
func test_menu_root_fills_the_screen() -> void:
	var menu := _menu()
	assert_eq(menu.anchor_left, 0.0, "the menu root is anchored to the left edge")
	assert_eq(menu.anchor_top, 0.0, "and the top edge")
	assert_eq(menu.anchor_right, 1.0, "and stretches to the right edge")
	assert_eq(menu.anchor_bottom, 1.0, "and to the bottom edge")
	# The offsets must be ZERO. A non-zero offset against full-rect anchors means the rect was
	# preserved instead of reset — exactly the bug.
	for pair in [
		["left", menu.offset_left], ["top", menu.offset_top],
		["right", menu.offset_right], ["bottom", menu.offset_bottom],
	]:
		assert_eq(float(pair[1]), 0.0,
			("the menu root's %s offset is 0, so full-rect anchors actually produce a "
				+ "full-rect box (got %s) — a preserved 0x0 rect is what crammed the whole "
				+ "menu into the corner") % [str(pair[0]), str(pair[1])])
	free_node(menu)


## The backdrop layers must fill the menu too — a gradient that covers only part of the screen
## leaves the rest flat black, which is what "a panel floating in a void" looked like.
func test_menu_backdrop_layers_fill_the_menu() -> void:
	var menu := _menu()
	var covered := 0
	for child in menu.get_children():
		var control := child as Control
		if control == null:
			continue
		if not (control is ColorRect or control is TextureRect):
			continue
		# Only the full-screen layers, not the corner ornaments (which are deliberately small).
		# ALL FOUR anchors must be checked: a BOTTOM_RIGHT-anchored ornament also has
		# `anchor_right == 1` and `anchor_bottom == 1`, so filtering on those two alone let
		# `OrnamentBR` through and the test failed on its intentional -18 inset.
		if control.anchor_left != 0.0 or control.anchor_top != 0.0:
			continue
		if control.anchor_right != 1.0 or control.anchor_bottom != 1.0:
			continue
		covered += 1
		assert_eq(float(control.offset_right), 0.0,
			"backdrop layer '%s' reaches the right edge" % control.name)
		assert_eq(float(control.offset_bottom), 0.0,
			"backdrop layer '%s' reaches the bottom edge" % control.name)
	assert_true(covered >= 2,
		"the ground fill and the gradient both span the screen (got %d)" % covered)
	free_node(menu)

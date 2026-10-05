extends TestCase
## Structural tests for the SettingsMenu (D-035) — the screen that lets a beta tester switch
## the game between Vietnamese and English.
##
## Contract under test: it builds one button per SUPPORTED language (read from the service,
## not a second hard-coded list), shows LOCALIZED language names rather than raw codes,
## actually changes the active language when a button is pressed, marks the active choice,
## and emits `close_requested` instead of navigating itself.
##
## It reads the live /root autoloads (D-019). It DOES mutate the shared Localization
## language — which is what it exists to do — so every test restores the original language
## afterwards, and the runner's isolation guard (shared GameState phase) stays untouched.

const SettingsScript := preload("res://src/presentation/menus/settings_menu.gd")
const LocScript := preload("res://src/infrastructure/localization.gd")


func _loc() -> Node:
	return scene_tree.root.get_node_or_null("Localization")


func _screen() -> Control:
	var screen: Control = SettingsScript.new()
	add_to_tree(screen)  # _ready() builds the UI + resolves autoloads
	return screen


func _buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child as Button)
		_buttons(child, out)


func _button_texts(screen: Control) -> Array:
	var found: Array[Button] = []
	_buttons(screen, found)
	var out: Array = []
	for b in found:
		out.append(b.text)
	return out


## Settings must be a COMPOSED screen, not a plaque on a flat fill (D-050).
##
## It shipped as the one screen that never got the D-041 composition: the menu had a painted
## backdrop, a horizon gradient, a vignette and four corner ornaments, and this screen had a
## single near-black `ColorRect`. Not a decision — the composition lived inside
## `main_menu.gd`, so the only way to have it here was to copy sixty lines. It now comes from
## `UITheme.build_backdrop()`, and this asserts the layers actually arrive.
func test_settings_is_a_composed_screen_not_a_flat_void() -> void:
	var screen := _screen()
	var fill := screen.get_node_or_null("Background") as ColorRect
	assert_not_null(fill, "a deep ink ground exists")
	if fill != null:
		assert_eq(fill.color, UIPalette.COLOR_BACKGROUND_DEEP,
			"the ground uses the deep night-blue token, not neutral black")
	for layer_name in ["BackdropGradient", "BackdropScene", "Vignette"]:
		var layer := screen.get_node_or_null(layer_name) as TextureRect
		assert_not_null(layer, "the %s layer exists" % layer_name)
		if layer == null:
			continue
		assert_not_null(layer.texture, "%s carries a texture" % layer_name)
		# A backdrop layer must never eat a click meant for a button.
		assert_eq(layer.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"%s ignores mouse input" % layer_name)
	for ornament_name in ["OrnamentTL", "OrnamentTR", "OrnamentBL", "OrnamentBR"]:
		assert_not_null(screen.get_node_or_null(ornament_name),
			"the %s corner ornament frames this screen too" % ornament_name)
	free_node(screen)


## One button per supported language, plus Back.
func test_builds_one_button_per_supported_language_plus_back() -> void:
	var screen := _screen()
	var found: Array[Button] = []
	_buttons(screen, found)
	var expected := LocScript.SUPPORTED_LANGUAGES.size() + 1
	assert_eq(found.size(), expected,
		"a button per supported language (%d) plus Back" % LocScript.SUPPORTED_LANGUAGES.size())
	free_node(screen)


## Language names must be localized words, never the raw "vi"/"en" codes, and never a raw
## localization key (`07-localization.md`).
func test_language_names_are_localized_not_raw_codes_or_keys() -> void:
	var loc := _loc()
	if loc == null:
		return
	var original := String(loc.call("get_language"))
	var screen := _screen()
	var texts := _button_texts(screen)
	for t in texts:
		assert_ne(t, "", "every button has text")
		assert_false(t.begins_with("UI_"), "button shows localized text, not a key (%s)" % t)
	# "Tiếng Việt" and "English" are the authored names; the active one is marked with > <.
	var joined := "|".join(texts)
	assert_true(joined.contains("Tiếng Việt"), "the Vietnamese option is named in Vietnamese")
	assert_true(joined.contains("English"), "the English option is named in English")
	free_node(screen)
	loc.call("set_language", original)


## Pressing a language button must actually change the ACTIVE language through the service —
## the whole point of the screen. Driven via the button's own `pressed` signal (the real
## path), not a private handler.
func test_pressing_a_language_button_switches_the_active_language() -> void:
	var loc := _loc()
	if loc == null:
		return
	var original := String(loc.call("get_language"))
	loc.call("set_language", "vi")
	var screen := _screen()

	var found: Array[Button] = []
	_buttons(screen, found)
	# Press the button whose label is the English option (not the Back button).
	var pressed_english := false
	for b in found:
		if b.text.contains("English"):
			b.pressed.emit()
			pressed_english = true
			break
	assert_true(pressed_english, "found the English option to press")
	await scene_tree.process_frame
	assert_eq(String(loc.call("get_language")), "en",
		"pressing the English option switched the active language")

	free_node(screen)
	loc.call("set_language", original)


## The active language is marked by TWO carriers, because neither is sufficient alone: a
## LOCALIZED text marker (readable regardless of theme or colour vision) and the PRIMARY
## button role (visible at a glance).
##
## It used to be `> Tiếng Việt <` — untranslatable ASCII punctuation wrapped around a
## translated name, which also pushed the label off-centre, and the only carrier. The test
## asserted that exact string, so it pinned the punctuation rather than the contract. It now
## asserts the marker is the LOCALIZED template applied to the language name, so changing the
## wording in the CSV does not break the test but dropping the marker does.
func test_active_language_is_marked_in_text_and_by_role() -> void:
	var loc := _loc()
	if loc == null:
		return
	var original := String(loc.call("get_language"))
	loc.call("set_language", "vi")
	var screen := _screen()

	var expected := String(loc.call("t_args", "UI_SETTINGS_LANGUAGE_ACTIVE",
		{"language": String(loc.call("t", "UI_LANGUAGE_VI"))}))
	assert_ne(expected, "UI_SETTINGS_LANGUAGE_ACTIVE",
		"the active-language marker has a localization row (an unresolved key returns itself)")
	var texts := _button_texts(screen)
	assert_true("|".join(texts).contains(expected),
		"the active language carries the localized in-use marker, got %s" % str(texts))

	# And the ROLE: exactly one language button is promoted to PRIMARY.
	var found: Array[Button] = []
	_buttons(screen, found)
	var primary := 0
	for button in found:
		if UITheme.button_role(button) == UITheme.ROLE_PRIMARY:
			primary += 1
			assert_true(button.text.contains(expected),
				"the PRIMARY-role button is the active language, not some other action")
	assert_eq(primary, 1,
		"exactly one button wears the PRIMARY role — the language in use (got %d)" % primary)

	free_node(screen)
	loc.call("set_language", original)


## The screen asks to be closed; it must NOT navigate or touch the lifecycle itself (Main
## owns navigation, exactly like the MainMenu intents).
func test_back_emits_close_requested() -> void:
	var screen := _screen()
	var fired := {"closed": 0}
	screen.close_requested.connect(func() -> void: fired["closed"] += 1)
	var found: Array[Button] = []
	_buttons(screen, found)
	# Back is the last button built.
	found[found.size() - 1].pressed.emit()
	assert_eq(fired["closed"], 1, "Back emitted close_requested")
	free_node(screen)

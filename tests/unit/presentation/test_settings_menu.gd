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


## The active language is marked in TEXT (not colour alone), so the current choice is
## readable regardless of theme or colour vision.
func test_active_language_is_marked_in_text() -> void:
	var loc := _loc()
	if loc == null:
		return
	var original := String(loc.call("get_language"))
	loc.call("set_language", "vi")
	var screen := _screen()
	var joined := "|".join(_button_texts(screen))
	assert_true(joined.contains("> Tiếng Việt <"),
		"the active language is marked in the label text")
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

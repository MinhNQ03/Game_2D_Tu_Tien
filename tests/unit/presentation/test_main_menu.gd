extends TestCase
## Structural tests for the MainMenu (Phase 04 UI hardening). The menu must wear the shared
## asset-backed theme, build the title treatment + four action buttons, keep Load Game and
## Settings disabled, resolve all text through Localization (no raw keys shown), and emit
## intent signals WITHOUT owning gameplay. It reads /root autoloads (live in the runner,
## D-019) read-only; `set_menu_context()` resets InputService to its baseline (MENU) so no
## cross-test contamination (the GameState isolation guard stays green).

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


func test_load_game_and_settings_are_disabled() -> void:
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
	assert_true("Settings" in disabled_texts, "Settings is disabled (placeholder)")
	assert_true("New Game" in enabled_texts, "New Game is enabled")
	assert_true("Quit" in enabled_texts, "Quit is enabled")
	free_node(menu)


func test_menu_emits_intents_without_owning_gameplay() -> void:
	var menu := _menu()
	var fired := {"new_game": 0, "quit": 0}
	menu.new_game_pressed.connect(func() -> void: fired["new_game"] += 1)
	menu.quit_pressed.connect(func() -> void: fired["quit"] += 1)
	# Fire the buttons' own `pressed` signal (the real path the menu listens to) so we drive
	# the public behaviour, not a private handler. The menu only EMITS its intent signals; it
	# does not touch GameState/SceneRouter (that wiring lives in Main).
	for b in _collect_buttons(menu):
		if not b.disabled:
			b.pressed.emit()
	assert_eq(fired["new_game"], 1, "new_game_pressed emitted")
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

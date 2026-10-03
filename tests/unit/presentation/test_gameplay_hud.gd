extends TestCase
## Structural tests for the GameplayHUD (Phase 04). The HUD must BUILD its labels, render a
## bound character's name key through Localization, and compose the control hint from the
## InputService display label (never a raw keycode). It reads /root autoloads (Localization,
## InputService) which are live in the runner (D-019) and are only READ here, so no shared
## state is mutated (the GameState isolation guard stays green).

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")


func _hud() -> Node:
	var hud: Node = HUDScript.new()
	add_to_tree(hud)  # _ready() builds the labels + resolves autoloads
	return hud


func _player_state() -> RefCounted:
	var stats := StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var t := TemplateScript.new()
	t.id = &"char_x"
	t.name_key = &"CHARACTER_PLAYER_NAME"
	t.title_key = &"CHARACTER_PLAYER_TITLE"
	t.base_stats = stats
	return StateScript.create_from_template(t, &"inst_x")


func test_hud_builds_labels() -> void:
	var hud := _hud()
	# Four labels: name, title, map, hint. Find them by walking the single Control root.
	var labels: Array[Label] = []
	_collect_labels(hud, labels)
	assert_true(labels.size() >= 4, "HUD builds at least name/title/map/hint labels")
	free_node(hud)


func test_hud_shows_character_name() -> void:
	var hud := _hud()
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "en")
	hud.set_character(_player_state())
	# The name label should resolve CHARACTER_PLAYER_NAME ("Wanderer" in en).
	var labels: Array[Label] = []
	_collect_labels(hud, labels)
	var found := false
	for label in labels:
		if label.text == "Wanderer":
			found = true
	assert_true(found, "HUD renders the character's localized name")
	free_node(hud)


func test_hud_prompts_use_graphic_badges_with_display_labels() -> void:
	var hud := _hud()
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "en")
	hud.set_interact_available(true)

	# Gather all label text + confirm the key badges exist as graphic chips (UIKeyBadge is a
	# PanelContainer wearing an asset-backed stylebox — not plain floating text).
	var all_text := _all_label_text(hud)
	assert_true("E" in all_text, "a key badge shows the 'E' glyph")
	assert_true("Esc" in all_text, "a key badge shows the 'Esc' glyph")
	assert_true("Interact" in all_text, "the interact prompt shows the localized action word")
	assert_true("Menu" in all_text, "the menu prompt shows the localized action word")
	# Never leak a raw keycode number or a raw action name.
	for t in all_text:
		assert_false(t.contains("69"), "no raw keycode in a prompt (%s)" % t)
		assert_false(t.contains("interact"), "no raw action name in a prompt (%s)" % t)
		assert_false(t.contains("open_menu"), "no raw action name in a prompt (%s)" % t)

	# The key glyphs sit inside graphic badge panels (PanelContainer holding a single Label),
	# proving a graphic treatment, not floating text. Interact + menu => at least 2.
	assert_true(_key_badge_count(hud) >= 2, "interact + menu each have a graphic key badge")
	free_node(hud)


## Collect every Label's text under a node (recursive).
func _all_label_text(node: Node) -> Array:
	var out: Array = []
	var labels: Array[Label] = []
	_collect_labels(node, labels)
	for label in labels:
		out.append(label.text)
	return out


## Count key-badge chips: PanelContainers whose only child is a Label (the UIKeyBadge shape).
func _key_badge_count(node: Node) -> int:
	var n := 0
	if node is PanelContainer and node.get_child_count() == 1 and node.get_child(0) is Label:
		n += 1
	for child in node.get_children():
		n += _key_badge_count(child)
	return n


## Walk the HUD subtree collecting every Label (the HUD builds them under a Control root).
func _collect_labels(node: Node, out: Array[Label]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child as Label)
		_collect_labels(child, out)

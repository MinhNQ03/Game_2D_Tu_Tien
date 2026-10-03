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


func test_hud_hint_uses_display_label_not_keycode() -> void:
	var hud := _hud()
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "en")
	hud.set_interact_available(true)
	var labels: Array[Label] = []
	_collect_labels(hud, labels)
	var hint_text := ""
	for label in labels:
		if label.text.contains("Interact") or label.text.contains("Menu"):
			hint_text = label.text
	assert_true(hint_text.contains("E"), "interact hint shows the 'E' key label")
	assert_true(hint_text.contains("Esc"), "menu hint shows the 'Esc' key label")
	# It must NOT leak a raw keycode number.
	assert_false(hint_text.contains("69"), "no raw keycode in the hint")
	free_node(hud)


## Walk the HUD subtree collecting every Label (the HUD builds them under a Control root).
func _collect_labels(node: Node, out: Array[Label]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child as Label)
		_collect_labels(child, out)

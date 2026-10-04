extends TestCase
## Tests for the `FactionPanel` (Phase 07 presentation): it must render a `SectPoliticsView`
## through Localization, never leak a raw content id or an enum number to the screen (§21),
## distinguish "no session" from "this sect has no factions", report truncation instead of
## silently dropping a faction, and wear the shared D-041 visual language.
##
## The view is built BY HAND here rather than from a live session: that is the point of a
## read-only DTO — presentation can be tested against any landscape, including ones the
## shipped content does not contain (a player faction, an ALLIED relation, an overflow).
##
## `FactionPanel` extends PanelContainer, so every instance is freed in every method (L-019).

const PanelScript := preload("res://src/presentation/faction/faction_panel.gd")
const ViewScript := preload("res://src/presentation/faction/sect_politics_view.gd")
const TemplateScript := preload("res://src/data/factions/faction_template_data.gd")


func _panel() -> Node:
	var panel: Node = PanelScript.new()
	add_to_tree(panel)  # _ready() resolves Localization + builds the labels
	return panel


func _use_language(code: String) -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", code)


func _localized(key: String) -> String:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc == null:
		return ""
	return String(loc.call("t", key))


func _row(
		name_key: StringName,
		stance: int,
		influence: int,
		share: int) -> SectPoliticsView.Row:
	var row := SectPoliticsView.Row.new()
	row.name_key = name_key
	row.doctrine_key = &"FACTION_AZURE_TERRACE_DOCTRINE"
	row.stance = stance
	row.influence = influence
	row.influence_share = share
	var keys: Array[StringName] = [&"FACTION_GOAL_KEEP_COVENANT"]
	row.goal_keys = keys
	return row


func _view(rows: Array) -> SectPoliticsView:
	var view: SectPoliticsView = ViewScript.new()
	view.is_available = true
	view.sect_id = &"sect_azure_cloud"
	view.total_influence = 100
	var listed: Array[SectPoliticsView.Row] = []
	for row in rows:
		listed.append(row)
	view.rows = listed
	return view


## Collect every Label's text under a node (recursive), VISIBLE ones only — a hidden label
## still holds its old text, and asserting on hidden text would let a panel "pass" while
## showing the player nothing.
func _visible_text(node: Node) -> Array:
	var out: Array = []
	_collect_visible(node, out)
	return out


func _collect_visible(node: Node, out: Array) -> void:
	for child in node.get_children():
		var control := child as Control
		if control != null and not control.visible:
			continue
		if child is Label:
			out.append((child as Label).text)
		_collect_visible(child, out)


func _joined(node: Node) -> String:
	var parts: Array[String] = []
	for text in _visible_text(node):
		parts.append(String(text))
	return "\n".join(parts)


func test_panel_builds_and_wears_the_shared_panel_plate() -> void:
	var panel := _panel()
	assert_true(panel is PanelContainer, "the panel is a framed PanelContainer")
	assert_not_null((panel as PanelContainer).get_theme_stylebox("panel"),
		"it wears a panel stylebox (the shared D-041 plate, not a bare rect)")
	assert_true((panel as Control).custom_minimum_size.x > 0,
		"it declares a width FLOOR so a long localized string can still widen it")
	free_node(panel)


## "No session" and "this sect has no factions" are DIFFERENT statements and must read
## differently — collapsing them would tell the player their sect is apolitical when the
## truth is that the subsystem is not running.
func test_no_session_and_no_factions_read_differently() -> void:
	var panel := _panel()
	_use_language("en")

	panel.call("set_view", ViewScript.new())  # is_available == false
	var unavailable := _joined(panel)
	assert_true(unavailable.contains(_localized("UI_FACTION_PANEL_UNAVAILABLE")),
		"with no session the panel says so (got '%s')" % unavailable)

	panel.call("set_view", _view([]))  # available, but zero rows
	var empty := _joined(panel)
	assert_true(empty.contains(_localized("UI_FACTION_PANEL_NONE")),
		"with a live session and no factions it says THAT instead (got '%s')" % empty)
	assert_ne(_localized("UI_FACTION_PANEL_UNAVAILABLE"), _localized("UI_FACTION_PANEL_NONE"),
		"and the two messages are genuinely different text")
	free_node(panel)


func test_panel_renders_localized_names_goals_and_doctrine() -> void:
	var panel := _panel()
	_use_language("en")
	panel.call("set_view", _view([
		_row(&"FACTION_AZURE_TERRACE_NAME", TemplateScript.Stance.LOYALIST, 45, 39),
	]))
	var text := _joined(panel)

	assert_true(text.contains(_localized("UI_FACTION_PANEL_TITLE")), "the section title shows")
	assert_true(text.contains(_localized("FACTION_AZURE_TERRACE_NAME")),
		"the faction's localized name shows")
	assert_true(text.contains(_localized("FACTION_AZURE_TERRACE_DOCTRINE")),
		"and the argument it is making — the reason the panel exists")
	assert_true(text.contains(_localized("FACTION_GOAL_KEEP_COVENANT")),
		"its goals show, localized")
	assert_true(text.contains(_localized("FACTION_STANCE_LOYALIST")),
		"its stance shows as a WORD, not an enum number")
	assert_true(text.contains("45"), "the raw influence weight shows")
	assert_true(text.contains("39"), "and its share of the sect")
	free_node(panel)


## §21 / `07-localization.md`: no internal id, enum ordinal or English-ish literal may reach
## the screen. This is the guard that would catch a future row rendered with `str(stance)`.
func test_panel_never_leaks_a_raw_id_or_enum_number() -> void:
	var panel := _panel()
	for language in ["en", "vi"]:
		_use_language(language)
		panel.call("set_view", _view([
			_row(&"FACTION_AZURE_TERRACE_NAME", TemplateScript.Stance.RADICAL, 31, 27),
		]))
		var text := _joined(panel)
		for leak in [
			"faction_azure", "sect_azure_cloud", "FACTION_", "UI_FACTION_", "goal_",
			"LOYALIST", "REFORMIST", "RADICAL",
		]:
			assert_false(text.contains(leak),
				"[%s] no raw token '%s' reaches the screen (got '%s')" % [language, leak, text])
	free_node(panel)


## The sect's direction and a faction's status must be carried by TEXT, not by colour alone —
## colour is never the only carrier of meaning (`UI_UX_BIBLE.md` §4).
func test_status_is_carried_by_words_not_colour_alone() -> void:
	var panel := _panel()
	_use_language("en")

	var contested := _view([
		_row(&"FACTION_AZURE_TERRACE_NAME", TemplateScript.Stance.LOYALIST, 45, 45),
		_row(&"FACTION_AZURE_OPEN_ROAD_NAME", TemplateScript.Stance.REFORMIST, 38, 38),
	])
	contested.is_contested = true
	(contested.rows[0] as SectPoliticsView.Row).is_dominant = true
	panel.call("set_view", contested)
	var text := _joined(panel)
	assert_true(text.contains(_localized("UI_FACTION_PANEL_CONTESTED")),
		"a contested sect says 'contested' in words")
	assert_true(text.contains(_localized("UI_FACTION_PANEL_DOMINANT")),
		"and the leading faction is marked in words")

	var settled := _view([
		_row(&"FACTION_AZURE_TERRACE_NAME", TemplateScript.Stance.LOYALIST, 90, 90),
	])
	settled.is_contested = false
	panel.call("set_view", settled)
	assert_true(_joined(panel).contains(_localized("UI_FACTION_PANEL_SETTLED")),
		"a settled sect says 'settled'")
	free_node(panel)


func test_panel_marks_the_players_side_and_its_relations() -> void:
	var panel := _panel()
	_use_language("en")

	panel.call("set_view", _view([
		_row(&"FACTION_AZURE_TERRACE_NAME", TemplateScript.Stance.LOYALIST, 45, 45),
	]))
	assert_true(_joined(panel).contains(_localized("UI_FACTION_PANEL_NO_SIDE")),
		"with no allegiance the panel says the player has taken no side")

	var mine := _row(&"FACTION_AZURE_OPEN_ROAD_NAME", TemplateScript.Stance.REFORMIST, 38, 38)
	mine.is_player_faction = true
	var theirs := _row(&"FACTION_AZURE_TERRACE_NAME", TemplateScript.Stance.LOYALIST, 45, 45)
	theirs.relation_to_player_faction = &"RIVAL"
	var ally := _row(&"FACTION_AZURE_FRONTIER_NAME", TemplateScript.Stance.RADICAL, 31, 31)
	ally.relation_to_player_faction = &"ALLIED"
	panel.call("set_view", _view([theirs, mine, ally]))
	var text := _joined(panel)
	assert_true(text.contains(_localized("UI_FACTION_PANEL_YOUR_SIDE")),
		"the player's own side is named")
	assert_false(text.contains(_localized("UI_FACTION_PANEL_NO_SIDE")),
		"and the no-side line is gone")
	assert_true(text.contains(_localized("UI_FACTION_PANEL_RELATION_RIVAL")),
		"a rival of the player's side is marked")
	assert_true(text.contains(_localized("UI_FACTION_PANEL_RELATION_ALLIED")),
		"and an ally of it")
	free_node(panel)


## Truncation must be REPORTED. A content author who adds a faction past the panel's capacity
## has to be able to see that it stopped being shown, rather than wondering why their data
## "did not load".
func test_overflow_is_reported_not_silent() -> void:
	var panel := _panel()
	_use_language("en")
	var many: Array = []
	var total := int(PanelScript.MAX_ROWS) + 2
	for i in total:
		many.append(_row(StringName("FACTION_AZURE_TERRACE_NAME"), 0, 10, 10))
	panel.call("set_view", _view(many))
	var text := _joined(panel)
	assert_true(text.contains("+2"),
		"the panel reports how many factions it could not show (got '%s')" % text)
	free_node(panel)


## Refreshing must REUSE the pre-built blocks, not rebuild them: the view is pushed on every
## membership/politics change, and churning nodes on a path the player triggers repeatedly
## would allocate for nothing (`05-performance-testing.md`).
func test_refreshing_reuses_nodes_instead_of_rebuilding() -> void:
	var panel := _panel()
	_use_language("en")
	panel.call("set_view", _view([
		_row(&"FACTION_AZURE_TERRACE_NAME", TemplateScript.Stance.LOYALIST, 45, 45),
	]))
	var before := _count_descendants(panel)
	for _i in 5:
		panel.call("set_view", _view([
			_row(&"FACTION_AZURE_OPEN_ROAD_NAME", TemplateScript.Stance.REFORMIST, 38, 38),
			_row(&"FACTION_AZURE_FRONTIER_NAME", TemplateScript.Stance.RADICAL, 31, 31),
		]))
	assert_eq(_count_descendants(panel), before,
		"the node count is unchanged after five refreshes — blocks are refilled, not rebuilt")
	free_node(panel)


## The stance → key map must be total: an unknown ordinal falls back to a real key rather than
## leaking the number (which is what `str(stance)` on the screen would do).
func test_stance_key_mapping_is_total() -> void:
	assert_eq(FactionPanel.stance_key(TemplateScript.Stance.LOYALIST),
		"FACTION_STANCE_LOYALIST", "loyalist maps to its key")
	assert_eq(FactionPanel.stance_key(TemplateScript.Stance.REFORMIST),
		"FACTION_STANCE_REFORMIST", "reformist maps to its key")
	assert_eq(FactionPanel.stance_key(TemplateScript.Stance.RADICAL),
		"FACTION_STANCE_RADICAL", "radical maps to its key")
	assert_eq(FactionPanel.stance_key(TemplateScript.Stance.NEUTRAL),
		"FACTION_STANCE_NEUTRAL", "neutral maps to its key")
	assert_eq(FactionPanel.stance_key(999), "FACTION_STANCE_NEUTRAL",
		"and an unknown ordinal falls back to a real key, never to the number")


func _count_descendants(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		n += 1 + _count_descendants(child)
	return n

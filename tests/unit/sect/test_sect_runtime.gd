extends TestCase
## Unit tests for SectRuntime (Phase 06 §24): it is a Node (NOT an autoload), a session loads
## the authored sect catalog + enrolls the player into the start sect through the service
## (roster is authoritative — the player's CharacterState cache matches), and end_session
## clears all state. The runtime Node is added to the tree so _ready-style lifecycle is real;
## it is freed afterward (L-019 — a Node created in a test must be freed by that test).

const SectRuntimeScript := preload("res://src/gameplay/world/sect_runtime.gd")
const CharacterStateScript := preload("res://src/domain/character/character_state.gd")
const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

const PLAYER := &"player"


func _player_state() -> CharacterState:
	var stats := StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var ct := CharacterTemplateScript.new()
	ct.id = &"char_player"
	ct.name_key = &"NAME"
	ct.base_stats = stats
	return CharacterStateScript.create_from_template(ct, PLAYER)


## Start a sect session on a fresh runtime Node, with a player-only resolver and NO
## relationship service (the authored catalog's declared diplomacy still records on the sect
## state; the mirror is simply skipped when no relationship service is present).
func _start(runtime: Node, player: CharacterState) -> bool:
	var resolver := func(cid: StringName) -> CharacterState:
		return player if cid == PLAYER else null
	return bool(runtime.call("start_session", null, resolver, PLAYER))


func test_runtime_is_a_node_not_autoload() -> void:
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	assert_true(runtime is Node, "SectRuntime is a Node")
	# Not registered as an autoload (nothing named SectRuntime directly under /root).
	var autoload_dupes := 0
	for child in scene_tree.root.get_children():
		if child.name == "SectRuntime":
			autoload_dupes += 1
	assert_eq(autoload_dupes, 0, "SectRuntime is not an autoload (named node under /root)")
	free_node(runtime)


func test_session_loads_authored_sect_and_enrolls_player() -> void:
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	var player := _player_state()
	assert_true(_start(runtime, player), "session starts from the authored catalog")
	assert_true(runtime.call("is_session_active"), "session active")
	# The authored catalog enrolls the player into sect_azure_cloud at rank_outer.
	assert_eq(runtime.call("get_player_sect_id"), &"sect_azure_cloud", "player joined start sect")
	var sect: SectState = runtime.call("get_player_sect")
	assert_not_null(sect, "player's SectState resolves")
	# ROSTER is authoritative: the player is on the roster AND the derived cache matches.
	assert_true(sect.is_member(PLAYER), "player is on the authoritative roster")
	assert_eq(sect.rank_of(PLAYER), &"rank_outer", "roster rank is the authored start rank")
	assert_eq(player.sect_id, &"sect_azure_cloud", "derived CharacterState.sect_id matches roster")
	assert_eq(player.sect_rank, &"rank_outer", "derived CharacterState.sect_rank matches roster")
	free_node(runtime)


func test_membership_view_is_populated_and_localizable() -> void:
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	var player := _player_state()
	_start(runtime, player)
	var view: SectMembershipView = runtime.call("get_player_membership_view")
	assert_not_null(view, "a membership view is always returned")
	assert_true(view.is_member, "view marks the player as a member")
	assert_eq(view.sect_name_key, &"SECT_AZURE_CLOUD_NAME", "view carries the sect name KEY")
	assert_eq(view.rank_name_key, &"SECT_RANK_OUTER_DISCIPLE", "view carries the rank name KEY")
	assert_true(view.influence > 0, "view surfaces the sect influence")
	free_node(runtime)


func test_session_end_clears_state() -> void:
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	var player := _player_state()
	_start(runtime, player)
	runtime.call("end_session")
	assert_false(runtime.call("is_session_active"), "session no longer active after end")
	assert_null(runtime.call("get_service"), "service dropped on end")
	assert_null(runtime.call("get_store"), "store dropped on end")
	assert_eq(runtime.call("get_player_sect_id"), &"", "player sect cleared on end")
	var view: SectMembershipView = runtime.call("get_player_membership_view")
	assert_false(view.is_member, "view reports no membership after session end")
	free_node(runtime)

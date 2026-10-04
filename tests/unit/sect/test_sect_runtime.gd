extends TestCase
## Unit tests for SectRuntime (Phase 06 §24): it is a Node (NOT an autoload), a session loads
## the authored sect catalog + enrolls the player into the start sect through the service
## (roster is authoritative — the player's CharacterState cache matches), the start is
## FAIL-CLOSED (no half-session is ever observable), and end_session clears all state.
##
## The runtime Node is added to the tree so _ready-style lifecycle is real; it is freed
## afterward (L-019 — a Node created in a test must be freed by that test). The relationship
## graph is a REAL in-memory store/service: the authored catalog declares Sect↔Sect enmity, so
## a session REQUIRES somewhere to mirror it into and the runtime now refuses to start without
## one (the mirror is not an optional extra — without it the sect state would declare
## diplomacy that no relationship edge records).

const SectRuntimeScript := preload("res://src/gameplay/world/sect_runtime.gd")
const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")
const RelConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")
const RelStoreScript := preload("res://src/domain/relationship/relationship_store.gd")
const RelServiceScript := preload("res://src/domain/relationship/relationship_service.gd")

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
	return CharacterState.create_from_template(ct, PLAYER)


## A real (in-memory) relationship service for the Sect↔Sect mirror — the same shape
## RelationshipRuntime provides in a live session, without touching disk.
## `dimensions` is `Array[Dictionary]`: build the typed array as a LOCAL first. A typed
## property will not accept an untyped array, and the resulting VM error would abort this
## helper — which the runner records as a PASS (it only counts assertion failures). See the
## D-037 follow-up / the headless gate's `SCRIPT ERROR:` check.
func _rel_service() -> RelationshipService:
	var dims: Array[Dictionary] = [{"id": &"affinity", "default": 0, "min": -100, "max": 100}]
	var cfg: RelationshipConfigData = RelConfigScript.new()
	cfg.dimensions = dims
	var store: RelationshipStore = RelStoreScript.new(cfg)
	return RelServiceScript.new(store, cfg)


## Start a sect session on a fresh runtime Node, with a player-only resolver and a real
## relationship service for the declared-diplomacy mirror.
func _start(runtime: Node, player: CharacterState,
		rel: RelationshipService = null) -> bool:
	var resolver := func(cid: StringName) -> CharacterState:
		return player if cid == PLAYER else null
	var service := rel if rel != null else _rel_service()
	return bool(runtime.call("start_session", service, resolver, PLAYER))


## Assert the runtime exposes NO session state at all (used after a failed start and after
## end_session) — a half-session must never be observable.
func _assert_no_session(runtime: Node, when: String) -> void:
	assert_false(runtime.call("is_session_active"), "%s: session is not active" % when)
	assert_null(runtime.call("get_service"), "%s: no service exposed" % when)
	assert_null(runtime.call("get_store"), "%s: no store exposed" % when)
	assert_eq(runtime.call("get_player_sect_id"), &"", "%s: no player sect id" % when)
	assert_null(runtime.call("get_player_sect"), "%s: no player SectState" % when)
	var view: SectMembershipView = runtime.call("get_player_membership_view")
	assert_false(view.is_member, "%s: the membership view reports no membership" % when)


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


## The authored catalog declares Azure↔Crimson enmity, so a successful start must have
## MIRRORED it into the relationship graph — not merely recorded it on the sect states.
func test_session_mirrors_authored_diplomacy_into_the_relationship_graph() -> void:
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	var rel := _rel_service()
	assert_true(_start(runtime, _player_state(), rel), "session starts")
	var edge := rel.get_store().get_edge(
		SectService.edge_id(&"sect_azure_cloud", &"sect_crimson_flame"))
	assert_not_null(edge, "the authored enmity produced a mirrored Sect↔Sect edge")
	if edge != null:
		assert_eq(edge.relationship_type, &"ENEMY", "mirrored at the declared type")
		assert_true(edge.symmetric, "a Sect↔Sect edge is symmetric (one edge per pair)")
	free_node(runtime)


## FAIL-CLOSED (§2): the authored catalog declares diplomacy, so starting WITHOUT a
## relationship service has nowhere to mirror it. That used to start anyway (the mirror was
## silently skipped), leaving a session whose sect state declared enemies the relationship
## graph had no record of. It must now refuse, and leave nothing behind.
func test_start_fails_closed_without_a_relationship_service() -> void:
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	var player := _player_state()
	var resolver := func(cid: StringName) -> CharacterState:
		return player if cid == PLAYER else null
	assert_false(bool(runtime.call("start_session", null, resolver, PLAYER)),
		"a catalog declaring diplomacy cannot start without a RelationshipService")
	_assert_no_session(runtime, "after a rejected start")
	# And the player's DERIVED cache must not have been written by the aborted attempt.
	assert_eq(player.sect_id, &"", "the aborted start left no sect id on the CharacterState")
	assert_eq(player.sect_rank, &"", "the aborted start left no sect rank on the CharacterState")
	free_node(runtime)


## FAIL-CLOSED (§2): the catalog names a player start sect, so a session with no player to
## enroll is incomplete — it must not report success with an empty membership.
func test_start_fails_closed_without_a_player_to_enroll() -> void:
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	assert_false(bool(runtime.call("start_session", _rel_service(), Callable(), &"")),
		"a catalog naming a start sect cannot start with no player instance id")
	_assert_no_session(runtime, "after a start with no player")
	free_node(runtime)


## FAIL-CLOSED at the RUNTIME boundary: a real session enrolling a real player needs a
## WORKING character resolver. Without one, `SectService` treats character checks as disabled
## (its documented contract for roster-only unit tests), so the enrolment would skip both the
## existence check and the derived-cache write — leaving a roster that names a player no
## `CharacterState` is bound to. The service contract is unchanged; the runtime refuses.
func test_start_fails_closed_without_a_working_character_resolver() -> void:
	# (a) An INVALID resolver (never set) with a real player id.
	var runtime: Node = SectRuntimeScript.new()
	add_to_tree(runtime)
	assert_false(bool(runtime.call("start_session", _rel_service(), Callable(), PLAYER)),
		"a non-empty player id with an invalid resolver is rejected")
	_assert_no_session(runtime, "after a start with an invalid resolver")
	free_node(runtime)

	# (b) A VALID resolver that does not resolve the player id. The player's own cache must
	#     be left exactly as it was — the aborted session may not write to it.
	var runtime_b: Node = SectRuntimeScript.new()
	add_to_tree(runtime_b)
	var player := _player_state()
	assert_eq(player.sect_id, &"", "the player starts with no cached sect")
	var blind := func(_cid: StringName) -> CharacterState:
		return null
	assert_false(bool(runtime_b.call("start_session", _rel_service(), blind, PLAYER)),
		"a resolver that cannot resolve the player id is rejected")
	_assert_no_session(runtime_b, "after a start with a non-resolving resolver")
	assert_eq(player.sect_id, &"", "the aborted start left sect_id untouched")
	assert_eq(player.sect_rank, &"", "the aborted start left sect_rank untouched")
	free_node(runtime_b)


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
	_assert_no_session(runtime, "after end_session")
	free_node(runtime)

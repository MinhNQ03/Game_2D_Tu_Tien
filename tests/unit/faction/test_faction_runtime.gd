extends TestCase
## Tests for `FactionRuntime` (Phase 07): the fail-closed session start, the absence of any
## observable half-session after a rejected start, the C-003 guard that nobody is enrolled,
## and the read-only politics view it hands to presentation.
##
## It drives the REAL node with the REAL shipped catalog, because the thing most worth proving
## is that the authored content actually starts a session — a stubbed catalog would pass while
## the shipped one was broken.
##
## `FactionRuntime` extends Node, so every instance is `add_to_tree`d and `free_node`d in
## EVERY method: an un-freed Node does not auto-release, and it pins its GDScript and native
## base class too, so one leak shows up as several leaked ObjectDB entries at process exit
## (L-019).

const RuntimeScript := preload("res://src/gameplay/world/faction_runtime.gd")

const SectTemplateScript := preload("res://src/data/sects/sect_template_data.gd")
const SectRankScript := preload("res://src/data/sects/sect_rank_data.gd")
const SectStoreScript := preload("res://src/domain/sect/sect_store.gd")

const RelConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")
const RelStoreScript := preload("res://src/domain/relationship/relationship_store.gd")
const RelServiceScript := preload("res://src/domain/relationship/relationship_service.gd")

const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

const AUTHORED_FACTION_CATALOG := "res://data/factions/faction_catalog.tres"
const PLAYER := &"player"

var _player_state: CharacterState = null


func _runtime() -> Node:
	var rt: Node = RuntimeScript.new()
	add_to_tree(rt)
	return rt


func _rel_service() -> RelationshipService:
	var dims: Array[Dictionary] = [
		{"id": &"affinity", "default": 0, "min": -100, "max": 100},
		{"id": &"rivalry", "default": 0, "min": 0, "max": 100},
	]
	var cfg: RelationshipConfigData = RelConfigScript.new()
	cfg.dimensions = dims
	var store: RelationshipStore = RelStoreScript.new(cfg)
	return RelServiceScript.new(store, cfg)


func _sect_ladder() -> Array[SectRankData]:
	var out: Array[SectRankData] = []
	var r: SectRankData = SectRankScript.new()
	r.rank_id = &"rank_outer"
	r.name_key = &"R_OUTER"
	r.authority = 10
	out.append(r)
	return out


## A sect store containing every parent sect the AUTHORED faction catalog names, so a session
## start over the shipped content has somewhere real to resolve its parents.
func _sect_store_for_authored_content() -> SectStore:
	var store: SectStore = SectStoreScript.new()
	var cat := load(AUTHORED_FACTION_CATALOG) as FactionCatalog
	if cat == null:
		return store
	for sect_id in cat.parent_sect_ids():
		var t: SectTemplateData = SectTemplateScript.new()
		t.id = sect_id
		t.name_key = &"SECT_NAME"
		t.doctrine_key = &"SECT_DOCTRINE"
		t.tier = 1
		t.rank_ladder = _sect_ladder()
		store.add(SectState.create_from_template(t))
	return store


func _resolver() -> Callable:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var ct: CharacterTemplateData = CharacterTemplateScript.new()
	ct.id = &"char_player"
	ct.name_key = &"NAME"
	ct.base_stats = stats
	_player_state = CharacterState.create_from_template(ct, PLAYER)
	var player := _player_state
	return func(cid: StringName) -> CharacterState:
		return player if cid == PLAYER else null


## Assert that NOTHING about a session is observable. A starter that writes as it goes leaves
## a half-session behind; building into locals and committing last makes that impossible by
## construction, and this is the assertion that proves it (L-025).
func _assert_no_session(rt: Node, when: String) -> void:
	assert_false(bool(rt.call("is_session_active")), "no active session %s" % when)
	assert_null(rt.call("get_service"), "no service %s" % when)
	assert_null(rt.call("get_store"), "no store %s" % when)
	assert_null(rt.call("get_catalog"), "no catalog %s" % when)
	assert_eq(rt.call("get_player_instance_id"), &"", "no player id %s" % when)
	var view: SectPoliticsView = rt.call("get_politics_view", &"sect_azure_cloud")
	assert_false(view.is_available, "the politics view reports unavailable %s" % when)


func test_a_session_starts_over_the_authored_content() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_true(sects.count() > 0, "the fixture registered the authored parent sect(s)")
	assert_true(
		bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"the session starts over the SHIPPED faction catalog")
	assert_true(bool(rt.call("is_session_active")), "and reports active")
	assert_not_null(rt.call("get_service"), "the service is exposed")
	assert_not_null(rt.call("get_store"), "and the store")
	free_node(rt)


## Idempotence: a second start on a live session is a no-op, not a rebuild that would discard
## accumulated political state.
func test_a_second_start_is_an_idempotent_no_op() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_true(bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"the first start succeeds")
	var store_before: FactionStore = rt.call("get_store")
	assert_true(bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"a second start returns true")
	assert_eq((rt.call("get_store") as FactionStore).get_instance_id(),
		store_before.get_instance_id(),
		"and it is the SAME store — the session was not silently rebuilt")
	free_node(rt)


## The sect store is a hard dependency: without it no faction's parent or membership can be
## verified, so starting anyway would ship a political world nobody could validate.
func test_start_requires_a_sect_store() -> void:
	var rt := _runtime()
	assert_false(bool(rt.call("start_session", null, _rel_service(), _resolver(), PLAYER)),
		"a null SectStore fails the start")
	_assert_no_session(rt, "after a missing sect store")
	free_node(rt)


## The authored catalog DOES declare politics, so a missing relationship graph must fail the
## start — there would be nowhere to mirror the declared rivalries into, and the faction state
## would claim relations the graph has no record of from the first frame.
func test_start_requires_a_graph_when_politics_is_declared() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_false(bool(rt.call("start_session", sects, null, _resolver(), PLAYER)),
		"declared politics with no RelationshipService fails the start")
	_assert_no_session(rt, "after a missing relationship service")
	free_node(rt)


## A faction whose parent sect is absent must fail the session rather than sit in the store
## answering every query with an empty result.
func test_start_fails_when_a_parent_sect_is_missing() -> void:
	var rt := _runtime()
	var empty: SectStore = SectStoreScript.new()
	assert_false(bool(rt.call("start_session", empty, _rel_service(), _resolver(), PLAYER)),
		"an empty sect store cannot satisfy the authored factions' parents")
	_assert_no_session(rt, "after an unresolvable parent sect")
	free_node(rt)


## THE C-003 GUARD. The authored start SECT is a scaffold; turning it into an authored FACTION
## allegiance would hand the player a political identity they never chose. So the session must
## enrol nobody, and the player's derived cache must still be empty afterwards.
func test_the_session_enrols_nobody() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_true(bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"the session starts")
	var store: FactionStore = rt.call("get_store")
	for faction in store.all():
		var f := faction as FactionState
		assert_eq(f.member_count(), 0,
			"faction '%s' has no members at session start (the player chooses a side in "
				% f.id + "gameplay, not in content)")
		assert_eq(f.leader_ref, &"", "and no leader was invented for it")
	assert_eq(_player_state.faction_id, &"",
		"the player's derived faction cache is still empty — no allegiance was assigned")
	free_node(rt)


## The player id is carried for the VIEW only. It must be readable back (so the panel can mark
## their side later) without having caused any enrolment.
func test_the_player_id_is_recorded_without_enrolment() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_true(bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"the session starts")
	assert_eq(rt.call("get_player_instance_id"), PLAYER, "the player id is recorded")
	var svc: FactionService = rt.call("get_service")
	assert_null(svc.faction_of(&"sect_azure_cloud", PLAYER),
		"but they belong to no faction")
	free_node(rt)


## The declared politics of the shipped content must actually reach the graph — otherwise the
## panel would show rivalries that no relationship edge backs.
func test_the_authored_politics_reaches_the_graph() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	var rel := _rel_service()
	assert_true(bool(rt.call("start_session", sects, rel, _resolver(), PLAYER)),
		"the session starts")
	assert_true(rel.get_store().edge_count() > 0,
		"the authored declarations produced real relationship edges")
	for edge_id in rel.get_store().edge_ids_sorted():
		var edge: RelationshipEdge = rel.get_store().get_edge(StringName(edge_id))
		assert_true(String(edge_id).begins_with(FactionService.EDGE_PREFIX),
			"every edge this session created is in the faction namespace (got '%s')" % edge_id)
		assert_eq(edge.from_ref.kind, RelationshipEndpoint.Kind.FACTION,
			"and both endpoints are typed as factions")
		assert_eq(edge.to_ref.kind, RelationshipEndpoint.Kind.FACTION, "on both ends")
	free_node(rt)


func test_the_politics_view_describes_the_authored_landscape() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_true(bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"the session starts")

	var view: SectPoliticsView = rt.call("get_politics_view", &"sect_azure_cloud")
	assert_true(view.is_available, "the view is available for the authored sect")
	assert_true(view.rows.size() >= 2, "it describes at least two parties (got %d)"
		% view.rows.size())
	assert_true(view.total_influence > 0, "the landscape has non-zero total influence")

	var dominant_count := 0
	var share_total := 0
	for row in view.rows:
		var r := row as SectPoliticsView.Row
		assert_ne(r.name_key, &"", "every row carries a localization key, not raw text")
		assert_ne(r.doctrine_key, &"", "and the argument that faction is making")
		assert_false(r.is_player_faction, "no row is the player's — they took no side")
		if r.is_dominant:
			dominant_count += 1
		share_total += r.influence_share
	assert_eq(dominant_count, 1, "exactly one faction holds sway")
	# Integer shares round, so the total is near 100 rather than exactly 100 — assert the band
	# instead of pretending the arithmetic is exact.
	assert_true(share_total >= 97 and share_total <= 103,
		"the shares account for the whole sect (got %d)" % share_total)

	# Rows must be ordered strongest-first, so the panel never has to sort.
	for i in range(1, view.rows.size()):
		var prev := view.rows[i - 1] as SectPoliticsView.Row
		var cur := view.rows[i] as SectPoliticsView.Row
		assert_true(prev.influence >= cur.influence,
			"rows are ordered by descending influence")
	free_node(rt)


## A sect with no factions is a real, displayable answer ("this sect has none"), which is a
## DIFFERENT statement from "there is no session" — the panel shows different text for each.
func test_a_sect_with_no_factions_is_available_but_empty() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_true(bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"the session starts")
	var view: SectPoliticsView = rt.call("get_politics_view", &"sect_with_no_factions")
	assert_true(view.is_available, "a live session yields an AVAILABLE view")
	assert_eq(view.rows.size(), 0, "with no rows for a sect that has no factions")
	free_node(rt)


func test_end_session_clears_everything() -> void:
	var rt := _runtime()
	var sects := _sect_store_for_authored_content()
	assert_true(bool(rt.call("start_session", sects, _rel_service(), _resolver(), PLAYER)),
		"the session starts")
	rt.call("end_session")
	_assert_no_session(rt, "after end_session")
	rt.call("end_session")
	_assert_no_session(rt, "after a second end_session (idempotent)")
	free_node(rt)

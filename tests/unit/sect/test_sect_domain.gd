extends TestCase
## Unit tests for the Sect domain (Phase 06): SectTemplateData/SectRankData validation,
## SectState (de)serialization + invariants, SectStore, and the SectService mutation path
## incl. the Relationship alliance/enemy mirror with transactional rollback (§23).
##
## Pure domain: everything is RefCounted built via `.new()` (no disk, no Node), so there is
## nothing to free (L-019 applies only to Nodes). The character seam is a plain Dictionary
## resolver; the relationship mirror uses a real RelationshipStore/Service + config.

const TemplateScript := preload("res://src/data/sects/sect_template_data.gd")
const RankScript := preload("res://src/data/sects/sect_rank_data.gd")
const StateScript := preload("res://src/domain/sect/sect_state.gd")
const StoreScript := preload("res://src/domain/sect/sect_store.gd")
const ServiceScript := preload("res://src/domain/sect/sect_service.gd")
const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")
const RelConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")
const RelStoreScript := preload("res://src/domain/relationship/relationship_store.gd")
const RelServiceScript := preload("res://src/domain/relationship/relationship_service.gd")

const PLAYER := &"player"
const RIVAL := &"rival"

var _known_characters: Dictionary = {}


# --- builders ----------------------------------------------------------------

func _rank(id: StringName, key: StringName, authority: int) -> SectRankData:
	var r: SectRankData = RankScript.new()
	r.rank_id = id
	r.name_key = key
	r.authority = authority
	return r


func _template(sid: StringName) -> SectTemplateData:
	var t: SectTemplateData = TemplateScript.new()
	t.id = sid
	t.name_key = &"SECT_NAME"
	t.doctrine_key = &"SECT_DOCTRINE"
	t.sect_type = 0
	t.tier = 2
	t.rank_ladder = [
		_rank(&"rank_outer", &"R_OUTER", 10),
		_rank(&"rank_inner", &"R_INNER", 20),
		_rank(&"rank_elder", &"R_ELDER", 40),
	]
	t.starting_resources = {"spirit_stones": 100}
	t.starting_territory = [&"region_a"]
	t.reputation_seed = {"world": 10}
	t.influence_seed = 5
	return t


## A service with a store + an optional REAL relationship mirror + an optional character
## resolver over a fixed set of existing character instance_ids.
func _service(with_rel: bool, existing_characters: Array) -> SectService:
	var store: SectStore = StoreScript.new()
	var svc: SectService = ServiceScript.new(store)
	if with_rel:
		var cfg: RelationshipConfigData = RelConfigScript.new()
		cfg.dimensions = [{"id": &"affinity", "default": 0, "min": -100, "max": 100}]
		var rel_store: RelationshipStore = RelStoreScript.new(cfg)
		var rel_svc: RelationshipService = RelServiceScript.new(rel_store, cfg)
		svc.set_relationship_service(rel_svc)
	if not existing_characters.is_empty():
		var known := {}
		for cid in existing_characters:
			known[String(cid)] = _character(StringName(cid))
		_known_characters = known
		svc.set_character_resolver(func(cid: StringName) -> CharacterState:
			return _known_characters.get(String(cid)))
	return svc


func _character(cid: StringName) -> CharacterState:
	var stats := StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var ct := CharacterTemplateScript.new()
	ct.id = &"char_x"
	ct.name_key = &"NAME"
	ct.base_stats = stats
	return CharacterState.create_from_template(ct, cid)


func _reg(svc: SectService, sid: StringName) -> void:
	var t := _template(sid)
	svc.register_sect(SectState.create_from_template(t), t)


# --- 1-3: template + rank validation -----------------------------------------

func test_1_template_valid() -> void:
	assert_true(_template(&"sect_a").is_valid(), "a well-formed template validates")


func test_2_malformed_template_rejected() -> void:
	var t := _template(&"sect_a")
	t.name_key = &""  # missing display name
	assert_false(t.is_valid(), "empty name_key invalidates the template")
	t.name_key = &"SECT_NAME"
	t.tier = 0
	assert_false(t.is_valid(), "tier < 1 invalidates")
	t.tier = 2
	t.default_enemy_sect_ids = [&"sect_a"]  # self in enemy list
	assert_false(t.is_valid(), "self in enemy list invalidates")


func test_3_rank_ladder_validation() -> void:
	var t := _template(&"sect_a")
	t.rank_ladder = [_rank(&"r1", &"K1", 10), _rank(&"r1", &"K2", 20)]
	assert_false(t.is_valid(), "duplicate rank_id invalidates ladder")
	t.rank_ladder = []
	assert_false(t.is_valid(), "empty rank ladder invalidates")
	var t2 := _template(&"sect_b")
	assert_eq(t2.lowest_rank().rank_id, &"rank_outer", "lowest authority rank is outer")
	assert_eq(t2.highest_rank().rank_id, &"rank_elder", "highest authority rank is elder")


# --- 4-6: state creation + serialization -------------------------------------

func test_4_state_creation() -> void:
	var state := SectState.create_from_template(_template(&"sect_a"))
	assert_not_null(state, "state builds from a valid template")
	assert_eq(state.id, &"sect_a", "id copied")
	assert_eq(state.get_resource(&"spirit_stones"), 100, "resources seeded")
	assert_eq(state.get_reputation(&"world"), 10, "reputation seeded")
	assert_eq(state.influence, 5, "influence seeded")
	assert_true(state.controls_territory(&"region_a"), "territory seeded")
	assert_eq(state.member_count(), 0, "roster starts empty (service enrolls members)")


func test_5_state_serialization_round_trip() -> void:
	var svc := _service(false, [])
	var t := _template(&"sect_a")
	var state := SectState.create_from_template(t)
	svc.register_sect(state, t)
	svc.join_member(&"sect_a", PLAYER, &"rank_inner")
	svc.assign_leader(&"sect_a", PLAYER)
	svc.adjust_resource(&"sect_a", &"spirit_stones", 50)
	var dict := state.to_dict()
	var restored: SectState = StateScript.new()
	assert_true(restored.from_dict(dict), "round-trips through to_dict/from_dict")
	assert_eq(restored.leader_ref, PLAYER, "leader preserved")
	assert_eq(restored.rank_of(PLAYER), &"rank_inner", "rank preserved")
	assert_eq(restored.get_resource(&"spirit_stones"), 150, "resource preserved")
	assert_eq(restored.to_dict(), dict, "second round-trip is byte-stable")


func test_6_malformed_state_rejected() -> void:
	var bad: SectState = StateScript.new()
	assert_false(bad.from_dict({"id": "sect_a", "leader_ref": "ghost", "rank_by_character": {}}),
		"leader not in roster fails closed")
	assert_false(bad.from_dict({"id": "sect_a", "elder_refs": ["ghost"], "rank_by_character": {}}),
		"elder not in roster fails closed")
	assert_false(bad.from_dict({"id": "sect_a", "rank_by_character": {}, "resources": {"x": -5}}),
		"negative resource fails closed")
	assert_false(bad.from_dict(
		{"id": "sect_a", "rank_by_character": {}, "reputation": {"world": 999}}),
		"out-of-range reputation fails closed")
	assert_false(bad.from_dict({"rank_by_character": {}}), "missing id fails closed")


# --- 7-8: store ---------------------------------------------------------------

func test_7_add_sect() -> void:
	var store: SectStore = StoreScript.new()
	assert_true(store.add(SectState.create_from_template(_template(&"sect_a"))), "add succeeds")
	assert_true(store.has(&"sect_a"), "store has the sect")
	assert_eq(store.count(), 1, "count is 1")


func test_8_duplicate_sect_rejected() -> void:
	var store: SectStore = StoreScript.new()
	store.add(SectState.create_from_template(_template(&"sect_a")))
	assert_false(store.add(SectState.create_from_template(_template(&"sect_a"))),
		"duplicate sect id rejected")
	assert_eq(store.count(), 1, "still only one")


# --- 9-14: membership + rank --------------------------------------------------

func test_9_join_member() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	assert_true(svc.join_member(&"sect_a", PLAYER, &"rank_outer"), "join succeeds")
	assert_true(svc.get_store().get_sect(&"sect_a").is_member(PLAYER), "player on roster")


func test_10_duplicate_join_rejected() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	svc.join_member(&"sect_a", PLAYER, &"rank_outer")
	assert_false(svc.join_member(&"sect_a", PLAYER, &"rank_inner"), "duplicate join rejected")


func test_11_leave_member() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	svc.join_member(&"sect_a", PLAYER, &"rank_outer")
	assert_true(svc.leave_member(&"sect_a", PLAYER), "leave succeeds")
	assert_false(svc.get_store().get_sect(&"sect_a").is_member(PLAYER), "player off roster")


func test_12_unknown_leave_rejected() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	assert_false(svc.leave_member(&"sect_a", &"ghost"), "leaving as a non-member rejected")


func test_13_rank_change() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	svc.join_member(&"sect_a", PLAYER, &"rank_outer")
	assert_true(svc.change_rank(&"sect_a", PLAYER, &"rank_elder"), "promote succeeds")
	assert_eq(svc.get_store().get_sect(&"sect_a").rank_of(PLAYER), &"rank_elder", "rank updated")


func test_14_invalid_rank_rejected() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	svc.join_member(&"sect_a", PLAYER, &"rank_outer")
	assert_false(svc.change_rank(&"sect_a", PLAYER, &"rank_nonexistent"),
		"promoting to an unknown rank rejected")
	assert_false(svc.join_member(&"sect_a", RIVAL, &"rank_nonexistent"),
		"joining at an unknown rank rejected")


# --- 15-17: leader / elder / roster invariants -------------------------------

func test_15_leader_invariant() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	assert_false(svc.assign_leader(&"sect_a", &"ghost"), "non-member cannot be leader")
	svc.join_member(&"sect_a", PLAYER, &"rank_outer")
	assert_true(svc.assign_leader(&"sect_a", PLAYER), "member becomes leader")
	var sect := svc.get_store().get_sect(&"sect_a")
	assert_eq(sect.leader_ref, PLAYER, "single leader_ref set")
	svc.join_member(&"sect_a", RIVAL, &"rank_inner")
	svc.assign_leader(&"sect_a", RIVAL)
	assert_eq(sect.leader_ref, RIVAL, "leadership transferred (still exactly one leader)")


func test_16_elder_invariant() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	svc.join_member(&"sect_a", PLAYER, &"rank_outer")
	svc.assign_leader(&"sect_a", PLAYER)
	assert_false(svc.assign_elder(&"sect_a", PLAYER), "the leader cannot also be an elder")
	svc.join_member(&"sect_a", RIVAL, &"rank_inner")
	assert_true(svc.assign_elder(&"sect_a", RIVAL), "a member becomes an elder")
	var sect := svc.get_store().get_sect(&"sect_a")
	assert_true(sect.elder_refs().has(RIVAL), "elder recorded")
	svc.assign_leader(&"sect_a", RIVAL)
	assert_false(sect.elder_refs().has(RIVAL), "new leader removed from elders")


func test_17_roster_invariant() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	assert_false(svc.join_member(&"sect_a", &"sect_a", &"rank_outer"), "sect cannot join itself")
	svc.join_member(&"sect_a", PLAYER, &"rank_outer")
	svc.assign_leader(&"sect_a", PLAYER)
	svc.join_member(&"sect_a", RIVAL, &"rank_inner")
	svc.assign_elder(&"sect_a", RIVAL)
	var sect := svc.get_store().get_sect(&"sect_a")
	assert_eq(sect.member_count(), 2, "two members on the roster")
	assert_false(sect.disciple_refs().has(PLAYER), "leader is not a plain disciple")
	assert_false(sect.disciple_refs().has(RIVAL), "elder is not a plain disciple")


# --- 18: CharacterState derived-cache sync -----------------------------------

func test_18_character_cache_sync() -> void:
	var svc := _service(false, [PLAYER])
	_reg(svc, &"sect_a")
	svc.join_member(&"sect_a", PLAYER, &"rank_inner")
	var cs: CharacterState = _known_characters[String(PLAYER)]
	assert_eq(cs.sect_id, &"sect_a", "join wrote the derived sect_id cache")
	assert_eq(cs.sect_rank, &"rank_inner", "join wrote the derived sect_rank cache")
	svc.change_rank(&"sect_a", PLAYER, &"rank_elder")
	assert_eq(cs.sect_rank, &"rank_elder", "rank change updates the cache")
	assert_false(svc.join_member(&"sect_a", &"ghost", &"rank_outer"),
		"cannot enroll a character the resolver can't find")
	# D-015: roster wins — drift the cache, then rebuild from the roster.
	cs.sect_id = &""
	cs.sect_rank = &""
	svc.sync_character_cache()
	assert_eq(cs.sect_id, &"sect_a", "sync rebuilt sect_id from the authoritative roster")
	assert_eq(cs.sect_rank, &"rank_elder", "sync rebuilt sect_rank from the roster")
	svc.leave_member(&"sect_a", PLAYER)
	assert_eq(cs.sect_id, &"", "leave cleared the derived cache")


# --- 19-22: economy -----------------------------------------------------------

func test_19_resource_mutation() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	assert_eq(svc.adjust_resource(&"sect_a", &"spirit_stones", 50), 150, "add resource")
	assert_eq(svc.adjust_resource(&"sect_a", &"spirit_stones", -1000), 0,
		"resource clamps at 0 (never negative)")


func test_20_reputation_clamp() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	svc.set_reputation(&"sect_a", &"world", 999)
	assert_eq(svc.get_store().get_sect(&"sect_a").get_reputation(&"world"), 100, "clamped to max")
	svc.set_reputation(&"sect_a", &"world", -999)
	assert_eq(svc.get_store().get_sect(&"sect_a").get_reputation(&"world"), -100, "clamped to min")


func test_21_influence_mutation() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	assert_eq(svc.adjust_influence(&"sect_a", 20), 25, "influence adds")
	assert_eq(svc.adjust_influence(&"sect_a", -1000), 0, "influence clamps at 0")


func test_22_territory_uniqueness() -> void:
	var svc := _service(false, [])
	_reg(svc, &"sect_a")
	svc.add_territory(&"sect_a", &"region_b")
	svc.add_territory(&"sect_a", &"region_b")  # duplicate ignored
	var sect := svc.get_store().get_sect(&"sect_a")
	assert_eq(sect.territory().size(), 2, "territory stays unique (region_a + region_b)")
	svc.remove_territory(&"sect_a", &"region_a")
	assert_false(sect.controls_territory(&"region_a"), "territory removed")


# --- 23-27: relationship mirror ----------------------------------------------

func test_23_alliance_mirror_to_relationship() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_alliance(&"sect_a", &"sect_b"), "alliance declared")
	var a := svc.get_store().get_sect(&"sect_a")
	var b := svc.get_store().get_sect(&"sect_b")
	assert_true(a.is_ally(&"sect_b") and b.is_ally(&"sect_a"), "symmetric declared alliance")
	var edge_id := SectService.edge_id(&"sect_a", &"sect_b")
	assert_true(svc.get_relationship_store().has_edge(edge_id), "mirrored relationship edge exists")


func test_24_enemy_mirror_to_relationship() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_enemy(&"sect_a", &"sect_b"), "enmity declared")
	var edge := svc.get_relationship_store().get_edge(SectService.edge_id(&"sect_a", &"sect_b"))
	assert_not_null(edge, "mirrored edge exists")
	assert_eq(edge.relationship_type, &"ENEMY", "edge typed ENEMY")


## §14 rollback: when the relationship mirror FAILS, the sect-side declared state must NOT
## change (the two stores never diverge). We force the failure with a stub relationship
## service whose create_edge always returns null.
func test_25_relationship_failure_rolls_back() -> void:
	var store: SectStore = StoreScript.new()
	var svc: SectService = ServiceScript.new(store)
	svc.set_relationship_service(_FailingRelService.new())
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_false(svc.add_alliance(&"sect_a", &"sect_b"),
		"alliance fails when the relationship mirror fails")
	var a := svc.get_store().get_sect(&"sect_a")
	var b := svc.get_store().get_sect(&"sect_b")
	assert_false(a.is_ally(&"sect_b"), "sect A declared-ally state rolled back")
	assert_false(b.is_ally(&"sect_a"), "sect B declared-ally state rolled back")


func test_26_symmetric_sect_relationship() -> void:
	assert_eq(SectService.edge_id(&"sect_a", &"sect_b"), SectService.edge_id(&"sect_b", &"sect_a"),
		"edge id is order-independent (one edge per pair)")


func test_27_duplicate_alliance_rejected() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_alliance(&"sect_a", &"sect_b"), "first alliance ok")
	assert_false(svc.add_alliance(&"sect_a", &"sect_b"), "duplicate alliance rejected")
	# Flipping ally -> enemy retypes the single edge (no duplicate).
	assert_true(svc.add_enemy(&"sect_a", &"sect_b"), "can switch to enemy")
	var edge := svc.get_relationship_store().get_edge(SectService.edge_id(&"sect_a", &"sect_b"))
	assert_eq(edge.relationship_type, &"ENEMY", "edge retyped to ENEMY (single edge)")
	var a := svc.get_store().get_sect(&"sect_a")
	assert_false(a.is_ally(&"sect_b"), "no longer declared ally")
	assert_true(a.is_enemy(&"sect_b"), "now declared enemy")


# --- 28: diplomacy on unknown/self sect rejected -----------------------------

func test_28_unknown_or_self_diplomacy_rejected() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	assert_false(svc.add_alliance(&"sect_a", &"sect_ghost"), "alliance with unknown sect rejected")
	assert_false(svc.add_alliance(&"sect_a", &"sect_a"), "a sect cannot ally itself")


# --- test doubles ------------------------------------------------------------

## A RelationshipService subclass whose create_edge ALWAYS fails, to exercise the §14
## transactional rollback deterministically. Built with a null store/config (SectService's
## `_ensure_edge` null-checks the store), and `create_edge` overridden to return null so the
## mirror step fails and the sect mutation must roll back.
class _FailingRelService extends RelationshipService:
	func _init() -> void:
		super(null, null)
	func create_edge(_edge_id: StringName, _from_ep: RelationshipEndpoint,
			_to_ep: RelationshipEndpoint, _relationship_type: StringName = &"STRANGER",
			_symmetric: bool = false, _known: bool = false) -> RelationshipEdge:
		return null

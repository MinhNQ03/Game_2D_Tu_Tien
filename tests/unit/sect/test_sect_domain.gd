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

const CatalogScript := preload("res://src/data/sects/sect_catalog.gd")

const PLAYER := &"player"
const RIVAL := &"rival"

## The authored catalog the game actually ships, for the referential-integrity drift guard.
const AUTHORED_CATALOG_PATH := "res://data/sects/sect_catalog.tres"

var _known_characters: Dictionary = {}

## The REAL RelationshipService built by `_service(true, ...)`, so the mirror tests can drive
## dimensions/history on the mirrored edge (not just read the store).
var _rel_service: RelationshipService = null


# --- builders ----------------------------------------------------------------

func _rank(id: StringName, key: StringName, authority: int) -> SectRankData:
	var r: SectRankData = RankScript.new()
	r.rank_id = id
	r.name_key = key
	r.authority = authority
	return r


# --- typed-fixture builders --------------------------------------------------
#
# Every `@export` below is a TYPED array (`Array[SectRankData]`, `Array[StringName]`,
# `Array[SectTemplateData]`, `Array[Dictionary]`), and a typed property will not accept an
# untyped one. The resulting GDScript VM error ABORTS the running function, and because the
# runner only counts recorded assertion failures, the test method would be reported as PASS
# while having executed nothing (the test-integrity bug fixed in the D-037 follow-up). A
# typed LOCAL assigned from an array literal is always safe — the declared type is known at
# compile time — so every fixture builds a typed local first and assigns THAT.

func _ladder(ranks: Array) -> Array[SectRankData]:
	var out: Array[SectRankData] = []
	for r in ranks:
		out.append(r)
	return out


func _ids(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for item in ids:
		out.append(StringName(item))
	return out


func _catalog_of(templates: Array) -> SectCatalog:
	var listed: Array[SectTemplateData] = []
	for t in templates:
		listed.append(t)
	var cat: SectCatalog = CatalogScript.new()
	cat.sects = listed
	return cat


## A minimal relationship config for the Sect↔Sect mirror (one dimension is enough to prove
## dimensions/history survive a retype).
func _rel_config() -> RelationshipConfigData:
	var dims: Array[Dictionary] = [{"id": &"affinity", "default": 0, "min": -100, "max": 100}]
	var cfg: RelationshipConfigData = RelConfigScript.new()
	cfg.dimensions = dims
	return cfg


func _template(sid: StringName) -> SectTemplateData:
	var t: SectTemplateData = TemplateScript.new()
	t.id = sid
	t.name_key = &"SECT_NAME"
	t.doctrine_key = &"SECT_DOCTRINE"
	t.sect_type = TemplateScript.SectType.ORTHODOX
	t.tier = 2
	t.rank_ladder = _ladder([
		_rank(&"rank_outer", &"R_OUTER", 10),
		_rank(&"rank_inner", &"R_INNER", 20),
		_rank(&"rank_elder", &"R_ELDER", 40),
	])
	t.starting_resources = {"spirit_stones": 100}
	t.starting_territory = _ids([&"region_a"])
	t.reputation_seed = {"world": 10}
	t.influence_seed = 5
	return t


## A service with a store + an optional REAL relationship mirror + an optional character
## resolver over a fixed set of existing character instance_ids.
func _service(with_rel: bool, existing_characters: Array) -> SectService:
	var store: SectStore = StoreScript.new()
	var svc: SectService = ServiceScript.new(store)
	_rel_service = null
	if with_rel:
		var cfg := _rel_config()
		var rel_store: RelationshipStore = RelStoreScript.new(cfg)
		var rel_svc: RelationshipService = RelServiceScript.new(rel_store, cfg)
		_rel_service = rel_svc
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
	t.default_enemy_sect_ids = _ids([&"sect_a"])  # self in enemy list
	assert_false(t.is_valid(), "self in enemy list invalidates")


func test_3_rank_ladder_validation() -> void:
	var t := _template(&"sect_a")
	t.rank_ladder = _ladder([_rank(&"r1", &"K1", 10), _rank(&"r1", &"K2", 20)])
	assert_false(t.is_valid(), "duplicate rank_id invalidates ladder")
	t.rank_ladder = _ladder([])
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


# --- 29-31: diplomacy retype is NON-DESTRUCTIVE (§1 hardening) ---------------

## An ally→enemy flip must RETYPE the existing mirrored edge in place: the same edge object,
## with its endpoints, flags, dimension values and history intact. The old implementation
## removed the edge and created a new one, which silently discarded all of that even on the
## success path (and destroyed it outright when the recreate failed — test 30).
func test_29_diplomacy_flip_retypes_the_edge_in_place() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_alliance(&"sect_a", &"sect_b"), "alliance declared")
	var eid := SectService.edge_id(&"sect_a", &"sect_b")
	var store := svc.get_relationship_store()

	# Give the mirrored edge real accumulated state so "preserved" is observable.
	assert_true(_rel_service.apply_delta(eid, &"affinity", 30, &"sect_pact"),
		"a dimension delta applies to the mirrored edge")
	var before: RelationshipEdge = store.get_edge(eid)
	var before_object_id := before.get_instance_id()
	var before_dimensions := before.get_dimensions_copy()
	var before_history := before.get_history_copy()
	var before_from := before.from_ref.compare_key()
	var before_to := before.to_ref.compare_key()

	assert_true(svc.add_enemy(&"sect_a", &"sect_b"), "ally -> enemy flip succeeds")

	var after: RelationshipEdge = store.get_edge(eid)
	assert_not_null(after, "the mirrored edge still exists after the flip")
	assert_eq(after.get_instance_id(), before_object_id,
		"the SAME edge object was retyped (not removed and recreated)")
	assert_eq(after.relationship_type, &"ENEMY", "only the relationship_type changed")
	assert_eq(after.id, eid, "edge id preserved")
	assert_eq(after.from_ref.compare_key(), before_from, "from_ref preserved")
	assert_eq(after.to_ref.compare_key(), before_to, "to_ref preserved")
	assert_true(after.symmetric, "symmetric flag preserved")
	assert_true(after.known, "known flag preserved")
	assert_eq(after.get_dimensions_copy(), before_dimensions,
		"every dimension value survived the retype")
	assert_eq(after.get_history_copy(), before_history, "the history log survived the retype")
	assert_eq(store.edge_count(), 1, "still exactly one edge for the pair (no duplicate)")


## When the relationship side REJECTS the retype, the previous edge must survive 100% intact
## and the sect side must not change either. This is the regression the destructive
## remove-then-create shape could not satisfy: it deleted the edge before it could fail.
func test_30_failed_retype_leaves_the_old_edge_fully_intact() -> void:
	var cfg := _rel_config()
	var rel_store: RelationshipStore = RelStoreScript.new(cfg)
	var rel_svc := _NoRetypeRelService.new(rel_store, cfg)
	var store: SectStore = StoreScript.new()
	var svc: SectService = ServiceScript.new(store)
	svc.set_relationship_service(rel_svc)
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_alliance(&"sect_a", &"sect_b"), "alliance declared (create_edge works)")
	var eid := SectService.edge_id(&"sect_a", &"sect_b")
	assert_true(rel_svc.apply_delta(eid, &"affinity", 30, &"sect_pact"), "dimension delta applies")
	var before: RelationshipEdge = rel_store.get_edge(eid)
	var before_object_id := before.get_instance_id()
	var before_dimensions := before.get_dimensions_copy()
	var before_history := before.get_history_copy()

	assert_false(svc.add_enemy(&"sect_a", &"sect_b"),
		"the flip fails when the relationship retype is rejected")

	var after: RelationshipEdge = rel_store.get_edge(eid)
	assert_not_null(after,
		"the old edge was NOT destroyed by the failed flip (it still exists)")
	assert_eq(after.get_instance_id(), before_object_id, "it is the same edge object")
	assert_eq(after.relationship_type, &"ALLY", "it still carries its ORIGINAL type")
	assert_eq(after.get_dimensions_copy(), before_dimensions, "its dimensions are untouched")
	assert_eq(after.get_history_copy(), before_history, "its history is untouched")
	var a := store.get_sect(&"sect_a")
	var b := store.get_sect(&"sect_b")
	assert_true(a.is_ally(&"sect_b") and b.is_ally(&"sect_a"),
		"the sect side kept the original declared alliance")
	assert_false(a.is_enemy(&"sect_b"), "the sect side did NOT record the rejected enmity")


func test_31_set_relationship_type_rejects_bad_input() -> void:
	var cfg := _rel_config()
	var rel_store: RelationshipStore = RelStoreScript.new(cfg)
	var rel_svc: RelationshipService = RelServiceScript.new(rel_store, cfg)
	assert_false(rel_svc.set_relationship_type(&"sect_rel:nope", &"ENEMY"),
		"retyping an unknown edge is rejected (it never creates one)")
	assert_false(rel_store.has_edge(&"sect_rel:nope"),
		"the rejected retype did not conjure an edge")
	var edge := rel_svc.create_edge(
		&"e1", RelationshipEndpoint.for_sect(&"sect_a"),
		RelationshipEndpoint.for_sect(&"sect_b"), &"ALLY", true, true)
	assert_not_null(edge, "edge created for the empty-type check")
	assert_false(rel_svc.set_relationship_type(&"e1", &""), "an empty type is rejected")
	assert_eq(edge.relationship_type, &"ALLY", "the edge keeps its type after a rejection")


# --- 32: default-diplomacy mirror fails closed (§2 hardening) ----------------

## `apply_default_diplomacy()` used to SKIP a declared ally/enemy whose sect was absent, and
## to skip the whole mirror when no relationship service was installed. Both produced a
## session whose sect state declared diplomacy that the relationship graph had no record of.
func test_32_default_diplomacy_fails_closed() -> void:
	# (a) a dangling declaration is an error, not something to skip.
	var svc := _service(true, [])
	var t := _template(&"sect_a")
	t.default_enemy_sect_ids = _ids([&"sect_ghost"])
	svc.register_sect(SectState.create_from_template(t), t)
	assert_false(svc.apply_default_diplomacy(),
		"a declared enemy that is not in the store fails the mirror instead of being skipped")

	# (b) declared diplomacy with NO relationship service to mirror into is an error.
	var store: SectStore = StoreScript.new()
	var no_mirror: SectService = ServiceScript.new(store)
	var t2 := _template(&"sect_a")
	t2.default_enemy_sect_ids = _ids([&"sect_b"])
	no_mirror.register_sect(SectState.create_from_template(t2), t2)
	_reg(no_mirror, &"sect_b")
	assert_false(no_mirror.apply_default_diplomacy(),
		"declared diplomacy with no RelationshipService installed fails closed")

	# (c) the legitimate no-mirror case: nothing declares diplomacy at all.
	var roster_only: SectService = ServiceScript.new(StoreScript.new())
	_reg(roster_only, &"sect_a")
	assert_true(roster_only.apply_default_diplomacy(),
		"a roster-only service with no declared diplomacy needs no mirror")

	# (d) the happy path still mirrors both ends of a declared pair.
	var ok := _service(true, [])
	var ta := _template(&"sect_a")
	ta.default_enemy_sect_ids = _ids([&"sect_b"])
	ok.register_sect(SectState.create_from_template(ta), ta)
	_reg(ok, &"sect_b")
	assert_true(ok.apply_default_diplomacy(), "a resolvable declaration mirrors successfully")
	var mirrored := ok.get_relationship_store().get_edge(
		SectService.edge_id(&"sect_a", &"sect_b"))
	assert_not_null(mirrored, "the declared pair produced a mirrored edge")
	assert_eq(mirrored.relationship_type, &"ENEMY", "mirrored at the declared type")


# --- 33-43: from_dict STRICT TYPE validation (§4 hardening) ------------------
#
# Each case feeds a payload that differs from `_valid_payload()` in EXACTLY ONE field, so a
# rejection can only be caused by the field under test. Every case asserts BOTH halves of the
# contract: from_dict returns false AND the receiving state is left byte-identical (atomic).

func test_33_valid_payload_is_accepted() -> void:
	# The fixture itself must be ACCEPTED, otherwise every negative case below would pass for
	# the wrong reason (a broken fixture rather than the strict type check).
	var state: SectState = StateScript.new()
	assert_true(state.from_dict(_valid_payload()), "the baseline payload hydrates")
	assert_eq(state.id, &"sect_z", "id hydrated")
	assert_eq(state.get_resource(&"spirit_stones"), 100, "int resource hydrated")
	assert_eq(state.influence, 5, "int influence hydrated")
	assert_eq(state.get_reputation(&"world"), 10, "int reputation hydrated")
	assert_eq(state.rank_of(PLAYER), &"rank_inner", "string rank hydrated")


func test_34_string_resource_quantity_rejected() -> void:
	var p := _valid_payload()
	p["resources"] = {"spirit_stones": "100"}
	_assert_rejected(p, "a resource quantity given as the string \"100\"")
	# A non-string resource ID is equally invented by coercion (`String(7)` -> "7").
	var q := _valid_payload()
	q["resources"] = {7: 100}
	_assert_rejected(q, "a resource id given as an int")


func test_35_float_resource_quantity_rejected() -> void:
	var p := _valid_payload()
	p["resources"] = {"spirit_stones": 100.0}
	_assert_rejected(p, "a resource quantity given as the float 100.0")


func test_36_string_influence_rejected() -> void:
	var p := _valid_payload()
	p["influence"] = "5"
	_assert_rejected(p, "influence given as the string \"5\"")


func test_37_float_influence_rejected() -> void:
	var p := _valid_payload()
	p["influence"] = 5.0
	_assert_rejected(p, "influence given as the float 5.0")


func test_38_non_int_reputation_rejected() -> void:
	var p := _valid_payload()
	p["reputation"] = {"world": "10"}
	_assert_rejected(p, "a reputation value given as the string \"10\"")
	var q := _valid_payload()
	q["reputation"] = {"world": 10.0}
	_assert_rejected(q, "a reputation value given as the float 10.0")
	var r := _valid_payload()
	r["reputation"] = {"world": true}
	_assert_rejected(r, "a reputation value given as a bool")
	var s := _valid_payload()
	s["reputation"] = {12: 10}
	_assert_rejected(s, "a reputation scope given as an int")


func test_39_non_string_rank_id_rejected() -> void:
	var p := _valid_payload()
	p["rank_by_character"] = {"player": 2}
	_assert_rejected(p, "a rank id given as an int")
	# The roster is keyed by the member id, so an int key would coerce to the id "7" and the
	# payload would otherwise be perfectly consistent (no leader to contradict it).
	var q := _valid_payload()
	q["rank_by_character"] = {7: "rank_inner"}
	q["leader_ref"] = ""
	_assert_rejected(q, "a member id given as an int")


func test_40_non_string_leader_ref_rejected() -> void:
	# The roster deliberately contains the member "1", so `String(1)` would resolve to a REAL
	# member and the payload would validate on every other rule — the type check is the only
	# thing standing between a numeric leader_ref and an accepted state.
	var p := _valid_payload()
	p["rank_by_character"] = {"1": "rank_inner"}
	p["leader_ref"] = 1
	_assert_rejected(p, "leader_ref given as an int")
	var q := _valid_payload()
	q["leader_ref"] = null
	_assert_rejected(q, "leader_ref given as null (String(null) would read as 'no leader')")


func test_41_non_string_elder_ref_rejected() -> void:
	# Same shape: the roster contains "7", so an int elder ref would coerce onto a real member.
	var p := _valid_payload()
	p["rank_by_character"] = {"7": "rank_inner"}
	p["leader_ref"] = ""
	p["elder_refs"] = [7]
	_assert_rejected(p, "an elder ref given as an int")


func test_42_non_string_territory_or_diplomacy_id_rejected() -> void:
	var p := _valid_payload()
	p["territory"] = [1]
	_assert_rejected(p, "a territory id given as an int")
	var q := _valid_payload()
	q["ally_sect_ids"] = [42]
	_assert_rejected(q, "an ally sect id given as an int")
	var r := _valid_payload()
	r["enemy_sect_ids"] = [true]
	_assert_rejected(r, "an enemy sect id given as a bool")


func test_43_malformed_id_or_template_id_rejected() -> void:
	var p := _valid_payload()
	p["template_id"] = 123
	_assert_rejected(p, "template_id given as an int")
	var q := _valid_payload()
	q["id"] = 99
	_assert_rejected(q, "id given as an int")
	var r := _valid_payload()
	r["id"] = null
	_assert_rejected(r, "id given as null")


# --- 44: rank ladder authority is strictly increasing (§5 hardening) ---------

## The array order is the official progression and `authority` is what rules compare, so the
## two must agree. A flat or descending ladder makes "the next rank" and "more authority"
## contradict each other (and silently disagrees with lowest_rank()/highest_rank()).
func test_44_rank_ladder_authority_must_strictly_increase() -> void:
	var t := _template(&"sect_a")
	t.rank_ladder = _ladder([
		_rank(&"r1", &"K1", 10), _rank(&"r2", &"K2", 20), _rank(&"r3", &"K3", 30),
	])
	assert_eq(t.rank_ladder.size(), 3, "the fixture ladder actually carries its three ranks")
	assert_true(t.is_valid(), "a strictly increasing ladder (10, 20, 30) is valid")
	assert_eq(t.lowest_rank().rank_id, &"r1", "lowest_rank is the FIRST authored entry")
	assert_eq(t.highest_rank().rank_id, &"r3", "highest_rank is the LAST authored entry")

	t.rank_ladder = _ladder([
		_rank(&"r1", &"K1", 10), _rank(&"r2", &"K2", 20), _rank(&"r3", &"K3", 20),
	])
	assert_false(t.is_valid(), "a FLAT step (10, 20, 20) is rejected - promotion grants nothing")
	assert_true(_errors(t).contains("STRICTLY greater"),
		"the reason is the authority ordering, not something else: %s" % _errors(t))

	t.rank_ladder = _ladder([
		_rank(&"r1", &"K1", 20), _rank(&"r2", &"K2", 10), _rank(&"r3", &"K3", 30),
	])
	assert_false(t.is_valid(), "a dip (20, 10, 30) is rejected")

	t.rank_ladder = _ladder([
		_rank(&"r1", &"K1", 30), _rank(&"r2", &"K2", 20), _rank(&"r3", &"K3", 10),
	])
	assert_false(t.is_valid(), "a fully descending ladder (30, 20, 10) is rejected")


# --- 45-46: catalog referential integrity (§6 hardening) --------------------

## A declared ally/enemy pointing at a sect that is not in the catalog used to be dropped
## silently at mirror time. Only the CATALOG can answer "does this id exist", so that check
## lives here and makes the catalog INVALID - SectRuntime then refuses to load it.
func test_45_catalog_rejects_dangling_or_contradictory_diplomacy() -> void:
	var azure := _template(&"sect_azure")
	var crimson := _template(&"sect_crimson")
	var cat := _catalog_of([azure, crimson])
	assert_eq(cat.sects.size(), 2, "the fixture catalog actually lists both sects")
	assert_true(cat.is_valid(), "two plain sects with no declared diplomacy validate")

	azure.default_enemy_sect_ids = _ids([&"sect_crimson"])
	crimson.default_enemy_sect_ids = _ids([&"sect_azure"])
	assert_true(cat.is_valid(), "a mutual enmity between two LISTED sects validates")

	# The §6 example: a declared enemy that does not exist in the catalog.
	azure.default_enemy_sect_ids = _ids([&"sect_ghost"])
	assert_false(cat.is_valid(),
		"a declared enemy 'sect_ghost' absent from the catalog invalidates it")
	assert_true(_cat_errors(cat).contains("sect_ghost"), "the error names the dangling id")

	azure.default_enemy_sect_ids = _ids([])
	azure.default_ally_sect_ids = _ids([&"sect_ghost"])
	assert_false(cat.is_valid(), "a dangling ALLY reference invalidates the catalog too")

	# Self-reference, duplicates and ally/enemy overlap are all rejected.
	azure.default_ally_sect_ids = _ids([&"sect_azure"])
	assert_false(cat.is_valid(), "a sect declaring ITSELF an ally invalidates the catalog")
	azure.default_ally_sect_ids = _ids([&"sect_crimson", &"sect_crimson"])
	assert_false(cat.is_valid(), "a duplicated declared ally invalidates the catalog")
	azure.default_ally_sect_ids = _ids([&"sect_crimson"])
	azure.default_enemy_sect_ids = _ids([&"sect_crimson"])
	assert_false(cat.is_valid(), "the same sect as BOTH ally and enemy invalidates the catalog")


# --- 47-48: default diplomacy must be SYMMETRIC and non-conflicting ---------

## A default declaration describes a MUTUAL standing, and the service mirrors it as ONE
## symmetric Sect↔Sect edge per pair. A one-sided declaration therefore produces an edge that
## only one sect's state records, and a contradictory pair has no correct answer at all — the
## "winner" would be whichever sect the catalog happens to list last. Both are content bugs.
func test_47_default_diplomacy_must_be_declared_on_both_sects() -> void:
	var a := _template(&"sect_a")
	var b := _template(&"sect_b")
	var cat := _catalog_of([a, b])

	# Mutual declarations are accepted.
	a.default_ally_sect_ids = _ids([&"sect_b"])
	b.default_ally_sect_ids = _ids([&"sect_a"])
	assert_true(cat.is_valid(), "a MUTUAL alliance validates: %s" % _cat_errors(cat))
	a.default_ally_sect_ids = _ids([])
	b.default_ally_sect_ids = _ids([])
	a.default_enemy_sect_ids = _ids([&"sect_b"])
	b.default_enemy_sect_ids = _ids([&"sect_a"])
	assert_true(cat.is_valid(), "a MUTUAL enmity validates: %s" % _cat_errors(cat))

	# One-sided ally.
	a.default_enemy_sect_ids = _ids([])
	b.default_enemy_sect_ids = _ids([])
	a.default_ally_sect_ids = _ids([&"sect_b"])
	assert_false(cat.is_valid(), "a ONE-SIDED alliance is rejected")
	assert_true(_cat_errors(cat).contains("BOTH sects"),
		"the reason is the missing counterpart declaration: %s" % _cat_errors(cat))

	# One-sided enemy.
	a.default_ally_sect_ids = _ids([])
	a.default_enemy_sect_ids = _ids([&"sect_b"])
	assert_false(cat.is_valid(), "a ONE-SIDED enmity is rejected")

	# Conflict across the pair: A says ally, B says enemy.
	a.default_enemy_sect_ids = _ids([])
	a.default_ally_sect_ids = _ids([&"sect_b"])
	b.default_enemy_sect_ids = _ids([&"sect_a"])
	assert_false(cat.is_valid(), "ALLY on one side and ENEMY on the other is rejected")
	assert_true(_cat_errors(cat).contains("CONFLICTING"),
		"the reason is the conflict: %s" % _cat_errors(cat))

	# And the mirror image (B ally, A enemy) is rejected the same way.
	a.default_ally_sect_ids = _ids([])
	a.default_enemy_sect_ids = _ids([&"sect_b"])
	b.default_enemy_sect_ids = _ids([])
	b.default_ally_sect_ids = _ids([&"sect_a"])
	assert_false(cat.is_valid(), "ENEMY on one side and ALLY on the other is rejected")


## The verdict must not depend on authoring order. The validation keys every pair on the two
## ids SORTED, so listing the sects (or their declarations) the other way round can never
## change the result — otherwise iteration order would silently pick the relationship type.
func test_48_pair_validation_is_order_independent() -> void:
	# Same content, both list orders: a one-sided declaration stays invalid either way.
	for reversed in [false, true]:
		var a := _template(&"sect_a")
		var b := _template(&"sect_b")
		a.default_enemy_sect_ids = _ids([&"sect_b"])  # only A declares
		var cat := _catalog_of([b, a] if reversed else [a, b])
		assert_false(cat.is_valid(),
			"one-sided enmity invalid with reversed=%s: %s" % [reversed, _cat_errors(cat)])
		assert_true(_cat_errors(cat).contains("BOTH sects"),
			"same reason with reversed=%s: %s" % [reversed, _cat_errors(cat)])

	# And a conflicting pair stays invalid in either list order.
	for reversed in [false, true]:
		var a2 := _template(&"sect_a")
		var b2 := _template(&"sect_b")
		a2.default_ally_sect_ids = _ids([&"sect_b"])
		b2.default_enemy_sect_ids = _ids([&"sect_a"])
		var cat2 := _catalog_of([b2, a2] if reversed else [a2, b2])
		assert_false(cat2.is_valid(),
			"conflicting pair invalid with reversed=%s" % reversed)
		assert_true(_cat_errors(cat2).contains("CONFLICTING"),
			"same reason with reversed=%s: %s" % [reversed, _cat_errors(cat2)])

	# A mutual pair is valid in either order.
	for reversed in [false, true]:
		var a3 := _template(&"sect_a")
		var b3 := _template(&"sect_b")
		a3.default_ally_sect_ids = _ids([&"sect_b"])
		b3.default_ally_sect_ids = _ids([&"sect_a"])
		var cat3 := _catalog_of([b3, a3] if reversed else [a3, b3])
		assert_true(cat3.is_valid(),
			"mutual alliance valid with reversed=%s: %s" % [reversed, _cat_errors(cat3)])


## Drift guard (L-014): the catalog the game actually ships must satisfy the rules above, so
## authoring a dangling reference into content fails the suite rather than the player's boot.
func test_46_authored_catalog_is_referentially_sound() -> void:
	var cat := load(AUTHORED_CATALOG_PATH) as SectCatalog
	assert_not_null(cat, "the authored sect catalog loads as a SectCatalog")
	if cat == null:
		return
	assert_true(cat.is_valid(),
		"the authored catalog validates: %s" % str(cat.validation_errors()))
	# Every declared ally/enemy in shipped content resolves to a listed sect.
	for tmpl in cat.sects:
		for a in tmpl.default_ally_sect_ids:
			assert_not_null(cat.find_sect(a),
				"authored ally '%s' of '%s' resolves" % [a, tmpl.id])
		for e in tmpl.default_enemy_sect_ids:
			assert_not_null(cat.find_sect(e),
				"authored enemy '%s' of '%s' resolves" % [e, tmpl.id])


# --- 49-52: clear_diplomacy is transactional (§1 follow-up) -----------------

## The happy path: the mirrored edge goes FIRST, then both declarations, then the signal.
func test_49_clear_diplomacy_removes_edge_and_both_declarations() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_alliance(&"sect_a", &"sect_b"), "alliance declared")
	var eid := SectService.edge_id(&"sect_a", &"sect_b")
	var store := svc.get_relationship_store()
	assert_true(store.has_edge(eid), "mirrored edge exists before the clear")

	var events: Array = []
	svc.diplomacy_changed.connect(
		func(sid: StringName, other: StringName, relation: StringName) -> void:
			events.append([sid, other, relation]))

	assert_true(svc.clear_diplomacy(&"sect_a", &"sect_b"), "clear succeeds")
	assert_false(store.has_edge(eid), "the mirrored edge is gone")
	var a := svc.get_store().get_sect(&"sect_a")
	var b := svc.get_store().get_sect(&"sect_b")
	assert_false(a.is_ally(&"sect_b"), "sect A declaration cleared")
	assert_false(b.is_ally(&"sect_a"), "sect B declaration cleared")
	assert_eq(events.size(), 1, "exactly one diplomacy_changed emitted")
	if events.size() == 1:
		assert_eq(events[0][2], &"NONE", "emitted with relation NONE")

	# Idempotent: clearing again is a no-op that succeeds and emits nothing further.
	assert_true(svc.clear_diplomacy(&"sect_a", &"sect_b"), "clearing again is an idempotent ok")
	assert_eq(events.size(), 1, "a no-op clear emits no fake change event")


## If removing the mirrored edge is REJECTED, nothing may change: not the edge, not either
## sect. Previously both sects were cleared first and `remove_edge`'s bool was discarded, so
## this scenario left the sect state saying "no relation" while the edge survived.
func test_50_failed_edge_removal_preserves_sect_state_and_edge() -> void:
	var cfg := _rel_config()
	var rel_store: RelationshipStore = RelStoreScript.new(cfg)
	var rel_svc := _NoRemoveRelService.new(rel_store, cfg)
	var store: SectStore = StoreScript.new()
	var svc: SectService = ServiceScript.new(store)
	svc.set_relationship_service(rel_svc)
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_alliance(&"sect_a", &"sect_b"), "alliance declared")
	var eid := SectService.edge_id(&"sect_a", &"sect_b")

	assert_false(svc.clear_diplomacy(&"sect_a", &"sect_b"),
		"clear fails when the relationship removal is rejected")
	assert_true(rel_store.has_edge(eid), "the mirrored edge still exists")
	assert_eq(rel_store.get_edge(eid).relationship_type, &"ALLY", "and keeps its type")
	var a := store.get_sect(&"sect_a")
	var b := store.get_sect(&"sect_b")
	assert_true(a.is_ally(&"sect_b"), "sect A still declares the alliance")
	assert_true(b.is_ally(&"sect_a"), "sect B still declares the alliance")


## A declared relation whose mirrored edge has vanished is a DIVERGENCE, not something to
## paper over by clearing the sect side: fail closed and leave the roster for inspection.
func test_51_missing_mirror_edge_fails_closed_without_clearing() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	assert_true(svc.add_enemy(&"sect_a", &"sect_b"), "enmity declared")
	var eid := SectService.edge_id(&"sect_a", &"sect_b")
	# Drop the edge behind the service's back to simulate a diverged graph.
	assert_true(svc.get_relationship_store().remove_edge(eid), "edge removed out-of-band")

	assert_false(svc.clear_diplomacy(&"sect_a", &"sect_b"),
		"clear fails closed when the expected mirrored edge is missing")
	var a := svc.get_store().get_sect(&"sect_a")
	var b := svc.get_store().get_sect(&"sect_b")
	assert_true(a.is_enemy(&"sect_b"), "sect A declaration preserved exactly")
	assert_true(b.is_enemy(&"sect_a"), "sect B declaration preserved exactly")

	# Likewise with NO relationship service at all: a declared relation cannot be unmirrored.
	var no_mirror: SectService = ServiceScript.new(StoreScript.new())
	_reg(no_mirror, &"sect_a")
	_reg(no_mirror, &"sect_b")
	no_mirror.get_store().get_sect(&"sect_a").insert_ally(&"sect_b")
	no_mirror.get_store().get_sect(&"sect_b").insert_ally(&"sect_a")
	assert_false(no_mirror.clear_diplomacy(&"sect_a", &"sect_b"),
		"clear fails closed with no RelationshipService to unmirror into")
	assert_true(no_mirror.get_store().get_sect(&"sect_a").is_ally(&"sect_b"),
		"declaration preserved when there is no mirror to remove")


## The sect mirror owns only the ALLY/ENEMY edges it creates. It must never delete an edge of
## an unrelated type between the same pair, and a clear must not disturb other edges.
func test_52_clear_never_corrupts_unrelated_relationship_state() -> void:
	var svc := _service(true, [])
	_reg(svc, &"sect_a")
	_reg(svc, &"sect_b")
	var store := svc.get_relationship_store()
	var eid := SectService.edge_id(&"sect_a", &"sect_b")

	# (a) No declared relation + an unrelated edge on the pair: the no-op must not touch it.
	var unrelated := _rel_service.create_edge(
		eid, RelationshipEndpoint.for_sect(&"sect_a"), RelationshipEndpoint.for_sect(&"sect_b"),
		&"MASTER_DISCIPLE", true, true)
	assert_not_null(unrelated, "an unrelated edge exists on the pair")
	assert_true(svc.clear_diplomacy(&"sect_a", &"sect_b"),
		"clearing a pair with nothing declared is an idempotent ok")
	assert_true(store.has_edge(eid), "the unrelated edge survived the no-op clear")
	assert_eq(store.get_edge(eid).relationship_type, &"MASTER_DISCIPLE", "with its own type")

	# (b) A declared relation whose edge carries an unrelated type: fail closed, keep the edge.
	svc.get_store().get_sect(&"sect_a").insert_ally(&"sect_b")
	svc.get_store().get_sect(&"sect_b").insert_ally(&"sect_a")
	assert_false(svc.clear_diplomacy(&"sect_a", &"sect_b"),
		"clear refuses to delete an edge whose type this mirror does not own")
	assert_true(store.has_edge(eid), "the unrelated edge is NOT destroyed")
	assert_eq(store.get_edge(eid).relationship_type, &"MASTER_DISCIPLE", "type untouched")
	assert_true(svc.get_store().get_sect(&"sect_a").is_ally(&"sect_b"),
		"and the sect declaration is left exactly as it was")

	# (c) A successful clear leaves OTHER edges in the graph alone.
	var bystander := _rel_service.create_edge(
		&"rel_bystander", RelationshipEndpoint.for_character(&"x"),
		RelationshipEndpoint.for_character(&"y"), &"RIVAL", true, true)
	assert_not_null(bystander, "a bystander edge exists")
	assert_true(_rel_service.remove_edge(eid), "clear the unrelated pair edge out-of-band")
	svc.get_store().get_sect(&"sect_a").erase_ally(&"sect_b")
	svc.get_store().get_sect(&"sect_b").erase_ally(&"sect_a")
	assert_true(svc.add_alliance(&"sect_a", &"sect_b"), "declare a clean alliance")
	assert_true(svc.clear_diplomacy(&"sect_a", &"sect_b"), "and clear it cleanly")
	assert_true(store.has_edge(&"rel_bystander"), "the bystander edge is untouched")
	assert_eq(store.get_edge(&"rel_bystander").relationship_type, &"RIVAL",
		"with its own type intact")


# --- strict-type fixtures ----------------------------------------------------

## A VALID `from_dict` payload. Every strict-type case below mutates exactly one field of
## this, so the rejection can only come from the field under test (test 33 proves the
## baseline is accepted).
func _valid_payload() -> Dictionary:
	return {
		"id": "sect_z",
		"template_id": "sect_z",
		"leader_ref": "player",
		"elder_refs": [],
		"rank_by_character": {"player": "rank_inner"},
		"resources": {"spirit_stones": 100},
		"territory": ["region_a"],
		"reputation": {"world": 10},
		"influence": 5,
		"ally_sect_ids": [],
		"enemy_sect_ids": [],
	}


## Assert `payload` is REJECTED by `from_dict` AND that the receiving state is unchanged.
## The receiver is a populated state (not a blank one) so "unchanged" is a real claim: a
## partial commit would be visible as a diff in its snapshot.
func _assert_rejected(payload: Dictionary, what: String) -> void:
	var state := _populated_state()
	var before := state.to_dict()
	assert_false(state.from_dict(payload), "%s is rejected" % what)
	assert_eq(state.to_dict(), before, "%s left the existing state unchanged" % what)


## All validation errors of a template / catalog joined, for asserting WHICH invariant fired.
func _errors(tmpl: SectTemplateData) -> String:
	return " | ".join(tmpl.validation_errors())


func _cat_errors(cat: SectCatalog) -> String:
	return " | ".join(cat.validation_errors())


## A sect with a member, a leader, resources, territory and reputation — something to lose.
func _populated_state() -> SectState:
	var svc := _service(false, [])
	var t := _template(&"sect_a")
	var state := SectState.create_from_template(t)
	svc.register_sect(state, t)
	svc.join_member(&"sect_a", PLAYER, &"rank_inner")
	svc.assign_leader(&"sect_a", PLAYER)
	return state


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


## A RelationshipService whose IN-PLACE RETYPE always fails, built on a REAL store/config so
## `create_edge` genuinely works and the pre-existing edge can be inspected after the
## rejection. This is what proves the non-destructive contract: with the old
## remove-then-create shape there would be no edge left to inspect at all.
class _NoRetypeRelService extends RelationshipService:
	func _init(store: RelationshipStore, config: RelationshipConfigData) -> void:
		super(store, config)
	func set_relationship_type(_edge_id: StringName, _relationship_type: StringName) -> bool:
		return false


## A RelationshipService whose edge REMOVAL always fails (the edge stays in the real store),
## to prove `clear_diplomacy` checks that result instead of discarding it.
class _NoRemoveRelService extends RelationshipService:
	func _init(store: RelationshipStore, config: RelationshipConfigData) -> void:
		super(store, config)
	func remove_edge(_edge_id: StringName) -> bool:
		return false

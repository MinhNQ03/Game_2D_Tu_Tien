extends TestCase
## Unit tests for the Faction domain (Phase 07, D-042): data validation, `FactionState`
## (de)serialization + invariants, `FactionStore` and its per-sect index, and the
## `FactionService` mutation path — including the sect-roster membership authority, the
## Faction↔Faction relationship mirror with transactional rollback, and the deterministic
## politics rules.
##
## Pure domain: everything is `RefCounted` built via `.new()` (no disk, no Node), so there is
## nothing to free — L-019 applies only to Nodes. The sect side is a REAL `SectStore` driven
## through a REAL `SectService`, not a stub, because the whole point of the membership rule is
## that the faction service defers to the actual roster; a stub roster would let the test pass
## while the real composition was broken.
##
## Every `@export` touched below is a TYPED array, and a typed property will not accept an
## untyped one — the resulting VM error ABORTS the method, which the runner then reports as
## PASS because it only counts recorded assertion failures (L-026). So every fixture builds a
## TYPED LOCAL and assigns that.

const GoalScript := preload("res://src/data/factions/faction_goal_data.gd")
const TemplateScript := preload("res://src/data/factions/faction_template_data.gd")
const CatalogScript := preload("res://src/data/factions/faction_catalog.gd")
const StateScript := preload("res://src/domain/faction/faction_state.gd")
const StoreScript := preload("res://src/domain/faction/faction_store.gd")
const ServiceScript := preload("res://src/domain/faction/faction_service.gd")

const SectTemplateScript := preload("res://src/data/sects/sect_template_data.gd")
const SectRankScript := preload("res://src/data/sects/sect_rank_data.gd")
const SectStoreScript := preload("res://src/domain/sect/sect_store.gd")
const SectServiceScript := preload("res://src/domain/sect/sect_service.gd")

const RelConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")
const RelStoreScript := preload("res://src/domain/relationship/relationship_store.gd")
const RelServiceScript := preload("res://src/domain/relationship/relationship_service.gd")

const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

const SECT_A := &"sect_a"
const SECT_B := &"sect_b"
const F1 := &"faction_one"
const F2 := &"faction_two"
const F3 := &"faction_three"
const PLAYER := &"player"
const OUTSIDER := &"outsider"

## The authored catalog the game actually ships, for the content drift guard.
const AUTHORED_CATALOG_PATH := "res://data/factions/faction_catalog.tres"
const AUTHORED_SECT_CATALOG_PATH := "res://data/sects/sect_catalog.tres"

var _known_characters: Dictionary = {}
var _rel_service: RelationshipService = null
var _sect_service: SectService = null


# --- typed-fixture builders --------------------------------------------------

func _goal(gid: StringName, key: StringName, kind: int, priority: int) -> FactionGoalData:
	var g: FactionGoalData = GoalScript.new()
	g.goal_id = gid
	g.name_key = key
	g.kind = kind
	g.priority = priority
	return g


func _goals(entries: Array) -> Array[FactionGoalData]:
	var out: Array[FactionGoalData] = []
	for entry in entries:
		out.append(entry)
	return out


func _ids(entries: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in entries:
		out.append(StringName(entry))
	return out


func _template(
		fid: StringName,
		sect_id: StringName = SECT_A,
		stance: int = 0,
		influence: int = 40) -> FactionTemplateData:
	var t: FactionTemplateData = TemplateScript.new()
	t.id = fid
	t.parent_sect_id = sect_id
	t.name_key = &"FACTION_NAME"
	t.doctrine_key = &"FACTION_DOCTRINE"
	t.stance = stance
	t.influence_seed = influence
	t.goals = _goals([
		_goal(&"goal_power", &"G_POWER", GoalScript.GoalKind.AUTHORITY, 3),
		_goal(&"goal_creed", &"G_CREED", GoalScript.GoalKind.DOCTRINE, 1),
	])
	t.starting_resources = {"spirit_stones": 80}
	return t


func _catalog_of(templates: Array) -> FactionCatalog:
	var listed: Array[FactionTemplateData] = []
	for t in templates:
		listed.append(t)
	var cat: FactionCatalog = CatalogScript.new()
	cat.factions = listed
	return cat


## A relationship config carrying the two dimensions the faction mirror's survival test needs.
func _rel_config() -> RelationshipConfigData:
	var dims: Array[Dictionary] = [
		{"id": &"affinity", "default": 0, "min": -100, "max": 100},
		{"id": &"rivalry", "default": 0, "min": 0, "max": 100},
	]
	var cfg: RelationshipConfigData = RelConfigScript.new()
	cfg.dimensions = dims
	return cfg


func _sect_ladder() -> Array[SectRankData]:
	var out: Array[SectRankData] = []
	var r: SectRankData = SectRankScript.new()
	r.rank_id = &"rank_outer"
	r.name_key = &"R_OUTER"
	r.authority = 10
	out.append(r)
	return out


func _sect_template(sid: StringName) -> SectTemplateData:
	var t: SectTemplateData = SectTemplateScript.new()
	t.id = sid
	t.name_key = &"SECT_NAME"
	t.doctrine_key = &"SECT_DOCTRINE"
	t.tier = 1
	t.rank_ladder = _sect_ladder()
	return t


func _character(cid: StringName) -> CharacterState:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var ct: CharacterTemplateData = CharacterTemplateScript.new()
	ct.id = &"char_x"
	ct.name_key = &"NAME"
	ct.base_stats = stats
	return CharacterState.create_from_template(ct, cid)


## A real SectStore with `sect_ids` registered, and `members` enrolled into the FIRST sect
## through a real `SectService` — the authoritative path, not a hand-written roster.
func _sect_store(sect_ids: Array, members: Array) -> SectStore:
	var store: SectStore = SectStoreScript.new()
	var svc: SectService = SectServiceScript.new(store)
	var known := {}
	for cid in members:
		known[String(cid)] = _character(StringName(cid))
	_known_characters = known
	svc.set_character_resolver(func(cid: StringName) -> CharacterState:
		return _known_characters.get(String(cid)))
	for sid in sect_ids:
		var t := _sect_template(StringName(sid))
		svc.register_sect(SectState.create_from_template(t), t)
	if not sect_ids.is_empty():
		for cid in members:
			svc.join_member(StringName(sect_ids[0]), StringName(cid), &"rank_outer")
	_sect_service = svc
	return store


## A FactionService with a store, a real sect store, an optional REAL relationship mirror, and
## the character resolver bound to whatever `_sect_store` already created.
func _service(sect_store: SectStore, with_rel: bool) -> FactionService:
	var store: FactionStore = StoreScript.new()
	var svc: FactionService = ServiceScript.new(store)
	svc.set_sect_store(sect_store)
	_rel_service = null
	if with_rel:
		var cfg := _rel_config()
		var rel_store: RelationshipStore = RelStoreScript.new(cfg)
		var rel_svc: RelationshipService = RelServiceScript.new(rel_store, cfg)
		_rel_service = rel_svc
		svc.set_relationship_service(rel_svc)
	svc.set_character_resolver(func(cid: StringName) -> CharacterState:
		return _known_characters.get(String(cid)))
	return svc


func _reg(svc: FactionService, tmpl: FactionTemplateData) -> bool:
	return svc.register_faction(FactionState.create_from_template(tmpl), tmpl)


# === 1. Goal data validation ================================================

func test_01_goal_validation() -> void:
	var g := _goal(&"goal_a", &"K", GoalScript.GoalKind.AUTHORITY, 2)
	assert_true(g.is_valid(), "a well-formed goal validates")
	g.goal_id = &""
	assert_false(g.is_valid(), "empty goal_id invalidates")
	g.goal_id = &"goal_a"
	g.name_key = &""
	assert_false(g.is_valid(), "empty name_key invalidates (no hard-coded display text)")
	g.name_key = &"K"
	g.priority = 0
	assert_false(g.is_valid(), "priority < 1 invalidates")
	g.priority = 2
	g.kind = 99
	assert_false(g.is_valid(), "an out-of-range kind invalidates (closed enum)")


# === 2-3. Template validation ===============================================

func test_02_template_valid() -> void:
	var t := _template(F1)
	assert_true(t.is_valid(), "a well-formed faction template validates: %s"
		% str(t.validation_errors()))


## Each negative case differs from the KNOWN-GOOD fixture in exactly ONE field and would
## otherwise be accepted, so a pass actually proves the specific rule (L-024).
func test_03_template_invariants() -> void:
	var t := _template(F1)
	t.parent_sect_id = &""
	assert_false(t.is_valid(), "a faction with no parent sect is not a faction")

	t = _template(F1)
	t.doctrine_key = &""
	assert_false(t.is_valid(),
		"a faction with no stated position cannot be disagreed with on the merits")

	t = _template(F1)
	t.goals = _goals([])
	assert_false(t.is_valid(), "a faction with no goal has no politics to resolve")

	t = _template(F1)
	t.goals = _goals([
		_goal(&"dup", &"A", GoalScript.GoalKind.AUTHORITY, 2),
		_goal(&"dup", &"B", GoalScript.GoalKind.DOCTRINE, 1),
	])
	assert_false(t.is_valid(), "duplicate goal_id invalidates")

	t = _template(F1)
	t.influence_seed = TemplateScript.INFLUENCE_MAX + 1
	assert_false(t.is_valid(), "influence above the bound invalidates")

	t = _template(F1)
	t.influence_seed = -1
	assert_false(t.is_valid(), "negative influence invalidates")

	t = _template(F1)
	t.stance = 99
	assert_false(t.is_valid(), "an out-of-range stance invalidates (closed enum)")

	t = _template(F1)
	t.id = SECT_A
	assert_false(t.is_valid(), "a faction id equal to its parent sect id invalidates")

	t = _template(F1)
	t.default_rival_faction_ids = _ids([F1])
	assert_false(t.is_valid(), "a faction cannot declare itself a rival")

	t = _template(F1)
	t.default_allied_faction_ids = _ids([F2])
	t.default_rival_faction_ids = _ids([F2])
	assert_false(t.is_valid(), "the same faction cannot be both allied and rival")

	t = _template(F1)
	t.starting_resources = {"spirit_stones": -5}
	assert_false(t.is_valid(), "a negative resource quantity invalidates")

	t = _template(F1)
	t.starting_resources = {"spirit_stones": 10.0}
	assert_false(t.is_valid(), "a float resource quantity invalidates (integer counts only)")


## Goal ordering must be deterministic: descending priority, ties broken by goal_id. Without
## the tie-break two equal-priority goals could render in either order between runs.
func test_04_goals_order_deterministically() -> void:
	var t := _template(F1)
	t.goals = _goals([
		_goal(&"b_goal", &"B", GoalScript.GoalKind.AUTHORITY, 2),
		_goal(&"a_goal", &"A", GoalScript.GoalKind.DOCTRINE, 2),
		_goal(&"top", &"T", GoalScript.GoalKind.RESOURCES, 9),
	])
	var ordered := t.goals_by_priority()
	assert_eq(ordered.size(), 3, "all goals returned")
	assert_eq(ordered[0].goal_id, &"top", "highest priority first")
	assert_eq(ordered[1].goal_id, &"a_goal", "equal priority resolves by goal_id")
	assert_eq(ordered[2].goal_id, &"b_goal", "and the tie-break is total")
	# Repeating the call must give the identical order (no incidental dictionary ordering).
	var again := t.goals_by_priority()
	for i in ordered.size():
		assert_eq(again[i].goal_id, ordered[i].goal_id, "the order is stable across calls")


# === 5. Catalog cross-template integrity ====================================

func test_05_catalog_integrity() -> void:
	var a := _template(F1)
	var b := _template(F2)
	a.default_rival_faction_ids = _ids([F2])
	b.default_rival_faction_ids = _ids([F1])
	var cat := _catalog_of([a, b])
	assert_true(cat.is_valid(), "a mutually-declared pair validates: %s"
		% str(cat.validation_errors()))

	# Empty.
	assert_false(_catalog_of([]).is_valid(), "an empty catalog invalidates")

	# Duplicate ids.
	assert_false(_catalog_of([_template(F1), _template(F1)]).is_valid(),
		"duplicate faction ids invalidate")

	# Dangling declaration.
	var lone := _template(F1)
	lone.default_rival_faction_ids = _ids([&"faction_ghost"])
	assert_false(_catalog_of([lone]).is_valid(),
		"a declaration naming a faction not in the catalog invalidates")

	# One-sided declaration.
	var x := _template(F1)
	var y := _template(F2)
	x.default_rival_faction_ids = _ids([F2])
	assert_false(_catalog_of([x, y]).is_valid(),
		"a one-sided declaration invalidates; internal politics must be mutual")

	# Disagreeing pair.
	var p := _template(F1)
	var q := _template(F2)
	p.default_allied_faction_ids = _ids([F2])
	q.default_rival_faction_ids = _ids([F1])
	assert_false(_catalog_of([p, q]).is_valid(),
		"ALLIED on one side and RIVAL on the other invalidates")


## The rule that keeps this system "internal politics" rather than a second diplomacy system:
## a declared pair must share a parent sect. Cross-sect standing is the SECTS' own declared
## ally/enemy, already shipped — two independent answers to "are these groups hostile" is the
## duplication D-015 settled for membership.
func test_06_catalog_rejects_cross_sect_politics() -> void:
	var here := _template(F1, SECT_A)
	var there := _template(F2, SECT_B)
	here.default_rival_faction_ids = _ids([F2])
	there.default_rival_faction_ids = _ids([F1])
	var cat := _catalog_of([here, there])
	assert_false(cat.is_valid(), "a declared pair spanning two sects invalidates")
	var joined := str(cat.validation_errors())
	assert_true(joined.contains("inside ONE sect") or joined.contains("one sect"),
		"and the error says why (got %s)" % joined)


func test_07_catalog_lookups_are_deterministic() -> void:
	var cat := _catalog_of([
		_template(F3, SECT_A), _template(F1, SECT_A), _template(F2, SECT_B),
	])
	assert_not_null(cat.find_faction(F1), "find_faction resolves a known id")
	assert_null(cat.find_faction(&"nope"), "find_faction returns null for an unknown id")
	var of_a := cat.factions_of_sect(SECT_A)
	assert_eq(of_a.size(), 2, "two factions belong to sect_a")
	assert_eq(of_a[0].id, F1, "factions_of_sect is sorted by id (faction_one first)")
	assert_eq(of_a[1].id, F3, "and faction_three second")
	var parents := cat.parent_sect_ids()
	assert_eq(parents.size(), 2, "two distinct parent sects")
	assert_eq(parents[0], SECT_A, "parent sect ids are sorted")


# === 8-9. State creation + serialization ====================================

func test_08_state_creation_from_template() -> void:
	var t := _template(F1, SECT_A, TemplateScript.Stance.REFORMIST, 55)
	var state := FactionState.create_from_template(t)
	assert_not_null(state, "state builds from a valid template")
	assert_eq(state.id, F1, "id copied")
	assert_eq(state.parent_sect_id, SECT_A, "parent sect copied")
	assert_eq(state.stance, int(TemplateScript.Stance.REFORMIST), "stance copied")
	assert_eq(state.influence, 55, "influence seeded")
	assert_eq(state.get_resource(&"spirit_stones"), 80, "resources seeded")
	assert_eq(state.goal_ids().size(), 2, "goal ids seeded from the template")
	# Leadership + roster start EMPTY: taking a side always flows through the service, which
	# is the only thing that can consult the parent sect's roster.
	assert_eq(state.leader_ref, &"", "no leader is invented")
	assert_eq(state.member_count(), 0, "no members are invented")

	assert_null(FactionState.create_from_template(null), "a null template yields null")
	var bad := _template(F1)
	bad.doctrine_key = &""
	assert_null(FactionState.create_from_template(bad), "an invalid template yields null")


func test_09_state_round_trips_through_a_dict() -> void:
	var state := FactionState.create_from_template(
		_template(F1, SECT_A, TemplateScript.Stance.RADICAL, 33))
	state.insert_member(PLAYER)
	state.write_leader(PLAYER)
	state.insert_rival(F2)
	var data := state.to_dict()

	var restored := FactionState.new()
	assert_true(restored.from_dict(data), "a well-formed payload hydrates")
	assert_eq(restored.id, state.id, "id survives")
	assert_eq(restored.parent_sect_id, state.parent_sect_id, "parent sect survives")
	assert_eq(restored.leader_ref, PLAYER, "leader survives")
	assert_eq(restored.influence, 33, "influence survives")
	assert_eq(restored.stance, int(TemplateScript.Stance.RADICAL), "stance survives")
	assert_true(restored.is_member(PLAYER), "roster survives")
	assert_true(restored.is_rival_of(F2), "declared rivalry survives")
	assert_eq(str(restored.to_dict()), str(data), "the round trip is byte-stable")


## Serialization must be DETERMINISTIC: the same state always produces the same dict, whatever
## order its collections were filled in, or two saves of one world would not compare equal.
func test_10_serialization_is_order_independent() -> void:
	var a := FactionState.create_from_template(_template(F1))
	a.insert_member(&"c_zz")
	a.insert_member(&"c_aa")
	var b := FactionState.create_from_template(_template(F1))
	b.insert_member(&"c_aa")
	b.insert_member(&"c_zz")
	assert_eq(str(a.to_dict()), str(b.to_dict()),
		"insertion order does not change the snapshot")


# === 11-12. from_dict type gates + atomicity ================================

## A coercion that SUCCEEDS on bad input is indistinguishable from valid input, so every field
## is type-gated BEFORE conversion (L-024). Each payload below differs from the known-good one
## in exactly one field and would otherwise be accepted.
func test_11_from_dict_rejects_coercible_garbage() -> void:
	var good := _good_payload()
	var baseline := FactionState.new()
	assert_true(baseline.from_dict(good.duplicate(true)),
		"the baseline fixture IS accepted (so every rejection below is about its one change)")

	var cases := {
		"id": 100,                      # String(100) would invent the id "100"
		"parent_sect_id": null,         # String(null) would invent ""
		"leader_ref": true,             # String(true) would invent "true"
		"template_id": 7,
		"influence": "40",              # int("40") would invent 40
		"stance": 1.0,                  # a float is not an enum ordinal
		"member_refs": "player",        # not an Array
		"goal_ids": [42],               # a number is not an id
		"resources": {"spirit_stones": 10.0},   # a float quantity
		"allied_faction_ids": [true],
		"rival_faction_ids": {},        # not an Array
	}
	var keys: Array = cases.keys()
	keys.sort()
	for field in keys:
		var payload: Dictionary = good.duplicate(true)
		payload[field] = cases[field]
		var state := FactionState.new()
		assert_false(state.from_dict(payload),
			"a wrong-typed '%s' is REJECTED, never coerced" % field)


func test_12_from_dict_rejects_broken_invariants() -> void:
	var payload: Dictionary = _good_payload()
	payload["influence"] = StateScript.INFLUENCE_MAX + 1
	assert_false(FactionState.new().from_dict(payload), "out-of-range influence is rejected")

	payload = _good_payload()
	payload["stance"] = 99
	assert_false(FactionState.new().from_dict(payload), "an unknown stance is rejected")

	payload = _good_payload()
	payload["leader_ref"] = "someone_else"
	assert_false(FactionState.new().from_dict(payload),
		"a leader who is not in the roster is rejected")

	payload = _good_payload()
	payload["member_refs"] = ["player", "player"]
	assert_false(FactionState.new().from_dict(payload), "a duplicate member is rejected")

	payload = _good_payload()
	payload["parent_sect_id"] = payload["id"]
	assert_false(FactionState.new().from_dict(payload),
		"a parent sect id equal to the faction id is rejected")

	payload = _good_payload()
	payload["allied_faction_ids"] = [String(F2)]
	payload["rival_faction_ids"] = [String(F2)]
	assert_false(FactionState.new().from_dict(payload),
		"the same faction being both allied and rival is rejected")

	payload = _good_payload()
	payload["rival_faction_ids"] = [payload["id"]]
	assert_false(FactionState.new().from_dict(payload), "self in the rival list is rejected")

	payload = _good_payload()
	payload["resources"] = {"spirit_stones": -1}
	assert_false(FactionState.new().from_dict(payload),
		"a negative resource quantity is rejected")


## A rejected payload must leave the receiver BYTE-IDENTICAL. Staging-then-committing is the
## whole reason: a validator that writes as it goes leaves a half-hydrated object behind.
func test_13_a_rejected_payload_changes_nothing() -> void:
	var state := FactionState.create_from_template(
		_template(F1, SECT_A, TemplateScript.Stance.LOYALIST, 42))
	state.insert_member(PLAYER)
	var before := str(state.to_dict())

	var payload: Dictionary = _good_payload()
	payload["influence"] = "not an int"
	assert_false(state.from_dict(payload), "the payload is rejected")
	assert_eq(str(state.to_dict()), before,
		"and the state is byte-identical to before the call")


func _good_payload() -> Dictionary:
	var state := FactionState.create_from_template(
		_template(F1, SECT_A, TemplateScript.Stance.LOYALIST, 40))
	state.insert_member(PLAYER)
	state.write_leader(PLAYER)
	return state.to_dict()


# === 14-16. Store ===========================================================

func test_14_store_add_and_remove() -> void:
	var store: FactionStore = StoreScript.new()
	assert_eq(store.count(), 0, "a fresh store is empty")
	assert_true(store.add(FactionState.create_from_template(_template(F1))), "add succeeds")
	assert_eq(store.count(), 1, "count reflects the add")
	assert_true(store.has(F1), "has() finds it")
	assert_false(store.add(FactionState.create_from_template(_template(F1))),
		"a duplicate id is rejected")
	assert_false(store.add(null), "a null state is rejected")
	var orphan := FactionState.create_from_template(_template(F2))
	orphan.parent_sect_id = &""
	assert_false(store.add(orphan), "a faction with no parent sect is rejected")
	assert_true(store.remove(F1), "remove succeeds")
	assert_false(store.remove(F1), "removing twice reports false")
	assert_eq(store.count(), 0, "and the store is empty again")


## The per-sect index must stay consistent through add AND remove — a stale index would make
## a removed faction keep voting in its sect's politics.
func test_15_store_per_sect_index_is_consistent() -> void:
	var store: FactionStore = StoreScript.new()
	store.add(FactionState.create_from_template(_template(F1, SECT_A)))
	store.add(FactionState.create_from_template(_template(F3, SECT_A)))
	store.add(FactionState.create_from_template(_template(F2, SECT_B)))
	assert_eq(store.factions_of_sect(SECT_A).size(), 2, "two factions in sect_a")
	assert_eq(store.factions_of_sect(SECT_B).size(), 1, "one in sect_b")
	assert_eq(store.factions_of_sect(&"sect_ghost").size(), 0, "none in an unknown sect")
	assert_eq((store.factions_of_sect(SECT_A)[0] as FactionState).id, F1,
		"factions_of_sect is deterministic (sorted by id)")
	assert_eq(store.sect_ids_sorted().size(), 2, "two distinct parent sects")

	store.remove(F1)
	assert_eq(store.factions_of_sect(SECT_A).size(), 1,
		"the index drops a removed faction")
	store.remove(F2)
	assert_eq(store.sect_ids_sorted().size(), 1,
		"a sect with no remaining factions leaves the index")


func test_16_store_hydrate_is_fail_closed() -> void:
	var store: FactionStore = StoreScript.new()
	store.add(FactionState.create_from_template(_template(F1)))
	var before := str(store.to_dict())

	assert_false(store.hydrate("not a dict"), "a non-dict payload is rejected")
	assert_false(store.hydrate({"factions": "nope"}), "a non-array 'factions' is rejected")
	assert_false(store.hydrate({"factions": [{"id": 5}]}), "a malformed entry is rejected")
	var dup := _good_payload()
	assert_false(store.hydrate({"factions": [dup, dup.duplicate(true)]}),
		"a duplicate id in the payload is rejected")
	assert_eq(str(store.to_dict()), before, "and the store is unchanged after every rejection")

	assert_true(store.hydrate({"factions": [_good_payload()]}), "a valid payload hydrates")
	assert_eq(store.count(), 1, "the store now holds exactly the payload")
	assert_eq(store.factions_of_sect(SECT_A).size(), 1, "and the per-sect index was rebuilt")


# === 17-20. Membership: the SECT roster is the authority ====================

## The heart of D-015 for factions: a faction is a group INSIDE a sect, so somebody who is not
## on the sect's roster cannot take a side inside it. Allowing it would make the faction roster
## an independent membership source competing with the sect roster.
func test_17_only_sect_members_may_take_a_side() -> void:
	var sects := _sect_store([SECT_A], [PLAYER, OUTSIDER])
	# OUTSIDER exists as a character but is NOT enrolled in the sect: remove them from the
	# sect roster so the only difference from PLAYER is sect membership.
	_sect_service.leave_member(SECT_A, OUTSIDER)
	var svc := _service(sects, false)
	assert_true(_reg(svc, _template(F1, SECT_A)), "the faction registers")

	assert_true(svc.join_member(F1, PLAYER), "a sect member may take a side")
	assert_false(svc.join_member(F1, OUTSIDER),
		"a character who is not in the parent sect may NOT take a side inside it")
	assert_false(svc.get_store().get_faction(F1).is_member(OUTSIDER),
		"and nothing was written for them")


func test_18_membership_rejections() -> void:
	var sects := _sect_store([SECT_A], [PLAYER])
	var svc := _service(sects, false)
	_reg(svc, _template(F1, SECT_A))

	assert_false(svc.join_member(&"faction_ghost", PLAYER), "an unknown faction is rejected")
	assert_false(svc.join_member(F1, &""), "an empty character id is rejected")
	assert_false(svc.join_member(F1, &"never_existed"),
		"a character the resolver cannot find is rejected (no invented characters)")
	assert_true(svc.join_member(F1, PLAYER), "the real member joins")
	assert_false(svc.join_member(F1, PLAYER), "a duplicate join is rejected")


## One seat per sect. This is what makes `CharacterState.faction_id` a valid single value
## rather than a list — without it the derived cache could not represent the truth.
func test_19_one_faction_seat_per_sect() -> void:
	var sects := _sect_store([SECT_A], [PLAYER])
	var svc := _service(sects, false)
	_reg(svc, _template(F1, SECT_A))
	_reg(svc, _template(F2, SECT_A))

	assert_true(svc.join_member(F1, PLAYER), "the player takes the first side")
	assert_false(svc.join_member(F2, PLAYER),
		"they cannot hold a seat in a second faction of the same sect")
	assert_true(svc.leave_member(F1, PLAYER), "after leaving the first")
	assert_true(svc.join_member(F2, PLAYER), "they may take another side")


func test_20_leadership_is_drawn_from_members() -> void:
	var sects := _sect_store([SECT_A], [PLAYER])
	var svc := _service(sects, false)
	_reg(svc, _template(F1, SECT_A))

	assert_false(svc.assign_leader(F1, PLAYER),
		"leadership cannot be imposed on a non-member")
	assert_true(svc.join_member(F1, PLAYER), "the player takes the side")
	assert_true(svc.assign_leader(F1, PLAYER), "and may then lead it")
	assert_eq(svc.get_store().get_faction(F1).leader_ref, PLAYER, "the leader is recorded")
	assert_true(svc.assign_leader(F1, PLAYER), "re-assigning the same leader is idempotent")
	# Leaving clears leadership rather than leaving a dangling leader_ref behind.
	assert_true(svc.leave_member(F1, PLAYER), "the leader leaves")
	assert_eq(svc.get_store().get_faction(F1).leader_ref, &"",
		"and leadership is cleared, never left dangling")
	assert_true(svc.assign_leader(F1, &""), "clearing an already-empty leader is idempotent")


# === 21-22. Derived CharacterState.faction_id cache =========================

func test_21_derived_faction_cache_follows_the_roster() -> void:
	var sects := _sect_store([SECT_A], [PLAYER])
	var svc := _service(sects, false)
	_reg(svc, _template(F1, SECT_A))
	var player: CharacterState = _known_characters[String(PLAYER)]
	assert_eq(player.faction_id, &"", "the cache starts empty")

	svc.join_member(F1, PLAYER)
	assert_eq(player.faction_id, F1, "joining writes the derived cache")
	assert_true(svc.verify_character_cache(), "and the cache agrees with the roster")

	svc.leave_member(F1, PLAYER)
	assert_eq(player.faction_id, &"", "leaving clears it")


## The roster WINS. A cache that disagrees is reported, never trusted, and `sync` rebuilds it
## FROM the roster rather than the other way round.
func test_22_roster_wins_over_a_drifted_cache() -> void:
	var sects := _sect_store([SECT_A], [PLAYER])
	var svc := _service(sects, false)
	_reg(svc, _template(F1, SECT_A))
	svc.join_member(F1, PLAYER)
	var player: CharacterState = _known_characters[String(PLAYER)]

	player.faction_id = &"faction_lie"
	assert_false(svc.verify_character_cache(), "a drifted cache is detected, not tolerated")
	svc.sync_character_cache()
	assert_eq(player.faction_id, F1, "sync rebuilds the cache FROM the roster")
	assert_true(svc.verify_character_cache(), "and it agrees again")


# === 23-27. The relationship mirror =========================================

func test_23_declared_politics_mirrors_to_a_real_graph_edge() -> void:
	var sects := _sect_store([SECT_A], [])
	var svc := _service(sects, true)
	var a := _template(F1, SECT_A)
	var b := _template(F2, SECT_A)
	a.default_rival_faction_ids = _ids([F2])
	b.default_rival_faction_ids = _ids([F1])
	_reg(svc, a)
	_reg(svc, b)
	assert_true(svc.apply_default_politics(), "the declared pair mirrors")

	var eid := ServiceScript.edge_id(F1, F2)
	var edge: RelationshipEdge = _rel_service.get_store().get_edge(eid)
	assert_not_null(edge, "a relationship edge exists for the pair")
	assert_eq(edge.relationship_type, ServiceScript.REL_TYPE_RIVAL, "carrying the right type")
	assert_true(edge.symmetric, "the edge is symmetric (one edge per pair)")
	# The endpoints must be typed FACTION, not SECT: a faction id in the sect namespace would
	# silently merge a faction's politics into its parent sect's diplomacy.
	assert_eq(edge.from_ref.kind, RelationshipEndpoint.Kind.FACTION,
		"endpoints are typed as factions")
	assert_eq(edge.to_ref.kind, RelationshipEndpoint.Kind.FACTION, "on both ends")


## The edge id must be pair-canonical AND namespaced away from the sect mirror. Sharing
## `"sect_rel:"` would make the two mirrors collide on a pair and the second create would be
## rejected as a duplicate id.
func test_24_edge_ids_are_canonical_and_namespaced() -> void:
	assert_eq(ServiceScript.edge_id(F1, F2), ServiceScript.edge_id(F2, F1),
		"A-B and B-A map to ONE edge id")
	var eid := String(ServiceScript.edge_id(F1, F2))
	assert_true(eid.begins_with(ServiceScript.EDGE_PREFIX),
		"the id is namespaced to the faction mirror (got '%s')" % eid)
	assert_ne(eid, String(SectServiceScript.edge_id(F1, F2)),
		"and is distinct from the sect mirror's id for the same pair")


## L-023: changing a relation must RETYPE the existing edge in place, never delete and
## recreate. Asserting the type alone would pass for a brand-new edge, so this pins object
## IDENTITY plus the dimension values and the history that a recreate would have discarded.
func test_25_changing_a_relation_retypes_the_edge_in_place() -> void:
	var sects := _sect_store([SECT_A], [])
	var svc := _service(sects, true)
	_reg(svc, _template(F1, SECT_A))
	_reg(svc, _template(F2, SECT_A))
	assert_true(svc.add_rivalry(F1, F2), "the rivalry is declared")

	var eid := ServiceScript.edge_id(F1, F2)
	var edge: RelationshipEdge = _rel_service.get_store().get_edge(eid)
	assert_not_null(edge, "the edge exists")
	# Accumulate state a recreate would silently throw away.
	assert_true(_rel_service.apply_delta(eid, &"rivalry", 30, &"FEUD"),
		"a dimension accumulates on the edge")
	var identity := edge.get_instance_id()
	var history_before := edge.history_size()
	assert_true(history_before > 0, "and the history recorded it")

	assert_true(svc.add_alliance(F1, F2), "the pair later aligns instead")
	var after: RelationshipEdge = _rel_service.get_store().get_edge(eid)
	assert_not_null(after, "the edge still exists")
	assert_eq(after.get_instance_id(), identity,
		"it is the SAME object, retyped in place — not a replacement")
	assert_eq(after.relationship_type, ServiceScript.REL_TYPE_ALLIED, "with the new type")
	assert_eq(after.get_dimension(&"rivalry"), 30,
		"the accumulated dimension survived the retype")
	assert_eq(after.history_size(), history_before, "and so did the history")
	# The faction side must agree, symmetrically, and never hold both relations at once.
	var f1 := svc.get_store().get_faction(F1)
	var f2 := svc.get_store().get_faction(F2)
	assert_true(f1.is_allied_with(F2) and f2.is_allied_with(F1), "both sides read allied")
	assert_false(f1.is_rival_of(F2) or f2.is_rival_of(F1), "and neither still reads rival")


func test_26_politics_rejections_leave_nothing_changed() -> void:
	var sects := _sect_store([SECT_A, SECT_B], [])
	var svc := _service(sects, true)
	_reg(svc, _template(F1, SECT_A))
	_reg(svc, _template(F2, SECT_A))
	_reg(svc, _template(F3, SECT_B))

	assert_false(svc.add_rivalry(F1, F1), "a faction cannot align with itself")
	assert_false(svc.add_rivalry(F1, &"faction_ghost"), "an unknown faction is rejected")
	# Cross-sect politics is the sects' own diplomacy, not this system's.
	assert_false(svc.add_rivalry(F1, F3),
		"two factions in different sects cannot declare internal politics")
	assert_eq(_rel_service.get_store().edge_count(), 0,
		"and no edge was created by any rejected call")

	assert_true(svc.add_rivalry(F1, F2), "a legitimate rivalry is declared")
	assert_false(svc.add_rivalry(F1, F2), "declaring it twice is rejected")


## `clear_politics` runs the RELATIONSHIP side first and checks it, so the two stores can
## never diverge — and it refuses to destroy an edge it does not own.
func test_27_clear_politics_is_transactional() -> void:
	var sects := _sect_store([SECT_A], [])
	var svc := _service(sects, true)
	_reg(svc, _template(F1, SECT_A))
	_reg(svc, _template(F2, SECT_A))

	# (a) Nothing declared: an idempotent no-op that must not touch an unrelated edge.
	var eid := ServiceScript.edge_id(F1, F2)
	var unrelated := _rel_service.create_edge(
		eid, RelationshipEndpoint.for_faction(F1), RelationshipEndpoint.for_faction(F2),
		&"MENTORSHIP", true, true)
	assert_not_null(unrelated, "an unrelated edge exists on the pair")
	assert_true(svc.clear_politics(F1, F2), "clearing an undeclared pair is a no-op")
	assert_not_null(_rel_service.get_store().get_edge(eid),
		"and the unrelated edge was NOT destroyed")

	# (b) Declared, but the mirrored edge carries a type this mirror does not own.
	svc.get_store().get_faction(F1).insert_rival(F2)
	svc.get_store().get_faction(F2).insert_rival(F1)
	assert_false(svc.clear_politics(F1, F2),
		"refusing to clear when the edge carries an unrelated type")
	assert_not_null(_rel_service.get_store().get_edge(eid), "the edge is still there")
	assert_true(svc.get_store().get_faction(F1).is_rival_of(F2),
		"and the faction side was not half-cleared")

	# (c) A real declared pair clears cleanly, both sides.
	assert_true(_rel_service.remove_edge(eid), "drop the unrelated edge out-of-band")
	svc.get_store().get_faction(F1).erase_rival(F2)
	svc.get_store().get_faction(F2).erase_rival(F1)
	assert_true(svc.add_rivalry(F1, F2), "declare a real rivalry")
	assert_true(svc.clear_politics(F1, F2), "it clears")
	assert_null(_rel_service.get_store().get_edge(eid), "the mirrored edge is gone")
	assert_false(svc.get_store().get_faction(F1).is_rival_of(F2), "and both sides are clear")
	assert_false(svc.get_store().get_faction(F2).is_rival_of(F1), "symmetrically")


## A declaration with no graph to mirror into, or naming a faction that is not in the store,
## FAILS the whole mirror rather than being skipped — skipping is what produces a session
## whose faction state claims a rivalry the graph has no record of (D-038's lesson).
func test_28_the_mirror_fails_closed() -> void:
	var sects := _sect_store([SECT_A], [])
	# No relationship service, but politics IS declared.
	var svc := _service(sects, false)
	var a := _template(F1, SECT_A)
	var b := _template(F2, SECT_A)
	a.default_rival_faction_ids = _ids([F2])
	b.default_rival_faction_ids = _ids([F1])
	_reg(svc, a)
	_reg(svc, b)
	assert_false(svc.apply_default_politics(),
		"declared politics with no graph to mirror into fails the mirror")

	# A graph, but a dangling declaration.
	var svc2 := _service(sects, true)
	var lone := _template(F1, SECT_A)
	lone.default_rival_faction_ids = _ids([&"faction_ghost"])
	_reg(svc2, lone)
	assert_false(svc2.apply_default_politics(), "a dangling declaration fails the mirror")

	# No declarations at all: a mirror-less service is then legitimate.
	var svc3 := _service(sects, false)
	_reg(svc3, _template(F1, SECT_A))
	assert_true(svc3.apply_default_politics(),
		"with nothing declared, having no mirror is fine")


# === 29-32. Deterministic politics rules ====================================

func test_29_influence_share_is_exact_and_bounded() -> void:
	var svc := _landscape([["one", 50], ["two", 30], ["three", 20]])
	assert_eq(svc.total_influence_of_sect(SECT_A), 100, "the total is the sum")
	assert_eq(svc.influence_share(&"faction_one"), 50, "50/100 is 50%")
	assert_eq(svc.influence_share(&"faction_two"), 30, "30/100 is 30%")
	assert_eq(svc.influence_share(&"faction_three"), 20, "20/100 is 20%")
	assert_eq(svc.influence_share(&"faction_ghost"), 0, "an unknown faction has no share")


## A sect whose factions all sit at zero must not divide by zero, and must report "nobody
## holds sway" rather than an arbitrary winner.
func test_30_a_powerless_landscape_degrades_cleanly() -> void:
	var svc := _landscape([["one", 0], ["two", 0]])
	assert_eq(svc.total_influence_of_sect(SECT_A), 0, "the total is zero")
	assert_eq(svc.influence_share(&"faction_one"), 0, "no share, and no division by zero")
	assert_null(svc.dominant_faction_of(SECT_A), "nobody holds sway")
	assert_false(svc.is_contested(SECT_A), "and nothing is contested")
	assert_null(svc.dominant_faction_of(&"sect_ghost"), "an unknown sect has no dominant")


## The tie-break must be FIXED, not incidental. Without it, two factions on equal influence
## would resolve to whichever the store iterated first, so "who leads the sect" could differ
## between runs on identical data and a reloaded save could disagree with its source.
func test_31_dominance_has_a_deterministic_tie_break() -> void:
	var svc := _landscape([["zzz", 40], ["aaa", 40]])
	var winner := svc.dominant_faction_of(SECT_A)
	assert_not_null(winner, "a tie still resolves to somebody")
	assert_eq(winner.id, &"faction_aaa", "the lexicographically smaller id wins a tie")
	# Repeated calls must agree — this is the property that makes a save reproducible.
	for _i in 5:
		assert_eq(svc.dominant_faction_of(SECT_A).id, &"faction_aaa",
			"and the answer is identical on every call")

	var clear_svc := _landscape([["aaa", 10], ["zzz", 90]])
	assert_eq(clear_svc.dominant_faction_of(SECT_A).id, &"faction_zzz",
		"a real lead beats the tie-break ordering")


func test_32_contested_reflects_the_margin() -> void:
	var close := _landscape([["one", 45], ["two", 38], ["three", 31]])
	assert_true(close.is_contested(SECT_A),
		"a 7-point gap is within the contested margin (%d)" % ServiceScript.CONTESTED_MARGIN)
	var settled := _landscape([["one", 90], ["two", 10]])
	assert_false(settled.is_contested(SECT_A), "an 80-point gap is settled")
	var alone := _landscape([["one", 60]])
	assert_false(alone.is_contested(SECT_A),
		"a single faction is not contested — there is no second party")


func test_33_adjust_influence_clamps_and_reports() -> void:
	var svc := _landscape([["one", 50]])
	assert_eq(svc.adjust_influence(&"faction_one", 10), 60, "a delta applies")
	assert_eq(svc.adjust_influence(&"faction_one", 1000), StateScript.INFLUENCE_MAX,
		"and clamps at the ceiling")
	assert_eq(svc.adjust_influence(&"faction_one", -1000), StateScript.INFLUENCE_MIN,
		"and at the floor")
	assert_eq(svc.adjust_influence(&"faction_ghost", 5), -1, "an unknown faction reports -1")


## Build a one-sect landscape of `[suffix, influence]` pairs, with no relationship mirror
## (these rules are pure arithmetic over stored integers and touch no graph).
func _landscape(entries: Array) -> FactionService:
	var sects := _sect_store([SECT_A], [])
	var svc := _service(sects, false)
	for entry in entries:
		var fid := StringName("faction_%s" % String((entry as Array)[0]))
		_reg(svc, _template(fid, SECT_A, 0, int((entry as Array)[1])))
	return svc


# === 34-35. Cross-store integrity ===========================================

func test_34_a_faction_must_name_a_real_sect() -> void:
	var sects := _sect_store([SECT_A], [])
	var svc := _service(sects, false)
	_reg(svc, _template(F1, SECT_A))
	assert_true(svc.validate_against_sects(), "a faction in a real sect validates")

	var orphan := _service(sects, false)
	_reg(orphan, _template(F2, &"sect_that_does_not_exist"))
	assert_false(orphan.validate_against_sects(),
		"a faction naming an unknown parent sect is reported, not silently empty")

	# A faction id colliding with a sect id would make the two namespaces ambiguous.
	var collide := _service(sects, false)
	var bad := _template(&"faction_x", SECT_A)
	var state := FactionState.create_from_template(bad)
	state.id = SECT_A
	state.parent_sect_id = SECT_A
	collide.get_store().add(state)
	assert_false(collide.validate_against_sects(),
		"a faction id that collides with a sect id is rejected")


func test_35_registration_rejects_a_state_template_mismatch() -> void:
	var sects := _sect_store([SECT_A, SECT_B], [])
	var svc := _service(sects, false)
	var tmpl := _template(F1, SECT_A)
	var state := FactionState.create_from_template(tmpl)
	state.parent_sect_id = SECT_B  # now disagrees with its own template
	assert_false(svc.register_faction(state, tmpl),
		"a state whose parent sect disagrees with its template is rejected")
	assert_false(svc.register_faction(null, tmpl), "a null state is rejected")
	assert_false(svc.register_faction(
		FactionState.create_from_template(_template(F2, SECT_A)), null),
		"a null template is rejected")


# === 36. The no-duplication guard ===========================================

## The architectural rule D-042 pinned, asserted so it cannot regress: there is NO faction-side
## storage of any relationship dimension. `affinity`/`trust`/`respect`/`fear`/`rivalry`/`debt`
## are the six frozen dimensions (CL-12) and they live ONLY on relationship edges — a second
## copy on `FactionState` would be a second answer to "how does A feel about B", the exact
## defect D-015 had to undo for sect membership.
##
## It asserts on the SERIALIZED shape, which is the thing a save would carry and therefore the
## thing a future refactor would have to change to reintroduce the duplication.
func test_36_no_faction_side_copy_of_relationship_dimensions() -> void:
	var state := FactionState.create_from_template(_template(F1, SECT_A))
	state.insert_rival(F2)
	var keys: Array = state.to_dict().keys()
	for dimension in ["affinity", "trust", "respect", "fear", "rivalry", "debt"]:
		assert_false(keys.has(dimension),
			"FactionState does not serialize '%s' — that dimension lives on the relationship "
				% dimension + "edge, and a second copy would be a second source of truth")
	for forbidden in ["attitude_toward_player", "attitudes_toward_factions"]:
		assert_false(keys.has(forbidden),
			"the §7 sketch's inline '%s' was pinned to a relationship edge in D-042"
				% forbidden)
	# What it DOES carry is the DECLARED relation (a political fact), not a scalar standing.
	assert_true(keys.has("rival_faction_ids"),
		"it carries the declared rivalry as a list of ids, which the graph mirrors")


# === 37-40. The authored content drift guard ================================

## The shipped catalog must satisfy every rule, so adding a faction without satisfying them
## fails the suite instead of failing a player's session.
func test_37_the_authored_catalog_is_valid() -> void:
	var cat := load(AUTHORED_CATALOG_PATH) as FactionCatalog
	assert_not_null(cat, "the authored faction catalog loads")
	if cat == null:
		return
	assert_true(cat.is_valid(), "the authored faction catalog is valid: %s"
		% str(cat.validation_errors()))
	assert_true(cat.factions.size() >= 2,
		"politics needs at least two parties (got %d)" % cat.factions.size())


## Every authored faction's parent sect must exist in the shipped SECT catalog. Neither
## catalog can check this alone, so without this test a renamed sect id would only surface as
## a failed session at runtime.
func test_38_authored_factions_name_real_authored_sects() -> void:
	var factions := load(AUTHORED_CATALOG_PATH) as FactionCatalog
	var sects := load(AUTHORED_SECT_CATALOG_PATH) as SectCatalog
	assert_not_null(factions, "the faction catalog loads")
	assert_not_null(sects, "the sect catalog loads")
	if factions == null or sects == null:
		return
	for tmpl in factions.factions:
		if tmpl == null:
			continue
		assert_not_null(sects.find_sect(tmpl.parent_sect_id),
			"authored faction '%s' names parent sect '%s', which must exist in the sect catalog"
				% [tmpl.id, tmpl.parent_sect_id])


## WORLD_BIBLE §8 / C-005: every authored group must hold a defensible position, and no sect
## may be authored as simply good or simply evil. For a faction landscape that means the sides
## must actually DIFFER in stance — three factions that all agree are not a disagreement.
func test_39_the_authored_landscape_is_a_real_disagreement() -> void:
	var cat := load(AUTHORED_CATALOG_PATH) as FactionCatalog
	assert_not_null(cat, "the authored catalog loads")
	if cat == null:
		return
	for sect_id in cat.parent_sect_ids():
		var of_sect := cat.factions_of_sect(sect_id)
		if of_sect.size() < 2:
			continue
		var stances := {}
		for tmpl in of_sect:
			stances[tmpl.stance] = true
			assert_ne(tmpl.doctrine_key, &"",
				"faction '%s' states its own position" % tmpl.id)
		assert_true(stances.size() >= 2,
			("sect '%s' has %d factions but only %d distinct stance(s): a landscape where "
				+ "everyone agrees is not an internal disagreement (C-005)")
				% [sect_id, of_sect.size(), stances.size()])


## The authored landscape must be reproducible: loading the shipped content twice and asking
## the same political questions must give identical answers. This is the end-to-end
## determinism assertion — it would fail the moment anything in this path reached for RNG,
## which Phase 07 must not do (the seeded seam belongs to Phase 08, D-040).
func test_40_the_authored_landscape_resolves_deterministically() -> void:
	var first := _authored_service()
	var second := _authored_service()
	if first == null or second == null:
		return
	for sect_id in first.get_store().sect_ids_sorted():
		var sid := StringName(sect_id)
		assert_eq(first.total_influence_of_sect(sid), second.total_influence_of_sect(sid),
			"the influence total is identical across two independent loads")
		assert_eq(first.is_contested(sid), second.is_contested(sid),
			"and so is the contested verdict")
		var a := first.dominant_faction_of(sid)
		var b := second.dominant_faction_of(sid)
		assert_eq(a != null, b != null, "both agree whether anyone holds sway")
		if a != null and b != null:
			assert_eq(a.id, b.id, "and on exactly who")
		for faction in first.get_store().factions_of_sect(sid):
			var fid := (faction as FactionState).id
			assert_eq(first.influence_share(fid), second.influence_share(fid),
				"every share is identical for '%s'" % fid)


## A service loaded from the SHIPPED content (no relationship mirror needed: these are pure
## arithmetic reads). Returns null if the content cannot be loaded, so the caller bails
## without reporting a misleading failure.
func _authored_service() -> FactionService:
	var cat := load(AUTHORED_CATALOG_PATH) as FactionCatalog
	if cat == null:
		return null
	var store: FactionStore = StoreScript.new()
	var svc: FactionService = ServiceScript.new(store)
	for tmpl in cat.factions:
		if tmpl == null:
			continue
		svc.register_faction(FactionState.create_from_template(tmpl), tmpl)
	return svc

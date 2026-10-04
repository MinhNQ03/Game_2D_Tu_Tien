extends TestCase
## Unit tests for the relationship graph (Phase 05 — matrix B–U): endpoints, edge create/
## reject, dimension defaults, delta mutation + clamp + zero no-op + unknown-dim reject,
## directed/symmetric queries, symmetric duplicate reject + reverse update, debt perspective,
## history append/capacity, deterministic event→delta, serialize round-trip + malformed
## reject + index rebuild, endpoint lookup, edge removal updates indexes.
##
## All subjects are RefCounted (store/service/edge/endpoint) or Resource (config); no Node is
## created, so there is nothing to free (L-019 N/A here, but the suite still ends clean).

const EndpointScript := preload("res://src/domain/relationship/relationship_endpoint.gd")
const StoreScript := preload("res://src/domain/relationship/relationship_store.gd")
const ServiceScript := preload("res://src/domain/relationship/relationship_service.gd")
const ConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")

const CONFIG_PATH := "res://data/relationship/relationship_config.tres"
const RULES_PATH := "res://data/relationship/relationship_rules.tres"


func _config() -> Resource:
	return load(CONFIG_PATH)


func _service(config: Resource = null) -> RefCounted:
	var cfg: Resource = config if config != null else _config()
	var store: RefCounted = StoreScript.new(cfg)
	return ServiceScript.new(store, cfg)


func _char(id: StringName) -> RefCounted:
	return EndpointScript.for_character(id)


func _sect(id: StringName) -> RefCounted:
	return EndpointScript.for_sect(id)


# T — endpoint typing + compare + serialize round-trip -----------------------
func test_endpoint_typing_and_serialization() -> void:
	var a := _char(&"player")
	var s := _sect(&"player")  # same raw id, different KIND — must not be equal
	assert_false(a.equals(s), "character 'player' != sect 'player' (kind distinguishes)")
	assert_eq(a.to_dict(), {"kind": "character", "id": "player"}, "endpoint serializes typed")
	var restored: RefCounted = EndpointScript.from_dict(a.to_dict())
	assert_true(restored.equals(a), "endpoint round-trips")
	assert_null(EndpointScript.from_dict({"kind": "bogus", "id": "x"}), "unknown kind rejected")
	assert_null(EndpointScript.from_dict({"kind": "character", "id": ""}), "empty id rejected")


# B/D — edge creation seeds config defaults; C — invalid endpoint rejected ----
func test_edge_creation_and_defaults() -> void:
	var svc := _service()
	var edge = svc.create_edge(&"e1", _char(&"a"), _char(&"b"), &"FRIEND")
	assert_not_null(edge, "edge created")
	assert_eq(svc.get_store().edge_count(), 1, "store holds one edge")
	assert_eq(edge.get_dimension(&"affinity"), 0, "affinity seeded to config default")
	assert_eq(edge.get_dimension(&"trust"), 0, "trust seeded to config default")
	# C: invalid endpoints / self-link / duplicate id are rejected (null).
	assert_null(svc.create_edge(&"e2", _char(&""), _char(&"b")), "empty endpoint id rejected")
	assert_null(svc.create_edge(&"e3", _char(&"a"), _char(&"a")), "self-link rejected")
	assert_null(svc.create_edge(&"e1", _char(&"c"), _char(&"d")), "duplicate edge id rejected")


# E/F/G/H — delta mutation, clamp, zero no-op, unknown dimension --------------
func test_delta_clamp_zero_and_unknown_dimension() -> void:
	var svc := _service()
	svc.create_edge(&"e1", _char(&"a"), _char(&"b"))
	# E: a real delta changes the value and returns true.
	assert_true(svc.apply_delta(&"e1", &"trust", 30), "trust +30 applied")
	assert_eq(svc.get_store().get_edge(&"e1").get_dimension(&"trust"), 30, "trust now 30")
	# F: clamp at the configured max (trust max 100).
	assert_true(svc.apply_delta(&"e1", &"trust", 999), "trust pushed past max")
	assert_eq(svc.get_store().get_edge(&"e1").get_dimension(&"trust"), 100, "trust clamped to 100")
	# G: a delta that can't move the value (already at the bound) is a no-op (returns false).
	assert_false(svc.apply_delta(&"e1", &"trust", 50), "already at max => no-op")
	assert_false(svc.apply_delta(&"e1", &"trust", 0), "zero delta => no-op")
	# H: unknown dimension is rejected (loud) — returns false, no silent create.
	assert_false(svc.apply_delta(&"e1", &"charisma", 10), "unknown dimension rejected")
	# missing edge is rejected (no implicit create).
	assert_false(svc.apply_delta(&"ghost", &"trust", 10), "unknown edge rejected")


# I — directed edge query (A->B exists, B->A does not) -----------------------
func test_directed_edge_query() -> void:
	var svc := _service()
	var store: RefCounted = svc.get_store()
	svc.create_edge(&"d1", _char(&"a"), _char(&"b"), &"RIVAL", false)
	assert_not_null(store.find_between(_char(&"a"), _char(&"b")), "A->B found")
	assert_null(store.find_between(_char(&"b"), _char(&"a"), false), "B->A not found (directed)")
	# A separate B->A directed edge may coexist.
	assert_not_null(svc.create_edge(&"d2", _char(&"b"), _char(&"a"), &"RIVAL", false),
		"opposite directed edge is a distinct edge")
	assert_eq(store.edge_count(), 2, "two distinct directed edges")


# J/K — symmetric query from either side; L — duplicate symmetric rejected ----
func test_symmetric_query_and_duplicate_reject() -> void:
	var svc := _service()
	var store: RefCounted = svc.get_store()
	var edge = svc.create_edge(&"s1", _char(&"b"), _char(&"a"), &"SWORN", true)
	assert_not_null(edge, "symmetric edge created")
	# Canonical order: 'a' < 'b', so from_ref must be 'a' regardless of create order.
	assert_eq(String(edge.from_ref.id), "a", "symmetric edge stored in canonical order")
	# J/K: queryable from both directions -> same edge.
	var ab = store.find_between(_char(&"a"), _char(&"b"))
	var ba = store.find_between(_char(&"b"), _char(&"a"))
	assert_true(ab != null and ba != null and ab.id == ba.id, "A-B and B-A resolve to one edge")
	# L: creating the reverse pair as another symmetric edge is a duplicate (rejected).
	assert_null(svc.create_edge(&"s2", _char(&"a"), _char(&"b"), &"SWORN", true),
		"duplicate symmetric pair rejected")


# L (update) — updating a symmetric edge from the B side hits the same single edge ----
func test_symmetric_reverse_update() -> void:
	var svc := _service()
	var store: RefCounted = svc.get_store()
	svc.create_edge(&"s1", _char(&"a"), _char(&"b"), &"SWORN", true)
	var edge_id: StringName = store.find_between(_char(&"b"), _char(&"a")).id
	assert_true(svc.apply_delta(edge_id, &"respect", 20), "update via the B-side edge id")
	assert_eq(store.find_between(_char(&"a"), _char(&"b")).get_dimension(&"respect"), 20,
		"the single shared edge reflects the update from either side")


# M — debt perspective: symmetric reverse query negates ONLY debt ------------
func test_debt_perspective_on_symmetric_edge() -> void:
	var svc := _service()
	var a := _char(&"a")
	var b := _char(&"b")
	var edge = svc.create_edge(&"s1", a, b, &"SWORN", true)  # canonical from = a
	svc.apply_delta(&"s1", &"debt", 30)      # +30 from a's perspective (b owes a 30)
	svc.apply_delta(&"s1", &"respect", 15)   # non-directional
	# a's perspective (canonical): debt as stored.
	assert_eq(svc.read_dimension_as(&"s1", a, &"debt"), 30, "a sees debt +30 (b owes a)")
	# b's perspective (reverse): debt negated.
	assert_eq(svc.read_dimension_as(&"s1", b, &"debt"), -30, "b sees debt -30 (b owes a)")
	# respect is NOT flipped by perspective.
	assert_eq(svc.read_dimension_as(&"s1", a, &"respect"), 15, "a sees respect 15")
	assert_eq(svc.read_dimension_as(&"s1", b, &"respect"), 15, "b sees respect 15 (not flipped)")
	assert_eq(edge.get_dimension(&"debt"), 30, "stored value is the canonical-from perspective")


# M (directed) — a directed edge is read as stored regardless of viewer -------
func test_debt_not_flipped_on_directed_edge() -> void:
	var svc := _service()
	var a := _char(&"a")
	var b := _char(&"b")
	svc.create_edge(&"d1", a, b, &"RIVAL", false)
	svc.apply_delta(&"d1", &"debt", -20)
	assert_eq(svc.read_dimension_as(&"d1", a, &"debt"), -20, "directed debt read as stored (from)")
	assert_eq(svc.read_dimension_as(&"d1", b, &"debt"), -20,
		"directed edge has one perspective; not flipped for 'to'")


# N/O — history appends on real change; capacity bounds it -------------------
func test_history_append_and_capacity() -> void:
	# `dimensions` is Array[Dictionary]: build the typed array explicitly rather than relying
	# on the compiler inferring the receiver's class well enough to type an array literal. An
	# untyped array here raises a GDScript VM error that ABORTS this method, which the runner
	# would record as a PASS (it only counts assertion failures) — see the D-037 follow-up.
	var dims: Array[Dictionary] = [{"id": &"trust", "default": 0, "min": 0, "max": 1000}]
	var cfg: RelationshipConfigData = ConfigScript.new()
	cfg.dimensions = dims
	cfg.history_capacity = 3
	assert_eq(cfg.dimensions.size(), 1, "the fixture config actually carries its dimension")
	assert_eq(cfg.history_capacity, 3, "the fixture config actually carries its capacity")
	var svc := _service(cfg)
	svc.create_edge(&"e1", _char(&"a"), _char(&"b"))
	for i in range(5):
		svc.apply_delta(&"e1", &"trust", 1, &"tick")
	var edge: RefCounted = svc.get_store().get_edge(&"e1")
	assert_eq(edge.history_size(), 3, "history bounded to capacity (3), oldest dropped")
	var hist: Array = edge.get_history_copy()
	# Newest-last; the last entry's new_value is the final value (5).
	assert_eq(int(hist[hist.size() - 1]["new_value"]), 5, "newest entry kept")
	assert_eq(int(hist[0]["new_value"]), 3, "oldest surviving entry is the 3rd change")
	# A no-op delta writes NO history.
	var before: int = edge.history_size()
	svc.apply_delta(&"e1", &"trust", 0)
	assert_eq(edge.history_size(), before, "zero delta writes no history")


# relationship_changed signal fires once per real change, with correct payload -
func test_change_signal_payload() -> void:
	var svc := _service()
	svc.create_edge(&"e1", _char(&"a"), _char(&"b"))
	var seen := {"n": 0, "old": -999, "new": -999, "dim": "", "cause": ""}
	svc.relationship_changed.connect(
		func(_eid: StringName, dim: StringName, old_v: int, new_v: int, cause: StringName) -> void:
			seen["n"] += 1
			seen["dim"] = String(dim)
			seen["old"] = old_v
			seen["new"] = new_v
			seen["cause"] = String(cause))
	svc.apply_delta(&"e1", &"affinity", 12, &"gift")
	assert_eq(seen["n"], 1, "one change signal")
	assert_eq(seen["dim"], "affinity", "dimension in payload")
	assert_eq(seen["old"], 0, "old value in payload")
	assert_eq(seen["new"], 12, "new value in payload")
	assert_eq(seen["cause"], "gift", "cause in payload")
	svc.apply_delta(&"e1", &"affinity", 0)  # no-op
	assert_eq(seen["n"], 1, "no signal for a no-op delta")


# P — deterministic event → delta (from the authored rule catalog) -----------
func test_event_delta_is_deterministic() -> void:
	var cfg := _config()
	var cat: Resource = load(RULES_PATH)
	assert_true(cat.is_valid(), "rule catalog valid: %s" % str(cat.validation_errors()))
	# Run the same event on two independent fresh graphs; results must be identical.
	var r1 := _apply_event_fresh(cfg, cat, &"HELPED_STRANGER")
	var r2 := _apply_event_fresh(cfg, cat, &"HELPED_STRANGER")
	assert_eq(r1, r2, "same event on same start state is deterministic")
	assert_eq(int(r1["affinity"]), 8, "HELPED_STRANGER affinity +8")
	assert_eq(int(r1["trust"]), 5, "HELPED_STRANGER trust +5")
	# An unknown event is rejected (no silent change).
	var svc := _service(cfg)
	svc.set_rules(cat.build_lookup())
	svc.create_edge(&"e1", _char(&"a"), _char(&"b"))
	assert_false(svc.apply_event(&"e1", &"NOT_A_REAL_EVENT"), "unknown event rejected")


func _apply_event_fresh(cfg: Resource, cat: Resource, event: StringName) -> Dictionary:
	var store: RefCounted = StoreScript.new(cfg)
	var svc: RefCounted = ServiceScript.new(store, cfg)
	svc.set_rules(cat.build_lookup())
	svc.create_edge(&"e1", _char(&"a"), _char(&"b"))
	svc.apply_event(&"e1", event)
	return store.get_edge(&"e1").get_dimensions_copy()


# Q/S — serialization round-trip + index rebuild -----------------------------
func test_serialization_round_trip_rebuilds_indexes() -> void:
	var cfg := _config()
	var svc := _service(cfg)
	svc.create_edge(&"e_sym", _char(&"a"), _char(&"b"), &"SWORN", true)
	svc.create_edge(&"e_dir", _char(&"a"), _sect(&"sect_x"), &"ALLY", false)
	svc.apply_delta(&"e_sym", &"respect", 40)
	svc.apply_delta(&"e_dir", &"debt", -25)
	var snapshot: Dictionary = svc.get_store().to_dict()

	# Hydrate a brand-new store from the snapshot.
	var store2: RefCounted = StoreScript.new(cfg)
	assert_true(store2.hydrate(snapshot), "hydrate accepts a well-formed snapshot")
	assert_eq(store2.edge_count(), 2, "both edges restored")
	# Index rebuilt: endpoint + between lookups work after hydrate.
	assert_not_null(store2.find_between(_char(&"b"), _char(&"a")), "symmetric lookup after hydrate")
	assert_eq(store2.get_edge(&"e_sym").get_dimension(&"respect"), 40, "dimension restored")
	assert_eq(store2.find_for_endpoint(_char(&"a")).size(), 2, "endpoint index rebuilt (a on both)")
	# Deterministic: re-serializing yields the identical snapshot.
	assert_eq(store2.to_dict(), snapshot, "re-serialization is byte-stable (deterministic)")


# R — malformed snapshot is rejected, store left unchanged (fail-closed) ------
func test_malformed_snapshot_rejected() -> void:
	var cfg := _config()
	var store: RefCounted = StoreScript.new(cfg)
	assert_false(store.hydrate("not a dict"), "non-dict payload rejected")
	assert_false(store.hydrate({"edges": "not an array"}), "non-array edges rejected")
	# duplicate edge id
	var dup := {"edges": [
		_edge_dict("e1", "a", "b"), _edge_dict("e1", "c", "d")]}
	assert_false(store.hydrate(dup), "duplicate edge id rejected")
	# unknown dimension
	var bad_dim := {"edges": [_edge_dict("e1", "a", "b", {"charisma": 5})]}
	assert_false(store.hydrate(bad_dim), "unknown dimension rejected")
	# out-of-range value
	var bad_range := {"edges": [_edge_dict("e1", "a", "b", {"trust": 9999})]}
	assert_false(store.hydrate(bad_range), "out-of-range dimension rejected")
	# malformed endpoint
	var bad_ep := {"edges": [{"id": "e1", "from": {"kind": "bogus", "id": "a"},
		"to": {"kind": "character", "id": "b"}, "dimensions": {}}]}
	assert_false(store.hydrate(bad_ep), "malformed endpoint rejected")
	assert_eq(store.edge_count(), 0, "store unchanged after every rejected hydrate")


func _edge_dict(eid: String, from_id: String, to_id: String,
		dims: Dictionary = {}) -> Dictionary:
	return {
		"id": eid,
		"from": {"kind": "character", "id": from_id},
		"to": {"kind": "character", "id": to_id},
		"relationship_type": "STRANGER",
		"symmetric": false,
		"known": false,
		"dimensions": dims,
		"history": [],
	}


# U — edge removal updates both indexes --------------------------------------
func test_edge_removal_updates_indexes() -> void:
	var svc := _service()
	var store: RefCounted = svc.get_store()
	svc.create_edge(&"e1", _char(&"a"), _char(&"b"))
	svc.create_edge(&"e2", _char(&"a"), _char(&"c"))
	assert_eq(store.find_for_endpoint(_char(&"a")).size(), 2, "a has two edges")
	assert_true(svc.remove_edge(&"e1"), "remove e1")
	assert_false(store.has_edge(&"e1"), "e1 gone from id index")
	assert_eq(store.find_for_endpoint(_char(&"a")).size(), 1, "a's endpoint index updated")
	assert_null(store.find_between(_char(&"a"), _char(&"b")), "between-lookup no longer finds e1")
	assert_false(svc.remove_edge(&"e1"), "removing a gone edge returns false")

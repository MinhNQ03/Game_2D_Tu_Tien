extends TestCase
## Unit tests for RelationshipConfigData (Phase 05 — matrix A: config validity).
## Pure Resource; no tree, no autoloads, no Node leaks (RefCounted/Resource auto-free).

const ConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"


func _dim(id: StringName, def: int, dmin: int, dmax: int) -> Dictionary:
	return {"id": id, "default": def, "min": dmin, "max": dmax}


## Build a config fixture.
##
## `dimensions` is `Array[Dictionary]`, so the value assigned to it MUST be a typed array:
## pushing a plain untyped `Array` (which is what the `dims` parameter is) at a typed property
## raises `Invalid assignment of property 'dimensions' with value of type 'Array'`. That is a
## GDScript VM error, which ABORTS the running function — so this helper used to return
## `null`, every caller then hit `Invalid call ... on a null value`, and the test method died
## before reaching a single assertion. The runner only counts recorded assertion failures, so
## all six tests built on this helper reported PASS while executing nothing (fixed in the
## D-037 follow-up; the headless gate now fails on any `SCRIPT ERROR:`).
##
## The receiver is also typed as `RelationshipConfigData` rather than `Resource` so the
## compiler can check the property statically instead of discovering it at runtime.
func _config(dims: Array, capacity: int = 8) -> RelationshipConfigData:
	var typed: Array[Dictionary] = []
	for spec in dims:
		typed.append(spec)
	var cfg: RelationshipConfigData = ConfigScript.new()
	cfg.dimensions = typed
	cfg.history_capacity = capacity
	return cfg


# A — authored config is valid + carries the six documented dimensions with the §2 ranges.
func test_authored_config_is_valid() -> void:
	var cfg := load(CONFIG_PATH) as RelationshipConfigData
	assert_not_null(cfg, "relationship_config.tres loads")
	assert_true(cfg.is_valid(), "authored config valid: %s" % str(cfg.validation_errors()))
	for dim in ["affinity", "trust", "respect", "fear", "rivalry", "debt"]:
		assert_true(cfg.has_dimension(StringName(dim)), "config has dimension '%s'" % dim)
	assert_eq(cfg.get_min(&"affinity"), -100, "affinity min")
	assert_eq(cfg.get_max(&"affinity"), 100, "affinity max")
	assert_eq(cfg.get_min(&"trust"), 0, "trust min")
	assert_eq(cfg.get_max(&"trust"), 100, "trust max")
	assert_eq(cfg.get_min(&"debt"), -100, "debt min (signed)")
	assert_eq(cfg.get_max(&"debt"), 100, "debt max")


## Each negative case below asserts the REPORTED REASON, not just "invalid". A config whose
## fixture silently failed to build has no dimensions at all, so it is "invalid" for the
## wrong reason — exactly how these tests used to look green while testing nothing. Pinning
## the reason makes that impossible: a broken fixture now reports "at least one dimension"
## instead of the invariant under test, and the assertion fails.
func test_empty_config_invalid() -> void:
	var cfg := _config([])
	assert_false(cfg.is_valid(), "no dimensions => invalid")
	assert_true(_reason(cfg).contains("at least one dimension"),
		"the reason is the missing dimensions: %s" % _reason(cfg))


func test_default_out_of_range_invalid() -> void:
	var cfg := _config([_dim(&"x", 50, 0, 10)])  # default 50 > max 10
	assert_eq(cfg.dimensions.size(), 1, "the fixture actually carries its dimension")
	assert_false(cfg.is_valid(), "default outside [min,max] => invalid")
	assert_true(_reason(cfg).contains("default 50 not in [0, 10]"),
		"the reason names the out-of-range default: %s" % _reason(cfg))


func test_min_greater_than_max_invalid() -> void:
	var cfg := _config([_dim(&"x", 5, 10, 0)])  # min 10 > max 0
	assert_eq(cfg.dimensions.size(), 1, "the fixture actually carries its dimension")
	assert_false(cfg.is_valid(), "min > max => invalid")
	assert_true(_reason(cfg).contains("min 10 > max 0"),
		"the reason names the inverted range: %s" % _reason(cfg))


func test_duplicate_dimension_id_invalid() -> void:
	var cfg := _config([_dim(&"x", 0, 0, 10), _dim(&"x", 0, 0, 10)])
	assert_eq(cfg.dimensions.size(), 2, "the fixture actually carries both dimensions")
	assert_false(cfg.is_valid(), "duplicate dimension id => invalid")
	assert_true(_reason(cfg).contains("duplicate dimension id 'x'"),
		"the reason names the duplicate id: %s" % _reason(cfg))


func test_negative_history_capacity_invalid() -> void:
	var cfg := _config([_dim(&"x", 0, 0, 10)], -1)
	assert_false(cfg.is_valid(), "negative history_capacity => invalid")
	assert_true(_reason(cfg).contains("history_capacity must be >= 0"),
		"the reason names the capacity: %s" % _reason(cfg))


func test_clamp_and_defaults_map() -> void:
	var cfg := _config([_dim(&"affinity", 0, -100, 100), _dim(&"trust", 0, 0, 100)])
	assert_eq(cfg.clamp_value(&"affinity", 150), 100, "clamps above max")
	assert_eq(cfg.clamp_value(&"affinity", -150), -100, "clamps below min")
	assert_eq(cfg.clamp_value(&"trust", -5), 0, "trust floored at 0")
	var defaults: Dictionary = cfg.defaults_map()
	assert_eq(int(defaults["affinity"]), 0, "defaults map seeds affinity")
	assert_true(defaults.has("trust"), "defaults map includes every dimension")


## All validation errors joined, for asserting WHICH invariant was reported.
func _reason(cfg: RelationshipConfigData) -> String:
	return " | ".join(cfg.validation_errors())

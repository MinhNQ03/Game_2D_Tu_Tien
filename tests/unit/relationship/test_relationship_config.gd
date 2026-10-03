extends TestCase
## Unit tests for RelationshipConfigData (Phase 05 — matrix A: config validity).
## Pure Resource; no tree, no autoloads, no Node leaks (RefCounted/Resource auto-free).

const ConfigScript := preload("res://src/data/relationship/relationship_config_data.gd")
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"


func _dim(id: StringName, def: int, dmin: int, dmax: int) -> Dictionary:
	return {"id": id, "default": def, "min": dmin, "max": dmax}


func _config(dims: Array, capacity: int = 8) -> Resource:
	var cfg: Resource = ConfigScript.new()
	cfg.dimensions = dims
	cfg.history_capacity = capacity
	return cfg


# A — authored config is valid + carries the six documented dimensions with the §2 ranges.
func test_authored_config_is_valid() -> void:
	var cfg: Resource = load(CONFIG_PATH)
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


func test_empty_config_invalid() -> void:
	var cfg := _config([])
	assert_false(cfg.is_valid(), "no dimensions => invalid")


func test_default_out_of_range_invalid() -> void:
	var cfg := _config([_dim(&"x", 50, 0, 10)])  # default 50 > max 10
	assert_false(cfg.is_valid(), "default outside [min,max] => invalid")


func test_min_greater_than_max_invalid() -> void:
	var cfg := _config([_dim(&"x", 5, 10, 0)])  # min 10 > max 0
	assert_false(cfg.is_valid(), "min > max => invalid")


func test_duplicate_dimension_id_invalid() -> void:
	var cfg := _config([_dim(&"x", 0, 0, 10), _dim(&"x", 0, 0, 10)])
	assert_false(cfg.is_valid(), "duplicate dimension id => invalid")


func test_negative_history_capacity_invalid() -> void:
	var cfg := _config([_dim(&"x", 0, 0, 10)], -1)
	assert_false(cfg.is_valid(), "negative history_capacity => invalid")


func test_clamp_and_defaults_map() -> void:
	var cfg := _config([_dim(&"affinity", 0, -100, 100), _dim(&"trust", 0, 0, 100)])
	assert_eq(cfg.clamp_value(&"affinity", 150), 100, "clamps above max")
	assert_eq(cfg.clamp_value(&"affinity", -150), -100, "clamps below min")
	assert_eq(cfg.clamp_value(&"trust", -5), 0, "trust floored at 0")
	var defaults: Dictionary = cfg.defaults_map()
	assert_eq(int(defaults["affinity"]), 0, "defaults map seeds affinity")
	assert_true(defaults.has("trust"), "defaults map includes every dimension")

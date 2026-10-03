extends TestCase
## Unit tests for MapData + MapExit + MapCatalog (src/data/maps/*). Fresh instances; no
## autoloads. Verifies the Phase-03 (reopen, D-022) map schema invariants and that the
## authored map `.tres` + catalog content is well-formed (content validation, TEST_PLAN).

const MapDataScript := preload("res://src/data/maps/map_data.gd")
const MapExitScript := preload("res://src/data/maps/map_exit.gd")
const MapCatalogScript := preload("res://src/data/maps/map_catalog.gd")
const HUB := "res://data/maps/map_hub.tres"
const FIELD := "res://data/maps/map_field.tres"
const CATALOG := "res://data/maps/map_catalog.tres"
const HUB_SCENE := "res://src/gameplay/maps/hub_map.tscn"


func _exit(id: StringName, to_id: StringName, entry: StringName) -> Resource:
	var e: Resource = MapExitScript.new()
	e.id = id
	e.to_map_id = to_id
	e.entry_point = entry
	return e


func _map(id: StringName, name_key: String, scene_key: String, scene_path: String,
		bounds: Rect2, default_spawn: StringName, exits: Array) -> Resource:
	var m: Resource = MapDataScript.new()
	m.id = id
	m.name_key = name_key
	m.scene_key = scene_key
	m.scene_path = scene_path
	m.bounds = bounds
	m.default_spawn_id = default_spawn
	m.exits.assign(exits)
	return m


func _valid_map(id: StringName, scene_key: String, exits: Array) -> Resource:
	return _map(id, "UI_X", scene_key, HUB_SCENE, Rect2(0, 0, 100, 100), &"spawn_default", exits)


# --- MapExit -----------------------------------------------------------------

func test_exit_valid_with_id_and_destination() -> void:
	assert_true(_exit(&"exit_a", &"map_field", &"from_hub").is_valid(), "well-formed exit valid")


func test_exit_invalid_without_id() -> void:
	assert_false(_exit(&"", &"map_field", &"x").is_valid(), "exit without id is invalid")


func test_exit_invalid_without_destination() -> void:
	assert_false(_exit(&"exit_a", &"", &"x").is_valid(), "exit without to_map_id is invalid")


# --- MapData -----------------------------------------------------------------

func test_valid_map_passes() -> void:
	var m := _valid_map(&"map_hub", "map_hub", [_exit(&"e1", &"map_field", &"from_hub")])
	assert_true(m.is_valid(), "well-formed map valid: %s" % str(m.validation_errors()))


func test_missing_scene_path_invalid() -> void:
	var m := _map(&"map_x", "UI_X", "x", "", Rect2(0, 0, 10, 10), &"spawn_default", [])
	assert_false(m.is_valid(), "empty scene_path invalid")


func test_nonexistent_scene_path_invalid() -> void:
	var m := _map(&"map_x", "UI_X", "x", "res://does/not/exist.tscn",
		Rect2(0, 0, 10, 10), &"spawn_default", [])
	assert_false(m.is_valid(), "nonexistent scene_path invalid")


func test_zero_bounds_invalid() -> void:
	var m := _map(&"map_x", "UI_X", "x", HUB_SCENE, Rect2(0, 0, 0, 0), &"spawn_default", [])
	assert_false(m.is_valid(), "zero-size bounds invalid")


func test_missing_default_spawn_invalid() -> void:
	var m := _map(&"map_x", "UI_X", "x", HUB_SCENE, Rect2(0, 0, 10, 10), &"", [])
	assert_false(m.is_valid(), "empty default_spawn_id invalid")


func test_duplicate_exit_id_invalid() -> void:
	var m := _valid_map(&"map_x", "x", [
		_exit(&"dup", &"map_a", &"s"), _exit(&"dup", &"map_b", &"s")])
	assert_false(m.is_valid(), "duplicate exit id invalid")


func test_find_exit_by_id() -> void:
	var m := _valid_map(&"map_hub", "x", [_exit(&"exit_to_field", &"map_field", &"from_hub")])
	var found: Resource = m.find_exit(&"exit_to_field")
	assert_not_null(found, "finds exit by id")
	assert_eq(found.to_map_id, &"map_field", "resolves the right destination")
	assert_null(m.find_exit(&"nope"), "no exit for an unknown id")


# --- MapCatalog --------------------------------------------------------------

func test_catalog_valid() -> void:
	var hub := _valid_map(&"map_hub", "map_hub", [_exit(&"e", &"map_field", &"from_hub")])
	var field := _valid_map(&"map_field", "map_field", [_exit(&"e", &"map_hub", &"from_field")])
	var cat: Resource = MapCatalogScript.new()
	cat.maps.assign([hub, field])
	assert_true(cat.is_valid(), "catalog valid: %s" % str(cat.validation_errors()))


func test_catalog_duplicate_map_id_invalid() -> void:
	var a := _valid_map(&"map_dup", "sk_a", [])
	var b := _valid_map(&"map_dup", "sk_b", [])
	var cat: Resource = MapCatalogScript.new()
	cat.maps.assign([a, b])
	assert_false(cat.is_valid(), "duplicate map id invalid")


func test_catalog_duplicate_scene_key_invalid() -> void:
	var a := _valid_map(&"map_a", "dup_key", [])
	var b := _valid_map(&"map_b", "dup_key", [])
	var cat: Resource = MapCatalogScript.new()
	cat.maps.assign([a, b])
	assert_false(cat.is_valid(), "duplicate scene_key invalid")


func test_catalog_dangling_exit_invalid() -> void:
	# An exit targeting a map not present in the catalog is a dangling edge.
	var a := _valid_map(&"map_a", "sk_a", [_exit(&"e", &"map_ghost", &"s")])
	var cat: Resource = MapCatalogScript.new()
	cat.maps.assign([a])
	assert_false(cat.is_valid(), "exit to a map not in the catalog is invalid")


func test_catalog_build_lookup() -> void:
	var a := _valid_map(&"map_a", "sk_a", [])
	var b := _valid_map(&"map_b", "sk_b", [])
	var cat: Resource = MapCatalogScript.new()
	cat.maps.assign([a, b])
	var lookup: Dictionary = cat.build_lookup()
	assert_eq(lookup.size(), 2, "lookup has both maps")
	assert_true(lookup.has(&"map_a") and lookup.has(&"map_b"), "lookup keyed by map id")


# --- Authored content is well-formed + the graph is consistent ---------------

func test_authored_maps_valid() -> void:
	var hub: Resource = load(HUB)
	var field: Resource = load(FIELD)
	assert_not_null(hub, "map_hub.tres loads")
	assert_not_null(field, "map_field.tres loads")
	if hub != null:
		assert_true(hub.is_valid(), "hub content valid: %s" % str(hub.validation_errors()))
	if field != null:
		assert_true(field.is_valid(), "field content valid: %s" % str(field.validation_errors()))


func test_authored_catalog_valid_and_bidirectional() -> void:
	var cat: Resource = load(CATALOG)
	assert_not_null(cat, "map_catalog.tres loads")
	if cat == null:
		return
	assert_true(cat.is_valid(), "authored catalog valid: %s" % str(cat.validation_errors()))
	var lookup: Dictionary = cat.build_lookup()
	assert_true(lookup.has(&"map_hub") and lookup.has(&"map_field"), "catalog has both maps")
	var hub: Resource = lookup.get(&"map_hub")
	var field: Resource = lookup.get(&"map_field")
	assert_not_null(hub.find_exit_to(&"map_field"), "hub exits to the field")
	assert_not_null(field.find_exit_to(&"map_hub"), "field exits back to the hub")

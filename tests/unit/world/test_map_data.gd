extends TestCase
## Unit tests for MapData + MapExit (src/data/maps/*). Fresh instances; no autoloads.
## Verifies the Phase-03 map schema invariants and that the authored map `.tres` content is
## well-formed (content validation, `docs/TEST_PLAN.md`).

const MapDataScript := preload("res://src/data/maps/map_data.gd")
const MapExitScript := preload("res://src/data/maps/map_exit.gd")
const HUB := "res://data/maps/map_hub.tres"
const FIELD := "res://data/maps/map_field.tres"


func _exit(to_id: StringName, entry: StringName) -> Resource:
	var e: Resource = MapExitScript.new()
	e.to_map_id = to_id
	e.entry_point = entry
	return e


func _map(id: StringName, name_key: String, scene_key: String, exits: Array) -> Resource:
	var m: Resource = MapDataScript.new()
	m.id = id
	m.name_key = name_key
	m.scene_key = scene_key
	m.exits.assign(exits)
	return m


# --- MapExit -----------------------------------------------------------------

func test_exit_valid_with_destination() -> void:
	assert_true(_exit(&"map_field", &"from_hub").is_valid(), "exit with to_map_id is valid")


func test_exit_invalid_without_destination() -> void:
	var e := _exit(&"", &"x")
	assert_false(e.is_valid(), "exit without to_map_id is invalid")
	assert_false(e.validation_errors().is_empty(), "reports an error")


# --- MapData -----------------------------------------------------------------

func test_valid_map_passes() -> void:
	var m := _map(&"map_hub", "UI_MAP_HUB_NAME", "map_hub", [_exit(&"map_field", &"from_hub")])
	assert_true(m.is_valid(), "well-formed map valid: %s" % str(m.validation_errors()))


func test_missing_id_invalid() -> void:
	assert_false(_map(&"", "UI_X", "x", []).is_valid(), "empty id invalid")


func test_missing_name_key_invalid() -> void:
	assert_false(_map(&"map_x", "", "x", []).is_valid(), "empty name_key invalid")


func test_missing_scene_key_invalid() -> void:
	assert_false(_map(&"map_x", "UI_X", "", []).is_valid(), "empty scene_key invalid")


func test_invalid_exit_makes_map_invalid() -> void:
	var m := _map(&"map_x", "UI_X", "x", [_exit(&"", &"")])
	assert_false(m.is_valid(), "a map with an invalid exit is invalid")


func test_find_exit_to() -> void:
	var m := _map(&"map_hub", "UI_X", "x", [_exit(&"map_field", &"from_hub")])
	var found: Resource = m.find_exit_to(&"map_field")
	assert_not_null(found, "finds the exit to map_field")
	assert_eq(found.entry_point, &"from_hub", "returns the right exit")
	assert_null(m.find_exit_to(&"map_nope"), "no exit to an unknown map")


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


func test_authored_map_graph_is_bidirectional() -> void:
	# The hub exits to the field, and the field exits back to the hub — a reachable round
	# trip (the Phase-03 exit criterion needs ≥2 maps you can move between repeatedly).
	var hub: Resource = load(HUB)
	var field: Resource = load(FIELD)
	if hub == null or field == null:
		assert_true(false, "authored maps must load")
		return
	assert_not_null(hub.find_exit_to(&"map_field"), "hub has an exit to the field")
	assert_not_null(field.find_exit_to(&"map_hub"), "field has an exit back to the hub")

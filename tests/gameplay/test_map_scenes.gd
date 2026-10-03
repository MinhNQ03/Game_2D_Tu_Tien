extends TestCase
## Gameplay smoke test: the hub + field map scenes are STRUCTURALLY sound.
##
## STRUCTURAL ONLY (D-019): we instantiate each map scene but do NOT add it to the tree,
## because MapBase._ready() calls InputService.set_gameplay_context() — a shared /root
## autoload mutation that must not happen inside the common runner (L-010). The scene
## actually running (input context, player placement, semantic interact, real transition)
## is verified in the dedicated isolated E2E process (tests/e2e/run_world_flow.gd). Here we
## only confirm each map is wired with the pieces MapBase + WorldRuntime depend on, then
## free the detached instance (no orphan, no autoload mutation).

const HubScene := preload("res://src/gameplay/maps/hub_map.tscn")
const FieldScene := preload("res://src/gameplay/maps/field_map.tscn")


func _assert_map_structure(scene: PackedScene, expected_name_key: String, expected_exit_to: StringName) -> void:
	var map: Node = scene.instantiate()  # NOT added to the tree
	assert_not_null(map, "map instantiates")
	if map == null:
		return

	assert_true(map is MapBase, "map root is a MapBase")

	# Player host: where WorldRuntime parents the persistent player.
	assert_not_null(map.get_node_or_null("PlayerHost"), "map has a PlayerHost")

	# Spawns: a default + at least one named entry point.
	var spawns := map.get_node_or_null("Spawns")
	assert_not_null(spawns, "map has a Spawns container")
	if spawns != null:
		assert_not_null(spawns.get_node_or_null("spawn_default"), "map has a default spawn marker")
		assert_true(spawns.get_child_count() >= 2, "map has a default + named spawn")

	# Exits: at least one MapExitZone that targets the expected neighbour.
	var exits := map.get_node_or_null("Exits")
	assert_not_null(exits, "map has an Exits container")
	var found_exit := false
	if exits != null:
		for zone in exits.get_children():
			if zone is MapExitZone and (zone as MapExitZone).to_map_id == expected_exit_to:
				found_exit = true
	assert_true(found_exit, "map has an exit zone to %s" % expected_exit_to)

	# Boundary walls so the player can't leave the arena.
	var walls := map.get_node_or_null("Walls")
	assert_not_null(walls, "map has a Walls container")
	if walls != null:
		assert_true(walls.get_child_count() >= 4, "arena has boundary walls on all sides")

	# Camera + localized HUD label (presentation only).
	assert_not_null(map.get_node_or_null("Camera2D"), "map has a Camera2D")
	assert_not_null(map.get_node_or_null("HUD/MapLabel"), "map has a HUD/MapLabel")

	# Name key is a localization key, never a literal (07-localization).
	assert_eq(map.map_name_key, expected_name_key, "map exposes its localization name key")

	# The scene-agnostic first-scene return contract Main/WorldRuntime wires to.
	assert_true(map.has_signal("return_to_menu_requested"),
		"map exposes return_to_menu_requested (first-scene contract)")
	assert_true(map.has_signal("exit_requested"),
		"map exposes exit_requested (map-transition intent)")

	map.free()


func test_hub_map_structure() -> void:
	_assert_map_structure(HubScene, "UI_MAP_HUB_NAME", &"map_field")


func test_field_map_structure() -> void:
	_assert_map_structure(FieldScene, "UI_MAP_FIELD_NAME", &"map_hub")

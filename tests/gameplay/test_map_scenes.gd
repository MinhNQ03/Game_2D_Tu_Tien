extends TestCase
## Gameplay structural test: the hub + field map scenes match their authoritative MapData
## (D-022). STRUCTURAL ONLY (D-019): we instantiate each map scene but do NOT add it to the
## tree, because MapBase._ready() calls InputService.set_gameplay_context() — a shared /root
## autoload mutation that must not happen inside the common runner (L-010). The scene
## actually running (input context, player placement, real transition) is verified in the
## dedicated isolated E2E process (tests/e2e/run_world_flow.gd).
##
## This test is the SOURCE-OF-TRUTH consistency guard between MapData and the scene:
##   - every MapExitZone's `exit_id` resolves to a `MapExit` in the map's MapData,
##   - every spawn referenced by MapData (default + each exit's entry_point for THIS map's
##     neighbours' arrival) exists as a Marker2D in the scene,
##   - the required node structure is present,
##   - the scene renders via the prototype tileset (not a bare Polygon2D floor).

const HubScene := preload("res://src/gameplay/maps/hub_map.tscn")
const FieldScene := preload("res://src/gameplay/maps/field_map.tscn")
const HUB_DATA := "res://data/maps/map_hub.tres"
const FIELD_DATA := "res://data/maps/map_field.tres"


func _assert_map_structure(scene: PackedScene, data_path: String) -> void:
	var map: Node = scene.instantiate()  # NOT added to the tree
	assert_not_null(map, "map instantiates")
	if map == null:
		return
	var data: MapData = load(data_path) as MapData
	assert_not_null(data, "MapData loads: %s" % data_path)

	assert_true(map is MapBase, "map root is a MapBase")

	# Required structure.
	assert_not_null(map.get_node_or_null("PlayerHost"), "map has a PlayerHost")
	assert_not_null(map.get_node_or_null("Camera2D"), "map has a Camera2D")
	assert_not_null(map.get_node_or_null("HUD/MapLabel"), "map has a HUD/MapLabel")

	# Visual root renders via the prototype TileMapLayer (not a Polygon2D-only floor).
	var ground := map.get_node_or_null("Visual/Ground")
	assert_not_null(ground, "map has a Visual/Ground tile layer")
	assert_true(ground is TileMapLayer, "ground is a TileMapLayer (texture-based, not Polygon2D)")
	if ground is TileMapLayer:
		assert_not_null((ground as TileMapLayer).tile_set, "ground has a TileSet assigned")
		# D-029: pixel-art tiles render nearest-filtered (no blur) like the rest of the world.
		assert_eq((ground as TileMapLayer).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"ground TileMapLayer is nearest-filtered (pixel art)")

	# Boundary walls (static collision) under Collision/Walls.
	var walls := map.get_node_or_null("Collision/Walls")
	assert_not_null(walls, "map has a Collision/Walls container")
	if walls != null:
		assert_true(walls.get_child_count() >= 4, "arena has boundary walls on all sides")

	# Spawns: the MapData default_spawn_id MUST exist as a marker in the scene.
	var spawns := map.get_node_or_null("Spawns")
	assert_not_null(spawns, "map has a Spawns container")
	if spawns != null and data != null:
		assert_not_null(spawns.get_node_or_null(String(data.default_spawn_id)),
			"default_spawn_id '%s' exists in the scene" % data.default_spawn_id)

	# Every exit zone's exit_id MUST resolve to a MapExit in the MapData (no drift, D-022).
	var exits := map.get_node_or_null("Exits")
	assert_not_null(exits, "map has an Exits container")
	var zone_count := 0
	if exits != null and data != null:
		for zone in exits.get_children():
			if zone is MapExitZone:
				zone_count += 1
				var ez := zone as MapExitZone
				assert_not_null(data.find_exit(ez.exit_id),
					"exit zone '%s' exit_id '%s' resolves in MapData" % [ez.name, ez.exit_id])
	assert_true(zone_count >= 1, "map has at least one exit zone")

	# The scene-agnostic signals Main/WorldRuntime wire to.
	assert_true(map.has_signal("return_to_menu_requested"), "map exposes return_to_menu_requested")
	assert_true(map.has_signal("exit_requested"), "map exposes exit_requested")

	# MapBase exposes the data-binding API WorldRuntime calls.
	assert_true(map.has_method("apply_map_data"), "map exposes apply_map_data")
	assert_true(map.has_method("get_spawn_position"), "map exposes get_spawn_position")

	map.free()


## Cross-map: each map's exit entry_point must exist as a spawn marker in the DESTINATION
## map's scene (so arrival from an exit always lands on a real marker — spawn contract).
func test_exit_entry_points_exist_in_destination_scenes() -> void:
	var hub_data: MapData = load(HUB_DATA) as MapData
	var field_data: MapData = load(FIELD_DATA) as MapData
	var hub: Node = HubScene.instantiate()
	var field: Node = FieldScene.instantiate()
	_assert_entry_points_land(hub_data, {"map_hub": hub, "map_field": field})
	_assert_entry_points_land(field_data, {"map_hub": hub, "map_field": field})
	hub.free()
	field.free()


func _assert_entry_points_land(data: MapData, scenes: Dictionary) -> void:
	if data == null:
		return
	for map_exit in data.exits:
		if map_exit == null or map_exit.entry_point == &"":
			continue
		var dest: Node = scenes.get(String(map_exit.to_map_id))
		assert_not_null(dest, "destination scene for '%s' available" % map_exit.to_map_id)
		if dest != null:
			var spawns := dest.get_node_or_null("Spawns")
			assert_not_null(spawns, "destination '%s' has Spawns" % map_exit.to_map_id)
			if spawns != null:
				assert_not_null(spawns.get_node_or_null(String(map_exit.entry_point)),
					"exit '%s' entry_point '%s' exists in map '%s'" % [
						map_exit.id, map_exit.entry_point, map_exit.to_map_id])


func test_hub_map_structure() -> void:
	_assert_map_structure(HubScene, HUB_DATA)


func test_field_map_structure() -> void:
	_assert_map_structure(FieldScene, FIELD_DATA)


# --- D-029 decorative-prop visual contract (production-foundation art) --------
# Each map renders presentation-only garden props under Visual/Decor. They must be nearest-
# filtered Sprite2D with a real texture of the authored pixel dimensions — a decoration that
# fails to load (null/wrong-size texture) is a visual regression even though it never touches
# gameplay. STRUCTURAL ONLY (not added to the tree, like the structure test above).
const EXPECTED_PROP_SIZES := {
	"res://assets/sprites/props/prop_lantern.png": Vector2i(16, 24),
	"res://assets/sprites/props/prop_tree.png": Vector2i(32, 32),
	"res://assets/sprites/props/prop_rock.png": Vector2i(16, 16),
	"res://assets/sprites/props/prop_planter.png": Vector2i(16, 16),
}


func _assert_decor_contract(scene: PackedScene, label: String) -> void:
	var map: Node = scene.instantiate()  # NOT added to the tree
	assert_not_null(map, "%s instantiates" % label)
	if map == null:
		return
	# Ground must still be the FIRST child of Visual (node-path lookups depend on it).
	var visual := map.get_node_or_null("Visual")
	assert_not_null(visual, "%s has a Visual root" % label)
	if visual != null and visual.get_child_count() > 0:
		assert_eq(visual.get_child(0).name, StringName("Ground"),
			"%s: Visual/Ground is still the first child" % label)
	var decor := map.get_node_or_null("Visual/Decor")
	assert_not_null(decor, "%s has a Visual/Decor container" % label)
	if decor == null:
		map.free()
		return
	var sprites := 0
	for child in decor.get_children():
		if not (child is Sprite2D):
			continue
		sprites += 1
		var sprite := child as Sprite2D
		assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"%s decor '%s' is nearest-filtered (pixel art, no blur)" % [label, sprite.name])
		assert_not_null(sprite.texture, "%s decor '%s' has a texture" % [label, sprite.name])
		if sprite.texture == null:
			continue
		var tex_path := sprite.texture.resource_path
		assert_true(EXPECTED_PROP_SIZES.has(tex_path),
			"%s decor '%s' uses a known prop texture (%s)" % [label, sprite.name, tex_path])
		if EXPECTED_PROP_SIZES.has(tex_path):
			var want: Vector2i = EXPECTED_PROP_SIZES[tex_path]
			var got := Vector2i(sprite.texture.get_width(), sprite.texture.get_height())
			assert_eq(got, want,
				"%s decor '%s' texture is authored size %s" % [label, sprite.name, str(want)])
	assert_true(sprites >= 1, "%s has at least one decorative prop sprite" % label)
	map.free()


func test_hub_decor_contract() -> void:
	_assert_decor_contract(HubScene, "hub")


func test_field_decor_contract() -> void:
	_assert_decor_contract(FieldScene, "field")

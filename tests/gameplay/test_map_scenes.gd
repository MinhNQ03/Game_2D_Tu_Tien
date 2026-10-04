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

## Base tile size (`06-art-assets.md`). Used to convert the scene's tile-coordinate
## `fill_rect` into world units so it can be compared with `MapData.bounds`.
const TILE_PX := 16


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

	# SOURCE-OF-TRUTH GUARD (D-036): `MapData.bounds` drives the camera limits and the camera
	# zoom, while the painted floor lives in the SCENE as `fill_rect` (tile coords). If the
	# two drift, the camera is clamped to the wrong rectangle — either letting the view run
	# off the painted floor, or over-zooming to "cover" a map larger than what exists. They
	# are authored by hand in different files, so they are checked against each other here.
	if ground is TileMapLayer and data != null:
		var cells: Rect2i = (ground as TileMapLayer).fill_rect
		var painted := Rect2(
			Vector2(cells.position) * TILE_PX, Vector2(cells.size) * TILE_PX)
		assert_eq(data.bounds, painted,
			"MapData.bounds %s matches the painted floor %s (fill_rect %s x %dpx tiles)"
			% [str(data.bounds), str(painted), str(cells), TILE_PX])

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
	# Phase 06: a sect banner (emblem) is a valid Visual/Decor decoration too.
	"res://assets/sprites/sects/emblem_azure_cloud.png": Vector2i(16, 16),
	"res://assets/sprites/sects/emblem_crimson_flame.png": Vector2i(16, 16),
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


# --- D-045 East Asian tileset floor ------------------------------------------

## The autotile mask table must be COMPLETE and UNAMBIGUOUS.
##
## `_paint_stone` looks the computed neighbour mask up in `AUTOTILE_BY_MASK` with
## `.get(mask, AUTOTILE_BY_MASK[0])` — so a MISSING key does not error, it silently falls back
## to the `single` tile and paints a visibly wrong edge. That is invisible to the compiler, to
## the linter and to CI, and it cannot be eyeballed here (Godot is not runnable locally,
## D-009). So the table's completeness is asserted directly: all 16 combinations of the four
## cardinal bits must be present, and no two may point at the same atlas cell.
func test_autotile_mask_table_is_complete_and_unambiguous() -> void:
	var table: Dictionary = PrototypeGround.AUTOTILE_BY_MASK
	assert_eq(table.size(), 16,
		"all 16 cardinal neighbour combinations are mapped (got %d)" % table.size())

	var bits := [
		PrototypeGround.MASK_N, PrototypeGround.MASK_E,
		PrototypeGround.MASK_S, PrototypeGround.MASK_W,
	]
	# Every subset of the four bits must have an entry — that is what "complete" means here.
	for combination in 16:
		var mask := 0
		for i in 4:
			if combination & (1 << i) != 0:
				mask |= int(bits[i])
		assert_true(table.has(mask),
			"mask %d is mapped (missing keys fall back to 'single' and paint a wrong edge)"
				% mask)

	# Distinct coordinates: two masks sharing a cell would mean one of them is wrong, since
	# each mask describes a different edge shape.
	var seen := {}
	var keys: Array = table.keys()
	keys.sort()
	for mask in keys:
		var coord: Vector2i = table[mask]
		var key := "%d,%d" % [coord.x, coord.y]
		assert_false(seen.has(key),
			"mask %s has its own atlas cell (%s collides with mask %s)"
				% [str(mask), key, str(seen.get(key))])
		seen[key] = mask
		# And it must sit inside the 12x4 sheet the pack ships.
		assert_true(coord.x >= 0 and coord.x < 12 and coord.y >= 0 and coord.y < 4,
			"mask %s maps inside the 12x4 autotile sheet (got %s)" % [str(mask), str(coord)])


## The cardinal bits must be distinct powers of two, or two different neighbour patterns
## would compute the same mask and the table lookup above would be meaningless.
func test_cardinal_mask_bits_are_independent() -> void:
	var bits := [
		PrototypeGround.MASK_N, PrototypeGround.MASK_E,
		PrototypeGround.MASK_S, PrototypeGround.MASK_W,
	]
	var combined := 0
	for bit in bits:
		assert_true(int(bit) > 0, "each cardinal bit is positive")
		assert_eq(int(bit) & (int(bit) - 1), 0, "bit %s is a power of two" % str(bit))
		assert_eq(combined & int(bit), 0, "bit %s does not overlap another" % str(bit))
		combined |= int(bit)


## Tile variety must be DETERMINISTIC (D-040 — no RNG before Phase 08's seeded seam), in
## range, and not degenerate.
##
## "Deterministic" is the load-bearing property: with `randi()` the map would paint
## differently every run, so a screenshot, a save and a reloaded save would disagree about the
## world. Asserting the same cell twice is what proves no RNG crept in.
func test_ground_variant_is_deterministic_and_in_range() -> void:
	var cells := [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-7, 13),
		Vector2i(31, 29), Vector2i(-40, -40), Vector2i(1000, 997),
	]
	for count in [1, 4, 8]:
		for cell in cells:
			var first := PrototypeGround.variant_for_cell(cell, count)
			assert_true(first >= 0 and first < count,
				"variant for %s is in [0,%d) (got %d)" % [str(cell), count, first])
			# Called again it MUST agree — this is the no-RNG assertion.
			for _repeat in 3:
				assert_eq(PrototypeGround.variant_for_cell(cell, count), first,
					"variant for %s is stable across calls (no RNG)" % str(cell))
	# A single-variant material must not divide by anything or wander.
	assert_eq(PrototypeGround.variant_for_cell(Vector2i(5, 9), 1), 0,
		"a one-variant material always resolves to index 0")

	# And it must actually VARY: a hash that returns a constant would reintroduce the flat
	# single-tile floor this replaced, while still passing every assertion above.
	var produced := {}
	for y in 8:
		for x in 8:
			produced[PrototypeGround.variant_for_cell(Vector2i(x, y), 4)] = true
	assert_eq(produced.size(), 4,
		"all 4 variants appear across an 8x8 patch (got %d) — a constant hash would mean a "
			% produced.size() + "flat one-tile floor again")


## Neighbouring cells must not land on the same variant too often, or the "variety" is a
## pattern. A plain `(x + y) % count` passes the tests above and still produces visible
## diagonal stripes, which is exactly why the hash multiplies x and y by different odd primes.
func test_ground_variants_do_not_form_diagonal_stripes() -> void:
	var diagonal_matches := 0
	var samples := 0
	for y in 16:
		for x in 16:
			samples += 1
			var here := PrototypeGround.variant_for_cell(Vector2i(x, y), 4)
			var down_right := PrototypeGround.variant_for_cell(Vector2i(x + 1, y + 1), 4)
			if here == down_right:
				diagonal_matches += 1
	# With 4 variants, chance agreement is ~25%. A `(x+y)%4` hash would score 0% on this
	# particular diagonal and 100% on the anti-diagonal, so a wide band around chance is the
	# honest assertion — it catches a degenerate pattern without pretending to test randomness
	# quality, which a deterministic hash does not owe us.
	var ratio := float(diagonal_matches) / float(samples)
	assert_true(ratio > 0.05 and ratio < 0.60,
		"diagonal neighbours agree %.0f%% of the time — near chance, not a stripe pattern"
			% (ratio * 100.0))


## The shipped TileSet must carry BOTH atlas sources the painter addresses by id, at the
## project's 16px cell. The painter calls `set_cell(..., SOURCE_GROUND/SOURCE_AUTOTILE, ...)`
## with bare ints, so a TileSet missing a source paints nothing at all — silently.
func test_east_asian_tileset_has_both_sources_at_16px() -> void:
	# Loaded by path rather than read off a map scene, so the resource stays checked even if a
	# map is later repointed at a different tileset.
	var tileset := load("res://data/maps/east_asian_tileset.tres") as TileSet
	assert_not_null(tileset, "the East Asian TileSet loads")
	if tileset == null:
		return
	assert_eq(tileset.tile_size, Vector2i(TILE_PX, TILE_PX),
		"the TileSet cell matches the project's %dpx world grid" % TILE_PX)
	for source_id in [PrototypeGround.SOURCE_GROUND, PrototypeGround.SOURCE_AUTOTILE]:
		assert_true(tileset.has_source(int(source_id)),
			"source id %s exists (the painter addresses it by that bare int)" % str(source_id))

	# The ground sheet must expose the 8 fills the painter indexes (4 moss + 4 stone), or a
	# variant lookup would address an undeclared tile and paint nothing.
	var ground_source := tileset.get_source(
		int(PrototypeGround.SOURCE_GROUND)) as TileSetAtlasSource
	assert_not_null(ground_source, "the ground source is an atlas source")
	if ground_source == null:
		return
	var needed := PrototypeGround.KOKE_COLUMNS + PrototypeGround.TA_COLUMNS
	for column in needed:
		assert_true(ground_source.has_tile(Vector2i(column, 0)),
			"ground tile %d:0 is declared (4 moss + 4 stone fills)" % column)

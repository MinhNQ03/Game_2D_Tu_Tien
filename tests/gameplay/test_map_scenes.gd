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

## Clearance a solid combat target must leave around a spawn→exit walking line, in pixels.
## Two tiles: wide enough that a 32px-wide character walking the line does not clip the
## target's 28px collision box, with a tile of margin so it does not merely *barely* pass.
const MIN_PATH_CLEARANCE_PX := 32


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

	# The floor is TEXTURE art: a tiled TileMapLayer, or (D-062) the painted floor drawn from the
	# map's layout data — never a Polygon2D-only floor.
	var ground := map.get_node_or_null("Visual/Ground")
	assert_not_null(ground, "map has a Visual/Ground floor")
	assert_true(ground is TileMapLayer or ground is PaintedGround,
		"ground is a TileMapLayer or a PaintedGround (texture-based, not Polygon2D)")
	if ground is TileMapLayer:
		assert_not_null((ground as TileMapLayer).tile_set, "ground has a TileSet assigned")
	if ground is PaintedGround:
		var layout := (ground as PaintedGround).layout
		assert_not_null(layout, "the painted floor has its layout data")
		if layout != null:
			assert_eq(" | ".join(layout.validation_errors()), "",
				"the painted floor's layout is complete")
	if ground is CanvasItem:
		# D-029: pixel art renders nearest-filtered (no blur) like the rest of the world.
		assert_eq((ground as CanvasItem).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"the floor is nearest-filtered (pixel art)")

	# SOURCE-OF-TRUTH GUARD (D-036): `MapData.bounds` drives the camera limits and the camera
	# zoom, while the painted floor lives in the SCENE as `fill_rect` (tile coords). If the
	# two drift, the camera is clamped to the wrong rectangle — either letting the view run
	# off the painted floor, or over-zooming to "cover" a map larger than what exists. They
	# are authored by hand in different files, so they are checked against each other here.
	if ground != null and data != null:
		var cells: Rect2i = ground.get("fill_rect")
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
#
# D-057B replaced the 32x32 tree and the 16x24 lantern with props that MOVE (a broadleaf tree
# padded for its sway, a lantern post whose paper lantern hangs and swings, a banner pole whose
# cloth waves, grass tufts), and retired the 2x-scaled emblem that stood in for a banner — a
# 16px emblem at scale 2 showed pixels twice the size of every pixel around it.
const EXPECTED_PROP_SIZES := {
	"res://assets/sprites/props/prop_tree_broadleaf.png": Vector2i(40, 44),
	"res://assets/sprites/props/prop_lantern_post.png": Vector2i(20, 48),
	"res://assets/sprites/props/prop_banner_pole.png": Vector2i(16, 48),
	"res://assets/sprites/props/prop_grass_1.png": Vector2i(16, 12),
	"res://assets/sprites/props/prop_grass_2.png": Vector2i(16, 12),
	"res://assets/sprites/props/prop_grass_3.png": Vector2i(16, 12),
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


## A combat target is a SOLID body, so a map must not park one on the line a player walks
## from a spawn to an exit (Phase 09).
##
## The hub's training dummy first shipped at (620, 304) — dead centre of the straight
## east-west run from `spawn_default` (496, 304) to the field exit (944, 304) — so leaving
## spawn walked you straight into it. Nothing caught it: the movement E2E takes one short
## step and the transition E2E places the player at the exit, so no test walks the corridor,
## and the capture happens to show the player standing still. This makes the clearance
## arithmetic instead of something to notice in a screenshot.
##
## It checks perpendicular distance to each spawn→exit SEGMENT, not just to the endpoints: a
## target can be far from both ends and still sit in the middle of the path.
func test_combat_targets_do_not_block_a_spawn_to_exit_path() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var scene: PackedScene = entry[0]
		var label: String = String(entry[1])
		var root := scene.instantiate()
		add_to_tree(root)
		var targets: Array[Node] = root.call("get_combat_targets")
		var spawns := root.get_node_or_null("Spawns")
		var exits := root.get_node_or_null("Exits")
		if targets.is_empty() or spawns == null or exits == null:
			free_node(root)
			continue
		for target_node in targets:
			var target := target_node as Node2D
			if target == null:
				continue
			for spawn in spawns.get_children():
				var spawn_2d := spawn as Node2D
				if spawn_2d == null:
					continue
				for exit_node in exits.get_children():
					var exit_2d := exit_node as Node2D
					if exit_2d == null:
						continue
					var distance := _distance_to_segment(
						target.position, spawn_2d.position, exit_2d.position)
					assert_true(distance >= MIN_PATH_CLEARANCE_PX,
						("%s: target '%s' sits %.0fpx from the %s -> %s walking line "
							+ "(minimum %dpx). A solid target on a spawn-to-exit line means "
							+ "leaving spawn walks into it.") % [
								label, target.name, distance, spawn_2d.name, exit_2d.name,
								MIN_PATH_CLEARANCE_PX])
		free_node(root)


## Shortest distance from `point` to the segment `a`-`b`. A point-to-ENDPOINT check would pass
## for a target parked exactly half-way along the path, which is the case that actually hurts.
func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var span := b - a
	var length_squared := span.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(a + span * t)


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
			"ground tile %d:0 is declared (4 moss + 4 flooded-paddy fills)" % column)


## The two promises the paddy layout makes, pinned on the REAL map scenes.
##
## `ta` is 田, a flooded rice paddy — not stone, as the first version of this floor assumed.
## That mistake shipped a cross of open water through the middle of the village, so the layout
## now owes the player two things, and neither is visible to any other gate:
##   1. a DRY WALKWAY down the middle they can always travel;
##   2. paddies that never touch the map edge, where the boundary walls are.
## The scenes are instantiated but deliberately NOT added to the tree, for the reason in this
## file's header: `MapBase._ready()` calls `InputService.set_gameplay_context()`, a shared
## `/root` autoload mutation that must not happen inside the common runner (L-010), and the
## runner's isolation guard would fail the suite for it. Nothing here needs the tree —
## `is_paddy_cell()` is a pure function of the authored exports, so the layout can be queried
## without the layer ever painting a cell.
func test_paddy_layout_leaves_a_dry_walkway_and_clears_the_walls() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var packed: PackedScene = (entry as Array)[0]
		var label: String = (entry as Array)[1]
		var map: Node = packed.instantiate()  # NOT added to the tree (L-010)
		assert_not_null(map, "%s map instantiates" % label)
		if map == null:
			continue
		# Either floor answers the same questions (fill_rect, walkway, is_paddy_cell).
		var ground := map.get_node_or_null("Visual/Ground")
		assert_not_null(ground, "%s has a ground layer" % label)
		if ground == null:
			map.free()
			continue

		var rect: Rect2i = ground.get("fill_rect")
		var centre_y := rect.position.y + int(rect.size.y * 0.5)
		var half: int = int(ground.get("walkway_half_height"))

		# 1. The walkway band must be completely dry, across the FULL width of the map.
		var flooded_on_walkway := 0
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for dy in range(-half, half + 1):
				if ground.call("is_paddy_cell", Vector2i(x, centre_y + dy)):
					flooded_on_walkway += 1
		assert_eq(flooded_on_walkway, 0,
			("%s: the central walkway (%d rows) is entirely dry — %d flooded cell(s) would "
				+ "put water across the player's only through-route")
				% [label, half * 2 + 1, flooded_on_walkway])

		# 2. No paddy may sit on the outermost ring, where the boundary walls are: a flooded
		#    cell under a wall reads as water leaking into the collision edge.
		var flooded_on_edge := 0
		var x1 := rect.position.x + rect.size.x - 1
		var y1 := rect.position.y + rect.size.y - 1
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if ground.call("is_paddy_cell", Vector2i(x, rect.position.y)):
				flooded_on_edge += 1
			if ground.call("is_paddy_cell", Vector2i(x, y1)):
				flooded_on_edge += 1
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			if ground.call("is_paddy_cell", Vector2i(rect.position.x, y)):
				flooded_on_edge += 1
			if ground.call("is_paddy_cell", Vector2i(x1, y)):
				flooded_on_edge += 1
		assert_eq(flooded_on_edge, 0,
			"%s: no paddy touches the map edge (%d did)" % [label, flooded_on_edge])

		# 3. And it must actually produce SOME paddies — a layout that floods nothing would
		#    pass both assertions above while silently reverting to a flat one-material floor.
		var flooded_total := 0
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				if ground.call("is_paddy_cell", Vector2i(x, y)):
					flooded_total += 1
		assert_true(flooded_total > 0,
			"%s: the layout actually places paddies (a layout that floods nothing is a flat "
				% label + "single-material floor again)")
		# Never added to the tree, so it is freed directly rather than via `free_node` (L-019:
		# a Node created in a test must be released by that test either way).
		map.free()


# --- D-057B: the world's depth and its ambient motion --------------------------------------

const SWAY_SHADER := "res://src/presentation/ambient/pixel_sway.gdshader"
const MIST_SHADER := "res://src/presentation/ambient/mist_drift.gdshader"

## Textures that MOVE in the wind, and so must wear the sway material.
const SWAYING_TEXTURES := [
	"res://assets/sprites/props/prop_tree_broadleaf.png",
	"res://assets/sprites/props/prop_grass_1.png",
	"res://assets/sprites/props/prop_grass_2.png",
	"res://assets/sprites/props/prop_grass_3.png",
]


## The world is DEPTH-SORTED: a body walking behind a tree is drawn behind it. Before D-057B
## the decor was drawn first and every body over it, so the player stood on top of a canopy.
## The floor sits below the ground-decal layer (-1, the hostile telegraph), which sits below
## the world.
func test_the_world_is_depth_sorted_and_layered() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var map: Node2D = (entry[0] as PackedScene).instantiate()
		var label := String(entry[1])
		assert_true(map.y_sort_enabled, "%s root y-sorts its world" % label)
		for path in ["Visual", "Visual/Decor", "CombatTargets", "PlayerHost"]:
			var node := map.get_node_or_null(path) as Node2D
			assert_true(node != null and node.y_sort_enabled,
				"%s/%s takes part in the depth sort" % [label, path])
		var ground := map.get_node_or_null("Visual/Ground") as CanvasItem
		assert_true(ground != null and ground.z_index < -1,
			"%s floor is under the ground-decal layer (z %d)" % [label,
				ground.z_index if ground != null else 0])
		map.free()


## Every prop is ROOTED where it stands: its origin is its base (so the depth sort compares
## feet with feet), and no prop stands in a flooded paddy cell.
func test_decor_props_are_rooted_on_dry_ground() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var map: Node = (entry[0] as PackedScene).instantiate()
		var label := String(entry[1])
		var ground := map.get_node("Visual/Ground")
		var checked := 0
		for child in map.get_node("Visual/Decor").get_children():
			var sprite := child as Sprite2D
			if sprite == null or sprite.texture == null:
				continue
			checked += 1
			assert_false(sprite.centered, "%s '%s' is base-anchored" % [label, sprite.name])
			assert_true(sprite.offset.y <= -float(sprite.texture.get_height()) + 2.0,
				"%s '%s' hangs its drawing ABOVE its origin (offset %s)"
					% [label, sprite.name, str(sprite.offset)])
			var cell := Vector2i(floori(sprite.position.x / 16.0),
				floori(sprite.position.y / 16.0))
			assert_false(bool(ground.call("is_flooded_cell", cell)),
				"%s '%s' does not stand in flooded ground (cell %s)"
					% [label, sprite.name, str(cell)])
		assert_true(checked >= 10, "%s checked its props (%d)" % [label, checked])
		map.free()


## What moves in the wind wears the sway material — ONE shared material per kind, so a
## field of grass is one material and the phase comes from world position, not per-instance
## state. What hangs (cloth, a paper lantern) hangs from the TOP.
func test_ambient_motion_is_wired_by_material() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var map: Node = (entry[0] as PackedScene).instantiate()
		var label := String(entry[1])
		var grass_materials := {}
		var swaying := 0
		var hanging := 0
		for child in map.get_node("Visual/Decor").get_children():
			var sprite := child as Sprite2D
			if sprite == null or sprite.texture == null:
				continue
			if SWAYING_TEXTURES.has(sprite.texture.resource_path):
				swaying += 1
				var material := sprite.material as ShaderMaterial
				assert_true(material != null and material.shader.resource_path == SWAY_SHADER,
					"%s '%s' sways (pixel_sway material)" % [label, sprite.name])
				if material != null and sprite.texture.resource_path.contains("grass"):
					grass_materials[material.get_instance_id()] = true
			for hung_name in ["Cloth", "Lantern"]:
				var hung := sprite.get_node_or_null(hung_name) as Sprite2D
				if hung == null:
					continue
				hanging += 1
				var hung_material := hung.material as ShaderMaterial
				assert_true(hung_material != null
					and bool(hung_material.get_shader_parameter(&"hang")),
					"%s %s/%s hangs from its top" % [label, sprite.name, hung_name])
		assert_true(swaying >= 10, "%s has wind-moved props (%d)" % [label, swaying])
		assert_true(hanging >= 2, "%s has hanging props (%d)" % [label, hanging])
		assert_eq(grass_materials.size(), 1, "%s grass shares ONE material" % label)
		map.free()


## The field has low mist, on the ground-decal layer, drifting by its own shader.
func test_the_field_has_drifting_mist() -> void:
	var map: Node = FieldScene.instantiate()
	var atmosphere := map.get_node_or_null("Visual/Atmosphere") as CanvasItem
	assert_not_null(atmosphere, "the field has an Atmosphere layer")
	if atmosphere != null:
		assert_eq(atmosphere.z_index, -1, "mist lies on the ground-decal layer, under bodies")
		assert_true(atmosphere.get_child_count() >= 4, "several banks of mist")
		for bank in atmosphere.get_children():
			var material := (bank as CanvasItem).material as ShaderMaterial
			assert_true(material != null and material.shader.resource_path == MIST_SHADER,
				"'%s' drifts (mist_drift material)" % bank.name)
	map.free()


## The water you SEE is the water that STOPS you (D-062): every open-water cell of a painted
## floor lies inside one of the map's water blockers — built from the same layout data — and the
## bridge is where the blockers stop, so the west road stays a road.
func test_painted_water_is_the_water_that_blocks() -> void:
	var map: Node = HubScene.instantiate()  # NOT added to the tree (L-010)
	var ground := map.get_node_or_null("Visual/Ground") as PaintedGround
	var water := map.get_node_or_null("Collision/Water") as WaterBlockers
	if ground == null:
		map.free()
		return  # a tiled floor has no open water to check
	assert_not_null(water, "a painted floor with water has its blockers under Collision/")
	if water == null or ground.layout == null:
		map.free()
		return
	var layout := ground.layout
	assert_true(water.polygon_count() > 0, "the stream has blocking polygons")
	var cells := 0
	var covered := 0
	for y in layout.fill_rect.size.y:
		for x in layout.fill_rect.size.x:
			var cell := layout.fill_rect.position + Vector2i(x, y)
			if not layout.is_water_cell(cell):
				continue
			cells += 1
			var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * float(layout.tile_px)
			for poly in layout.blockers:
				if Geometry2D.is_point_in_polygon(centre, poly):
					covered += 1
					break
	assert_true(cells > 0, "the hub's stream paints open water")
	assert_true(float(covered) >= 0.9 * float(cells),
		"%d of %d open-water cells are blocked — painted water must not be walkable" % [
			covered, cells])
	# The bridge: the west road's centre line crosses the stream between two blockers.
	var road := Vector2(150, 306)
	for poly in layout.blockers:
		assert_false(Geometry2D.is_point_in_polygon(road, poly),
			"the plank bridge at %s is walkable" % str(road))
	map.free()


## Solid world props (D-062) stand where the PLAYER cannot be blocked: no footprint covers a
## gameplay anchor (a spawn, an exit, a cultivation site, a knowledge source, a pickup, a combat
## target) or the spawn -> exit corridor, and every prop's origin stands on dry ground.
func test_solid_props_never_block_the_play() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var map: Node2D = (entry[0] as PackedScene).instantiate()  # NOT in the tree (L-010)
		var label := String(entry[1])
		var props: Array[WorldProp] = []
		for child in map.get_node("Visual/Decor").get_children():
			if child is WorldProp:
				props.append(child as WorldProp)
		var anchors: Array[Vector2] = []
		for path in ["Spawns", "Exits", "CultivationSites", "KnowledgeSources", "Pickups",
				"CombatTargets"]:
			var holder := map.get_node_or_null(path)
			if holder == null:
				continue
			for child in holder.get_children():
				if child is Node2D:
					anchors.append((child as Node2D).position)
		var ground := map.get_node("Visual/Ground")
		var spawn := map.get_node_or_null("Spawns/spawn_default") as Node2D
		for prop in props:
			if prop.prop == null:
				continue
			var foot := prop.prop.footprint
			if foot.size.x <= 0.0:
				continue
			var rect := Rect2(prop.position + foot.position, foot.size).grow(8.0)
			for anchor in anchors:
				assert_false(rect.has_point(anchor),
					"%s '%s' footprint %s keeps clear of the anchor at %s" % [
						label, prop.name, str(rect), str(anchor)])
			if spawn != null:
				for exit_zone in map.get_node("Exits").get_children():
					var a := spawn.position
					var b := (exit_zone as Node2D).position
					var closest := Geometry2D.get_closest_point_to_segment(rect.get_center(),
						a, b)
					assert_false(rect.grow(MIN_PATH_CLEARANCE_PX * 0.5).has_point(closest),
						"%s '%s' stays off the spawn -> exit line" % [label, prop.name])
			var cell := Vector2i(floori(prop.position.x / 16.0), floori(prop.position.y / 16.0))
			assert_false(bool(ground.call("is_flooded_cell", cell)),
				"%s '%s' stands on dry ground" % [label, prop.name])
		map.free()

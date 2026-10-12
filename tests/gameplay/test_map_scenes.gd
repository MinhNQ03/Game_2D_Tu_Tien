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
		# 3. ...and the floor is not ONE material. The tiled floor proves it by placing
		#    paddies; a painted floor (D-062) names its materials, and a forest has no paddies.
		if ground is PaintedGround:
			var painted := (ground as PaintedGround).layout.materials
			assert_true(painted.size() >= 3,
				"%s: the painted floor uses several materials (%s), not one stamped everywhere"
					% [label, str(painted)])
		else:
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
		# EVERY body a prop stands on: the pipeline's WorldProps AND the PropBody under a sprite a
		# scene places itself (D-063: the stele and the spring were bodiless, and this test only
		# looked at WorldProps, so nothing noticed).
		var props: Array[Dictionary] = []
		for child in map.get_node("Visual/Decor").get_children():
			if child is WorldProp:
				props.append({"node": child, "data": (child as WorldProp).prop,
					"at": (child as Node2D).position, "own": null})
		for found in map.find_children("*", "StaticBody2D", true, false):
			if found is PropBody:
				var body := found as PropBody
				props.append({"node": body, "data": body.prop, "at": _map_position(body, map),
					"own": body.get_parent()})
		var anchors: Array[Dictionary] = []
		for path in ["Spawns", "Exits", "CultivationSites", "KnowledgeSources", "Pickups",
				"CombatTargets"]:
			var holder := map.get_node_or_null(path)
			if holder == null:
				continue
			for child in holder.get_children():
				if child is Node2D:
					anchors.append({"node": child, "at": (child as Node2D).position})
		var ground := map.get_node("Visual/Ground")
		var spawn := map.get_node_or_null("Spawns/spawn_default") as Node2D
		for entry_prop in props:
			var data := entry_prop["data"] as PropData
			if data == null:
				continue
			var foot := data.footprint
			if foot.size.x <= 0.0:
				continue
			var prop_node := entry_prop["node"] as Node
			var at: Vector2 = entry_prop["at"]
			var rect := Rect2(at + foot.position, foot.size).grow(8.0)
			for anchor in anchors:
				if anchor["node"] == entry_prop["own"]:
					continue  # a stele's own plinth is not in the way of reading the stele
				assert_false(rect.has_point(anchor["at"]),
					"%s '%s' footprint %s keeps clear of the anchor at %s" % [
						label, prop_node.name, str(rect), str(anchor["at"])])
			if spawn != null:
				for exit_zone in map.get_node("Exits").get_children():
					var a := spawn.position
					var b := (exit_zone as Node2D).position
					var closest := Geometry2D.get_closest_point_to_segment(rect.get_center(),
						a, b)
					assert_false(rect.grow(MIN_PATH_CLEARANCE_PX * 0.5).has_point(closest),
						"%s '%s' stays off the spawn -> exit line" % [label, prop_node.name])
			var cell := Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
			assert_false(bool(ground.call("is_flooded_cell", cell)),
				"%s '%s' stands on dry ground" % [label, prop_node.name])
		map.free()


## A node's position in its map's space, read off-tree (a global transform needs the tree).
func _map_position(node: Node, map: Node) -> Vector2:
	var at := Vector2.ZERO
	var current := node
	while current != null and current != map:
		if current is Node2D:
			at += (current as Node2D).position
		current = current.get_parent()
	return at


## A pipeline sprite placed directly in a scene (the training post, the Lạc Hà stele and spring)
## stands on the ORIGIN the pipeline measured (D-062): its offset is exactly -PropData.origin.
## If a re-render moves the origin and the scene is not updated, the prop floats or sinks — this
## fails instead.
func test_pipeline_sprites_stand_on_their_measured_origin() -> void:
	var by_texture := {}
	var dir := DirAccess.open("res://data/world/props")
	assert_not_null(dir, "the prop data folder exists")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var data := load("res://data/world/props/" + file) as PropData
			if data != null and data.texture != null:
				by_texture[data.texture.resource_path] = data
	var checked := 0
	for scene_path in ["res://src/gameplay/maps/hub_map.tscn",
			"res://src/gameplay/maps/field_map.tscn",
			"res://src/gameplay/entities/training_dummy.tscn"]:
		var root: Node = (load(scene_path) as PackedScene).instantiate()
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child in node.get_children():
				stack.append(child)
			var sprite := node as Sprite2D
			if sprite == null or sprite.texture == null:
				continue
			var data: PropData = by_texture.get(sprite.texture.resource_path)
			if data == null:
				continue
			checked += 1
			assert_false(sprite.centered, "%s '%s' is drawn from its origin" % [
				scene_path.get_file(), sprite.name])
			assert_eq(sprite.offset, -data.origin, "%s '%s' stands on the measured origin" % [
				scene_path.get_file(), sprite.name])
		root.free()
	assert_true(checked >= 3, "the post, the stele and the spring were checked (%d)" % checked)


## D-073 §3: what the story puts in a map is drawn as what the story says it is. The cart
## WAITING on the east road is the whole cart, there until the vein breaks; the cart LEFT in
## the woods is the wreck, there once it has — a wheel off, crates split — and never the same
## picture as the one that was standing. Each is solid exactly where its own art says.
func test_the_cart_that_waits_is_whole_and_the_cart_that_was_left_is_a_wreck() -> void:
	var hub: Node = HubScene.instantiate()
	var field: Node = FieldScene.instantiate()
	var waiting := hub.get_node_or_null("Visual/Decor/CarterCart/Prop_CarterCart") as WorldProp
	var left := field.get_node_or_null("Visual/Decor/CartWreck/Prop_CartWreck") as WorldProp
	assert_not_null(waiting, "the village has the carter's cart")
	assert_not_null(left, "the woods have what was left of it")
	if waiting == null or left == null:
		hub.free()
		field.free()
		return
	assert_eq(waiting.prop.id, &"cart", "the cart that waits is the whole cart")
	assert_eq(left.prop.id, &"cart_wreck", "the cart that was left is drawn BROKEN")
	assert_ne(left.prop.texture, waiting.prop.texture, "never the standing cart's picture")
	var there_until := hub.get_node("Visual/Decor/CarterCart/Presence") as StoryPresence
	var there_after := field.get_node("Visual/Decor/CartWreck/Presence") as StoryPresence
	assert_eq([there_until.flag_id, there_until.present_when_set], [&"flag_vein_broke", false],
		"the whole cart is there UNTIL the vein breaks")
	assert_eq([there_after.flag_id, there_after.present_when_set], [&"flag_vein_broke", true],
		"the wreck is there ONCE it has: the two are never in the world together")
	# The wreck's body is the canted bed, inside its own picture; the litter round it is not.
	var size := Vector2(left.prop.texture.get_size())
	var drawn := Rect2(-left.prop.origin, size)
	assert_true(drawn.encloses(left.prop.footprint),
		"the wreck is solid only where it is drawn (%s in %s)" % [left.prop.footprint, drawn])
	assert_true(left.prop.footprint.size.x < size.x * 0.7,
		"and the wheel, the lid and the spill round it are walked over, not walls")
	hub.free()
	field.free()


# === Creature territory against what the player MUST reach (PX-2; H21-16) =====================

const FIELD_SPAWNS := "res://data/enemies/spawn_table_field.tres"
## A required thing must be this far outside a standing creature's detect radius: a body's
## width, so the player does not trip it by standing at the far edge of the prompt's reach.
const TERRITORY_MARGIN_PX := 24.0
## The uncontested way from the village entrance to the Survey Shaft, in world pixels: along
## the forest road east, then up the surveyors' footpath to the door. (The old haul track from
## the wreck is the CONTESTED way: it crosses the cairn wolf's ground, and is marked as such.)
const SAFE_WAY_TO_THE_SHAFT: Array[Vector2] = [Vector2(92, 304), Vector2(230, 318),
	Vector2(360, 300), Vector2(496, 304), Vector2(600, 300), Vector2(700, 322),
	Vector2(860, 300), Vector2(902, 300), Vector2(898, 200)]


## "Nobody is spawned on a route the player must take or within detection range of a safe
## service" (PLAYER_EXPERIENCE_STANDARD PX-2). Measured, because it was false twice over: the
## socket the bridge REQUIRES the player to examine stood 127 px from a wolf that notices at
## 170 — and "from the wolf" meant nothing, because its patrol was a random walk that took it
## up to its 340 px leash from where the map put it (real window: 205 px from its den, on the
## player at the socket and again on the footpath; handoff H21-16). A creature's REACH is now
## a number its data owns — how far it strays (`AiProfileData.stray_radius`) plus how far it
## notices — and everything the player must reach stands outside it.
func test_nothing_the_player_must_reach_in_the_woods_is_inside_a_creatures_territory() -> void:
	var table := load(FIELD_SPAWNS) as EnemySpawnTableData
	assert_true(table != null and table.is_valid(), "the woods' standing creatures load")
	var field: Node = FieldScene.instantiate()
	var required := {}
	for path: String in ["Spawns/from_hub", "Spawns/spawn_default", "Exits/ExitToHub",
			"KnowledgeSources/StakeSocket", "KnowledgeSources/ShaftSeal",
			"Interactables/KoThan"]:
		var node := field.get_node_or_null(path) as Node2D
		assert_not_null(node, "the woods have '%s'" % path)
		if node != null:
			required[path] = node.position
	for i in table.size():
		var creature := table.enemies[i]
		var profile := creature.ai_profile
		assert_true(profile.patrol_radius > 0.0,
			"'%s' keeps to a ground of its own, or its reach is its whole leash" % creature.id)
		var reach := profile.stray_radius(creature.stats.move_speed) + profile.detect_radius
		var den := table.positions[i]
		for what: String in required:
			var gap := den.distance_to(required[what])
			assert_true(gap >= reach + TERRITORY_MARGIN_PX,
				"'%s' is %.0f px from the den at %s; the creature reaches %.0f (+%.0f)"
				% [what, gap, den, reach, TERRITORY_MARGIN_PX])
		# ...and there is a WAY to the door that never enters its reach at all.
		for k in SAFE_WAY_TO_THE_SHAFT.size() - 1:
			var a := SAFE_WAY_TO_THE_SHAFT[k]
			var b := SAFE_WAY_TO_THE_SHAFT[k + 1]
			var nearest := Geometry2D.get_closest_point_to_segment(den, a, b)
			assert_true(den.distance_to(nearest) > reach,
				"the safe way %s -> %s passes %.0f px from the den at %s (reach %.0f)"
				% [a, b, den.distance_to(nearest), den, reach])
		# The wreck and the old haul track ARE its ground: the contested way stays contested,
		# or "safe" would only mean the creature had been taken out of the woods.
	var seal := field.get_node("KnowledgeSources/ShaftSeal") as Node2D
	assert_true(SAFE_WAY_TO_THE_SHAFT.back().distance_to(seal.position) < 16.0,
		"the safe way leads to the seal")
	var wreck := field.get_node("Visual/Decor/CartWreck") as Node2D
	var cairn_wolf := table.enemies[0]
	assert_true(table.positions[0].distance_to(wreck.position)
			< cairn_wolf.ai_profile.detect_radius,
		"the cairn wolf still holds the wreck: the contested way is still contested")
	field.free()



const ITEM_CATALOG := "res://data/items/item_catalog.tres"
const STORY_CATALOG := "res://data/story/story_catalog.tres"
const LOCALE_TABLE := "res://locale/aetheria.csv"


## THE PICKUP LEDGER (D-073 follow-up, FG-3). Everything lying in either map, held to what
## the bag's owner relies on: ONE id in the whole world (the run remembers a pickup by id, so
## a shared id makes the second vanish when the first is taken); a catalogued item in a count
## an empty bag can take WHOLE (a pickup is never split); a gate that names a real story flag
## and, when it is somebody's, can say whose in both languages; and no body of its own — a
## pickup is walked ONTO, so nothing is left to bump into once it is gone.
func test_everything_lying_in_the_world_has_one_identity_a_cause_and_no_body() -> void:
	var catalog := load(ITEM_CATALOG) as ItemCatalogData
	var story := load(STORY_CATALOG) as StoryCatalogData
	assert_true(catalog != null and story != null, "the item and story catalogs load")
	var keys := {}
	var table := FileAccess.open(LOCALE_TABLE, FileAccess.READ)
	assert_not_null(table, "the locale table opens")
	while table != null and not table.eof_reached():
		var row := table.get_csv_line()
		if row.size() >= 3:
			keys[row[0]] = row[1].strip_edges() != "" and row[2].strip_edges() != ""
	var empty := InventoryState.new()
	var seen := {}
	var total := 0
	for scene: PackedScene in [HubScene, FieldScene]:
		var map: Node = scene.instantiate()
		var host := map.get_node_or_null("Pickups")
		assert_not_null(host, "%s has a Pickups holder" % map.name)
		for child in host.get_children() if host != null else []:
			var pickup := child as WorldItem
			assert_not_null(pickup, "%s/%s is a WorldItem" % [map.name, child.name])
			if pickup == null:
				continue
			total += 1
			var what := "%s/%s" % [map.name, pickup.name]
			assert_true(pickup.pickup_id != &"" and not seen.has(pickup.pickup_id),
				"%s has an id of its own ('%s', also %s)" % [what, pickup.pickup_id,
					seen.get(pickup.pickup_id, "nobody's")])
			seen[pickup.pickup_id] = what
			assert_true(pickup.item != null and catalog.entry(pickup.item.id) == pickup.item,
				"%s is a catalogued item" % what)
			if pickup.item != null:
				assert_true(pickup.count >= 1 and pickup.count <= empty.room_for(pickup.item),
					"%s (x%d) fits an empty bag whole" % [what, pickup.count])
			for flag_id: StringName in [pickup.held_by_flag, pickup.appears_with_flag]:
				assert_true(flag_id == &"" or story.flag(flag_id) != null,
					"%s is gated by a flag the story has ('%s')" % [what, flag_id])
			if pickup.held_by_flag != &"":
				assert_true(bool(keys.get(String(pickup.held_reason_key), false)),
					"%s can say whose it is, in vi and en ('%s')"
					% [what, pickup.held_reason_key])
			for part in pickup.find_children("*", "CollisionObject2D", true, false):
				assert_true(false, "%s has a body (%s): a pickup is walked onto" % [what,
					part.name])
		map.free()
	assert_true(total >= 8, "both maps' pickups were looked at (%d)" % total)


## NO GHOSTS (D-073 follow-up, FG-3). What the story has taken out of a map — the cart after
## the Night, the stake somebody pulled, the wreck before it happened — is gone as a THING:
## not drawn (which is also what takes it off the interact key: `MapBase` offers only what is
## visible) and with every collision shape under it switched off. Brought back, it is solid
## again. Both ways, on every `StoryPresence` in both maps, with the bodies BUILT as `_ready`
## builds them (off-tree, a `WorldProp` has no shape yet and the check would pass on nothing).
func test_what_the_story_removes_leaves_no_picture_and_no_body() -> void:
	var presences := 0
	var with_bodies := 0
	for scene: PackedScene in [HubScene, FieldScene]:
		var map: Node = scene.instantiate()
		for found in map.find_children("*", "StaticBody2D", true, false):
			if found is WorldProp:
				(found as WorldProp).build()
			elif found is PropBody:
				(found as PropBody).build()
		for found in map.find_children("*", "", true, false):
			var presence := found as StoryPresence
			if presence == null:
				continue
			presences += 1
			var host := presence.get_parent() as CanvasItem
			var what := "%s/%s" % [map.name, host.name]
			var bodies: Array[Node] = host.find_children("*", "CollisionObject2D", true, false)
			if host is CollisionObject2D:
				bodies.append(host)
			var shapes := 0
			for set_now: bool in [true, false, true]:
				presence.apply(func(_flag: StringName) -> bool: return set_now)
				var there: bool = set_now == presence.present_when_set
				assert_eq(host.visible, there, "%s is %s when its flag is %s"
					% [what, "drawn" if there else "not drawn", set_now])
				for body: CollisionObject2D in bodies:
					for owner_id in body.get_shape_owners():
						shapes += 1
						assert_eq(body.is_shape_owner_disabled(owner_id), not there,
							"%s: %s is %s when its flag is %s" % [what, body.name,
								"solid" if there else "bodiless", set_now])
			if shapes > 0:
				with_bodies += 1
			# FAIL CLOSED: with nobody to ask, a thing that needs a flag SET is not there.
			presence.apply(Callable())
			assert_eq(host.visible, not presence.present_when_set,
				"%s with no story to ask is as if its flag were unset" % what)
		map.free()
	assert_true(presences >= 6, "every StoryPresence in both maps was tried (%d)" % presences)
	assert_true(with_bodies >= 3,
		"the cart, the wreck and the stake had real shapes to switch (%d)" % with_bodies)


## The court's paving as a band of its ellipse (foreshortened like all ground: the layout's
## radii), between the wet ring round the basin and the kerb.
const COURT_RADIUS := Vector2(54, 31)
const COURT_PAVING_BAND := Vector2(0.64, 0.9)
## How much lighter (mean luminance, 0-1) each quarter of the paving must be than the ground
## it is compared with. Measured on the painted floor when written: the four quarters 0.61 to
## 0.66, the square beside it 0.54, the meadow 0.45. (The first court painted measured 0.51
## — DARKER than the square, under its own mortar; this test is what found it.)
const COURT_LIGHTER_BY := 0.05


## Mean luminance of the floor inside an ellipse's band `band` (fractions of its radius),
## over one quarter turn starting at `turn` (0 = east, in quarter turns), or all of it (-1).
func _band_luminance(image: Image, centre: Vector2, band: Vector2, turn: int = -1) -> float:
	var total := 0.0
	var count := 0
	for y in range(int(centre.y - COURT_RADIUS.y), int(centre.y + COURT_RADIUS.y) + 1):
		for x in range(int(centre.x - COURT_RADIUS.x), int(centre.x + COURT_RADIUS.x) + 1):
			var unit := (Vector2(x, y) - centre) / COURT_RADIUS
			if unit.length() < band.x or unit.length() > band.y:
				continue
			# a quarter is centred on its direction: east is -45 to +45 degrees
			if turn >= 0 and posmod(int(floor((unit.angle() + PI / 4.0) / (PI / 2.0))), 4) != turn:
				continue
			total += image.get_pixel(x, y).get_luminance()
			count += 1
	return total / float(maxi(count, 1))


## THE SPRING THAT BEARS THE VILLAGE'S NAME IS ITS FOCAL POINT
## (docs/VISUAL_CRAFT_WORKFLOW.md, proof W1). The Lạc Hà spring stands at the CENTRE of a
## laid court, and that court is the lightest ground round it: lighter than the worn
## square beside it and than the meadow. Until this test the
## spring was a 52 px basin on the corner of the square, on the square's own flags — nothing
## on the floor said it mattered. Each quarter of the paving is judged on its own, so a court
## that drifts off the spring (or a spring moved off its court) fails by the side it left.
func test_the_lac_ha_spring_stands_at_the_centre_of_the_floors_lightest_ground() -> void:
	var map: Node = HubScene.instantiate()  # NOT added to the tree (L-010)
	var ground := map.get_node("Visual/Ground") as PaintedGround
	ground.apply_layout()
	assert_true(ground.layout.materials.has("court"), "the hub's floor has a laid court")
	var image := ground.layout.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var spring := (map.get_node("CultivationSites/LacHaSpring") as Node2D).position \
		- ground.position
	var whole := Vector2(0.0, COURT_PAVING_BAND.y)
	var square := _band_luminance(image, spring + Vector2(150, -30), whole)
	var meadow := _band_luminance(image, spring + Vector2(-40, 110), whole)
	for turn in 4:
		var court := _band_luminance(image, spring, COURT_PAVING_BAND, turn)
		assert_true(court >= square + COURT_LIGHTER_BY,
			"quarter %d of the court (%.3f) is lighter than the square (%.3f)"
			% [turn, court, square])
		assert_true(court >= meadow + COURT_LIGHTER_BY,
			"quarter %d of the court (%.3f) is lighter than the meadow (%.3f)"
			% [turn, court, meadow])
	map.free()


## How many swaying grass tufts the hub's scene holds. The scene sync drops a tuft the floor
## no longer has turf under; when undergrowth was added as a floor kind and the sync did not
## count it as turf, six tufts vanished from exactly the ground they belong on. Seen in the
## scene diff, pinned here.
const HUB_TUFTS := 27


func test_the_hub_keeps_every_swaying_tuft_that_stands_on_turf() -> void:
	var map: Node = HubScene.instantiate()  # NOT added to the tree (L-010)
	var tufts := 0
	for node in map.get_node("Visual/Decor").get_children():
		if String(node.name).begins_with("Grass"):
			tufts += 1
	assert_eq(tufts, HUB_TUFTS, "the hub's tufts (a sync that stops counting a kind of turf "
		+ "drops the tufts standing on it)")
	map.free()


## The spring's overflow is a runnel a hand deep: painted, stepped over, never a wall. It is
## on the floor ("rill") and it floods no cell and lies under no blocker along its run
## (INTANGIBLE_BY_DESIGN) — a line that leads to the spring must not fence the meadow.
func test_the_springs_runnel_is_drawn_but_never_blocks() -> void:
	var map: Node = HubScene.instantiate()  # NOT added to the tree (L-010)
	var ground := map.get_node("Visual/Ground") as PaintedGround
	ground.apply_layout()
	var layout := ground.layout
	assert_true(layout.materials.has("rill"), "the hub's floor has the spring's runnel")
	var spring := (map.get_node("CultivationSites/LacHaSpring") as Node2D).position
	# along the runnel, from below the court to short of the stream's bank
	for along: Vector2 in [Vector2(-70, 36), Vector2(-112, 44), Vector2(-164, 36)]:
		var at := spring + along
		var cell := Vector2i((at / float(layout.tile_px)).floor())
		assert_false(ground.is_flooded_cell(cell), "the runnel floods no cell (%s)" % str(cell))
		for poly in layout.blockers:
			assert_false(Geometry2D.is_point_in_polygon(at, poly),
				"the runnel at %s is under no blocker" % str(at))
	map.free()

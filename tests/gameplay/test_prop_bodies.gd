extends TestCase
## Physical truth (D-063 A2): what is DRAWN with mass has a BODY — and the body is not the reach.
##
## THE BUG IT GUARDS. The Lạc Hà stele — the story's first lesson, a tablet on a stone plinth —
## had no body: in the real app the player walked from y=340 to y=248, straight through its base
## at y=296, and E still read it, because reading is a DISTANCE test. The pipeline wrote its
## footprint as zero ("its scene owns the collision", which no scene did) and the scene placed a
## bare sprite; the spring was the same. The prop tests only walked `WorldProp` nodes.
##
## Two separate things are pinned for each body: the WALK (it stops on every side, holds when
## pushed, never traps) and the REACH (where the walk stops is still inside the owner's own
## distance test — adding a body changed no interaction).

const HubScene := preload("res://src/gameplay/maps/hub_map.tscn")
const FieldScene := preload("res://src/gameplay/maps/field_map.tscn")
const PlayerScene := preload("res://src/gameplay/entities/player.tscn")
const STELE := preload("res://data/world/props/stele.tres")
const SPRING := preload("res://data/world/props/spirit_spring.tres")

## The eight ways a walk meets a thing: from each side, and from each corner.
const APPROACHES: Array[Vector2] = [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT,
	Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]

## What a player WALKS THROUGH, and why — the only drawn things with no body. Anything else drawn
## in the world must stand on a PropBody (or be a WorldProp): a new sprite with neither fails.
const INTANGIBLE_BY_DESIGN := {
	"res://assets/sprites/props/prop_grass_1.png": "ground cover: a player walks through grass",
	"res://assets/sprites/props/prop_grass_2.png": "ground cover: a player walks through grass",
	"res://assets/sprites/props/prop_grass_3.png": "ground cover: a player walks through grass",
	"res://assets/sprites/props/prop_mist.png": "atmosphere: mist drifts above the ground",
	"res://assets/sprites/props/prop_banner_cloth.png":
		"hangs from the pole above head height; the pole's footing is the body",
	"res://assets/sprites/props/prop_lantern_hanging.png":
		"hangs from the post; the post's foot is the body",
}

## Where the world's drawn things live in a map (the training post is a combat target).
const WORLD_HOLDERS: Array[String] = ["Visual/Decor", "Visual/Atmosphere", "KnowledgeSources",
	"CultivationSites", "CombatTargets"]

## A pixel is DRAWN MASS from this alpha up; a baked cast shadow is lighter and is not mass.
const MASS_ALPHA := 200
## How far a body's edge may sit from a drawn pixel (the outline and the ellipse's polygon).
const EDGE_TOLERANCE_PX := 2


# --- structure: the bodies exist, from the pipeline's own data ------------------------------

func test_the_stele_and_the_spring_have_bodies_from_their_own_prop_data() -> void:
	var map: Node = HubScene.instantiate()  # NOT in the tree (L-010)
	for entry in [["KnowledgeSources/LacHaStele", STELE], ["CultivationSites/LacHaSpring", SPRING]]:
		var owner_node := map.get_node(String(entry[0]))
		var body := owner_node.get_node_or_null("Body") as PropBody
		assert_not_null(body, "%s has a PropBody" % entry[0])
		if body == null:
			continue
		assert_eq(body.prop, entry[1], "%s: built from the pipeline's PropData" % entry[0])
		assert_true(body.prop.footprint.has_area(), "%s: with a real footprint" % entry[0])
		assert_eq(body.position, Vector2.ZERO,
			"%s: at the owner's origin, the point its reach is measured from" % entry[0])
		body.build()
		assert_not_null(body.get_node_or_null("Footprint"),
			"%s: the body builds its collision off-tree too" % entry[0])
		assert_eq(body.collision_layer, CollisionLayers.WORLD, "%s: it is WORLD" % entry[0])
	assert_true(SPRING.footprint_round, "the spring's ring of stones is round")
	map.free()


# --- the walk and the reach ---------------------------------------------------------------

func test_a_walk_meets_the_stele_on_every_side_and_it_stays_readable() -> void:
	var map: Node = HubScene.instantiate()
	var reach := float((map.get_node("KnowledgeSources/LacHaStele") as KnowledgeSource).reach_px)
	map.free()
	await _approach_from_every_side(STELE, reach, "stele")


func test_a_walk_meets_the_spring_on_every_side_and_it_stays_a_place_to_sit() -> void:
	var map: Node = HubScene.instantiate()
	var site := map.get_node("CultivationSites/LacHaSpring") as CultivationSite
	var radius := float(site.site.radius_px)
	map.free()
	await _approach_from_every_side(SPRING, radius, "spring")


## For each approach: start outside, walk straight at the thing with the PLAYER'S OWN collision
## shape, and check the stop (outside the body), the reach (inside), the push (holds) and the
## way back (free).
func _approach_from_every_side(data: PropData, reach: float, label: String) -> void:
	var world := Node2D.new()
	add_to_tree(world)
	var body := PropBody.new()
	body.prop = data
	world.add_child(body)
	var probe := _player_probe()
	world.add_child(probe)
	await scene_tree.physics_frame
	var outline := _body_polygon(data)
	assert_false(outline.is_empty(), "%s: has a body to meet" % label)
	for side in APPROACHES:
		var dir := side.normalized()
		probe.global_position = dir * 80.0
		var hit := probe.move_and_collide(-dir * 120.0)
		var case := "%s from %s" % [label, str(side)]
		assert_not_null(hit, "%s: the walk is stopped" % case)
		var feet := probe.global_position
		assert_false(_overlaps(_probe_polygon(probe), outline),
			"%s: it stops OUTSIDE the body (feet at %s)" % [case, str(feet)])
		if reach < INF:
			assert_true(feet.length() <= reach,
				"%s: and still inside the reach — %.1f px from the origin, reach %.0f"
					% [case, feet.length(), reach])
		probe.move_and_collide(-dir * 40.0)
		assert_true(probe.global_position.distance_to(feet) < 1.0,
			"%s: pushing on does not pass through" % case)
		assert_false(probe.test_move(probe.global_transform, dir * 12.0),
			"%s: and walking away is free — never trapped" % case)
	free_node(world)


func test_a_walk_meets_every_kind_of_decor_and_is_never_trapped() -> void:
	var walked := 0
	for data: PropData in _prop_body_data():
		if data != STELE and data != SPRING:
			walked += 1
			await _approach_from_every_side(data, INF, String(data.id))
	assert_true(walked >= 4, "the banner pole, lantern post, rock and planter were walked into "
		+ "(%d) — a walk over nothing proves nothing" % walked)


# --- every drawn mass is a body, or is intangible on purpose ---------------------------------

## The RULE (D-063): what is drawn with physical mass has a body with a REAL collision shape —
## a PropBody under (or beside) its sprite, a WorldProp around the sprite it builds, a body like
## the training post around its own — built from the PropData of THAT texture at the sprite's own
## origin; or it is listed in INTANGIBLE_BY_DESIGN with the reason. An intangible thing has no
## body. The maps are instantiated off-tree, so every WorldProp and PropBody is first BUILT the
## way `_ready` builds it: a WorldProp's sprite only exists after that, and a scan that skipped
## the step would never see the pipeline's art at all.
func test_every_drawn_mass_has_a_body_or_is_intangible_by_design() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var map: Node = (entry[0] as PackedScene).instantiate()  # NOT in the tree (L-010)
		var world_props := 0
		for found in map.find_children("*", "StaticBody2D", true, false):
			if found is WorldProp:
				(found as WorldProp).build()
				world_props += 1
			elif found is PropBody:
				(found as PropBody).build()
		var checked := 0
		var checked_world_props := 0
		for holder_path in WORLD_HOLDERS:
			var holder := map.get_node_or_null(holder_path)
			if holder == null:
				continue
			for found in holder.find_children("*", "Sprite2D", true, false):
				var sprite := found as Sprite2D
				if sprite.texture == null:
					continue
				checked += 1
				var path := sprite.texture.resource_path
				var body := _body_of(sprite)
				var where := "%s %s" % [entry[1], str(map.get_path_to(sprite))]
				if INTANGIBLE_BY_DESIGN.has(path):
					assert_null(body, "%s is intangible by design (%s) and has no body"
						% [where, INTANGIBLE_BY_DESIGN[path]])
					continue
				assert_not_null(body, "%s (%s) is drawn with mass: it needs a body, or a reason "
					% [where, path.get_file()] + "in INTANGIBLE_BY_DESIGN")
				if body == null:
					continue
				assert_true(_has_collision(body),
					"%s: its body has a real collision shape, not just data" % where)
				var data := _data_of(body)
				if data == null:
					continue  # a body with its own authored shape (the training post)
				if body is WorldProp:
					checked_world_props += 1
				assert_eq(data.texture, sprite.texture,
					"%s stands on the PropData of its own texture" % where)
				assert_eq(_origin_offset(sprite, body), Vector2.ZERO,
					"%s: the body stands at the sprite's origin" % where)
		assert_true(checked >= 10,
			"%s: the scan saw the world's sprites (%d)" % [entry[1], checked])
		assert_eq(checked_world_props, world_props,
			"%s: every WorldProp's BUILT sprite was scanned (%d of %d)"
				% [entry[1], checked_world_props, world_props])
		map.free()


# --- the body sits under the drawn mass ---------------------------------------------------

## NO INVISIBLE WALL: every sample on a body's edge lies on (or beside) a drawn pixel.
## NO GHOST MASS: the drawn base is solid — every drawn pixel in the middle 60% of the base row
## lies INSIDE the body's actual shape (the rectangle, or the round body's rim polygon), tested
## as point-in-polygon in the prop's own space.
func test_each_body_sits_under_the_mass_that_is_drawn() -> void:
	var bodied := _prop_body_data()
	assert_true(bodied.size() >= 6,
		"the stele, the spring and the four kinds of decor stand on bodies (%d)" % bodied.size())
	for data: PropData in bodied:
		var image: Image = data.texture.get_image()
		var polygon := _body_polygon(data)
		assert_false(polygon.is_empty(), "%s: drawn with mass, so it has a body" % data.id)
		if polygon.is_empty():
			continue
		for point in _edge_samples(polygon):
			assert_true(_near_mass(image, point + data.origin),
				"%s: the body's edge at %s is drawn — no invisible wall" % [data.id, str(point)])
		# the drawn base: the row just above the ground line, or a round base's middle row
		var base_row := int(data.origin.y + data.footprint.get_center().y) \
			if data.footprint_round else int(data.origin.y) - 1
		var columns := _mass_columns(image, base_row)
		assert_true(columns.size() >= 3, "%s: its base row %d is drawn" % [data.id, base_row])
		var trim := int(floor(columns.size() * 0.2))
		var inside := 0
		for i in range(trim, columns.size() - trim):
			var point := Vector2(columns[i] + 0.5, base_row + 0.5) - data.origin
			assert_true(Geometry2D.is_point_in_polygon(point, polygon),
				"%s: the drawn base pixel at %s (prop space) is inside the body — no ghost mass"
					% [data.id, str(point)])
			inside += 1
		assert_true(inside >= 2, "%s: the base check sampled the base (%d px)" % [data.id, inside])


# --- helpers ----------------------------------------------------------------------------

## The body a sprite stands on: a PropBody child (decor), a PropBody sibling under the same owner
## (a stele's Stone and its Body), or the physics body that OWNS the sprite (the sprite a
## WorldProp builds, the training post's Visual). Null when it stands on nothing.
func _body_of(sprite: Sprite2D) -> CollisionObject2D:
	for child in sprite.get_children():
		if child is PropBody:
			return child as PropBody
	var parent := sprite.get_parent()
	if parent is KnowledgeSource or parent is CultivationSite:
		for sibling in parent.get_children():
			if sibling is PropBody:
				return sibling as PropBody
	if parent is PhysicsBody2D:
		return parent as PhysicsBody2D
	return null


## A body that stops a walk has at least one collision shape with an actual shape in it.
func _has_collision(body: CollisionObject2D) -> bool:
	for child in body.get_children():
		var shape := child as CollisionShape2D
		if shape != null and shape.shape != null and not shape.disabled:
			return true
	return false


func _data_of(body: CollisionObject2D) -> PropData:
	if body is PropBody:
		return (body as PropBody).prop
	if body is WorldProp:
		return (body as WorldProp).prop
	return null


## How far the body's origin sits from the sprite's (zero when it stands where it is drawn).
func _origin_offset(sprite: Sprite2D, body: CollisionObject2D) -> Vector2:
	if body.get_parent() == sprite:
		return body.position
	if sprite.get_parent() == body:
		return sprite.position + sprite.offset + _data_of(body).origin
	return body.position - sprite.position


## Every PropData a PropBody stands on, in either map, once each.
func _prop_body_data() -> Array[PropData]:
	var out: Array[PropData] = []
	for scene: PackedScene in [HubScene, FieldScene]:
		var map := scene.instantiate()
		for found in map.find_children("*", "StaticBody2D", true, false):
			var body := found as PropBody
			if body != null and body.prop != null and not out.has(body.prop):
				out.append(body.prop)
		map.free()
	return out


## A body with the REAL player's collision shape and mask (read from player.tscn, so a resized
## player cannot leave this test measuring a stale box).
func _player_probe() -> CharacterBody2D:
	var player := PlayerScene.instantiate()  # never added to the tree: only its shape is read
	var shape := player.get_node("CollisionShape2D") as CollisionShape2D
	var probe := CharacterBody2D.new()
	probe.collision_layer = CollisionLayers.PLAYER
	probe.collision_mask = CollisionLayers.WORLD | CollisionLayers.DUMMY
	var copy := CollisionShape2D.new()
	copy.name = "CollisionShape2D"
	copy.shape = shape.shape
	copy.position = shape.position
	probe.add_child(copy)
	player.free()
	return probe


func _probe_polygon(probe: CharacterBody2D) -> PackedVector2Array:
	var shape := probe.get_node("CollisionShape2D") as CollisionShape2D
	var half := (shape.shape as RectangleShape2D).size * 0.5
	var centre := probe.global_position + shape.position
	# shrunk by the physics safe margin: resting contact is not an overlap
	half -= Vector2(probe.safe_margin, probe.safe_margin) * 2.0
	return PackedVector2Array([centre + Vector2(-half.x, -half.y),
		centre + Vector2(half.x, -half.y), centre + Vector2(half.x, half.y),
		centre + Vector2(-half.x, half.y)])


## The body's SHAPE in the prop's own space — exactly what `PropBody.make_footprint` builds: the
## rectangle's four corners, or the round body's rim. Empty for a walk-through prop.
func _body_polygon(data: PropData) -> PackedVector2Array:
	var footprint := PropBody.make_footprint(data)
	if footprint == null:
		return PackedVector2Array()
	var out := PackedVector2Array()
	if footprint.shape is ConvexPolygonShape2D:
		out = (footprint.shape as ConvexPolygonShape2D).points
	else:
		var half := (footprint.shape as RectangleShape2D).size * 0.5
		var c := footprint.position
		out = PackedVector2Array([c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y),
			c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)])
	footprint.free()
	return out


## Points along a body's edge: every vertex and the middle of every side.
func _edge_samples(polygon: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in polygon.size():
		out.append(polygon[i])
		out.append((polygon[i] + polygon[(i + 1) % polygon.size()]) * 0.5)
	return out


func _overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, b).is_empty()


func _near_mass(image: Image, pixel: Vector2) -> bool:
	var px := Vector2i(roundi(pixel.x), roundi(pixel.y))
	for dy in range(-EDGE_TOLERANCE_PX, EDGE_TOLERANCE_PX + 1):
		for dx in range(-EDGE_TOLERANCE_PX, EDGE_TOLERANCE_PX + 1):
			var x := px.x + dx
			var y := px.y + dy
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() \
					and image.get_pixel(x, y).a8 >= MASS_ALPHA:
				return true
	return false


## The columns of a texture row that are DRAWN MASS, left to right.
func _mass_columns(image: Image, row: int) -> Array[int]:
	var out: Array[int] = []
	for x in image.get_width():
		if image.get_pixel(x, row).a8 >= MASS_ALPHA:
			out.append(x)
	return out

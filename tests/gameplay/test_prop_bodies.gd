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

## Where the world's drawn things live in a map.
const WORLD_HOLDERS: Array[String] = ["Visual/Decor", "Visual/Atmosphere", "KnowledgeSources",
	"CultivationSites"]

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
	var outline := _footprint_polygon(data)
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

## The RULE (D-063): what is drawn with physical mass has a body — a PropBody under (or beside)
## its sprite, built from the PropData of THAT texture, at the sprite's own origin — or is listed
## in INTANGIBLE_BY_DESIGN with the reason. And an intangible thing never grew a body.
func test_every_drawn_mass_has_a_body_or_is_intangible_by_design() -> void:
	for entry in [[HubScene, "hub"], [FieldScene, "field"]]:
		var map: Node = (entry[0] as PackedScene).instantiate()  # NOT in the tree (L-010)
		var checked := 0
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
				assert_true(body.prop != null and body.prop.texture == sprite.texture,
					"%s stands on the PropData of its own texture" % where)
				assert_true(body.prop != null and body.prop.footprint.has_area(),
					"%s: with a real footprint" % where)
				var body_at := body.position if body.get_parent() == sprite \
					else body.position - sprite.position
				assert_eq(body_at, Vector2.ZERO, "%s: the body stands at the sprite's origin"
					% where)
		assert_true(checked >= 10,
			"%s: the walk saw the world's sprites (%d)" % [entry[1], checked])
		map.free()


# --- the body sits under the drawn mass ---------------------------------------------------

## NO INVISIBLE WALL: every point on a body's edge lies on (or beside) a drawn pixel.
## NO GHOST MASS: the drawn base is solid — the middle of its base row lies inside the body.
func test_each_body_sits_under_the_mass_that_is_drawn() -> void:
	var bodied := _prop_body_data()
	assert_true(bodied.size() >= 6,
		"the stele, the spring and the four kinds of decor stand on bodies (%d)" % bodied.size())
	for data: PropData in bodied:
		var image: Image = data.texture.get_image()
		var outline := _footprint_polygon(data)
		assert_false(outline.is_empty(), "%s: drawn with mass, so it has a body" % data.id)
		for point in outline:
			assert_true(_near_mass(image, point + data.origin),
				"%s: the body's edge at %s is drawn — no invisible wall" % [data.id, str(point)])
		# the drawn base: the row above the ground line, or a round base's middle row
		var base_row := int(data.origin.y + data.footprint.get_center().y) \
			if data.footprint_round else int(data.origin.y) - 1
		var span := _mass_span(image, base_row)
		assert_true(span.y > span.x, "%s: its base row %d is drawn" % [data.id, base_row])
		var inner := Vector2(lerpf(span.x, span.y, 0.2), lerpf(span.x, span.y, 0.8)) \
			- Vector2(data.origin.x, data.origin.x)
		assert_true(inner.x >= data.footprint.position.x and inner.y <= data.footprint.end.x,
			"%s: the middle of its drawn base (%s) is inside the body (%.1f..%.1f) — no ghost mass"
				% [data.id, str(inner), data.footprint.position.x, data.footprint.end.x])


# --- helpers ----------------------------------------------------------------------------

## The PropBody standing a sprite on the ground: a child of the sprite (decor), or a sibling
## under the same owner (a stele's Stone and its Body).
func _body_of(sprite: Sprite2D) -> PropBody:
	for child in sprite.get_children():
		if child is PropBody:
			return child as PropBody
	var parent := sprite.get_parent()
	if parent is KnowledgeSource or parent is CultivationSite:
		for sibling in parent.get_children():
			if sibling is PropBody:
				return sibling as PropBody
	return null


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


## The body's outline in the prop's own space: the rectangle, or the round footprint's rim —
## exactly the shape `PropBody.make_footprint` builds.
func _footprint_polygon(data: PropData) -> PackedVector2Array:
	var footprint := PropBody.make_footprint(data)
	var out := PackedVector2Array()
	if footprint == null:
		return out  # a walk-through prop: nothing to stand under the drawing
	if footprint.shape is ConvexPolygonShape2D:
		out = (footprint.shape as ConvexPolygonShape2D).points
	else:
		var r := Rect2(footprint.position - (footprint.shape as RectangleShape2D).size * 0.5,
			(footprint.shape as RectangleShape2D).size)
		out = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y), r.get_center() + Vector2(0, r.size.y * 0.5),
			r.get_center() - Vector2(0, r.size.y * 0.5)])
	footprint.free()
	return out


## Overlap of the probe with a body outline (its hull: the rectangle's outline also carries two
## mid-edge samples for the drawn-mass check).
func _overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, Geometry2D.convex_hull(b)).is_empty()


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


## The first and last DRAWN-MASS pixel of a texture row, as (first, last + 1).
func _mass_span(image: Image, row: int) -> Vector2:
	var first := -1
	var last := -1
	for x in image.get_width():
		if image.get_pixel(x, row).a8 >= MASS_ALPHA:
			if first < 0:
				first = x
			last = x
	return Vector2(first, last + 1) if first >= 0 else Vector2.ZERO

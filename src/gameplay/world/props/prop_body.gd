extends StaticBody2D
class_name PropBody
## PropBody — Aetheria gameplay (the SOLID BASE of a sprite a scene places itself, D-063).
##
## A stele's plinth, a spring's ring of stones, a lantern's foot: the collision of the prop's
## `PropData.footprint`, and nothing else — the sprite, and whatever sways or swings on it, stays
## the scene's own. `WorldProp` is the same footprint plus a sprite; both build it with
## `make_footprint`, so a footprint is one rule.
##
## A BODY, never a reach. Whether the player can READ a stele or SIT at a spring is still decided
## by its owner's distance test (`KnowledgeSource.reach_px`, `CultivationSiteData.radius_px`);
## the body only stops a walk, and is sized so that standing against it on any side stays inside
## that reach (tested), so adding it changed no interaction.

## Points on the rim of a round footprint: smooth at 2x zoom, still a cheap convex shape.
const ROUND_POINTS := 16

@export var prop: PropData = null


func _init() -> void:
	# Static scenery: it is the WORLD the player and the creatures collide with; it hits nothing.
	collision_layer = CollisionLayers.WORLD
	collision_mask = 0


func _ready() -> void:
	build()


## Build the footprint collision from `prop`. Safe off-tree (the map tests instantiate scenes
## without adding them) and idempotent.
func build() -> void:
	for child in get_children():
		child.free()
	var footprint := make_footprint(prop)
	if footprint != null:
		add_child(footprint)


## The collision of a prop's footprint, in the prop's own space (origin = its front base, or the
## centre of a round base), or null for a walk-through prop.
static func make_footprint(data: PropData) -> CollisionShape2D:
	if data == null or data.footprint.size.x <= 0.0 or data.footprint.size.y <= 0.0:
		return null
	var foot := data.footprint
	var body := CollisionShape2D.new()
	body.name = "Footprint"
	if data.footprint_round:
		var rim := PackedVector2Array()
		var centre := foot.get_center()
		var radii := foot.size * 0.5
		for i in ROUND_POINTS:
			var angle := TAU * float(i) / float(ROUND_POINTS)
			rim.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		var convex := ConvexPolygonShape2D.new()
		convex.points = rim
		body.shape = convex
	else:
		var rect := RectangleShape2D.new()
		rect.size = foot.size
		body.shape = rect
		body.position = foot.get_center()
	return body

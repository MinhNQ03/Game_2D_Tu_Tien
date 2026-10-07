extends StaticBody2D
class_name WaterBlockers
## WaterBlockers — Aetheria gameplay (the stream and the pond are not walkable, D-062).
##
## One static body whose collision polygons come from the map's `GroundLayoutData.blockers` —
## the SAME data the painted floor was drawn from, so the water you see is the water that stops
## you, and the bridge is exactly where the polygons stop. Built once at `_ready`; no per-frame
## work.

@export var layout: GroundLayoutData = null


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		if child is CollisionPolygon2D:
			child.queue_free()
	if layout == null:
		return
	for i in layout.blockers.size():
		var shape := CollisionPolygon2D.new()
		shape.name = "Water%d" % i
		shape.polygon = layout.blockers[i]
		add_child(shape)


func polygon_count() -> int:
	return layout.blockers.size() if layout != null else 0

extends Sprite2D
class_name PaintedGround
## PaintedGround — Aetheria gameplay (a map floor painted from its layout, D-062).
##
## The successor of `PrototypeGround` for a map that has a painted layout: ONE texture painted by
## the art pipeline from the map's layout design (organic edges between grass, earth, paving and
## water, one pixel density) instead of a 16px tile stamped on a grid. It answers the SAME
## questions the tiled floor answers — `fill_rect`, `walkway_half_height`, `is_paddy_cell` — so
## the map contracts (bounds match, a dry through-route, no prop standing in water) hold for
## either floor. Purely visual: water collision is `WaterBlockers` under `Collision/`, built from
## the same layout data.

@export var layout: GroundLayoutData = null

var fill_rect: Rect2i:
	get:
		return layout.fill_rect if layout != null else Rect2i()

var walkway_half_height: int:
	get:
		return layout.walkway_half_height if layout != null else 0


func _init() -> void:
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	apply_layout()


## Bind the texture and place it on its painted extent. Called from `_ready`, and safe to call
## on a node that is NOT in the tree (the map tests instantiate scenes without adding them).
func apply_layout() -> void:
	if layout == null:
		return
	texture = layout.texture
	position = Vector2(layout.fill_rect.position * layout.tile_px)


func is_paddy_cell(cell: Vector2i) -> bool:
	return layout != null and layout.is_paddy_cell(cell)


## Flooded in any way — paddy or open water. What a prop must never stand in.
func is_flooded_cell(cell: Vector2i) -> bool:
	return layout != null and (layout.is_paddy_cell(cell) or layout.is_water_cell(cell))

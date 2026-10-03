extends TileMapLayer
class_name PrototypeGround
## PrototypeGround — Aetheria gameplay (prototype visual ground, Phase-03 early visual).
##
## Paints a map's floor + a wall-tile border using the shared prototype TileSet
## (`data/maps/prototype_tileset.tres`, 16px tiles) so maps render with real pixel-art
## TEXTURES, not Polygon2D placeholders. PROTOTYPE art only — a real environment pass
## replaces this later (`06-art-assets.md`). It is purely visual: collision stays on the
## map's static `Collision/Walls` bodies (this layer has no physics).
##
## The painted area is authored as data (`fill_rect` in tile coords) so each map scene sets
## its own extent; the code just stamps atlas tiles. Tile atlas columns in the tileset strip:
##   0 = grass (floor), 1 = path, 2 = wall/edge.

const SOURCE_ID := 0
const TILE_GRASS := Vector2i(0, 0)
const TILE_PATH := Vector2i(1, 0)
const TILE_WALL := Vector2i(2, 0)

## The rectangle of tile cells to paint (in TileMapLayer cell coordinates). Set per map.
@export var fill_rect: Rect2i = Rect2i(0, 0, 30, 20)

## If true, draw a one-cell wall-tile border around `fill_rect` (visual edge).
@export var draw_border: bool = true

## If true, draw a path stripe across the vertical middle of the floor (prototype variety).
@export var draw_path_stripe: bool = true


func _ready() -> void:
	_paint()


func _paint() -> void:
	clear()
	var x0 := fill_rect.position.x
	var y0 := fill_rect.position.y
	var x1 := fill_rect.position.x + fill_rect.size.x
	var y1 := fill_rect.position.y + fill_rect.size.y
	var mid_y := int(floor((y0 + y1) * 0.5))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var tile := TILE_GRASS
			var on_border := draw_border and (x == x0 or x == x1 - 1 or y == y0 or y == y1 - 1)
			if on_border:
				tile = TILE_WALL
			elif draw_path_stripe and y == mid_y:
				tile = TILE_PATH
			set_cell(Vector2i(x, y), SOURCE_ID, tile)

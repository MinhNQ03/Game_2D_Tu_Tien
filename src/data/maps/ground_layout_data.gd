extends Resource
class_name GroundLayoutData
## GroundLayoutData — Aetheria data (a painted map floor and what it means, D-062).
##
## Written by the ground painter (`tools/aetheria_art_pipeline/world/ground.py`) from a map's
## layout design, never by hand: the floor TEXTURE and the facts the game needs about it — the
## painted extent (the same `fill_rect` contract the tiled floor has, pinned against
## `MapData.bounds`), which cells are flooded paddy or open water, and the water BLOCKERS the
## map's collision is built from. One source: the picture and the rules cannot disagree.

@export var id: StringName = &""
@export var texture: Texture2D = null
## The painted extent in TILE cells (the floor texture covers exactly this rect).
@export var fill_rect: Rect2i = Rect2i(0, 0, 0, 0)
@export var tile_px: int = 16
## Rows either side of the map's centre row that the layout keeps dry (the through-route).
@export var walkway_half_height: int = 0
## One byte per cell of `fill_rect`, row-major: 1 = a flooded paddy cell.
@export var paddy_cells: PackedByteArray = PackedByteArray()
## One byte per cell of `fill_rect`, row-major: 1 = open water (stream, pond).
@export var water_cells: PackedByteArray = PackedByteArray()
## The materials the floor is painted with (grass, earth, stone, water, ...), as the painter
## names them — the proof a floor is not one material stamped everywhere.
@export var materials: PackedStringArray = PackedStringArray()
## Polygons (world px) the water blocks walking in; the gaps between them are the crossings.
@export var blockers: Array[PackedVector2Array] = []


func _cell_index(cell: Vector2i) -> int:
	var local := cell - fill_rect.position
	if local.x < 0 or local.y < 0 or local.x >= fill_rect.size.x or local.y >= fill_rect.size.y:
		return -1
	return local.y * fill_rect.size.x + local.x


func is_paddy_cell(cell: Vector2i) -> bool:
	var i := _cell_index(cell)
	return i >= 0 and i < paddy_cells.size() and paddy_cells[i] == 1


func is_water_cell(cell: Vector2i) -> bool:
	var i := _cell_index(cell)
	return i >= 0 and i < water_cells.size() and water_cells[i] == 1


## Why this layout is unusable, or "" (the painter and the scenes are checked against it).
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if texture == null:
		errors.append("the painted floor has no texture")
	elif texture.get_width() != fill_rect.size.x * tile_px \
			or texture.get_height() != fill_rect.size.y * tile_px:
		errors.append("the floor texture does not cover fill_rect exactly")
	var cells := fill_rect.size.x * fill_rect.size.y
	if paddy_cells.size() != cells or water_cells.size() != cells:
		errors.append("the cell maps do not cover fill_rect")
	return errors

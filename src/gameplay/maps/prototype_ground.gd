extends TileMapLayer
class_name PrototypeGround
## PrototypeGround — Aetheria gameplay (the painted map floor).
##
## Paints a map's floor from the **Verdant 00 East Asian Village** 16px tileset
## (`data/maps/east_asian_tileset.tres`) — moss ground (`koke`) with terraced flooded rice
## paddies (`ta` = 田, measured rgb(43,100,109): WATER, not stone) set into it, edged with a
## real 16-mask autotile so each paddy's bund meets the moss with drawn transition tiles
## instead of a hard seam.
##
## WHY THIS REPLACED THE 3-TILE VERSION (D-045). The previous floor had exactly three tiles —
## one grass, one path, one wall — stamped in a flat grid with a single straight stripe across
## the middle. A whole map drawn from one repeated grass tile is what read as bare and
## unfinished, and no amount of UI work could fix it: the floor is most of the screen.
##
## It stays **purely visual** — collision lives on the map's static `Collision/Walls` bodies,
## this layer has no physics — and the painted extent is still authored as data (`fill_rect`),
## so each map scene sets its own size and the code only stamps tiles.
##
## DETERMINISTIC (D-040): tile variety comes from a hash of the cell coordinate, **never**
## from `rand*()`. The same map always paints identically, which is what keeps a screenshot,
## a save and a reloaded save in agreement — and Phase 07 is not allowed to introduce an RNG
## (the seeded stream seam belongs to Phase 08).

## Atlas source ids, matching `east_asian_tileset.tres`.
const SOURCE_GROUND := 0
const SOURCE_AUTOTILE := 1

## Ground sheet layout, read from the pack's own `tiles.json` rather than eyeballed:
## columns 0-3 are `koke_1..4` (moss), columns 4-7 are `ta_1..4` (flooded paddy water).
const KOKE_COLUMNS := 4
const TA_FIRST_COLUMN := 4
const TA_COLUMNS := 4

## Cardinal neighbour bits for the autotile mask, as the pack defines them.
const MASK_N := 1
const MASK_E := 4
const MASK_S := 16
const MASK_W := 64

## mask -> atlas coordinate in `v16_ta_on_koke.png`, taken from `tiles.json`.
##
## Only the 16 CARDINAL masks are used. The pack ships a full 47-mask set that also encodes
## diagonal neighbours, but the extra 31 need the corner bits to be correct or they place
## visibly wrong corners — and that cannot be verified here (Godot is not runnable locally,
## D-009). The 16 cardinal tiles are a complete, self-consistent subset: every edge and corner
## of a rectangular courtyard is covered, which is exactly what this map needs. The remaining
## tiles stay available in the TileSet for a later pass that can be checked on screen.
const AUTOTILE_BY_MASK := {
	0: Vector2i(0, 0),    # single
	MASK_N: Vector2i(1, 0),
	MASK_E: Vector2i(2, 0),
	MASK_N | MASK_E: Vector2i(3, 0),
	MASK_S: Vector2i(5, 0),
	MASK_N | MASK_S: Vector2i(6, 0),
	MASK_E | MASK_S: Vector2i(7, 0),
	MASK_N | MASK_E | MASK_S: Vector2i(8, 0),
	MASK_W: Vector2i(1, 1),
	MASK_N | MASK_W: Vector2i(2, 1),
	MASK_E | MASK_W: Vector2i(3, 1),
	MASK_N | MASK_E | MASK_W: Vector2i(4, 1),
	MASK_S | MASK_W: Vector2i(6, 1),
	MASK_N | MASK_S | MASK_W: Vector2i(7, 1),
	MASK_E | MASK_S | MASK_W: Vector2i(8, 1),
	MASK_N | MASK_E | MASK_S | MASK_W: Vector2i(9, 1),
}

## The rectangle of tile cells to paint (in TileMapLayer cell coordinates). Set per map.
@export var fill_rect: Rect2i = Rect2i(0, 0, 30, 20)

## Half-height of the clear moss walkway down the middle of the map, in cells. The paddies sit
## OUTSIDE it, so the walkway is what the player actually travels along.
@export var walkway_half_height: int = 3

## Size of each terraced paddy block, in cells, and the gap of moss between blocks.
@export var paddy_block_width: int = 7
@export var paddy_block_height: int = 5
@export var paddy_gap: int = 3

## Inset from the map edge before the paddy terraces begin.
@export var paddy_margin: int = 3


func _ready() -> void:
	_paint()


func _paint() -> void:
	clear()
	var x0 := fill_rect.position.x
	var y0 := fill_rect.position.y
	var x1 := x0 + fill_rect.size.x
	var y1 := y0 + fill_rect.size.y
	for y in range(y0, y1):
		for x in range(x0, x1):
			var cell := Vector2i(x, y)
			if is_paddy_cell(cell):
				_paint_paddy(cell)
			else:
				_paint_moss(cell)


## Moss, with one of four authored variants chosen deterministically per cell. Four variants
## break up the repetition that made a single-tile floor look like graph paper.
func _paint_moss(cell: Vector2i) -> void:
	var column := variant_for_cell(cell, KOKE_COLUMNS)
	set_cell(cell, SOURCE_GROUND, Vector2i(column, 0))


## A flooded paddy cell. The INTERIOR gets a solid `ta` water variant; a cell with any moss
## neighbour gets the autotile tile for that exact neighbour pattern, so the paddy's bund
## (the raised earth edge) is drawn art rather than a hard rectangular cut.
func _paint_paddy(cell: Vector2i) -> void:
	var mask := 0
	if is_paddy_cell(cell + Vector2i(0, -1)):
		mask |= MASK_N
	if is_paddy_cell(cell + Vector2i(1, 0)):
		mask |= MASK_E
	if is_paddy_cell(cell + Vector2i(0, 1)):
		mask |= MASK_S
	if is_paddy_cell(cell + Vector2i(-1, 0)):
		mask |= MASK_W
	var fully_enclosed := mask == (MASK_N | MASK_E | MASK_S | MASK_W)
	if fully_enclosed:
		var column := TA_FIRST_COLUMN + variant_for_cell(cell, TA_COLUMNS)
		set_cell(cell, SOURCE_GROUND, Vector2i(column, 0))
		return
	var coord: Vector2i = AUTOTILE_BY_MASK.get(mask, AUTOTILE_BY_MASK[0])
	set_cell(cell, SOURCE_AUTOTILE, coord)


## Is this cell a flooded paddy? Pure function of the authored layout, so it can be asked
## about a NEIGHBOUR cell (including one outside `fill_rect`) while computing a mask.
##
## LAYOUT, and why it changed: the first version ran a wide band of this material straight
## across the middle of the map and called it a stone courtyard. It is not stone — `ta` is
## **田, a flooded rice paddy**, measured at rgb(43,100,109), and the shipped map rendered as a
## cross of open water through the village. The name was read instead of the pixels, which is
## exactly what L-021 exists to prevent.
##
## So the material is now used for what it IS: discrete terraced paddy BLOCKS set back from the
## map edge, in rows above and below a clear moss walkway, with moss gaps between them for the
## bunds to read. The player always has dry ground to travel on, and flooded terraces either
## side is what an East Asian village floor actually looks like.
## PUBLIC because the layout makes two promises a test has to be able to check — a dry central
## walkway and no paddy on the wall ring — and a test reaching for a `_`-prefixed method in
## another file is a cross-file private access the linter flags (GD002).
func is_paddy_cell(cell: Vector2i) -> bool:
	if paddy_block_width <= 0 or paddy_block_height <= 0:
		return false
	var centre_y := fill_rect.position.y + int(fill_rect.size.y * 0.5)
	# The central walkway is never flooded.
	if absi(cell.y - centre_y) <= walkway_half_height:
		return false
	# Stay inside the authored extent, inset by the margin, so a paddy never touches the wall.
	var x0 := fill_rect.position.x + paddy_margin
	var y0 := fill_rect.position.y + paddy_margin
	var x1 := fill_rect.position.x + fill_rect.size.x - paddy_margin
	var y1 := fill_rect.position.y + fill_rect.size.y - paddy_margin
	if cell.x < x0 or cell.x >= x1 or cell.y < y0 or cell.y >= y1:
		return false
	# Tile the region with block+gap cells; a cell is flooded only inside a block.
	var period_x := paddy_block_width + paddy_gap
	var period_y := paddy_block_height + paddy_gap
	return posmod(cell.x - x0, period_x) < paddy_block_width \
		and posmod(cell.y - y0, period_y) < paddy_block_height


## Flooded in any way (the tiled floor only floods paddies). The question a prop placement asks
## of either floor (`PaintedGround.is_flooded_cell`).
func is_flooded_cell(cell: Vector2i) -> bool:
	return is_paddy_cell(cell)


## A stable per-cell variant index in [0, count).
##
## A cheap integer hash, NOT `randi()`: the map must paint identically every run (D-040 — no
## RNG before Phase 08's seeded seam). The two odd multipliers decorrelate x from y so the
## variants do not fall into visible diagonal stripes, which is what a plain `(x + y) % count`
## produces.
##
## PUBLIC because the determinism is a contract worth asserting, and a test reaching for a
## `_`-prefixed helper in another file is a cross-file private access the linter flags (GD002).
static func variant_for_cell(cell: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	var h := cell.x * 73856093 ^ cell.y * 19349663
	return absi(h) % count

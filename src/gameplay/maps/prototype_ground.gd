extends TileMapLayer
class_name PrototypeGround
## PrototypeGround — Aetheria gameplay (the painted map floor).
##
## Paints a map's floor from the **Verdant 00 East Asian Village** 16px tileset
## (`data/maps/east_asian_tileset.tres`) — moss ground (`koke`) with a stone courtyard
## (`ta`) laid over it, edged with a real 16-mask autotile so the stone meets the moss with
## drawn transition tiles instead of a hard seam.
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
## columns 0-3 are `koke_1..4` (moss), columns 4-7 are `ta_1..4` (cut stone).
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

## Width of the stone avenue running east-west across the map, in cells. The avenue is what
## gives the courtyard a readable axis instead of an undifferentiated field.
@export var avenue_half_height: int = 2

## Half-extent of the stone plaza at the map centre, in cells. 0 disables it.
@export var plaza_half_width: int = 7
@export var plaza_half_height: int = 5


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
			if _is_stone(cell):
				_paint_stone(cell)
			else:
				_paint_moss(cell)


## Moss, with one of four authored variants chosen deterministically per cell. Four variants
## break up the repetition that made a single-tile floor look like graph paper.
func _paint_moss(cell: Vector2i) -> void:
	var column := _variant(cell, KOKE_COLUMNS)
	set_cell(cell, SOURCE_GROUND, Vector2i(column, 0))


## Stone. The INTERIOR gets a solid `ta` variant; a cell with any moss neighbour gets the
## autotile tile for that exact neighbour pattern, so the courtyard edge is drawn art rather
## than a hard rectangular cut.
func _paint_stone(cell: Vector2i) -> void:
	var mask := 0
	if _is_stone(cell + Vector2i(0, -1)):
		mask |= MASK_N
	if _is_stone(cell + Vector2i(1, 0)):
		mask |= MASK_E
	if _is_stone(cell + Vector2i(0, 1)):
		mask |= MASK_S
	if _is_stone(cell + Vector2i(-1, 0)):
		mask |= MASK_W
	var fully_enclosed := mask == (MASK_N | MASK_E | MASK_S | MASK_W)
	if fully_enclosed:
		var column := TA_FIRST_COLUMN + _variant(cell, TA_COLUMNS)
		set_cell(cell, SOURCE_GROUND, Vector2i(column, 0))
		return
	var coord: Vector2i = AUTOTILE_BY_MASK.get(mask, AUTOTILE_BY_MASK[0])
	set_cell(cell, SOURCE_AUTOTILE, coord)


## Is this cell part of the stone courtyard? Pure function of the authored layout, so it can
## be asked about a NEIGHBOUR cell (including one outside `fill_rect`) while computing a mask.
func _is_stone(cell: Vector2i) -> bool:
	var centre_x := fill_rect.position.x + int(fill_rect.size.x * 0.5)
	var centre_y := fill_rect.position.y + int(fill_rect.size.y * 0.5)
	if absi(cell.y - centre_y) <= avenue_half_height:
		return true
	if plaza_half_width > 0 and plaza_half_height > 0:
		if absi(cell.x - centre_x) <= plaza_half_width \
				and absi(cell.y - centre_y) <= plaza_half_height:
			return true
	return false


## A stable per-cell variant index in [0, count).
##
## A cheap integer hash, NOT `randi()`: the map must paint identically every run (D-040 — no
## RNG before Phase 08's seeded seam). The two odd multipliers decorrelate x from y so the
## variants do not fall into visible diagonal stripes, which is what a plain `(x + y) % count`
## produces.
static func _variant(cell: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	var h := cell.x * 73856093 ^ cell.y * 19349663
	return absi(h) % count

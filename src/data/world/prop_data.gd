extends Resource
class_name PropData
## PropData — Aetheria data (one world prop, D-062). Written by the art pipeline
## (`build.py props`), or by the stdlib generator for the decor it still draws
## (`tools/gen_prototype_assets.py`, footprint MEASURED from the drawn pixels, D-063) — never by
## hand: the sprite the prop wears, where its ORIGIN (the centre of its front base — the line the
## depth sort compares) falls in that sprite, and the solid footprint a body cannot walk through,
## in world px relative to the origin. Both write it through `aetheria_art.sheet`.

@export var id: StringName = &""
@export var texture: Texture2D = null
## The origin's pixel inside `texture` (from its top-left).
@export var origin: Vector2 = Vector2.ZERO
## The solid base, relative to the origin. Zero size = walk-through (grass, a hanging thing).
@export var footprint: Rect2 = Rect2()
## The base is the ELLIPSE inscribed in `footprint` (a pool in a ring of stones): its rectangle
## would stop a body at the diagonals well before it touched anything drawn (D-063).
@export var footprint_round: bool = false
## Moves in the wind (wears the shared sway material).
@export var sways: bool = false

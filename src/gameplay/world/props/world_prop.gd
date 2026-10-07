extends StaticBody2D
class_name WorldProp
## WorldProp — Aetheria gameplay (a solid thing standing in the world, D-062).
##
## A house, a tree, a fence, a well: the art pipeline's sprite drawn with its ORIGIN on this
## node — the centre of its front base, so the y-sort puts a figure behind the house when it is
## behind the front wall — and a collision rectangle for its footprint, from the SAME
## `PropData`. It lives in the y-sorted `Visual/Decor` like every prop, and is solid like a wall.

const SWAY_SHADER := preload("res://src/presentation/ambient/pixel_sway.gdshader")

@export var prop: PropData = null

var _sprite: Sprite2D = null

## ONE sway material per prop texture, shared by every instance (the phase comes from world
## position in the shader, not from per-instance state — the same rule as the grass and trees).
static var _sway_materials: Dictionary = {}


func _ready() -> void:
	build()


## Build the sprite and the footprint from `prop`. Safe to call off-tree (the map tests
## instantiate scenes without adding them) and idempotent.
func build() -> void:
	for child in get_children():
		child.free()
	_sprite = null
	if prop == null or prop.texture == null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = prop.texture
	_sprite.centered = false
	_sprite.offset = -prop.origin
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if prop.sways:
		_sprite.material = sway_material(prop)
	add_child(_sprite)
	var footprint := PropBody.make_footprint(prop)
	if footprint != null:
		add_child(footprint)


func sprite() -> Sprite2D:
	return _sprite


## The canopy sways above the trunk: the shear is zero at `pivot_row` (where the canopy meets
## the trunk, about half way up a broadleaf) and grows to the crown.
static func sway_material(data: PropData) -> ShaderMaterial:
	var key := data.texture.resource_path
	if _sway_materials.has(key):
		return _sway_materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SWAY_SHADER
	var pivot := roundf(data.origin.y * 0.55)
	mat.set_shader_parameter("pivot_row", pivot)
	mat.set_shader_parameter("span_rows", pivot)
	mat.set_shader_parameter("bend", 2.4)
	mat.set_shader_parameter("wind_px", 1.5)
	mat.set_shader_parameter("wind_hz", 0.2)
	mat.set_shader_parameter("gust_px", 1.5)
	_sway_materials[key] = mat
	return mat

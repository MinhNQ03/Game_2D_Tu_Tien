extends Node
class_name WindField
## WindField — Aetheria presentation (the map's one door into its ambient motion, Phase 12).
##
## The ambient wind itself needs no script: `pixel_sway` runs it from TIME and world position.
## What needs a script is an EVENT — a breakthrough's release pushing the grass flat in a ring
## around the cultivator, and (P15) a Phong technique's gust. Those two are the second-use pair
## that earns this node (M-14.2).
##
## It lives in the map scene (`Visual/WindField`) and joins the `wind_field` group, so whoever
## releases a force asks `get_tree().get_first_node_in_group(WindField.GROUP)` — there is one
## map at a time — without knowing the map's structure. It sets the impulse uniforms on every
## distinct sway material of the map (a handful: one per material kind, shared by all instances)
## and advances the wave's age for its short life, then switches itself off. PRESENTATION ONLY:
## the wind moves pictures, never bodies.

const GROUP := &"wind_field"
const SWAY_SHADER := "res://src/presentation/ambient/pixel_sway.gdshader"

## How long one impulse is animated before its uniforms are cleared.
const IMPULSE_SECONDS := 1.8

var _materials: Array[ShaderMaterial] = []
var _age: float = 0.0
var _active: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)
	var visual := get_parent()
	if visual != null:
		_collect(visual)


## Every distinct sway material under `node` (deduplicated: the grass of a whole map shares one).
func _collect(node: Node) -> void:
	for child in node.get_children():
		var item := child as CanvasItem
		if item != null:
			var material := item.material as ShaderMaterial
			if material != null and material.shader != null \
					and material.shader.resource_path == SWAY_SHADER \
					and not _materials.has(material):
				_materials.append(material)
		_collect(child)


func material_count() -> int:
	return _materials.size()


## Push one wave of force out from `origin` (world space): `strength_px` at the props nearest the
## origin, fading to nothing at `radius_px`. A new impulse replaces one still in flight.
func impulse(origin: Vector2, strength_px: float, radius_px: float = 220.0) -> void:
	_age = 0.0
	_active = true
	for material in _materials:
		material.set_shader_parameter(&"impulse_origin", origin)
		material.set_shader_parameter(&"impulse_strength", strength_px)
		material.set_shader_parameter(&"impulse_radius", radius_px)
		material.set_shader_parameter(&"impulse_age", 0.0)
	set_process(true)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	advance(delta)


## Advance the wave by `delta` seconds (public for tests, like every presentation clock here).
func advance(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= IMPULSE_SECONDS:
		_active = false
		set_process(false)
		for material in _materials:
			material.set_shader_parameter(&"impulse_strength", 0.0)
		return
	for material in _materials:
		material.set_shader_parameter(&"impulse_age", _age)

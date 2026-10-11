extends PointLight2D
class_name AmbienceLight
## AmbienceLight — Aetheria presentation (one light a map owns, D-073 §3).
##
## A lantern on its post, the glow of a broken vein. It says only WHAT it is (`role`) and where
## it stands; `MapAmbience` decides whether it burns, how brightly and in what colour, from the
## ambience the map is wearing. Off by default: by day a lantern lights nothing.
##
## The falloff is BANDED, not smooth — three flat rings — so a pool of light reads in the same
## language as the sprites it falls on (`aetheria_style.yaml` §10: steps, not gradients).

const ROLE_LANTERN := &"lantern"
const ROLE_VEIN := &"vein"
const TEXTURE_SIZE := 96

## What kind of light this is: `ROLE_LANTERN` or `ROLE_VEIN`.
@export var role: StringName = ROLE_LANTERN
## The radius of its pool, in world pixels.
@export_range(16.0, 240.0) var radius_px: float = 72.0

static var _banded: Texture2D = null


func _ready() -> void:
	texture = banded_texture()
	texture_scale = radius_px * 2.0 / float(TEXTURE_SIZE)
	blend_mode = Light2D.BLEND_MODE_ADD
	shadow_enabled = false
	enabled = false
	energy = 0.0


## The one falloff texture every ambience light shares: three flat bands.
static func banded_texture() -> Texture2D:
	if _banded != null:
		return _banded
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = PackedFloat32Array([0.0, 0.34, 0.62, 0.86])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.62, 0.62, 0.62, 1),
		Color(0.30, 0.30, 0.30, 1), Color(0, 0, 0, 1)])
	var made := GradientTexture2D.new()
	made.gradient = gradient
	made.width = TEXTURE_SIZE
	made.height = TEXTURE_SIZE
	made.fill = GradientTexture2D.FILL_RADIAL
	made.fill_from = Vector2(0.5, 0.5)
	made.fill_to = Vector2(1.0, 0.5)
	_banded = made
	return _banded

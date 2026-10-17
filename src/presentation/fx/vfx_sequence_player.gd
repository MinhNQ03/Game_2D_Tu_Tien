extends Sprite2D
class_name VfxSequencePlayer
## VfxSequencePlayer — Aetheria presentation (plays one rendered VFX sequence once).
##
## The rendered layer of an effect (experience upgrade): a `VfxSequenceData` strip played ONCE
## where a gameplay cue says something happened — a sitting begins, a bolt strikes, a vein
## gives way. It is told WHEN and WHERE; it never decides either, never writes simulation time
## and never touches state a rule reads (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §3, §10).
##
## Cheap by construction: one Sprite2D, frames chosen by `frame` over `hframes` (no texture
## change per tick), `_process` on only while it plays, hidden and idle when done — so the
## owner keeps one (or a small fixed set) and replays it instead of creating a node per effect.
## Pixel art: nearest filtering, drawn at the world's own density.

signal finished()

var _data: VfxSequenceData = null
var _age := -1.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	visible = false
	set_process(false)


## Load a sequence (null clears it). Does not play it.
func setup(data: VfxSequenceData) -> void:
	_data = data
	_age = -1.0
	visible = false
	set_process(false)
	if data == null or not data.validation_errors().is_empty():
		if data != null:
			push_error("[vfx] refusing an invalid sequence: %s" % str(data.validation_errors()))
		_data = null
		texture = null
		return
	texture = data.texture
	hframes = data.frame_count()
	vframes = 1
	frame = 0
	# The anchor pixel sits on this node's origin: a cue's point is the effect's point.
	offset = -Vector2(data.anchor)
	if data.additive:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
	else:
		material = null


## Play from the first frame, standing on `local_position` (in the parent's space). Replaying
## while playing restarts it: a second strike is a second burst, not a queued one.
func play_at(local_position: Vector2) -> void:
	if _data == null:
		return
	position = local_position.round()
	_age = 0.0
	frame = 0
	visible = true
	set_process(true)


func is_playing() -> bool:
	return _age >= 0.0


func sequence() -> VfxSequenceData:
	return _data


func stop() -> void:
	_age = -1.0
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _data == null or _age < 0.0:
		set_process(false)
		return
	_age += delta
	var index := int(_age * _data.fps)
	if index >= hframes:
		stop()
		finished.emit()
		return
	if index != frame:
		frame = index

extends Resource
class_name VfxSequenceData
## VfxSequenceData — Aetheria data (one rendered VFX frame sequence, experience upgrade).
##
## A horizontal strip of frames (`texture`), written with this resource by the art pipeline
## (`tools/aetheria_art_pipeline/build.py vfx`, from `designs/vfx.yaml`). The frame COUNT is
## derived from the texture's width, never authored beside it — like every sheet. Presentation
## data only: how fast it plays is never gameplay time, and nothing in the rules reads it.

@export var id: StringName = &""
@export var texture: Texture2D = null
## One frame's size in world pixels (one art pixel = one world pixel).
@export var frame_size: Vector2i = Vector2i.ZERO
## The frame pixel that sits on the point the cue names (feet, a palm, a strike).
@export var anchor: Vector2i = Vector2i.ZERO
@export var fps: float = 12.0
## Light that brightens what is under it (additive), or ordinary paint.
@export var additive: bool = true


func frame_count() -> int:
	if texture == null or frame_size.x <= 0:
		return 0
	return int(texture.get_width() / frame_size.x)


func duration() -> float:
	return frame_count() / fps if fps > 0.0 else 0.0


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("a VFX sequence has no id")
	if texture == null:
		errors.append("'%s' has no texture" % id)
		return errors
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("'%s' has no frame size" % id)
		return errors
	if texture.get_width() % frame_size.x != 0:
		errors.append("'%s': the strip (%d px) is not a whole number of %d px frames"
			% [id, texture.get_width(), frame_size.x])
	if texture.get_height() != frame_size.y:
		errors.append("'%s': the strip is %d px tall, its frames %d"
			% [id, texture.get_height(), frame_size.y])
	if frame_count() < 2:
		errors.append("'%s' has fewer than two frames: nothing moves" % id)
	if anchor.x < 0 or anchor.y < 0 or anchor.x >= frame_size.x or anchor.y >= frame_size.y:
		errors.append("'%s': the anchor %s is outside the frame" % [id, anchor])
	if fps <= 0.0:
		errors.append("'%s' plays at %s fps" % [id, fps])
	return errors

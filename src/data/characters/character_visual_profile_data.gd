extends Resource
class_name CharacterVisualProfileData
## CharacterVisualProfileData — Aetheria data (a character's VISUAL definition).
##
## The PRESENTATION-side definition of how a character looks (Phase 05 early art pipeline,
## D-026). It is referenced by `CharacterTemplateData.sprite_set_ref` and consumed ONLY by the
## presentation layer (`CharacterVisualComponent`). It carries NO gameplay/domain data — a
## `CharacterState` never holds a sprite (`docs/CHARACTER_SYSTEM.md` §3 three-tier partition:
## presentation tier is never serialized). Swapping a character's look is editing this data,
## not code.
##
## The prototype pipeline uses a horizontal sprite SHEET of directional frames at a fixed
## cell size (`docs/CHARACTER_ART_BIBLE.md`): one row, N columns, cell = `frame_size`. The
## component picks a column by facing direction. Idle vs. walk sheets are separate textures
## (both optional beyond idle in Phase 05 — walk falls back to idle if absent). Attack/other
## states are deferred to the combat phase.

## Frames are laid out left→right in this cardinal order within each sheet.
enum Direction { DOWN, UP, LEFT, RIGHT }

const DIRECTION_COUNT := 4

## Stable id for this profile (so a template/preview can reference it + a test can assert it).
@export var id: StringName = &""

## The idle sprite sheet (REQUIRED): one row of `DIRECTION_COUNT` frames, each `frame_size`.
@export var idle_sheet: Texture2D = null

## The walk sprite sheet (OPTIONAL in Phase 05): same layout as idle. If null, the component
## shows the idle frame while moving (documented fallback — no fake animation).
@export var walk_sheet: Texture2D = null

## The pixel size of ONE directional frame (the art baseline, e.g. 16x24). Collision footprint
## is independent of this (anchored at the feet) — see `docs/CHARACTER_ART_BIBLE.md`.
@export var frame_size: Vector2i = Vector2i(16, 24)

## Y offset (px) from the node origin to the sprite's TOP so the character's FEET sit on the
## origin (anchor-at-feet). Default places a `frame_size.y` tall sprite with its bottom at the
## origin. Presentation-only.
@export var anchor_offset: Vector2 = Vector2.ZERO


func is_valid() -> bool:
	return validation_errors().is_empty()


## Validate at the boundary (content from disk):
##   - id non-empty
##   - idle_sheet present
##   - frame_size positive
##   - idle_sheet width is DIRECTION_COUNT whole frames wide + exactly frame_size tall
##   - walk_sheet (if present) matches the same layout
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be non-empty")
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("frame_size must be positive (got %s)" % str(frame_size))
		return errors  # further sheet checks need a valid frame size
	if idle_sheet == null:
		errors.append("idle_sheet is required")
	else:
		errors.append_array(_sheet_errors("idle_sheet", idle_sheet))
	if walk_sheet != null:
		errors.append_array(_sheet_errors("walk_sheet", walk_sheet))
	return errors


## A sheet must be exactly `DIRECTION_COUNT` frames wide and one frame tall.
func _sheet_errors(label: String, sheet: Texture2D) -> Array[String]:
	var out: Array[String] = []
	var expected_w := frame_size.x * DIRECTION_COUNT
	if sheet.get_width() != expected_w:
		out.append("%s width %d != %d (%d frames of %dpx)" % [
			label, sheet.get_width(), expected_w, DIRECTION_COUNT, frame_size.x])
	if sheet.get_height() != frame_size.y:
		out.append("%s height %d != frame height %d" % [
			label, sheet.get_height(), frame_size.y])
	return out


## Map an input/velocity vector to a facing Direction (8-way movement collapses to the nearest
## cardinal — `docs/CHARACTER_ART_BIBLE.md`: 4-direction art, horizontal wins ties). Returns
## DOWN for a zero vector (a sensible resting facing).
static func direction_for_vector(v: Vector2) -> int:
	if v == Vector2.ZERO:
		return Direction.DOWN
	if absf(v.x) >= absf(v.y):
		return Direction.RIGHT if v.x > 0.0 else Direction.LEFT
	return Direction.DOWN if v.y > 0.0 else Direction.UP

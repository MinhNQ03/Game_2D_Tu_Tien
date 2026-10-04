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
## SHEET LAYOUT (D-046 — changed from the Phase-05 single-pose layout). A sheet is a GRID:
##   * one ROW per cardinal direction, in `Direction` order (DOWN, UP, LEFT, RIGHT),
##   * `frame_count` COLUMNS of animation frames,
##   * cell = `frame_size`.
## So `width = frame_size.x * frames` and `height = frame_size.y * DIRECTION_COUNT`, and the
## frame count is DERIVED from the texture width rather than authored twice (one less field
## that can drift out of sync with the art — L-014).
##
## The old layout was one row of 4 directional frames, i.e. exactly ONE frame per direction.
## Every profile also left `walk_sheet` null, so a character slid across the floor without
## ever animating. The grid exists so walking actually looks like walking.
##
## Idle vs. walk are separate textures and may have DIFFERENT frame counts (an idle breath
## needs fewer frames than a stride). `walk_sheet` stays optional: when absent the component
## shows the idle animation while moving — a documented fallback, not a fake.

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

## The pixel size of ONE animation frame (the art baseline, 32x48 since D-046). Collision
## footprint is independent of this (anchored at the feet) — see `docs/CHARACTER_ART_BIBLE.md`.
@export var frame_size: Vector2i = Vector2i(32, 48)

## Seconds per animation frame. Authored per profile so an elder can shuffle and a youth can
## stride without a code change. Must be > 0; a single-frame sheet ignores it.
@export var frame_duration: float = 0.16

## Y offset (px) from the node origin to the sprite's TOP so the character's FEET sit on the
## origin (anchor-at-feet). Default places a `frame_size.y` tall sprite with its bottom at the
## origin. Presentation-only.
@export var anchor_offset: Vector2 = Vector2.ZERO


func is_valid() -> bool:
	return validation_errors().is_empty()


## Validate at the boundary (content from disk):
##   - id non-empty
##   - frame_size positive, frame_duration positive
##   - idle_sheet present
##   - every sheet is a whole number of frames wide and exactly DIRECTION_COUNT rows tall
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be non-empty")
	if frame_duration <= 0.0:
		errors.append("frame_duration must be > 0 (got %f)" % frame_duration)
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


## A sheet must be a whole number of frames wide and exactly DIRECTION_COUNT frames tall.
func _sheet_errors(label: String, sheet: Texture2D) -> Array[String]:
	var out: Array[String] = []
	var w := sheet.get_width()
	var h := sheet.get_height()
	if w <= 0 or w % frame_size.x != 0:
		out.append("%s width %d is not a whole multiple of frame width %d" % [
			label, w, frame_size.x])
	var expected_h := frame_size.y * DIRECTION_COUNT
	if h != expected_h:
		out.append("%s height %d != %d (%d direction rows of %dpx)" % [
			label, h, expected_h, DIRECTION_COUNT, frame_size.y])
	return out


## How many animation frames `sheet` holds, derived from its width. 0 for a null/unusable
## sheet so a caller can never divide by it or index past the art.
func frame_count_of(sheet: Texture2D) -> int:
	if sheet == null or frame_size.x <= 0:
		return 0
	var w := sheet.get_width()
	if w <= 0 or w % frame_size.x != 0:
		return 0
	# Float divide then cast: the modulo above already proved the division is exact, and this
	# avoids the integer-division warning that this project treats as an error.
	return int(float(w) / float(frame_size.x))


## Map an input/velocity vector to a facing Direction (8-way movement collapses to the nearest
## cardinal — `docs/CHARACTER_ART_BIBLE.md`: 4-direction art, horizontal wins ties). Returns
## DOWN for a zero vector (a sensible resting facing).
static func direction_for_vector(v: Vector2) -> int:
	if v == Vector2.ZERO:
		return Direction.DOWN
	if absf(v.x) >= absf(v.y):
		return Direction.RIGHT if v.x > 0.0 else Direction.LEFT
	return Direction.DOWN if v.y > 0.0 else Direction.UP

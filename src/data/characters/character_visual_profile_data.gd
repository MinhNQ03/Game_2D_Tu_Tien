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

## The animation names a sheet is drawn and anchored under (the generator's names). The
## component reports which one is showing, so an anchor lookup needs no knowledge of sheets.
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_ATTACK := &"attack"
const ANIM_MEDITATE := &"meditate"
const ANIM_CAST := &"cast"
## The sword cut (D-063 A3): the same attack lifecycle as `ANIM_ATTACK`, a different body —
## coil → cut → follow-through → guard, drawn only for sword-wielding looks.
const ANIM_SLASH := &"slash"
const ANIM_TALK := &"talk"

## The shared anchor vocabulary (`CharacterAnchorData`): the striking point, the core, and
## the sword tip (D-063 A3).
const POINT_PALM := &"palm"
const POINT_CORE := &"core"
const POINT_BLADE := &"blade"

## Stable id for this profile (so a template/preview can reference it + a test can assert it).
@export var id: StringName = &""

## The idle sprite sheet (REQUIRED): one row of `DIRECTION_COUNT` frames, each `frame_size`.
@export var idle_sheet: Texture2D = null

## The walk sprite sheet (OPTIONAL in Phase 05): same layout as idle. If null, the component
## shows the idle frame while moving (documented fallback — no fake animation).
@export var walk_sheet: Texture2D = null

## The basic-attack sprite sheet (OPTIONAL, D-056): same GRID layout as the others — one row
## per direction, N animation columns — but played as a ONE-SHOT, non-looping ACTION rather
## than a locomotion loop (`docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` §2/§4).
##
## Optional because an entity that cannot attack has no use for one (a prop, a preview
## archetype), and because the component must degrade to locomotion rather than fail. But
## OPTIONAL IS NOT A LICENCE TO LEAVE IT NULL EVERYWHERE: `walk_sheet` shipped null in all four
## profiles for a whole phase, which made the documented idle fallback the only path that ever
## ran — an optional field no shipped data authors is a no-op with documentation (L-029). Every
## profile belonging to an entity that attacks authors this sheet.
##
## Its frames read as anticipation → contact → recovery. The COLUMN COUNT IS FREE: the player's
## is 8 and the mist wolf's is 6, derived from texture width like every other sheet, and the
## action layer maps gameplay progress across however many there are.
@export var attack_sheet: Texture2D = null

## The MEDITATION sheet (OPTIONAL, Phase 12): the seated cultivation pose — the descent into the
## seat, then one slow breath. Played as an ACTION (it out-ranks locomotion) whose progress the
## cultivation presentation drives: the first column is the descent, the rest the breath loop.
## Authored by every cultivator archetype; a creature has none.
@export var meditate_sheet: Texture2D = null

## The CAST sheet (OPTIONAL, Phase 15): one action, four phases, two columns each — the seal
## gathered at the chest, raised and held, the arm driven out, the settle. The cast presentation
## maps PREPARE / CHANNEL / RELEASE / RECOVER onto its quarters, whatever each phase's duration.
@export var cast_sheet: Texture2D = null

## The TALK sheet (OPTIONAL, Phase 17): a short conversational gesture — a hand lifted in
## greeting and lowered — played as a one-shot `talk` action when the character is spoken to.
## Same grid as every other sheet. A look without it keeps its idle when spoken to.
@export var talk_sheet: Texture2D = null

## The SWORD-CUT sheet (OPTIONAL, D-063 A3): the same GRID layout as the attack sheet — one
## row per direction, N animation columns — played as the one-shot body of a `slash`
## `AttackData.body_action`. Only sword-wielding looks author it; a profile without it falls
## back to the `attack` sheet for a slash, so an enemy or NPC is never left without a body.
@export var slash_sheet: Texture2D = null

## The pixel size of ONE animation frame (the art baseline, 32x48 since D-046). Collision
## footprint is independent of this (anchored at the feet) — see `docs/CHARACTER_ART_BIBLE.md`.
@export var frame_size: Vector2i = Vector2i(32, 48)

## Seconds per IDLE frame (and per walk frame when `stride_px` is 0). Authored per profile so an
## elder can breathe slower than a youth without a code change. Must be > 0; a single-frame
## sheet ignores it.
@export var frame_duration: float = 0.16

## Ground distance (px) the body covers in ONE full walk cycle (D-057B). When > 0 the walk is
## clocked by DISTANCE, not time: the component measures how far its own origin actually moved
## and advances the stride by that, so the feet cadence follows the real speed — a slowed or
## wall-blocked character slows or stops its stride instead of treading air at full cadence
## (the sliding-feet defect, `MOTION_DESIGN_CONTRACT.md` M-3.3/M-3.5). A remote character
## rendered from a position stream gets the right cadence for free, because the clock IS the
## position. 0 keeps the time-clocked walk (a preview figure that never moves).
@export var stride_px: float = 0.0

## The walk columns whose feet are close enough to the idle stance to ENTER or LEAVE the walk on
## (D-057B). The walk starts on the first of them (a weight shift onto one foot, not a leap into
## a full stride) and, when the character stops on any other column, the stride finishes to the
## next one before the idle takes over — the planted foot completes its step instead of the legs
## snapping together. Empty: start on column 0 and stop at once (a quadruped's four-beat gait
## has no feet-together frame, and a leg snap of 3px reads as a stop).
@export var walk_rest_columns: PackedInt32Array = PackedInt32Array()

## Where named body points are on every drawn frame (`CharacterAnchorData`). OPTIONAL — a prop
## or a preview has no use for one — but every profile of an entity that ATTACKS authors it,
## because its strike effect starts from the striking point (the same rule that made the
## attack sheet mandatory for attackers, L-029).
@export var anchors: CharacterAnchorData = null

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
	if attack_sheet != null:
		errors.append_array(_sheet_errors("attack_sheet", attack_sheet))
	if meditate_sheet != null:
		errors.append_array(_sheet_errors("meditate_sheet", meditate_sheet))
	if cast_sheet != null:
		errors.append_array(_sheet_errors("cast_sheet", cast_sheet))
	if slash_sheet != null:
		errors.append_array(_sheet_errors("slash_sheet", slash_sheet))
	if talk_sheet != null:
		errors.append_array(_sheet_errors("talk_sheet", talk_sheet))
	if stride_px < 0.0:
		errors.append("stride_px must be >= 0 (got %f)" % stride_px)
	var walk_frames := frame_count_of(walk_sheet)
	for column in walk_rest_columns:
		if column < 0 or column >= walk_frames:
			errors.append("walk_rest_columns holds %d, outside the %d-frame walk sheet"
				% [column, walk_frames])
	if anchors != null:
		errors.append_array(_anchor_errors())
	return errors


## The anchors must be measured in THIS profile's cell, and every anim they name must cover
## exactly the frames its sheet holds — an anchor set drawn for a 6-frame idle bound to an
## 8-frame one would put the palm of frame 6 nowhere.
func _anchor_errors() -> Array[String]:
	var out: Array[String] = []
	for reason in anchors.validation_errors():
		out.append("anchors: %s" % reason)
	if anchors.frame_size != frame_size:
		out.append("anchors measured in a %s cell, profile frame_size is %s" % [
			str(anchors.frame_size), str(frame_size)])
	for key: Variant in anchors.points:
		var parts := String(key).split("/")
		if parts.size() != 2:
			continue  # already reported by anchors.validation_errors()
		var anim := StringName(parts[0])
		var sheet := sheet_for_anim(anim)
		var frames := anchors.frame_count(anim, StringName(parts[1]))
		if sheet == null:
			out.append("anchors name '%s' but the profile has no %s sheet" % [String(key), anim])
		elif frames != frame_count_of(sheet):
			out.append("anchors '%s' cover %d frames, the %s sheet holds %d" % [
				String(key), frames, anim, frame_count_of(sheet)])
	return out


## The sheet an anchor anim key names. The keys are the generator's animation names.
func sheet_for_anim(anim: StringName) -> Texture2D:
	match anim:
		ANIM_IDLE:
			return idle_sheet
		ANIM_WALK:
			return walk_sheet
		ANIM_ATTACK:
			return attack_sheet
		ANIM_MEDITATE:
			return meditate_sheet
		ANIM_CAST:
			return cast_sheet
		ANIM_SLASH:
			return slash_sheet
		ANIM_TALK:
			return talk_sheet
		_:
			return null


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

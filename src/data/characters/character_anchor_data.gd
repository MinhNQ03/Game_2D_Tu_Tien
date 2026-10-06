extends Resource
class_name CharacterAnchorData
## CharacterAnchorData — Aetheria data (WHERE on a drawn frame a named body point is).
##
## A presentation-tier resource (D-057B). The art generator writes it beside the sheets it draws
## (`tools/gen_prototype_assets.py`), from the SAME pose that drew each frame, so a point can
## never disagree with the pixels it names: the striking palm of attack frame 3 facing LEFT is
## where the generator put the hand when it drew that frame.
##
## WHY IT EXISTS. An effect that must start FROM a body part — the palm a strike leaves, the jaw
## a bite closes, the dantian qi gathers into — otherwise guesses a constant offset from the
## entity origin. A guessed offset is right for one facing and one frame and visibly wrong for
## the rest (the D-056 pass-2 "blob beside a motionless figure" was a guessed offset). Two
## current consumers, the strike VFX and the hit spark origin, ask the same question of every
## actor, which is why this is a resource and not a per-actor constant (M-14.2).
##
## LAYOUT. `points["<anim>/<point>"]` is a `PackedVector2Array` ordered DIRECTION-MAJOR
## (`direction * frames + column`, directions in `CharacterVisualProfileData.Direction` order).
## Each value is relative to the FEET ORIGIN the runtime anchors every sprite at (cell
## bottom-centre), so a consumer adds it to the visual's origin with no further arithmetic. A
## packed array per key means a lookup allocates nothing.
##
## Point names are a shared vocabulary, not per-actor: `palm` is the striking point of any actor
## (a wolf's jaw is exported as its `palm`), `core` is the centre of mass / dantian. Presentation
## only — nothing here is serialized into `CharacterState` (M-12.2).

const DIRECTION_COUNT := 4

@export var id: StringName = &""

## The cell size the points were measured in. Must equal the profile's `frame_size`, or every
## point is in the wrong coordinate space.
@export var frame_size: Vector2i = Vector2i.ZERO

## "<anim>/<point>" -> PackedVector2Array (direction-major, feet-origin relative).
@export var points: Dictionary = {}


func is_valid() -> bool:
	return validation_errors().is_empty()


## Boundary validation: a non-empty id, a positive cell, and every entry a "<anim>/<point>" key
## holding a non-empty packed array whose length is a whole number of frames per direction.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be non-empty")
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("frame_size must be positive (got %s)" % str(frame_size))
	if points.is_empty():
		errors.append("points is empty — an anchor set that names nothing anchors nothing")
	for key: Variant in points:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			errors.append("key %s is not a string" % str(key))
			continue
		var parts := String(key).split("/")
		if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
			errors.append("key '%s' is not '<anim>/<point>'" % String(key))
			continue
		var value: Variant = points[key]
		if typeof(value) != TYPE_PACKED_VECTOR2_ARRAY:
			errors.append("'%s' is not a PackedVector2Array" % String(key))
			continue
		var count := (value as PackedVector2Array).size()
		if count == 0 or count % DIRECTION_COUNT != 0:
			errors.append("'%s' holds %d points, not a whole number of frames x %d directions"
				% [String(key), count, DIRECTION_COUNT])
	return errors


## How many frames per direction `<anim>/<point>` covers (0 when the key is absent).
func frame_count(anim: StringName, point: StringName) -> int:
	return _frames_in(_track(anim, point))


func has_point(anim: StringName, point: StringName) -> bool:
	return not _track(anim, point).is_empty()


## The feet-relative position of `point` on frame `column` of `anim`, facing `direction`.
## `fallback` when the key is absent or the index is out of range — a caller that draws from an
## anchor degrades to its own origin rather than to a point off the body.
func point_at(anim: StringName, point: StringName, direction: int, column: int,
		fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var track := _track(anim, point)
	if track.is_empty():
		return fallback
	var frames := _frames_in(track)
	if direction < 0 or direction >= DIRECTION_COUNT or column < 0 or column >= frames:
		return fallback
	return track[direction * frames + column]


## Frames per direction in a track. Float divide then cast — `validation_errors` proved the
## length a whole multiple, and this avoids the integer-division warning (as
## `CharacterVisualProfileData.frame_count_of` does).
func _frames_in(track: PackedVector2Array) -> int:
	return int(float(track.size()) / float(DIRECTION_COUNT))


func _track(anim: StringName, point: StringName) -> PackedVector2Array:
	var value: Variant = points.get("%s/%s" % [anim, point])
	if typeof(value) != TYPE_PACKED_VECTOR2_ARRAY:
		return PackedVector2Array()
	return value

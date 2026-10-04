extends Node2D
class_name CharacterVisualComponent
## CharacterVisualComponent — Aetheria presentation (a character's on-screen sprite).
##
## A PRESENTATION-ONLY component (Phase 05 early art pipeline, D-026): it renders a character
## using a `CharacterVisualProfileData` and reacts to a facing + moving state pushed in by the
## owner. It owns a child `Sprite2D` configured from the profile's sheet GRID — `vframes` =
## one row per direction, `hframes` = the animation frames of the ACTIVE sheet (D-046) —
## nearest-filtered, anchored so the character's feet sit on the node origin
## (`docs/CHARACTER_ART_BIBLE.md`).
##
## It also OWNS THE ANIMATION CLOCK: `_process` advances the column at the profile's
## `frame_duration`. `_process` is switched OFF whenever the active sheet holds a single
## frame, so a static character costs nothing per frame (`05-performance-testing.md`).
##
## It reads NO gameplay rules and owns NO movement: the owner (`Player`) keeps
## `MovementComponent` as the movement authority and simply tells this component which way it
## is facing and whether it is moving (`update_facing`). The component never mutates
## `CharacterState` (presentation tier only). If the profile is missing/invalid it fails LOUD
## and renders nothing rather than guessing.

var _profile: CharacterVisualProfileData = null
var _sprite: Sprite2D = null
var _direction: int = CharacterVisualProfileData.Direction.DOWN
var _moving: bool = false

## Animation cursor: which column of the ACTIVE sheet is showing, and how long it has been.
var _column: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	if _sprite == null:
		_build_sprite()


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art: no blur (06-art)
	_sprite.centered = false
	add_child(_sprite)
	_apply_profile_to_sprite()


## Bind the visual profile this component renders. Returns false (loud) on a missing/invalid
## profile so the owner can fail closed instead of showing a blank character. Safe before or
## after the node enters the tree.
func setup(profile: CharacterVisualProfileData) -> bool:
	if profile == null:
		push_error("[visual] setup with null CharacterVisualProfileData")
		return false
	if not profile.is_valid():
		push_error("[visual] invalid visual profile '%s': %s" % [
			String(profile.id), str(profile.validation_errors())])
		return false
	_profile = profile
	if _sprite == null and is_node_ready():
		_build_sprite()
	else:
		_apply_profile_to_sprite()
	return true


## Push the current facing (from a movement/intent vector) + whether the character is moving.
## The owner calls this from its movement update; this component only chooses the frame. No
## movement math happens here. A zero vector keeps the last facing (resting), not a snap to
## DOWN, so the character faces where it last walked.
##
## Switching between idle and walk RESTARTS the cursor, because the two sheets may hold
## different frame counts and a stale column could otherwise index past the shorter sheet.
func update_facing(facing_vector: Vector2, is_moving: bool) -> void:
	if is_moving != _moving:
		_moving = is_moving
		_column = 0
		_elapsed = 0.0
	if facing_vector != Vector2.ZERO:
		_direction = CharacterVisualProfileData.direction_for_vector(facing_vector)
	_refresh_frame()


func _process(delta: float) -> void:
	advance(delta)


## Advance the animation clock by `delta` seconds. PUBLIC so a test can drive the animation
## deterministically instead of waiting on real frames (and without reaching for `_process`,
## which would be a cross-file private access). Only does work while the active sheet has
## more than one frame.
func advance(delta: float) -> void:
	if _profile == null:
		return
	var total := _active_frame_count()
	if total <= 1:
		set_process(false)
		return
	var step := _profile.frame_duration
	if step <= 0.0:
		return
	_elapsed += delta
	while _elapsed >= step:
		_elapsed -= step
		_column = (_column + 1) % total
	_refresh_frame()


## The animation column currently showing (for tests / debug readouts).
func get_column() -> int:
	return _column


## The current facing Direction enum (for tests / debug readouts).
func get_direction() -> int:
	return _direction


## The owned Sprite2D (for tests to assert dimensions/filter/anchor). May be null before build.
func get_sprite() -> Sprite2D:
	return _sprite


# --- Rendering ---------------------------------------------------------------

func _apply_profile_to_sprite() -> void:
	if _sprite == null or _profile == null:
		return
	# One ROW per direction; the column count comes from the active sheet (set in _refresh).
	_sprite.vframes = CharacterVisualProfileData.DIRECTION_COUNT
	# Anchor at the feet: a non-centered sprite draws down-right from the origin, so lift it by
	# its full height and apply the authored offset so the feet rest on the origin.
	_sprite.position = Vector2(
		-_profile.frame_size.x / 2.0 + _profile.anchor_offset.x,
		-_profile.frame_size.y + _profile.anchor_offset.y)
	_column = 0
	_elapsed = 0.0
	_refresh_frame()


## The sheet that should be showing right now: the walk sheet while moving IF the profile
## authored one, else idle (the documented fallback — no fake animation).
func _active_sheet() -> Texture2D:
	if _profile == null:
		return null
	if _moving and _profile.walk_sheet != null:
		return _profile.walk_sheet
	return _profile.idle_sheet


func _active_frame_count() -> int:
	if _profile == null:
		return 0
	return _profile.frame_count_of(_active_sheet())


func _refresh_frame() -> void:
	if _sprite == null or _profile == null:
		return
	var sheet := _active_sheet()
	if sheet == null:
		return
	if _sprite.texture != sheet:
		_sprite.texture = sheet
	var total := _profile.frame_count_of(sheet)
	if total <= 0:
		return
	_sprite.hframes = total
	if _column >= total:
		_column = 0
	# Grid index: rows are directions, columns are animation frames.
	_sprite.frame = _direction * total + _column
	# Only pay for _process when there is actually something to animate.
	set_process(total > 1)

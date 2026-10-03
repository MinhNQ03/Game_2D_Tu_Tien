extends Node2D
class_name CharacterVisualComponent
## CharacterVisualComponent — Aetheria presentation (a character's on-screen sprite).
##
## A PRESENTATION-ONLY component (Phase 05 early art pipeline, D-026): it renders a character
## using a `CharacterVisualProfileData` and reacts to a facing + moving state pushed in by the
## owner. It owns a child `Sprite2D` configured from the profile's directional sheet (one row
## of 4 frames via `hframes`), nearest-filtered, anchored so the character's feet sit on the
## node origin (`docs/CHARACTER_ART_BIBLE.md`).
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
func update_facing(facing_vector: Vector2, is_moving: bool) -> void:
	_moving = is_moving
	if facing_vector != Vector2.ZERO:
		_direction = CharacterVisualProfileData.direction_for_vector(facing_vector)
	_refresh_frame()


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
	# Idle sheet is the base texture; it is one row of DIRECTION_COUNT frames.
	_sprite.texture = _profile.idle_sheet
	_sprite.hframes = CharacterVisualProfileData.DIRECTION_COUNT
	_sprite.vframes = 1
	# Anchor at the feet: a non-centered sprite draws down-right from the origin, so lift it by
	# its full height and apply the authored offset so the feet rest on the origin.
	_sprite.position = Vector2(
		-_profile.frame_size.x / 2.0 + _profile.anchor_offset.x,
		-_profile.frame_size.y + _profile.anchor_offset.y)
	_refresh_frame()


func _refresh_frame() -> void:
	if _sprite == null or _profile == null:
		return
	# Choose the walk sheet while moving IF the profile authored one; else stay on idle
	# (documented Phase-05 fallback — no fake animation).
	var sheet: Texture2D = _profile.idle_sheet
	if _moving and _profile.walk_sheet != null:
		sheet = _profile.walk_sheet
	if _sprite.texture != sheet:
		_sprite.texture = sheet
	_sprite.frame = _direction  # column index == Direction enum order

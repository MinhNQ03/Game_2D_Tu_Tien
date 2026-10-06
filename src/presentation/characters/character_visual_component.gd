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
## TWO LAYERS, NOT ONE (D-056). `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` §2:
##
##   * **LOCOMOTION** — `IDLE` / `WALK`. Continuous, looping, clocked HERE at the profile's
##     `frame_duration`.
##   * **ACTION** — `BASIC_ATTACK` today; `CAST`/`HIT`/`STUN`/`DEATH`/… reserved. Bounded,
##     ONE-SHOT, non-looping, and **driven from outside** via `drive_action(progress)`.
##
## ACTION OUT-RANKS LOCOMOTION, so a character mid-swing shows the swing even while walking.
## Facing is shared by both layers: turning mid-swing changes the direction row without
## restarting or cancelling the action.
##
## WHY AN ACTION IS DRIVEN RATHER THAN CLOCKED. The frame is a pure function of a progress
## value pushed in by whoever owns the action's timing, so this component CANNOT run at a
## different rate from the mechanic it depicts — "gameplay timing owns the truth" becomes
## structural instead of a comment, and a long authored wind-up spends more frames in the
## wind-up with no per-phase frame budget to maintain. A third layer, TRANSIENT FEEDBACK (hit
## flash, corpse tint, level-up flash), is deliberately NOT here: it modulates whatever pose is
## showing and is owned by `DamageFeedback` / `LevelUpFeedback`.
##
## `_process` is switched OFF whenever the active sheet holds a single frame and no action is
## running, so a static character costs nothing per frame (`05-performance-testing.md`) — which
## matters because every creature in the world carries one of these.
##
## It reads NO gameplay rules and owns NO movement: the owner (`Player`) keeps
## `MovementComponent` as the movement authority and simply tells this component which way it
## is facing and whether it is moving (`update_facing`). The component never mutates
## `CharacterState` (presentation tier only). If the profile is missing/invalid it fails LOUD
## and renders nothing rather than guessing.

## No action playing. Locomotion is showing.
const ACTION_NONE := &""

## The basic attack. The ONE action implemented; the rest of the vocabulary (CAST, HIT, STUN,
## DEATH, EMOTE…) is reserved in `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` §5 and has no
## implementation here, on purpose — a reserved name is a name, not a feature.
const ACTION_ATTACK := &"attack"

var _profile: CharacterVisualProfileData = null
var _sprite: Sprite2D = null
var _direction: int = CharacterVisualProfileData.Direction.DOWN
var _moving: bool = false

## Animation cursor: which column of the ACTIVE sheet is showing, and how long it has been.
var _column: int = 0
var _elapsed: float = 0.0

# --- ACTION LAYER (D-056) ----------------------------------------------------
#
# The second layer. `_action` out-ranks `_moving` when choosing a sheet, so a character
# mid-swing shows the swing even while walking. Empty means "locomotion".
#
# An action is NOT clocked here. `_action_progress` is pushed in from whoever owns the
# action's timing, which is what makes "gameplay timing owns the truth" structural rather
# than a comment: this component cannot drift from a lifecycle it does not time.
var _action: StringName = ACTION_NONE
var _action_progress: float = 0.0

## The optional sibling that reports an attack lifecycle, resolved once.
##
## OPTIONAL, the same way `AttackFeedback` and `DamageFeedback` resolve their siblings: an
## entity that cannot attack (a preview archetype, a prop) legitimately has none, and that is a
## correct scene rather than a mis-wired one.
##
## This wiring is deliberately CONCRETE and single. There is no "action source interface",
## because a second action SOURCE does not exist yet and inventing one would be the speculative
## abstraction `03-architecture.md` forbids. When CAST arrives it calls the same three public
## methods and nothing in this layer changes.
##
## TYPED, like `AttackFeedback`'s reference. It was declared `Node` and read through
## `call("state")` / `call("time_remaining")` — two dynamic dispatches per frame of every swing
## on every attacking creature, plus `call("attack_data")` once per swing — where a typed
## reference costs none and a renamed method fails at parse time instead of at runtime. The
## resolution stays OPTIONAL: a missing sibling, or a node of that name that is not an
## `AttackComponent`, casts to null and leaves the action layer unbound.
var _attack_source: AttackComponent = null

## The authored phase durations of the swing in flight, read ONCE per swing rather than every
## frame (`05-performance-testing.md`: no redundant per-frame work on a node every creature
## carries).
var _swing_windup: float = 0.0
var _swing_active: float = 0.0
var _swing_recovery: float = 0.0
var _swing_total: float = 0.0


func _ready() -> void:
	if _sprite == null:
		_build_sprite()
	_bind_attack_source()


## Connect to a sibling attack lifecycle if the entity has one.
##
## The component is built at RUNTIME by `Player`/`Enemy` and added as a child of the entity, so
## by the time this runs the scene's `AttackComponent` sibling already exists.
func _bind_attack_source() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var source := parent.get_node_or_null("AttackComponent") as AttackComponent
	if source == null:
		return
	_attack_source = source
	source.attack_started.connect(_on_attack_started)
	source.attack_finished.connect(_on_attack_finished)


func _on_attack_started() -> void:
	# Cache the authored phase durations for this swing. They come from the AttackData the
	# component is armed with, so a retuned attack moves the animation with it.
	var data := _attack_source.attack_data()
	if data == null:
		return
	_swing_windup = data.windup_seconds
	_swing_active = data.active_seconds
	_swing_recovery = data.recovery_seconds
	_swing_total = _swing_windup + _swing_active + _swing_recovery
	if _swing_total <= 0.0:
		return
	play_action(ACTION_ATTACK)


func _on_attack_finished() -> void:
	if _action == ACTION_ATTACK:
		end_action()


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
## Facing is SHARED between the layers, not owned by one: a character may turn mid-swing, so a
## facing change moves the direction row without restarting or cancelling an action in flight.
## Only the LOCOMOTION cursor reset is suppressed while an action plays — resetting it there
## would be resetting a cursor the action owns.
func update_facing(facing_vector: Vector2, is_moving: bool) -> void:
	if is_moving != _moving:
		_moving = is_moving
		if _action == ACTION_NONE:
			_column = 0
			_elapsed = 0.0
	if facing_vector != Vector2.ZERO:
		_direction = CharacterVisualProfileData.direction_for_vector(facing_vector)
	_refresh_frame()


# === The ACTION layer ========================================================

## Begin a one-shot action. Returns false when this profile has no sheet for it, in which case
## the character keeps playing locomotion — presentation DEGRADES, gameplay is unaffected.
##
## Starting an action resets the cursor, because the action sheet may hold a different number
## of columns than the locomotion sheet that was showing.
func play_action(action: StringName) -> bool:
	if _profile == null or action == ACTION_NONE:
		return false
	if _sheet_for_action(action) == null:
		return false
	_action = action
	_action_progress = 0.0
	_column = 0
	_elapsed = 0.0
	_refresh_frame()
	set_process(true)
	return true


## Set how far through the action we are, in [0, 1], from the authority that OWNS its timing.
##
## This is the whole reason the layer cannot drift: the frame is a pure function of the
## progress it is told, so a long authored wind-up spends more frames in the wind-up with no
## per-phase frame budget to keep in sync. Ignored when no action is playing.
func drive_action(progress: float) -> void:
	if _action == ACTION_NONE:
		return
	_action_progress = clampf(progress, 0.0, 1.0)
	_refresh_frame()


## Finish the action and return to locomotion. Safe to call when nothing is playing.
##
## This is also the CANCEL path (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §12): a rejected or
## interrupted action must be recoverable, not leave a character frozen in a pose.
func end_action() -> void:
	if _action == ACTION_NONE:
		return
	_action = ACTION_NONE
	_action_progress = 0.0
	_column = 0
	_elapsed = 0.0
	_refresh_frame()


func is_action_playing() -> bool:
	return _action != ACTION_NONE


func current_action() -> StringName:
	return _action


## How far through the current action, in [0, 1] (for tests / debug readouts).
func action_progress() -> float:
	return _action_progress


## The sheet an action name renders with, or null when this profile cannot play it.
##
## One `match` with one arm today. It stays a match rather than becoming a dictionary lookup or
## a registry because there is exactly one action; the day a second lands, THAT change adds the
## arm, and the day a fifth lands is the day a table earns its keep.
func _sheet_for_action(action: StringName) -> Texture2D:
	match action:
		ACTION_ATTACK:
			return _profile.attack_sheet
		_:
			return null


func _process(delta: float) -> void:
	advance(delta)


## Advance the animation clock by `delta` seconds. PUBLIC so a test can drive the animation
## deterministically instead of waiting on real frames (and without reaching for `_process`,
## which would be a cross-file private access). Only does work while the active sheet has
## more than one frame.
func advance(delta: float) -> void:
	if _profile == null:
		return
	if _action != ACTION_NONE:
		# An action is running: it is DRIVEN, not clocked. Pull the progress from the
		# authority that owns the action's timing instead of stepping a clock here, so the
		# animation cannot run at a different rate from the mechanic it depicts.
		_sync_action_from_authority()
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


## Read the action's progress from the lifecycle that owns it, and END the action when that
## lifecycle is no longer running one.
##
## Ending on the STATE rather than only on `attack_finished` is deliberate and load-bearing:
## `AttackComponent.cancel()` emits nothing, and `Enemy._on_health_died()` calls it — so a
## layer that waited for the finish signal would leave a corpse frozen mid-thrust. Reading the
## state makes cancel, death and session teardown all end the action by the same path.
func _sync_action_from_authority() -> void:
	if _action != ACTION_ATTACK or _attack_source == null \
			or not is_instance_valid(_attack_source):
		return
	if _swing_total <= 0.0:
		end_action()
		return
	var state := _attack_source.state()
	if state == AttackStateMachine.State.READY:
		end_action()
		return
	var remaining := _attack_source.time_remaining()
	# Elapsed time INTO the swing, accumulated across completed phases. The lifecycle reports
	# the time left in the CURRENT phase, so the phases before it are complete by definition.
	var elapsed := 0.0
	match state:
		AttackStateMachine.State.WINDUP:
			elapsed = _swing_windup - remaining
		AttackStateMachine.State.ACTIVE:
			elapsed = _swing_windup + (_swing_active - remaining)
		_:
			elapsed = _swing_windup + _swing_active + (_swing_recovery - remaining)
	drive_action(elapsed / _swing_total)


## The sheet that should be showing right now.
##
## PRECEDENCE: action, then walk, then idle. The action is checked FIRST because it out-ranks
## locomotion — a character mid-swing shows the swing even while walking
## (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §2).
func _active_sheet() -> Texture2D:
	if _profile == null:
		return null
	if _action != ACTION_NONE:
		var action_sheet := _sheet_for_action(_action)
		if action_sheet != null:
			return action_sheet
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
	# Guard the writes: this runs EVERY animated frame, so an unconditional `hframes` set and
	# `set_process` call would be redundant per-frame work on the hot path
	# (`05-performance-testing.md`). Only `frame` genuinely changes each tick.
	if _sprite.hframes != total:
		_sprite.hframes = total
	if _action != ACTION_NONE:
		# ONE-SHOT: the column is a pure function of the driven progress, CLAMPED to the last
		# frame rather than wrapped. A modulo here would loop the swing, which is what makes an
		# action different in kind from a locomotion cycle rather than just a different sheet.
		_column = clampi(int(_action_progress * float(total)), 0, total - 1)
	elif _column >= total:
		_column = 0
	# Grid index: rows are directions, columns are animation frames.
	_sprite.frame = _direction * total + _column
	# Only pay for _process when there is actually something to animate. An action always
	# needs the frame, even on a single-column sheet, because it must still be ENDED.
	var should_process := total > 1 or _action != ACTION_NONE
	if is_processing() != should_process:
		set_process(should_process)

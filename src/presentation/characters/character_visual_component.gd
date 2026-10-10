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
##   * **ACTION** — `BASIC_ATTACK` and the sword `SLASH` (D-063 A3) today;
##     `HIT`/`STUN`/`DEATH`/… reserved. Bounded, ONE-SHOT, non-looping, and **driven from
##     outside** via `drive_action(progress)`.
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
## LOCOMOTION IS A GAIT, NOT A LOOP (D-057B). `IDLE → WALK → SETTLE → IDLE`:
##
##   * the WALK is clocked by the DISTANCE the component's own origin actually moved
##     (`CharacterVisualProfileData.stride_px`), so the stride follows the real speed — a body
##     slowed by a wall slows its feet, a blocked one stops them, and a remote character drawn
##     from a position stream gets its cadence from that stream with no extra state;
##   * it starts and ends on the profile's `walk_rest_columns`: the walk opens with a weight
##     shift rather than a leap into full stride, and a stop lets the planted foot finish its
##     step (SETTLE) instead of snapping the legs together;
##   * a 180° turn passes through the side (or front) facing for `TURN_SECONDS`, so the body
##     reads as turning rather than flipping; turning mid-ACTION stays instant, because a strike
##     must face where it lands.
##
## The idle breath starts at a phase derived from where the character stands, so a pack of
## wolves or a row of disciples never breathes in lockstep (M-8.1, M-10.1: no synchronized
## loops) — deterministic, no RNG (M-8.2).
##
## `_process` is switched OFF whenever nothing can change the frame — a single-frame sheet, no
## action, no gait in progress, no turn — so a static character costs nothing per frame
## (`05-performance-testing.md`), which matters because every creature carries one of these.
##
## It reads NO gameplay rules and owns NO movement: the owner (`Player`) keeps
## `MovementComponent` as the movement authority and simply tells this component which way it
## is facing and whether it is moving (`update_facing`). The component never mutates
## `CharacterState` (presentation tier only). If the profile is missing/invalid it fails LOUD
## and renders nothing rather than guessing.

## No action playing. Locomotion is showing.
const ACTION_NONE := &""

## The basic attack: the palm strike. Which body an attack plays is data-driven
## (`AttackData.body_action`); the sword cut below is the second body, resolved with fallback.
const ACTION_ATTACK := &"attack"

## Seated cultivation (Phase 12). Driven by the cultivation presentation, not clocked here: the
## descent is the first column, the breath loop the rest (`CultivationFeedback`).
const ACTION_MEDITATE := &"meditate"

## A technique's cast (Phase 15): one action, four phases, driven by `CastFeedback` from the
## `CastStateMachine`'s own phase and progress.
const ACTION_CAST := &"cast"

## The sword cut (D-063 A3): the same attack lifecycle as `ACTION_ATTACK`, a different body —
## coil → cut → follow-through → guard, 8 columns driven by the authority's progress. Only
## sword-wielding looks author the sheet; anything else falls back to the palm strike, so an
## enemy or NPC is never left without a body for its swing.
const ACTION_SLASH := &"slash"

## A conversational gesture (Phase 17): NOT a strike — it has no attack lifecycle, hits nothing
## and is clocked by whoever is being spoken to (`WorldNpc`), through the same
## `play_action` / `drive_action` / `end_action` contract every other action uses.
const ACTION_TALK := &"talk"


## True for the attack-family actions: the palm strike and the sword cut. Both are driven by
## an `AttackComponent` lifecycle and share the strike sync, cancel and finish paths — the
## body differs, the lifecycle does not.
static func is_strike_action(action: StringName) -> bool:
	return action == ACTION_ATTACK or action == ACTION_SLASH


## The one-shot column for a driven `progress` in [0, 1] over `total` frames: clamped to the
## last frame, never wrapped — what makes an action different in kind from a locomotion
## cycle. Single home for the mapping, so a swing's VFX trail reads the same column the body
## draws (D-063 A3).
static func column_for_progress(progress: float, total: int) -> int:
	if total <= 0:
		return 0
	return clampi(int(clampf(progress, 0.0, 1.0) * float(total)), 0, total - 1)

## How long a 180° turn shows the intermediate facing. Three frames at 60fps: long enough to
## read as the body turning, short enough that the input still feels instant (M-4.4).
const TURN_SECONDS := 0.05

## Seconds per walk frame while a stop SETTLES onto a rest column. The body has already
## stopped, so this is the planted foot finishing its step — quick, never a second stride.
const SETTLE_FRAME_SECONDS := 0.05

## Moving intent with no measured displacement for this long reads as BLOCKED: the stride stops
## and the body settles, instead of treading air against a wall. Long enough to ride out a
## single physics frame with no movement.
const STALL_SECONDS := 0.1

## A per-frame displacement above this is a TELEPORT (a spawn, a map transfer), not a step, and
## must not spin the stride through a dozen frames at once.
const TELEPORT_PX := 48.0

## Below this per-frame displacement (px) the body is treated as not moving.
const MOVE_EPSILON_PX := 0.05

## FACING HYSTERESIS: the current facing is kept while the facing vector stays within ~53° of it
## (cosine 0.6), wider than the 45° boundary between cardinals. Without the band a creature
## chasing along a diagonal flips between two facings every frame, and a diagonal key press
## turns a character away from where it was looking.
const FACING_HOLD_DOT := 0.6

## The locomotion gait. Private to the component; `gait()` exposes it for tests/debug.
enum Gait { IDLE, WALK, SETTLE }

var _profile: CharacterVisualProfileData = null
var _sprite: Sprite2D = null
## The sprite's resting position (feet on the origin), so an offset a reaction applies can be
## measured and an anchor lookup can follow the drawn body rather than the node origin.
var _sprite_rest: Vector2 = Vector2.ZERO

## The LOGICAL facing (what the owner asked for) and the RENDERED row. They differ only during
## the brief intermediate frame of a 180° turn.
var _direction: int = CharacterVisualProfileData.Direction.DOWN
var _shown_direction: int = CharacterVisualProfileData.Direction.DOWN
var _turn_left: float = 0.0
## The last side facing, so a DOWN<->UP turn passes through the side the body last showed.
var _last_side: int = CharacterVisualProfileData.Direction.RIGHT

## The owner's movement INTENT, and the gait the component is actually rendering.
var _moving: bool = false
var _gait: int = Gait.IDLE

## Locomotion cursor: which column of the locomotion sheet is showing, the time accumulator for
## the clocked parts (idle, settle, a time-clocked walk), and the distance accumulator for a
## distance-clocked walk.
var _column: int = 0
var _elapsed: float = 0.0
var _stride_travel: float = 0.0
var _still_time: float = 0.0

## Where the origin was on the last tick, for the displacement the stride is clocked by.
var _last_origin: Vector2 = Vector2.ZERO
var _origin_known: bool = false

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
## The action's own column, a pure function of `_action_progress`. Separate from the locomotion
## cursor, so an action never resets the stride it interrupts and locomotion resumes intact.
var _action_column: int = 0

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
	# The attack names its body (D-063 A3): a sword swing plays the slash sheet, resolved
	# with fallback so a look without the sheet still gets the palm strike.
	play_action(resolve_body_action(data.body_action))


## Which action body to play for `body_action`: the named one when this profile can draw it,
## else the palm strike. A profile without the sheet is never left without a body for its
## swing (D-063 A3). An unsupported (typo'd) name is LOUD — a warning, never silent — but
## still falls back: a bad string degrades the swing, it never leaves it bodiless.
func resolve_body_action(body_action: StringName) -> StringName:
	if body_action != ACTION_NONE and _sheet_for_action(body_action) != null:
		return body_action
	if body_action != ACTION_NONE and not AttackData.BODY_ACTIONS.has(body_action):
		push_warning("[visual] unsupported body_action '%s' — falling back to the attack body"
			% body_action)
	return ACTION_ATTACK


func _on_attack_finished() -> void:
	if is_strike_action(_action):
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


## Push the current facing (from a movement/intent vector) + whether the character INTENDS to
## move. The owner calls this from its movement update; this component only chooses the frame.
## No movement math happens here. A zero vector keeps the last facing (resting), not a snap to
## DOWN, so the character faces where it last walked.
##
## `is_moving` is INTENT. Whether the stride actually advances is decided by the displacement
## the component measures (see the gait notes above): an intent that moves nothing settles.
## Facing is SHARED between the layers: a character may turn mid-swing, so a facing change moves
## the direction row without restarting or cancelling an action in flight.
func update_facing(facing_vector: Vector2, is_moving: bool) -> void:
	if facing_vector != Vector2.ZERO:
		_turn_to(_resolve_facing(facing_vector), facing_vector)
	if is_moving != _moving:
		_moving = is_moving
		if _moving:
			_begin_walk()
		else:
			_begin_stop()
	_refresh_frame()


# === The ACTION layer ========================================================

## Begin a one-shot action. Returns false when this profile has no sheet for it, in which case
## the character keeps playing locomotion — presentation DEGRADES, gameplay is unaffected.
func play_action(action: StringName) -> bool:
	if _profile == null or action == ACTION_NONE:
		return false
	if _sheet_for_action(action) == null:
		return false
	_action = action
	_action_progress = 0.0
	_action_column = 0
	# A strike faces where it lands: an intermediate turn frame in flight resolves at once.
	_finish_turn()
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
## interrupted action must be recoverable, not leave a character frozen in a pose. Locomotion
## resumes on its own cursor, which the action never touched.
func end_action() -> void:
	if _action == ACTION_NONE:
		return
	_action = ACTION_NONE
	_action_progress = 0.0
	_action_column = 0
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
## A `match`, one arm per action (attack since D-056, meditate since Phase 12). It stays a match
## rather than becoming a dictionary lookup or a registry while the actions are this few; the
## day a fifth lands is the day a table earns its keep.
func _sheet_for_action(action: StringName) -> Texture2D:
	match action:
		ACTION_ATTACK:
			return _profile.attack_sheet
		ACTION_SLASH:
			return _profile.slash_sheet
		ACTION_MEDITATE:
			return _profile.meditate_sheet
		ACTION_CAST:
			return _profile.cast_sheet
		ACTION_TALK:
			return _profile.talk_sheet
		_:
			return null


# === Anchors (D-057B) ========================================================

## Where the named body point (`CharacterVisualProfileData.POINT_PALM`, `POINT_CORE`, …) is on
## the frame SHOWING right now, in this node's local space (add `global_position` for world).
##
## It follows everything that moves the drawn body: the active sheet, the rendered facing row,
## the column, and any offset a reaction has put on the sprite — so an effect that starts from
## the palm starts from the palm that is drawn, on every facing and every frame. `fallback` when
## the profile carries no anchors or does not name the point (the effect then starts at the
## feet origin rather than at a guessed offset).
func anchor_point(point: StringName, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if _profile == null or _profile.anchors == null or _sprite == null:
		return fallback
	var anim := current_anim()
	if not _profile.anchors.has_point(anim, point):
		return fallback
	return (_profile.anchors.point_at(anim, point, _shown_direction, get_column(), fallback)
		+ (_sprite.position - _sprite_rest) + _feet_origin())


## True when the bound profile names `point` for the animation showing right now.
func has_anchor(point: StringName) -> bool:
	return (_profile != null and _profile.anchors != null
		and _profile.anchors.has_point(current_anim(), point))


## True when the bound profile names a depth for `point` of the animation showing right now.
func has_anchor_depth(point: StringName) -> bool:
	return (_profile != null and _profile.anchors != null
		and _profile.anchors.has_depth(current_anim(), point))


## Where `point` is at a driven action `progress` in [0, 1], in this node's local space. A
## pure function of (progress, facing): the strike VFX draws the blade's trail from the tip
## positions the rig actually drew, so the arc and the blade can never diverge (D-063 A3).
## `fallback` when no action is playing or the point is unnamed.
func anchor_point_at_progress(point: StringName, progress: float,
		fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if _profile == null or _profile.anchors == null or _sprite == null:
		return fallback
	if _action == ACTION_NONE:
		return fallback
	var sheet := _sheet_for_action(_action)
	if sheet == null:
		return fallback
	var column := column_for_progress(progress, _profile.frame_count_of(sheet))
	if not _profile.anchors.has_point(_action, point):
		return fallback
	return (_profile.anchors.point_at(_action, point, _shown_direction, column, fallback)
		+ (_sprite.position - _sprite_rest) + _feet_origin())


## How far in front of the body's core `point` is on the frame SHOWING right now, in px
## along the camera's view axis (positive = toward the viewer). Lets a drawn weapon layer in
## front of or behind the body exactly as the rig holds it (D-063 A3). `fallback` when the
## profile names no depth for the point.
func anchor_depth(point: StringName, fallback: float = 0.0) -> float:
	if _profile == null or _profile.anchors == null:
		return fallback
	return _profile.anchors.depth_at(current_anim(), point, _shown_direction, get_column(),
		fallback)


## The animation name of the sheet showing right now (`CharacterVisualProfileData.ANIM_*`) —
## the key an anchor lookup is made under.
func current_anim() -> StringName:
	if _profile == null:
		return CharacterVisualProfileData.ANIM_IDLE
	if _action != ACTION_NONE and _sheet_for_action(_action) != null:
		return _action
	if _shows_walk():
		return CharacterVisualProfileData.ANIM_WALK
	return CharacterVisualProfileData.ANIM_IDLE


## The drawn sprite's displacement from its resting place — a reaction's offset, read by an
## effect that must follow the body. Zero at rest.
func sprite_offset() -> Vector2:
	return (_sprite.position - _sprite_rest) if _sprite != null else Vector2.ZERO


## Displace the drawn body by `offset` from its resting place (a hit recoil). Presentation
## only: the entity, its collision and its hurtbox stay where gameplay put them.
func set_sprite_offset(offset: Vector2) -> void:
	if _sprite != null:
		_sprite.position = _sprite_rest + offset


func _feet_origin() -> Vector2:
	return _sprite_rest + Vector2(_profile.frame_size.x / 2.0, float(_profile.frame_size.y))


# === Clock ===================================================================

func _process(delta: float) -> void:
	advance(delta)


## Advance the presentation by `delta` seconds. PUBLIC so a test can drive the animation
## deterministically instead of waiting on real frames (and without reaching for `_process`,
## which would be a cross-file private access).
##
## The locomotion stride reads the displacement of this node's origin since the last call, so a
## test that moves the node and then advances is exactly what a moving character does.
func advance(delta: float) -> void:
	if _profile == null:
		return
	var moved := _observe_displacement()
	if _turn_left > 0.0:
		_turn_left -= delta
		if _turn_left <= 0.0:
			_finish_turn()
	if _action != ACTION_NONE:
		# An action is running: it is DRIVEN, not clocked. Pull the progress from the
		# authority that owns the action's timing instead of stepping a clock here, so the
		# animation cannot run at a different rate from the mechanic it depicts. Locomotion
		# holds its cursor underneath.
		_sync_action_from_authority()
		_refresh_frame()
		return
	match _gait:
		Gait.WALK:
			_advance_walk(delta, moved)
		Gait.SETTLE:
			_advance_settle(delta)
		_:
			if _moving and moved > MOVE_EPSILON_PX:
				_begin_walk()  # a blocked body that moves again picks its stride back up
			else:
				_advance_clock(delta, _profile.frame_duration)
	_refresh_frame()


## How far the origin moved since the last tick, with a teleport counted as no step at all.
func _observe_displacement() -> float:
	var origin := global_position
	if not _origin_known:
		_origin_known = true
		_last_origin = origin
		_seed_idle_phase(origin)
		return 0.0
	var moved := origin.distance_to(_last_origin)
	_last_origin = origin
	return 0.0 if moved > TELEPORT_PX else moved


## The idle breath starts at a phase derived from where the character first stands, so two
## creatures placed apart never breathe in lockstep. Deterministic: the same placement always
## gives the same phase (M-8.2) — no RNG, and no draw from a domain stream.
func _seed_idle_phase(origin: Vector2) -> void:
	if _gait != Gait.IDLE or _profile.frame_duration <= 0.0:
		return
	var frames := _profile.frame_count_of(_profile.idle_sheet)
	if frames <= 1:
		return
	var cycle := _profile.frame_duration * float(frames)
	var phase := fposmod(origin.x * 0.731 + origin.y * 0.547, cycle)
	_column = int(phase / _profile.frame_duration) % frames
	_elapsed = fposmod(phase, _profile.frame_duration)


## Step the locomotion cursor by time (idle, or a walk with no `stride_px`).
func _advance_clock(delta: float, step: float) -> void:
	var total := _active_frame_count()
	if total <= 1 or step <= 0.0:
		return
	_elapsed += delta
	while _elapsed >= step:
		_elapsed -= step
		_column = (_column + 1) % total


## The stride: clocked by DISTANCE when the profile authors `stride_px`, else by time. Moving
## intent that moves nothing for `STALL_SECONDS` stops the stride (blocked by a wall).
func _advance_walk(delta: float, moved: float) -> void:
	if _profile.stride_px <= 0.0:
		_advance_clock(delta, _profile.frame_duration)
		return
	if moved <= MOVE_EPSILON_PX:
		_still_time += delta
		if _still_time >= STALL_SECONDS:
			_begin_stop()
		return
	_still_time = 0.0
	var total := _active_frame_count()
	if total <= 1:
		return
	var step := _profile.stride_px / float(total)
	_stride_travel += moved
	while _stride_travel >= step:
		_stride_travel -= step
		_column = (_column + 1) % total


## The stop: the stride finishes onto the next rest column, then the idle takes over.
func _advance_settle(delta: float) -> void:
	var total := _profile.frame_count_of(_profile.walk_sheet)
	if total <= 1:
		_enter_idle()
		return
	_elapsed += delta
	while _elapsed >= SETTLE_FRAME_SECONDS:
		_elapsed -= SETTLE_FRAME_SECONDS
		_column = (_column + 1) % total
		if _profile.walk_rest_columns.has(_column):
			_enter_idle()
			return


# === Gait transitions ========================================================

## Moving intent: start (or resume) the stride. From a SETTLE the stride continues where the
## feet are — re-entering mid-stop must not jump the legs back to a rest pose.
func _begin_walk() -> void:
	if _profile == null or _profile.walk_sheet == null:
		return  # the documented fallback: no walk sheet, the idle shows while moving
	_still_time = 0.0
	if _gait == Gait.WALK:
		return
	if _gait == Gait.IDLE:
		_column = _profile.walk_rest_columns[0] if not _profile.walk_rest_columns.is_empty() \
			else 0
		_stride_travel = 0.0
	_gait = Gait.WALK
	_elapsed = 0.0
	set_process(true)


## Intent to stop (or a blocked stride): settle onto a rest column, or go straight to idle when
## the feet already rest or the profile names no rest columns.
func _begin_stop() -> void:
	if _gait != Gait.WALK:
		return
	if _profile.walk_rest_columns.is_empty() or _profile.walk_rest_columns.has(_column):
		_enter_idle()
		return
	_gait = Gait.SETTLE
	_elapsed = 0.0


## Back to the idle breath, from its first frame: a character that just stopped starts a breath.
func _enter_idle() -> void:
	_gait = Gait.IDLE
	_column = 0
	_elapsed = 0.0
	_stride_travel = 0.0
	_still_time = 0.0


# === Facing ==================================================================

## Turn to `direction`. A 180° reversal outside an action shows the intermediate facing first:
## LEFT<->RIGHT turns through the front (DOWN) — a top-down character turns toward the viewer —
## and DOWN<->UP through the side the input leans to, else the side last shown.
func _turn_to(direction: int, facing_vector: Vector2) -> void:
	if direction == _direction:
		return
	var reversing := _opposite(direction) == _direction
	_direction = direction
	if direction == CharacterVisualProfileData.Direction.LEFT \
			or direction == CharacterVisualProfileData.Direction.RIGHT:
		_last_side = direction
	if not reversing or _action != ACTION_NONE or _profile == null:
		_finish_turn()
		return
	if direction == CharacterVisualProfileData.Direction.LEFT \
			or direction == CharacterVisualProfileData.Direction.RIGHT:
		_shown_direction = CharacterVisualProfileData.Direction.DOWN
	elif facing_vector.x > 0.0:
		_shown_direction = CharacterVisualProfileData.Direction.RIGHT
	elif facing_vector.x < 0.0:
		_shown_direction = CharacterVisualProfileData.Direction.LEFT
	else:
		_shown_direction = _last_side
	_turn_left = TURN_SECONDS
	set_process(true)


## The cardinal facing for `facing_vector`, holding the current one inside the hysteresis band.
func _resolve_facing(facing_vector: Vector2) -> int:
	var candidate := CharacterVisualProfileData.direction_for_vector(facing_vector)
	if candidate == _direction:
		return candidate
	if facing_vector.normalized().dot(_unit(_direction)) >= FACING_HOLD_DOT:
		return _direction
	return candidate


static func _unit(direction: int) -> Vector2:
	match direction:
		CharacterVisualProfileData.Direction.DOWN:
			return Vector2.DOWN
		CharacterVisualProfileData.Direction.UP:
			return Vector2.UP
		CharacterVisualProfileData.Direction.LEFT:
			return Vector2.LEFT
		_:
			return Vector2.RIGHT


func _finish_turn() -> void:
	_turn_left = 0.0
	_shown_direction = _direction


static func _opposite(direction: int) -> int:
	match direction:
		CharacterVisualProfileData.Direction.DOWN:
			return CharacterVisualProfileData.Direction.UP
		CharacterVisualProfileData.Direction.UP:
			return CharacterVisualProfileData.Direction.DOWN
		CharacterVisualProfileData.Direction.LEFT:
			return CharacterVisualProfileData.Direction.RIGHT
		_:
			return CharacterVisualProfileData.Direction.LEFT


# === Readouts (tests / debug) ================================================

## The animation column currently showing: the action's while one plays, else locomotion's.
func get_column() -> int:
	return _action_column if _action != ACTION_NONE else _column


## The LOGICAL facing Direction (what the owner asked for).
func get_direction() -> int:
	return _direction


## The facing row actually RENDERED — differs from `get_direction()` only during the
## intermediate frame of a 180° turn.
func get_shown_direction() -> int:
	return _shown_direction


## The locomotion gait (`Gait`): IDLE, WALK or SETTLE.
func gait() -> int:
	return _gait


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
	_sprite_rest = Vector2(
		-_profile.frame_size.x / 2.0 + _profile.anchor_offset.x,
		-_profile.frame_size.y + _profile.anchor_offset.y)
	_sprite.position = _sprite_rest
	_gait = Gait.IDLE
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
	if not is_strike_action(_action) or _attack_source == null \
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


## True when locomotion is rendering the walk sheet: walking, or settling a stop.
func _shows_walk() -> bool:
	return _gait != Gait.IDLE and _profile.walk_sheet != null


## The sheet that should be showing right now.
##
## PRECEDENCE: action, then walk (or its settle), then idle. The action is checked FIRST because
## it out-ranks locomotion — a character mid-swing shows the swing even while walking
## (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §2).
func _active_sheet() -> Texture2D:
	if _profile == null:
		return null
	if _action != ACTION_NONE:
		var action_sheet := _sheet_for_action(_action)
		if action_sheet != null:
			return action_sheet
	if _shows_walk():
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
	var column := _column
	if _action != ACTION_NONE:
		# ONE-SHOT: the column is a pure function of the driven progress, CLAMPED to the last
		# frame rather than wrapped. A modulo here would loop the swing, which is what makes an
		# action different in kind from a locomotion cycle rather than just a different sheet.
		_action_column = column_for_progress(_action_progress, total)
		column = _action_column
	elif _column >= total:
		_column = 0
		column = 0
	# Grid index: rows are directions, columns are animation frames.
	_sprite.frame = _shown_direction * total + column
	# Only pay for _process when something can change the frame: a multi-frame sheet, an action
	# (it must still be ENDED), a gait in progress (the stride reads displacement), a moving
	# intent (a blocked body must notice when it moves again) or a turn in flight.
	var should_process := (total > 1 or _action != ACTION_NONE or _gait != Gait.IDLE
		or _moving or _turn_left > 0.0)
	if is_processing() != should_process:
		set_process(should_process)

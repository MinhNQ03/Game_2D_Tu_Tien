extends Node2D
class_name HitReaction
## HitReaction — Aetheria presentation (the BODY's physical response to a landed hit, D-057B).
##
## Before it, a struck wolf or post answered a blow only with a colour flash (`DamageFeedback`):
## the number changed and nothing was pushed — "the enemy's HP drops with no sense that it was
## struck" (`MOTION_DESIGN_CONTRACT.md` M-5.1). This node is layer 6 of M-5.2, the target
## reaction, and it obeys the governing law of WHAT was struck (M-2.1):
##
##   * `RECOIL` — a creature or a cultivator. The drawn body is shoved a few WHOLE pixels along
##     the blow, fast, and eases back: a body with weight and footing absorbing a strike.
##   * `PIVOT_WOBBLE` — a rigid object rooted at its base (the training post). It does not
##     travel; it LEANS away about its footing and rocks back, a damped oscillation, through the
##     `lean_px` of its `pixel_sway` material (a whole-pixel row shear, so no rotated "mixels").
##
## PURE PRESENTATION. It listens to `HurtboxComponent.damaged`, whose `push_direction` is a
## semantic fact of the hit (attacker -> target), and it moves ONLY the drawing: the entity, its
## collision and its hurtbox stay exactly where gameplay put them, and nothing here can decide a
## hit, a position or a death (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §3). Its clock is the
## transient-feedback kind M-5.4 allows: it decides nothing and ends on its own.
##
## A critical hit shoves harder (`critical_scale`) — the same fact `DamageFeedback` tints by, so
## the two layers agree. No camera shake: a basic hit is seen a thousand times (M-4.8, M-9.2).
##
## THE IMPACT is drawn here too, because it is what the struck body RECEIVES: a contact flash on
## the side the blow came from, and DEBRIS that obeys the struck MATERIAL — straw chaff from the
## post falls under gravity, the mist wolf sheds wisps that drift up, a cultivator's robe throws
## short pale streaks. The debris flies ALONG the blow (the force goes through the body), with a
## little back-splash, and is gone in a fifth of a second. Its pattern is a fixed table rotated
## a little per hit: varied, never random (M-8.2).
##
## The impact lives in WORLD space (`top_level`): debris that has left a body does not follow
## the body's recoil or walk, and it is not tinted by the body's hit flash (`DamageFeedback`
## owns the PARENT's modulate, which would otherwise cascade into the straw and turn it red).

enum Response { RECOIL, PIVOT_WOBBLE }

@export var response: Response = Response.RECOIL

## RECOIL: the peak displacement of the drawn body along the blow, in pixels (rounded to whole
## pixels every frame — a sub-pixel offset on nearest-filtered art shimmers).
@export var recoil_px: float = 3.0

## RECOIL: seconds from impact back to rest. The shove takes the first quarter.
@export var recoil_seconds: float = 0.18

## PIVOT_WOBBLE: the peak lean of the free end, in pixels.
@export var wobble_px: float = 3.0

## PIVOT_WOBBLE: oscillation frequency (Hz) and the seconds until it is fully at rest.
@export var wobble_hz: float = 4.0
@export var wobble_seconds: float = 0.75

## Multiplier on the displacement for a critical hit.
@export var critical_scale: float = 1.6

## PIVOT_WOBBLE: the CanvasItem whose `ShaderMaterial` carries `lean_px`.
@export var wobble_target: NodePath = ^"../Visual"

## THE IMPACT, per material. `debris_colour` is the material's (straw, mist, cloth);
## `debris_gravity` (px/s²) makes it fall (> 0, chaff), hang (0, sparks) or rise (< 0, mist).
@export var debris_colour: Color = Color(0.93, 0.92, 0.86)
@export var debris_gravity: float = 0.0
## Height (px above the feet) of the contact point on a body with no `core` anchor.
@export var impact_height: float = 14.0

## How long the impact (flash + debris) lasts, in seconds; a critical one lasts longer.
const IMPACT_SECONDS := 0.2
const IMPACT_SECONDS_CRITICAL := 0.26
## The contact flash shows for this long at the start of the impact.
const FLASH_SECONDS := 0.05
## The contact point sits this far from the body's core, toward the striker.
const CONTACT_INSET := 5.0

## The debris pattern: (angle off the blow in degrees, speed px/s, streak length px). Most of it
## goes THROUGH the body along the blow; the last entry is the back-splash.
const DEBRIS := [
	[-48.0, 70.0, 3.0], [-18.0, 96.0, 4.0], [4.0, 84.0, 3.0], [27.0, 104.0, 4.0],
	[56.0, 66.0, 2.0], [172.0, 44.0, 2.0],
]
## A critical hit adds these.
const DEBRIS_CRITICAL := [[-34.0, 120.0, 5.0], [41.0, 126.0, 5.0], [194.0, 52.0, 2.0]]

## The share of the recoil spent on the shove itself; the rest eases back.
const SHOVE_SHARE := 0.25

## How fast the wobble's envelope decays (1/s): about four visible rocks before rest.
const WOBBLE_DECAY := 5.5

var _hurtbox: HurtboxComponent = null
var _push: Vector2 = Vector2.ZERO
var _amplitude: float = 0.0
var _elapsed: float = 0.0
var _active: bool = false

## The impact in flight: where it struck (this node's space), whether it was critical, its
## age, and how far this hit's pattern is turned (a per-hit counter, not a random draw).
var _impact_at: Vector2 = Vector2.ZERO
var _impact_critical: bool = false
var _impact_elapsed: float = -1.0
var _hits: int = 0
var _pattern_turn: float = 0.0


func _ready() -> void:
	set_process(false)
	# Above the body it lands on: an impact drawn behind the body is an impact nobody sees.
	z_index = 1
	top_level = true
	global_position = Vector2.ZERO
	_hurtbox = get_parent().get_node_or_null("HurtboxComponent") as HurtboxComponent
	if _hurtbox == null:
		push_error("[hit_reaction] no sibling HurtboxComponent: nothing can strike this body")
		return
	_hurtbox.damaged.connect(_on_damaged)


func _on_damaged(amount: int, is_critical: bool, push_direction: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0:
		return
	_push = push_direction
	if _push == Vector2.ZERO:
		_push = Vector2.DOWN  # a hit with no direction still lands: shove away from the viewer
	var strength := critical_scale if is_critical else 1.0
	_amplitude = (recoil_px if response == Response.RECOIL else wobble_px) * strength
	_elapsed = 0.0
	_active = true
	_apply(0.0)
	_begin_impact(is_critical)
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## Advance the reaction by `delta` seconds. PUBLIC so a test can step it deterministically —
## the same contract as `DamageFeedback.advance()`.
func advance(delta: float) -> void:
	if _impact_elapsed >= 0.0:
		_impact_elapsed += delta
		if _impact_elapsed >= _impact_seconds():
			_impact_elapsed = -1.0
		queue_redraw()
	if _active:
		_elapsed += delta
		var duration := recoil_seconds if response == Response.RECOIL else wobble_seconds
		if _elapsed >= duration:
			_finish()
		else:
			_apply(_elapsed)
	if not _active and _impact_elapsed < 0.0:
		set_process(false)


func is_reacting() -> bool:
	return _active


func is_showing_impact() -> bool:
	return _impact_elapsed >= 0.0


## Where the current impact struck, in WORLD space.
func impact_point() -> Vector2:
	return _impact_at


## The debris of the current impact at its current age, as [start, end] segments in WORLD
## space — what `_draw` draws, exposed so a test can check the debris follows the blow and the
## material's gravity without reading pixels.
func debris_segments() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if _impact_elapsed < 0.0:
		return out
	var t := _impact_elapsed
	var life := _impact_seconds()
	var fade := clampf(t / life, 0.0, 1.0)
	var pattern: Array = DEBRIS.duplicate()
	if _impact_critical:
		pattern.append_array(DEBRIS_CRITICAL)
	var base := _push.angle() + _pattern_turn
	for entry: Array in pattern:
		var dir := Vector2.from_angle(base + deg_to_rad(float(entry[0])))
		var speed := float(entry[1])
		var length := float(entry[2]) * (1.0 - fade)
		var fall := Vector2(0.0, 0.5 * debris_gravity * t * t)
		var head := _impact_at + dir * speed * t + fall
		var tail := head - dir * maxf(length, 1.0)
		out.append(PackedVector2Array([tail.round(), head.round()]))
	return out


func _begin_impact(is_critical: bool) -> void:
	_impact_critical = is_critical
	_impact_elapsed = 0.0
	_hits += 1
	# Turn each hit's pattern by a fixed step inside ±12°, so two hits in a row never throw the
	# identical spray. Deterministic: the n-th hit always looks the same.
	_pattern_turn = deg_to_rad(float((_hits * 7) % 25) - 12.0)
	_impact_at = _contact_point()
	queue_redraw()


## The point the blow struck, in world space: the body's core, moved toward the striker by
## `CONTACT_INSET`.
func _contact_point() -> Vector2:
	var core := Vector2(0.0, -impact_height)
	var visual := _visual()
	if visual != null and visual.has_anchor(CharacterVisualProfileData.POINT_CORE):
		core = visual.position + visual.anchor_point(CharacterVisualProfileData.POINT_CORE)
	var body := get_parent() as Node2D
	var world := body.global_transform * core if body != null else core
	return (world - _push * CONTACT_INSET).round()


func _impact_seconds() -> float:
	return IMPACT_SECONDS_CRITICAL if _impact_critical else IMPACT_SECONDS


func _draw() -> void:
	if _impact_elapsed < 0.0:
		return
	var fade := clampf(_impact_elapsed / _impact_seconds(), 0.0, 1.0)
	if _impact_elapsed < FLASH_SECONDS:
		# The contact flash: a small cross, gold on a critical. Whole pixels, no glow sprite.
		var flash := UIPalette.IMPACT_FLASH_CRITICAL if _impact_critical \
			else UIPalette.IMPACT_FLASH
		var arm := 3.0 if _impact_critical else 2.0
		draw_rect(Rect2(_impact_at - Vector2(arm, 0.0), Vector2(arm * 2.0 + 1.0, 1.0)), flash)
		draw_rect(Rect2(_impact_at - Vector2(0.0, arm), Vector2(1.0, arm * 2.0 + 1.0)), flash)
	var colour := debris_colour
	colour.a = 0.95 * (1.0 - fade * fade)
	for segment in debris_segments():
		draw_line(segment[0], segment[1], colour, 1.0)


## The displacement the drawn body shows at `t` seconds after impact (RECOIL), in whole pixels.
func recoil_offset(t: float) -> Vector2:
	if recoil_seconds <= 0.0:
		return Vector2.ZERO
	var u := clampf(t / recoil_seconds, 0.0, 1.0)
	var k: float
	if u < SHOVE_SHARE:
		var s := u / SHOVE_SHARE
		k = 1.0 - (1.0 - s) * (1.0 - s)  # ease-out: the blow arrives at once
	else:
		var r := (u - SHOVE_SHARE) / (1.0 - SHOVE_SHARE)
		k = 1.0 - r * r * (3.0 - 2.0 * r)  # smoothstep back to the footing
	return (_push * _amplitude * k).round()


## The lean of the free end at `t` seconds after impact (PIVOT_WOBBLE), in pixels. It starts at
## zero and leans AWAY from the blow first: a post is pushed, it does not teleport.
func wobble_lean(t: float) -> float:
	var side := signf(_push.x) if absf(_push.x) > 0.2 else 1.0
	# A blow along the view axis still rocks the post, at half the lean: in a top-down view a
	# push away from the camera is mostly foreshortening, not a sideways tilt.
	var share := maxf(absf(_push.x), 0.5)
	return _amplitude * share * side * exp(-t * WOBBLE_DECAY) * sin(TAU * wobble_hz * t)


func _apply(t: float) -> void:
	match response:
		Response.RECOIL:
			var visual := _visual()
			if visual != null:
				visual.set_sprite_offset(recoil_offset(t))
		Response.PIVOT_WOBBLE:
			_set_lean(wobble_lean(t))


func _finish() -> void:
	_active = false
	_elapsed = 0.0
	match response:
		Response.RECOIL:
			var visual := _visual()
			if visual != null:
				visual.set_sprite_offset(Vector2.ZERO)  # ASSIGNED: rest is exact, never decayed
		Response.PIVOT_WOBBLE:
			_set_lean(0.0)


## The runtime-built visual of a creature or the player. Resolved per hit rather than cached:
## it is created after this node's `_ready`, and the player's may be rebuilt.
func _visual() -> CharacterVisualComponent:
	return get_parent().get_node_or_null("CharacterVisualComponent") as CharacterVisualComponent


func _set_lean(lean: float) -> void:
	var target := get_node_or_null(wobble_target) as CanvasItem
	if target == null:
		return
	var material := target.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"lean_px", lean)

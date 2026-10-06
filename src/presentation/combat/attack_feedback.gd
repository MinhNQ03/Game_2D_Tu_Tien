extends Node2D
class_name AttackFeedback
## AttackFeedback — Aetheria presentation (makes a swing VISIBLE: Phase 10 / D-051 §10b,
## rebuilt as a causal effect in D-057B).
##
## Draws the attack lifecycle. Nothing more.
##
## WHY IT EXISTS. Phase 09 shipped a correct `READY → WINDUP → ACTIVE → RECOVERY` state machine
## the player could not perceive at all. Phase 10 answered with one arc whose radius, width and
## alpha changed per phase — readable, but an arc drawn around the FEET has no source: nothing
## connects it to the hand that strikes, so it read as a ring that appears, not a blow that is
## thrown (`MOTION_DESIGN_CONTRACT.md` M-5.1, M-2.2).
##
## THE CAUSAL CHAIN IT DRAWS NOW (M-1.2, energy/force law of M-2.1: source → release → propagate
## → dissipate):
##
##   * WINDUP — for a HOSTILE swing, a GROUND TELEGRAPH of the reach it will cover: a thin
##     warning-red arc with end ticks on the ground under every body (its own child at z -1),
##     growing to full strength as the bite approaches — a telegraph is read and learned once
##     (`COMBAT_DESIGN.md` §7). The player's OWN swing draws none: its anticipation is the
##     body's coil (the action layer), and a ring around the player's feet on every one of a
##     thousand swings is noise (M-4.8; the first D-057B capture showed it as a stray curve in
##     the grass). Nothing glows at the hand: a PHÀM striker has no qi to show.
##   * ACTIVE — the RELEASE: streaks of driven air leave the STRIKING POINT (the `palm` anchor of
##     the frame being drawn — the wolf's jaw is its `palm`) and travel along the facing to the
##     edge of the reach. The source is the drawn hand on every facing and every frame, never a
##     guessed offset from the feet.
##   * RECOVERY — DISSIPATION: the streaks run on a few pixels, thin and fade; the telegraph is
##     gone. What is left is the cost of having swung, readable without a lingering ring.
##
## The IMPACT is not drawn here: it belongs to the struck body (`HitReaction`), which knows the
## blow landed and from where. This node draws what the attacker MAKES; that one draws what the
## target RECEIVES — the split an authoritative "attack started" / "attack hit" pair will need.
##
## IT IS PURE PRESENTATION. It reads the `AttackComponent`'s state and draws; it decides
## nothing, resolves nothing, and removing it changes no outcome. Every phase value is derived
## from the state machine's own remaining time — no clock of its own (M-5.4).
##
## IT COSTS NOTHING WHEN IDLE. `_process` is off in READY and switched on by the component's
## own `attack_started` signal, which matters because every enemy carries one of these. No
## particles, no shaders, no tweens: a handful of `draw_line` calls per frame of a swing, snapped
## to whole pixels so the 2x-zoomed pixel art stays crisp.

## Telegraph arc half-angle as a fraction of the authored `arc_degrees`. Slightly narrower than
## the real hit arc: over-promising reach is worse than under-promising it.
const ARC_FRACTION := 0.9

## Segments in the drawn telegraph arc: enough to read as a curve at 16px scale, cheap to draw.
const ARC_SEGMENTS := 12

## The streaks of driven air: perpendicular offsets (px) and how far behind the lead streak
## each one starts (a fraction of the throw), so they read as a volume of air, not one line.
const STREAK_OFFSETS: Array[float] = [-2.0, 0.0, 2.0]
const STREAK_LAGS: Array[float] = [0.18, 0.0, 0.12]

## How far the air keeps going past the reach while it dissipates, in pixels.
const DISSIPATE_PX := 5.0

## A DOWN-facing strike comes toward the viewer: its streaks start below the body (at this
## height above the feet) instead of being drawn across the striker's own legs (M-6.3).
const DOWN_STRIKE_START_Y := -4.0

## The height (px above the ground) a sideways strike's air arrives at: the body height of the
## things it hits — a wolf's core is ~12px up, a cultivator's ~16-20px.
const STRIKE_HEIGHT := -13.0

## A hostile swing telegraphs its reach on the ground. Authored per scene (`enemy.tscn`).
@export var hostile: bool = false

var _attack: AttackComponent = null
## The ground-telegraph layer: a child drawn at z -1, under every body but above the floor.
var _telegraph: Node2D = null

## Cached so `_draw` never calls into the component: `_draw` runs inside the renderer, and
## reaching into gameplay from there is how a presentation node ends up driving a frame.
var _state: int = AttackStateMachine.State.READY
var _progress: float = 0.0
var _facing: Vector2 = Vector2.DOWN
var _reach: float = 24.0
var _arc_degrees: float = 120.0
## Where the release starts (the striking point at the moment of release, this node's space).
var _source: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_process(false)
	_telegraph = Node2D.new()
	_telegraph.name = "Telegraph"
	_telegraph.z_as_relative = false
	_telegraph.z_index = -1
	_telegraph.draw.connect(_draw_telegraph)
	add_child(_telegraph)
	var component := get_parent().get_node_or_null("AttackComponent") as AttackComponent
	if component == null:
		# Not an error: an entity that cannot attack legitimately has no component. The node
		# simply never draws.
		return
	_attack = component
	_attack.attack_started.connect(_on_attack_started)
	_attack.attack_finished.connect(_on_attack_finished)


func _on_attack_started() -> void:
	# Read the authored geometry ONCE per swing rather than every frame.
	var data := _attack_data()
	if data != null:
		_reach = data.reach_pixels
		_arc_degrees = data.arc_degrees
	set_process(true)
	_sync()


func _on_attack_finished() -> void:
	set_process(false)
	_state = AttackStateMachine.State.READY
	queue_redraw()
	_telegraph.queue_redraw()


func _process(_delta: float) -> void:
	_sync()


## Pull the lifecycle into the draw cache (tests reach it through `sample()`).
func _sync() -> void:
	if _attack == null:
		return
	_state = _attack.state()
	_facing = _attack.facing()
	_progress = _phase_progress()
	# The strike leaves from the hand that is DRAWN. Behind the body when it faces away, in
	# front of it otherwise: a swing that renders behind a character facing the viewer is a
	# swing the player does not see, and one drawn over the head of a character facing away is
	# drawn through the body.
	var layer := 0 if _facing.y < -0.5 else 1
	if z_index != layer:
		z_index = layer
	if _state != AttackStateMachine.State.RECOVERY:
		_source = _striking_point()
	queue_redraw()
	_telegraph.queue_redraw()


## What this node would draw right now, for tests: the phase, its progress, and the release
## segment (empty outside ACTIVE/RECOVERY).
func sample() -> Dictionary:
	_sync()
	var segment := _streak_segment(0.0)
	return {
		"state": _state,
		"progress": _progress,
		"source": _source,
		"telegraph": hostile and _state == AttackStateMachine.State.WINDUP,
		"streak": segment,
		"z_index": z_index,
	}


## How far through the CURRENT phase the swing is, in [0, 1].
##
## Derived from the state machine's own remaining time rather than from a timer of its own, so
## the drawing cannot drift out of step with the mechanics it is depicting.
func _phase_progress() -> float:
	var data := _attack_data()
	if data == null:
		return 0.0
	var total := 0.0
	match _state:
		AttackStateMachine.State.WINDUP:
			total = data.windup_seconds
		AttackStateMachine.State.ACTIVE:
			total = data.active_seconds
		AttackStateMachine.State.RECOVERY:
			total = data.recovery_seconds
		_:
			return 0.0
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - (_attack.time_remaining() / total), 0.0, 1.0)


func _attack_data() -> AttackData:
	return _attack.attack_data() if _attack != null else null


## The striking point of the frame being drawn, in this node's space: the visual's `palm`
## anchor when the entity has one, else a point a third of the reach along the facing at body
## height — a documented degradation, not a guess presented as the hand.
func _striking_point() -> Vector2:
	var visual := get_parent().get_node_or_null("CharacterVisualComponent") \
		as CharacterVisualComponent
	var point := _facing * _reach * 0.33 + Vector2(0.0, -12.0)
	if visual != null and visual.has_anchor(CharacterVisualProfileData.POINT_PALM):
		point = visual.position + visual.anchor_point(CharacterVisualProfileData.POINT_PALM)
	if _facing.y > 0.5:
		point.y = maxf(point.y, DOWN_STRIKE_START_Y)
	return point


## The lead streak as [tail, head] in this node's space, or empty when no air is moving.
## `lag` delays a streak's start as a fraction of the throw.
func _streak_segment(lag: float) -> PackedVector2Array:
	# The air runs from the hand to the edge of the reach, measured along the facing (the hit
	# test's own geometry) and at least a third of the reach, so a hand already near the edge
	# still throws a visible streak. It ends at STRIKE_HEIGHT above the ground rather than at the
	# hand's own height: a chest-high palm thrown level passed OVER a wolf's back in the first
	# D-057B capture while the wolf took the hit. Angled down to body height, it meets a
	# creature and a cultivator alike.
	var along := maxf(_reach - _source.dot(_facing), _reach * 0.35)
	var reach_end := _source + _facing * along
	if absf(_facing.x) > 0.5:
		reach_end.y = maxf(reach_end.y, STRIKE_HEIGHT)
	match _state:
		AttackStateMachine.State.ACTIVE:
			var p := clampf((_progress - lag) / maxf(1.0 - lag, 0.01), 0.0, 1.0)
			var lead := 1.0 - (1.0 - p) * (1.0 - p)  # ease-out: the air leaves the hand fast
			var head := _source.lerp(reach_end, lead)
			var tail := _source.lerp(reach_end, maxf(0.0, lead - 0.55))
			return PackedVector2Array([tail.round(), head.round()])
		AttackStateMachine.State.RECOVERY:
			var p := _progress
			if p >= 1.0:
				return PackedVector2Array()
			var head := reach_end + _facing * DISSIPATE_PX * p
			var tail := _source.lerp(reach_end, 0.45 + 0.55 * p)
			return PackedVector2Array([tail.round(), head.round()])
		_:
			return PackedVector2Array()


func _draw() -> void:
	if _facing == Vector2.ZERO:
		return
	var alpha := 0.0
	match _state:
		AttackStateMachine.State.ACTIVE:
			alpha = 0.95
		AttackStateMachine.State.RECOVERY:
			alpha = 0.7 * (1.0 - _progress) * (1.0 - _progress)
		_:
			return
	var data := _attack_data()
	if data != null and data.weapon_family == &"weapon_kiem":
		_draw_blade_sweep(alpha)
		return
	var side := _facing.orthogonal()
	for i in STREAK_OFFSETS.size():
		var segment := _streak_segment(STREAK_LAGS[i])
		if segment.size() < 2 or segment[0] == segment[1]:
			continue
		var offset := (side * STREAK_OFFSETS[i]).round()
		var colour := UIPalette.STRIKE_TRAIL
		# The middle streak is the core of the push; the outer two are thinner air.
		colour.a = alpha * (1.0 if i == 1 else 0.55)
		draw_line(segment[0] + offset, segment[1] + offset, colour, 1.0)


## The ground telegraph: the reach the swing will cover, on the floor, during the wind-up.
func _draw_telegraph() -> void:
	if not hostile or _state != AttackStateMachine.State.WINDUP or _facing == Vector2.ZERO:
		return
	# A warning the player must read: it grows to full strength as the bite approaches.
	var colour := UIPalette.TELEGRAPH_HOSTILE
	colour.a = lerpf(0.25, 0.8, _progress)
	var centre := _facing.angle()
	var half := deg_to_rad(_arc_degrees * 0.5 * ARC_FRACTION)
	# A double line: one pixel at 2x zoom read as a stray hair in the grass, not a warning.
	_telegraph.draw_arc(Vector2.ZERO, _reach, centre - half, centre + half, ARC_SEGMENTS,
		colour, 1.0)
	var inner := colour
	inner.a *= 0.5
	_telegraph.draw_arc(Vector2.ZERO, _reach - 2.0, centre - half, centre + half, ARC_SEGMENTS,
		inner, 1.0)
	# End ticks: the arc's edges are where the hit stops, so they are marked.
	for edge in [centre - half, centre + half]:
		var dir := Vector2.from_angle(edge)
		_telegraph.draw_line((dir * (_reach - 3.0)).round(), (dir * _reach).round(), colour, 1.0)


## A Kiếm draws a CRESCENT, not air: the edge sweeping across the arc it actually covers, at body
## height, growing through the hit window and thinning through the recovery (Phase 14). The
## palm's air streaks would claim a palm strike while a sword is in the hand.
func _draw_blade_sweep(alpha: float) -> void:
	var half := deg_to_rad(_arc_degrees * 0.5 * ARC_FRACTION)
	var start := _facing.angle() - half
	var sweep := 1.0
	if _state == AttackStateMachine.State.ACTIVE:
		sweep = 1.0 - (1.0 - _progress) * (1.0 - _progress)
	var centre := Vector2(0.0, STRIKE_HEIGHT * 0.8)
	var radius := _reach * 0.8
	var colour := UIPalette.STRIKE_TRAIL
	colour.a = alpha
	draw_arc(centre, radius, start, start + 2.0 * half * sweep, ARC_SEGMENTS, colour, 2.0)
	colour.a = alpha * 0.45
	draw_arc(centre, radius - 3.0, start, start + 2.0 * half * sweep, ARC_SEGMENTS, colour, 1.0)


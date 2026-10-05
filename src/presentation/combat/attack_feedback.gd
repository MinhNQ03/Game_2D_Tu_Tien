extends Node2D
class_name AttackFeedback
## AttackFeedback — Aetheria presentation (makes a swing VISIBLE, Phase 10 / D-051 §10b).
##
## Draws the attack lifecycle. Nothing more.
##
## WHY IT EXISTS. Phase 09 shipped a correct `READY → WINDUP → ACTIVE → RECOVERY` state
## machine that the player could not perceive at all: pressing attack produced no swing, no
## impact and no recovery pause — only a number changing on the target. A playtest screenshot
## taken mid-attack showed a character standing still next to an undamaged-looking post
## (D-051 recorded it as COMBAT PRESENTATION DEBT). `COMBAT_DESIGN.md` §1 asks that hitting
## feel good and threats be readable, and §7 makes telegraph language a thing the player learns
## once — a telegraph nobody can see is not a telegraph.
##
## IT IS PURE PRESENTATION. It reads the `AttackComponent`'s state and draws; it decides
## nothing, resolves nothing, and removing it changes no outcome. The domain never knows it
## exists.
##
## RESTRAINT IS THE DESIGN, not a limitation. Three states are distinguished by ONE arc whose
## radius, width and alpha change — no particles, no shaders, no tweens, no VFX framework
## (C13: "the smallest asset set that looks intentional"). Every colour comes from `UIPalette`,
## so combat feedback cannot drift from the game's palette (C18: no ad-hoc combat styling).
##
## IT COSTS NOTHING WHEN IDLE. `_process` is off in READY and switched on by the component's
## own `attack_started` signal, which matters because every enemy carries one of these.

## Arc half-angle as a fraction of the attack's authored `arc_degrees`. Slightly narrower than
## the real hit arc: an arc drawn at exactly the hit width reads as a promise of reach the
## edges do not quite deliver, and over-promising reach is worse than under-promising it.
const ARC_FRACTION := 0.9

## Radius the WINDUP arc starts at, as a fraction of full reach. The wind-up should read as
## "gathering", so it begins close to the body and grows.
const WINDUP_START_SCALE := 0.35

## Line widths per phase, in pixels. ACTIVE is the thickest because it is the only phase in
## which a hit can land — the visual weight matches the mechanical weight.
const WINDUP_WIDTH := 2.0
const ACTIVE_WIDTH := 4.0
const RECOVERY_WIDTH := 2.0

## Segments in the drawn arc. 12 is enough to read as a curve at 16px scale and cheap to draw.
const ARC_SEGMENTS := 12

var _attack: AttackComponent = null
## Cached so `_draw` never calls into the component: `_draw` runs inside the renderer, and
## reaching into gameplay from there is how a presentation node ends up driving a frame.
var _state: int = AttackStateMachine.State.READY
var _progress: float = 0.0
var _facing: Vector2 = Vector2.DOWN
var _reach: float = 24.0
var _arc_degrees: float = 120.0


func _ready() -> void:
	set_process(false)
	# Drawn ABOVE the body sprite: a swing that renders behind the character is a swing the
	# player does not see.
	z_index = 1
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


func _on_attack_finished() -> void:
	set_process(false)
	_state = AttackStateMachine.State.READY
	queue_redraw()


func _process(_delta: float) -> void:
	if _attack == null:
		return
	_state = _attack.state()
	_facing = _attack.facing()
	_progress = _phase_progress()
	queue_redraw()


## How far through the CURRENT phase the swing is, in [0, 1].
##
## Derived from the state machine's own remaining time rather than from a timer of its own, so
## the drawing cannot drift out of step with the mechanics it is depicting — the exact failure
## mode of a presentation layer that keeps its own clock.
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


func _draw() -> void:
	if _state == AttackStateMachine.State.READY or _facing == Vector2.ZERO:
		return
	var colour: Color
	var radius: float
	var width: float
	match _state:
		AttackStateMachine.State.WINDUP:
			# GATHERING: a dim, thin arc that grows toward full reach. The player can see a
			# commitment being made before anything can be hit.
			colour = UIPalette.GAUGE_FILL
			colour.a = 0.30 + 0.35 * _progress
			radius = _reach * lerpf(WINDUP_START_SCALE, 0.85, _progress)
			width = WINDUP_WIDTH
		AttackStateMachine.State.ACTIVE:
			# THE HIT WINDOW: bright, full reach, thickest. This is the only phase that can
			# land, and it is the only one that looks like a strike.
			colour = UIPalette.GOLD_PRIMARY
			colour.a = 0.95
			radius = _reach
			width = ACTIVE_WIDTH
		_:
			# RECOVERY: fading out at full reach, so the cost of having swung is visible —
			# which is what makes the timing readable rather than instantaneous.
			colour = UIPalette.GOLD_SECONDARY
			colour.a = 0.45 * (1.0 - _progress)
			radius = _reach
			width = RECOVERY_WIDTH
	var centre := deg_to_rad(rad_to_deg(_facing.angle()))
	var half := deg_to_rad(_arc_degrees * 0.5 * ARC_FRACTION)
	draw_arc(Vector2.ZERO, radius, centre - half, centre + half, ARC_SEGMENTS, colour, width)

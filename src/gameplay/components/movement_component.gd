extends Node
class_name MovementComponent
## MovementComponent — Aetheria gameplay (entity component).
##
## Turns a MOVE INTENT (a direction vector) into collision-aware top-down motion on a
## `CharacterBody2D`. It is the intent boundary required by `docs/MULTIPLAYER_PLAN.md`
## §2/§3: today the Player feeds intent from `InputService`; later a network command can
## feed the SAME `apply_intent(...)` without changing this component. It does NOT read
## input itself (no `Input.*`, no physical keys) and does NOT own speed (that comes from
## StatsComponent/data) — it just applies motion.
##
## Pure-math helper `resolve_velocity()` is separated so movement direction/speed logic is
## unit-testable headless without a physics step (`docs/TEST_PLAN.md` §3).
##
## TWO WAYS TO MOVE, one per kind of caller:
##   * `apply_intent` — go THIS way. The player's keys, a patrol heading, a retreat. A wall
##     stops it, and that is correct: the player is the one who steers.
##   * `apply_pursuit` — get THERE. A brain that wants to reach a target or a home has nobody
##     to steer for it, so this is where "walk round the tree" lives (Q19-04). The brain still
##     only says APPROACH; world space, collision and the way round stay on this side.

## How squarely a pursuer must run into something before it stops sliding and walks round:
## the cosine between its heading and the surface normal. Below it, `move_and_slide` already
## carries the body along the surface at most of its speed and nothing needs deciding.
const DETOUR_START_DOT := 0.7
## The look-ahead is one physics step of travel plus this, so "the line is clear" means the
## next step really is, whatever the body's resting gap against the surface.
const DETOUR_PROBE_MARGIN_PX := 1.0
## The way round when a pursuer meets a surface exactly head-on and neither side is nearer the
## target. A constant, not a draw: the same meeting always resolves the same way, on every
## machine and in every replay (no `rand*`, no stream consumed).
const DETOUR_DEFAULT_HAND := 1
## Below this lean (the cosine between the straight line and the surface) it is a head-on tie.
const DETOUR_TIE_LEAN := 0.01

## The body this component moves. Set via @export in the entity scene, or `setup()` in code.
@export var body: CharacterBody2D = null

## Which way round the thing in the way: +1 / -1 while one is being walked round, 0 while the
## pursuit is on its straight line. HELD for as long as the line stays blocked — that is what
## carries a pursuer past the point where the target is dead ahead, where "the side the target
## is on" changes sign and a rule that re-chose every tick would turn back.
var _detour_hand: int = 0
## One change of mind per obstacle. The chosen way can be shut (a tree against the map's edge);
## the other is tried once, and a body shut in on both sides stays put instead of pacing.
var _detour_reversed: bool = false
## Reused by every look-ahead, so a detour allocates nothing per tick.
var _probe_hit: KinematicCollision2D = null
## Look-aheads made since this component was built — a read-only counter, so a budget test can
## assert the query RATE (none in the open, at most one a tick) instead of trusting the rule.
var _probes: int = 0


## Inject the body in code (used by scenes/tests that build the entity programmatically).
const FIXED_STEP_ONLY := ("a body is moved from the fixed physics step only: outside it "
	+ "move_and_slide() integrates against the wall-clock frame time (H21-21)")


func setup(target_body: CharacterBody2D) -> void:
	body = target_body


## Pure, physics-free: given a raw intent and a speed, return the velocity to apply.
## - intent is normalized so diagonal movement is NOT faster than cardinal.
## - a near-zero intent or non-positive speed yields ZERO (deterministic stop).
## Static so tests can call it without any node/physics.
static func resolve_velocity(intent: Vector2, speed: float) -> Vector2:
	if speed <= 0.0:
		return Vector2.ZERO
	if intent.length() < 0.001:
		return Vector2.ZERO
	return intent.normalized() * speed


## Apply a move intent for this physics frame. Sets the body's velocity from
## `resolve_velocity()` and advances it with `move_and_slide()` (collision-aware; never a
## raw `position += velocity * delta` teleport). Returns the body's post-slide velocity.
## Call from the owner's `_physics_process` only — asserted in debug builds (`in_fixed_step`); a
## test steps it from inside a physics frame (`TestCase.fixed_step`).
##
## `_delta` is part of the Phase-02 contract but intentionally UNUSED: `move_and_slide()`
## already integrates against Godot's fixed physics step internally, so multiplying speed
## by `delta` here would double-apply the timestep. The parameter is kept so the call site
## reads as a normal per-physics-frame call and so a future movement model that *does* need
## the frame time (e.g. manual acceleration curves) can use it without changing the
## signature callers depend on (the multiplayer intent boundary, `docs/MULTIPLAYER_PLAN.md`).
func apply_intent(intent: Vector2, speed: float, _delta: float = 0.0) -> Vector2:
	if body == null:
		push_error("[movement] apply_intent with no body assigned")
		return Vector2.ZERO
	body.velocity = resolve_velocity(intent, speed)
	assert(in_fixed_step(), FIXED_STEP_ONLY)
	body.move_and_slide()
	return body.velocity


## True inside the engine's fixed physics step — the only place a body may be moved from.
##
## WHY IT IS ENFORCED (H21-21). `move_and_slide()` takes no delta: inside a physics frame it
## integrates against the fixed physics step, and OUTSIDE one against the engine's process
## step — a wall-clock quantity that the engine also clamps and compensates. A caller outside
## the physics step therefore moves its body by `speed x how long the last rendered frame
## happened to take`: under 0.1 ms nothing moves at all, at 150 ms one tick is a third of a
## second of travel. Twenty tests stepped their worlds that way and passed on luck; the
## pet-kill one failed once in CI with nobody having moved in 2400 ticks.
static func in_fixed_step() -> bool:
	return Engine.is_in_physics_frame()


## Pursue: move toward `toward` and, when something solid stands squarely in the way, walk
## ROUND it instead of pressing against it. Returns the unit heading the body was actually
## steered along (ZERO when it was told to stand), which is what the caller should face.
##
## WHY THIS EXISTS (Q19-04). `move_and_slide` slides a blocked body along the surface by the
## part of its velocity that lies along it. For a body walking straight at a target, that part
## points at the target's own row — so the slide carries it to the point where the target is
## dead ahead through the obstacle, and there it is zero. The stall is a STABLE resting point,
## not a rare alignment: measured on a pine trunk, a Vụ Lang started 0.01, 0.5 and 2 px off the
## target's row all came to rest against the trunk and stayed there.
##
## THE RULE, in the order it is applied:
##   1. No obstacle met: this is `apply_intent(toward)`. An open field costs no query.
##   2. Met squarely (`DETOUR_START_DOT`): choose a HAND — the side of the surface the target
##      lies toward, or `DETOUR_DEFAULT_HAND` on an exact tie — and hold it.
##   3. While a hand is held, look one step ahead along the straight line (one `test_move`).
##      Blocked: walk along the surface it hit, on the held hand, at full speed. Clear: the
##      obstacle is behind it — let the hand go and walk the straight line again.
##   4. The way round is itself shut: reverse the hand, once.
##
## `goal` is the body being pursued, if it is one. Touching IT is arriving, never an obstacle —
## without that a creature would try to walk round the very player it has just reached.
##
## BOUNDED AND DETERMINISTIC: at most one extra query per tick, only while a hand is held; no
## search, no path, no node, no timer, no randomness. A convex footprint — every prop this
## project builds (`PropBody.make_footprint`) — is rounded in one pass. A pocket closed on
## both sides is NOT solved here: the body rests in it (rule 4 gives it one reversal, not a
## pacing loop). Finding a way out of a room is navigation, and belongs to whoever authors
## rooms.
func apply_pursuit(toward: Vector2, speed: float, delta: float, goal: Node = null) -> Vector2:
	if body == null:
		push_error("[movement] apply_pursuit with no body assigned")
		return Vector2.ZERO
	if speed <= 0.0 or toward.length() < 0.001:
		end_pursuit()
		apply_intent(Vector2.ZERO, 0.0, delta)
		return Vector2.ZERO
	var straight := toward.normalized()
	var heading := straight
	if _detour_hand != 0:
		var ahead := _surface_ahead(straight, speed, goal)
		if ahead != Vector2.ZERO:
			heading = detour_heading(ahead, _detour_hand)
		else:
			end_pursuit()
	apply_intent(heading, speed, delta)
	var met := _surface_met(heading, goal)
	if met == Vector2.ZERO:
		return heading
	if _detour_hand == 0:
		_detour_hand = choose_hand(met, straight)
		_detour_reversed = false
	elif heading != straight and not _detour_reversed:
		_detour_hand = -_detour_hand
		_detour_reversed = true
	return heading


## Forget the way round. Called when a pursuit ends (arrived, or the brain let go), so the next
## one chooses afresh instead of inheriting a hand from an obstacle it has left behind.
func end_pursuit() -> void:
	_detour_hand = 0
	_detour_reversed = false


## +1 / -1 while something is being walked round, 0 on the straight line. Read-only, for
## tests and diagnostics; nothing decides on it.
func detour_hand() -> int:
	return _detour_hand


func detour_probes() -> int:
	return _probes


## Pure: which way round a surface with `normal`, for a body that wants to go `straight`.
## The side the target lies toward; `DETOUR_DEFAULT_HAND` when it lies toward neither.
static func choose_hand(normal: Vector2, straight: Vector2) -> int:
	var lean := detour_heading(normal, 1).dot(straight)
	if absf(lean) < DETOUR_TIE_LEAN:
		return DETOUR_DEFAULT_HAND
	return 1 if lean > 0.0 else -1


## Pure: the unit heading that follows a surface with `normal` on `hand` — the normal turned a
## quarter turn. One hand keeps the obstacle on one side all the way round it, which is what
## turns the next face of a trunk into a continuation instead of a new decision.
static func detour_heading(normal: Vector2, hand: int) -> Vector2:
	return Vector2(-normal.y, normal.x) * float(hand)


## The normal of whatever blocks the next step along `straight`, or ZERO when it is clear (or
## what it would touch is the `goal` itself).
func _surface_ahead(straight: Vector2, speed: float, goal: Node) -> Vector2:
	if _probe_hit == null:
		_probe_hit = KinematicCollision2D.new()
	_probes += 1
	var reach := speed * body.get_physics_process_delta_time() + DETOUR_PROBE_MARGIN_PX
	if not body.test_move(body.global_transform, straight * reach, _probe_hit):
		return Vector2.ZERO
	if goal != null and _probe_hit.get_collider() == goal:
		return Vector2.ZERO
	return _probe_hit.get_normal()


## The normal of a surface the last step ran SQUARELY into while heading `heading`, or ZERO.
## A glancing touch is not one: sliding already handles it.
func _surface_met(heading: Vector2, goal: Node) -> Vector2:
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		if goal != null and hit.get_collider() == goal:
			continue
		if hit.get_normal().dot(heading) < -DETOUR_START_DOT:
			return hit.get_normal()
	return Vector2.ZERO

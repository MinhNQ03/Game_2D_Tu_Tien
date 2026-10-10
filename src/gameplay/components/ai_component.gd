extends Node
class_name AIComponent
## AIComponent — Aetheria gameplay (turns an AI decision into real movement and attacks).
##
## The gameplay side of `AiBrain`: it builds the brain's PERCEPTION from real positions, asks
## for an INTENT, and executes that intent through the SAME seams the player uses —
## `MovementComponent` for motion and `AttackComponent` for swinging. It owns no rules.
##
## `AI DECISION → INTENT → GAMEPLAY RESOLUTION`, which is the deliberate mirror of
## `PLAYER INPUT → INTENT → GAMEPLAY RESOLUTION` (`MULTIPLAYER_PLAN.md` §3). The decision is
## separable from the resolution, so a future authoritative server can own both without this
## node existing.
##
## IT HAS NO `_physics_process` AND NO TIMER OF ITS OWN. The session ticks it
## (`CombatRuntime.tick_enemies`), for two reasons:
##   * **Measurable cost.** One callback for N enemies instead of N callbacks, so "AI costs
##     X ms for N enemies" is a number a budget test can assert
##     (`05-performance-testing.md`).
##   * **No per-frame thinking.** `tick()` executes MOVEMENT every tick (motion must be smooth)
##     but only asks the brain for a DECISION every `decision_interval` — the separation
##     Phase 10 requires. A component that decided every frame would also be unreadable: the
##     player could not see a committed choice.
##
## IT MUTATES NOTHING IT DOES NOT OWN: no health, no damage, no formula, no quest, relationship,
## sect or faction state. Damage happens only because `AttackComponent` resolves a real swing
## through `CombatService`, exactly as the player's does.

## The brain changed state. Presentation can read this to show a telegraph; no gameplay rule
## depends on it.
signal ai_state_changed(state_name: String)

var _brain: AiBrain = null
var _profile: AiProfileData = null
var _movement: MovementComponent = null
var _attack: AttackComponent = null
var _visual: CharacterVisualComponent = null
var _body: CharacterBody2D = null

## Where it spawned. The anchor for the leash and for RETURN — captured at arm time rather than
## read from a node, so a creature cannot "forget home" if something reparents it.
var _home := Vector2.ZERO
## A home that MOVES (an ally's owner), or null for a fixed home. See `set_home_anchor`.
var _home_anchor: Node2D = null

## Resolved each tick by the session, which knows who the targets are. The component never
## searches the tree for a player (that would be a presentation-layer dependency pointing the
## wrong way, and it would also be O(tree) per enemy per tick).
var _target: Node2D = null

var _speed: float = 60.0
var _seconds_since_decision: float = 0.0
## The last intent, re-executed every tick between decisions. This is what makes movement
## smooth while thinking stays throttled.
var _intent: int = AiBrain.Intent.HOLD
var _last_state_name := "IDLE"
## Decisions made since arming — a read-only counter so a budget test can assert the decision
## RATE rather than trusting the interval was honoured.
var _decisions: int = 0

## Effects a technique applies (Phase 15). GAMEPLAY: a stunned creature (Choáng) decides nothing
## and its swing is cancelled; a knocked-back body slides along the push through its own
## collision (`move_and_slide`), so a wall stops it.
var _stun_left: float = 0.0
var _knock_velocity: Vector2 = Vector2.ZERO

## How long a knockback takes to play out; its velocity eases to rest across it.
const KNOCKBACK_SECONDS := 0.2


## Arm this component. Returns false (loud) when it could not, so the spawner can fail closed
## rather than drop an inert creature into the world that merely looks alive.
##
## `rng` must be the session's seeded stream — the component does not create one, and the brain
## refuses to arm without it, which is what keeps enemy behaviour reproducible.
func arm(data: EnemyData, rng: RngStream, home: Vector2) -> bool:
	if data == null or not data.is_valid():
		push_error("[ai] cannot arm: EnemyData is missing or invalid")
		return false
	return arm_profile(data.ai_profile, data.engage_distance,
		data.stats.move_speed if data.stats != null else 60.0, rng, home, String(data.id))


## Arm from the BEHAVIOUR facts alone — what any creature this component drives has in common:
## a profile, how close it closes before swinging, how fast it moves, a seeded stream and a
## home. `arm()` is this with an `EnemyData`'s values; a pet arms with its `PetData`'s (Phase
## 16). One component, one brain: an ally is authored, not re-implemented.
func arm_profile(profile: AiProfileData, engage_distance: float, move_speed: float,
		rng: RngStream, home: Vector2, label: String) -> bool:
	if profile == null or not profile.is_valid():
		push_error("[ai] cannot arm '%s': the AiProfileData is missing or invalid" % label)
		return false
	var body := get_parent() as CharacterBody2D
	if body == null:
		push_error("[ai] cannot arm: an AIComponent must be a child of a CharacterBody2D")
		return false
	_body = body
	_movement = _sibling("MovementComponent") as MovementComponent
	_attack = _sibling("AttackComponent") as AttackComponent
	_visual = _sibling_of_class("CharacterVisualComponent") as CharacterVisualComponent
	if _movement == null:
		push_error("[ai] cannot arm '%s': no MovementComponent to move with" % label)
		return false
	var brain := AiBrain.new(profile, rng)
	if not brain.is_armed():
		push_error("[ai] cannot arm '%s': the brain refused its profile/stream" % label)
		return false
	_profile = profile
	_brain = brain
	_brain.set_engage_distance(engage_distance)
	_home = home
	_home_anchor = null
	_speed = move_speed
	return true


func is_armed() -> bool:
	return _brain != null and _brain.is_armed()


## Tell the component what it is hunting. Null means "nothing to hunt", which the brain reads
## as a lost target and resolves by going home.
func set_target(target: Node2D) -> void:
	_target = target


func target() -> Node2D:
	return _target


func brain_state_name() -> String:
	return _brain.state_name() if _brain != null else "IDLE"


func brain_state() -> int:
	return _brain.state() if _brain != null else AiBrain.State.IDLE


func decisions() -> int:
	return _decisions


## Where home is NOW: the anchor's position while one is set and alive, else the fixed point.
func home() -> Vector2:
	if _home_anchor != null and is_instance_valid(_home_anchor):
		_home = _home_anchor.global_position
	return _home


## Make home a NODE that moves — an ally's owner (Phase 16). The leash, the follow distance
## and RETURN are then all measured to where the owner is now. If the anchor goes away, home
## stays at the last place it was seen (the creature does not bolt to a stale spawn point).
## Null returns to a fixed home at the current one.
func set_home_anchor(anchor: Node2D) -> void:
	_home_anchor = anchor


func home_anchor() -> Node2D:
	return _home_anchor if _home_anchor != null and is_instance_valid(_home_anchor) else null


## The behaviour profile it was armed with (null before `arm`).
func profile() -> AiProfileData:
	return _profile


## One AI tick: decide if the interval elapsed, then execute the current intent.
##
## Public and delta-driven so a test can step AI with EXACT deltas. The headless runner does
## not run physics callbacks the way a game does (L-016), so a component that could only be
## advanced by the engine would be untestable — and AI timing is precisely what needs testing.
func tick(delta: float) -> void:
	if not is_armed() or _body == null or not is_instance_valid(_body):
		return
	if _knock_velocity.length_squared() > 1.0:
		_body.velocity = _knock_velocity
		_body.move_and_slide()
		_knock_velocity = _knock_velocity.move_toward(Vector2.ZERO,
			_knock_velocity.length() / maxf(KNOCKBACK_SECONDS, delta) * delta * 2.0)
		if _stun_left <= 0.0:
			return
	if _stun_left > 0.0:
		_stun_left = maxf(0.0, _stun_left - delta)
		_movement.apply_intent(Vector2.ZERO, 0.0, delta)
		_face(Vector2.ZERO, false)
		return
	_seconds_since_decision += delta
	if _seconds_since_decision >= _profile.decision_interval:
		# The brain is advanced by the time that ACTUALLY elapsed, not by the nominal
		# interval. Passing the interval instead made the brain's internal clock run SLOWER
		# than the world under a variable frame rate: at 5-second frames it experienced 0.2s
		# per tick, so `alert_seconds`, `recover_seconds` and every other state timing
		# stretched by the same factor and the creature could sit in one state indefinitely.
		# Found by the long-frame integration test, which is exactly what it is for (C18).
		var elapsed := _seconds_since_decision
		# KEEP THE REMAINDER rather than zeroing the accumulator. Zeroing discards the
		# overshoot, and since 12 frames at 60fps sum to 0.19999999999999998 — just under a
		# 0.2s interval — the decision slipped to every 13th frame, an 8% slower cadence than
		# authored (138 decisions where 150 were expected, caught by the AI budget test).
		# `fmod` carries the leftover forward, so the long-run average is exactly the
		# interval, and a long frame (already accounted for in `elapsed`) does not queue a
		# burst of catch-up decisions.
		_seconds_since_decision = fmod(elapsed, _profile.decision_interval)
		_intent = _brain.decide(_perceive(), elapsed)
		_decisions += 1
		var state_now := _brain.state_name()
		if state_now != _last_state_name:
			_last_state_name = state_now
			ai_state_changed.emit(state_now)
	_execute(_intent, delta)


## Build the brain's perception from the real world. The ONE place positions become scalars.
func _perceive() -> Dictionary:
	var has_target := _target != null and is_instance_valid(_target)
	# A dead target is NOT a target. Without this the creature keeps swinging at a corpse,
	# which reads as the AI being broken rather than as the enemy being relentless.
	if has_target and _target.has_method("is_dead") and bool(_target.call("is_dead")):
		has_target = false
	var distance := INF
	if has_target:
		distance = _body.global_position.distance_to(_target.global_position)
	return {
		"has_target": has_target,
		"target_distance": distance,
		"home_distance": _body.global_position.distance_to(home()),
		# The brain must not ask for a swing mid-swing: `AttackComponent` owns the commitment
		# rule, and this is how the brain respects it instead of duplicating it.
		"can_attack": _attack != null and _attack.can_attack(),
	}


## Execute an intent: a movement vector through `MovementComponent`, or a swing request
## through `AttackComponent`. Facing is pushed from the SAME vector that drives motion, so the
## creature always looks where it is going and swings where it is looking.
func _execute(intent: int, delta: float) -> void:
	var direction := Vector2.ZERO
	var speed_scale := _profile.chase_speed_scale
	match intent:
		AiBrain.Intent.WANDER:
			direction = Vector2.RIGHT.rotated(_brain.patrol_angle())
			speed_scale = _profile.patrol_speed_scale
		AiBrain.Intent.APPROACH:
			direction = _toward_target()
		AiBrain.Intent.BACK_OFF:
			direction = -_toward_target()
		AiBrain.Intent.RETURN_HOME:
			direction = _body.global_position.direction_to(home())
			speed_scale = _profile.effective_return_speed_scale()
		AiBrain.Intent.SWING:
			# Face the target, then swing. Facing FIRST matters: `CombatService` tests the arc
			# against the attacker's facing, so a swing requested before turning would miss a
			# target the creature is standing on top of.
			var facing := _toward_target()
			if _attack != null and facing != Vector2.ZERO:
				_attack.set_facing(facing)
				_attack.request_attack()
			_face(facing, false)
			_movement.apply_intent(Vector2.ZERO, 0.0, delta)
			return
		_:
			direction = Vector2.ZERO
	if _attack != null:
		speed_scale *= _attack.movement_scale()  # a swing in flight roots the body (D-057B)
	_movement.apply_intent(direction, _speed * speed_scale, delta)
	_face(direction, direction != Vector2.ZERO and speed_scale > 0.0)


func _toward_target() -> Vector2:
	if _target == null or not is_instance_valid(_target):
		return Vector2.ZERO
	return _body.global_position.direction_to(_target.global_position)


## Drive the facing of both the attack component and the sprite from one vector.
func _face(direction: Vector2, moving: bool) -> void:
	if direction == Vector2.ZERO:
		if _visual != null:
			_visual.update_facing(Vector2.ZERO, false)
		return
	if _attack != null:
		_attack.set_facing(direction)
	if _visual != null:
		_visual.update_facing(direction, moving)


## Choáng: suspend decisions for `seconds` (the longer of a running stun and this one) and cancel
## any swing in flight — Lôi "buys interruption" (`COMBAT_DESIGN.md` §3).
func apply_stun(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_stun_left = maxf(_stun_left, seconds)
	if _attack != null:
		_attack.cancel()


func is_stunned() -> bool:
	return _stun_left > 0.0


func stun_remaining() -> float:
	return _stun_left


## Shove the body `displacement` px (Phong "buys repositioning"): played out over
## KNOCKBACK_SECONDS as a velocity that eases to rest, through the body's own collision.
func apply_knockback(displacement: Vector2) -> void:
	_knock_velocity = displacement / KNOCKBACK_SECONDS


func is_knocked_back() -> bool:
	return _knock_velocity.length_squared() > 1.0


## Stop acting, permanently as far as this component is concerned.
##
## Called on death and on teardown. It resets the brain, drops the target, cancels any swing in
## flight and zeroes the body's velocity — all four, because each one alone leaves a visible
## wrong: a dead creature that keeps sliding, keeps hunting, or lands a hit from beyond the
## grave (C11).
func stop() -> void:
	if _brain != null:
		_brain.reset()
	_target = null
	_home_anchor = null
	_intent = AiBrain.Intent.HOLD
	if _attack != null and is_instance_valid(_attack):
		_attack.cancel()
	if _body != null and is_instance_valid(_body):
		_body.velocity = Vector2.ZERO
	_stun_left = 0.0
	_knock_velocity = Vector2.ZERO


## A direct child of this component's PARENT, by node name.
func _sibling(node_name: String) -> Node:
	var parent := get_parent()
	return parent.get_node_or_null(node_name) if parent != null else null


## A direct sibling by CLASS, for components a scene may name freely.
func _sibling_of_class(type_name: String) -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and script.get_global_name() == type_name:
			return child
	return null

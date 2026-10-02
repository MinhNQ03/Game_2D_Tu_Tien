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

## The body this component moves. Set via @export in the entity scene, or `setup()` in code.
@export var body: CharacterBody2D = null


## Inject the body in code (used by scenes/tests that build the entity programmatically).
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
## Call from the owner's `_physics_process` only.
func apply_intent(intent: Vector2, speed: float) -> Vector2:
	if body == null:
		push_error("[movement] apply_intent with no body assigned")
		return Vector2.ZERO
	body.velocity = resolve_velocity(intent, speed)
	body.move_and_slide()
	return body.velocity

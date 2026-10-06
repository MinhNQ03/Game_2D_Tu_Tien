extends Node
class_name AttackComponent
## AttackComponent — Aetheria gameplay (an entity's ability to attack, Phase 09, D-007).
##
## The gameplay-side driver of the real-time attack lifecycle: it holds the entity's
## `AttackStateMachine`, advances it with the physics clock, and when the hit window opens it
## asks `CombatService` what the swing hit and applies the results through the targets'
## hurtboxes.
##
## IT DECIDES NOTHING. Timing is `AttackStateMachine`, geometry and the crit roll are
## `CombatService`, the number is `DamageRules`, who exists is `CombatHurtboxRegistry`, and
## health is the target entity's own. This component is the wiring between them, which is why
## it is small and why none of the combat rules are in a node (`03-architecture.md`).
##
## DEPENDENCIES ARE INJECTED, NOT LOOKED UP. `arm()` takes the attack definition, the service
## and the registry; nothing here reads `/root`. That is the same shape as the player's
## `bind_character_state()`, and it is what lets a test drive a real attack with no autoloads
## and no session (D-019).
##
## IT RUNS ITS CLOCK ONLY WHILE ATTACKING. `_physics_process` is disabled in READY and enabled
## by `request_attack()`, so an idle entity costs nothing per frame
## (`05-performance-testing.md`) — which matters because every future NPC will carry one.

## A swing began (the entity entered WINDUP). Presentation plays the wind-up animation.
signal attack_started()

## The hit window resolved. `results` is `CombatService`'s result array (possibly empty, which
## is a whiff — a normal outcome). Emitted once per swing, after damage has been applied.
signal attack_resolved(results: Array)

## The swing finished and the entity is READY again. Presentation returns to idle.
signal attack_finished()

var _attack: AttackData = null
var _service: CombatService = null
var _registry: CombatHurtboxRegistry = null
var _fsm: AttackStateMachine = null

## The attacker's own id, so it is excluded from its own swing. Without this every attack
## would hit the attacker, which is always inside its own reach.
var _attacker_id: StringName = &""

## Facing used for the arc test, pushed by the entity. Defaults to DOWN because that is the
## project's canonical rest facing (the character sheets' first row, `06-art-assets.md`), so
## an entity that never reports a facing still swings somewhere sensible rather than nowhere.
var _facing: Vector2 = Vector2.DOWN

## Swings resolved since arming, and the damage they dealt. Read-only counters for tests and
## the debug overlay: "the attack resolved" is otherwise only observable via a signal, and a
## test that must connect a signal to see whether anything happened cannot assert the simple
## thing (`08-ai-review-protocol.md`).
var _swings_resolved: int = 0
var _damage_dealt: int = 0


func _ready() -> void:
	# Idle costs nothing: the clock starts when an attack does.
	set_physics_process(false)


## Arm this component. Returns false (loud) if it cannot attack afterwards, so a caller can
## fail closed rather than discover later that the entity silently cannot fight.
##
## `attacker_id` must match the attacker's own hurtbox id — that is how it is kept out of its
## own swing.
func arm(
		attack: AttackData,
		service: CombatService,
		registry: CombatHurtboxRegistry,
		attacker_id: StringName) -> bool:
	if attack == null or not attack.is_valid():
		push_error("[attack] cannot arm: the AttackData is missing or invalid")
		return false
	if service == null or not service.is_ready():
		push_error("[attack] cannot arm: no usable CombatService (it needs a seeded stream)")
		return false
	if registry == null:
		push_error("[attack] cannot arm: no hurtbox registry, so a swing could find nothing")
		return false
	if attacker_id == &"":
		push_error("[attack] cannot arm: an attacker needs an id or it will hit itself")
		return false
	_attack = attack
	_service = service
	_registry = registry
	_attacker_id = attacker_id
	_fsm = AttackStateMachine.new(attack)
	return _fsm.is_armed()


## True once this component can actually swing.
func is_armed() -> bool:
	return _fsm != null and _fsm.is_armed()


## Report the attacker's facing (the direction a swing points). Zero-length input is IGNORED
## rather than stored: an entity that stops moving keeps the facing it stopped with, which is
## what a player expects, and storing the zero would leave the next swing with no direction
## at all (`CombatService` refuses those).
func set_facing(facing: Vector2) -> void:
	if facing.length_squared() <= 0.0:
		return
	_facing = facing.normalized()


func facing() -> Vector2:
	return _facing


## The current lifecycle state (`AttackStateMachine.State`). Presentation reads this to pick
## an animation; it is never used to decide whether a hit lands.
func state() -> int:
	return _fsm.state() if _fsm != null else AttackStateMachine.State.READY


func state_name() -> String:
	return _fsm.state_name() if _fsm != null else AttackStateMachine.STATE_NAMES[0]


## Seconds left in the current lifecycle phase (0.0 in READY).
##
## Exposed for PRESENTATION (`AttackFeedback` derives how far through a phase a swing is from
## it) so the drawing cannot keep a clock of its own and drift out of step with the mechanics
## it depicts. No gameplay rule reads it.
func time_remaining() -> float:
	return _fsm.time_remaining() if _fsm != null else 0.0


## The attack this component is armed with, or null. For presentation, which needs the authored
## reach and arc to draw a swing that matches the one being resolved.
func attack_data() -> AttackData:
	return _attack


## The fraction of normal speed the attacker keeps right now: 1.0 while READY, the authored
## `AttackData.committed_move_scale` while a swing is in flight (D-057B). GAMEPLAY — the
## movers (`Player`, `AIComponent`) multiply their speed by it, so a committed swing roots the
## attacker the same way for every actor, and presentation never decides how far anyone moves.
func movement_scale() -> float:
	if _attack == null or state() == AttackStateMachine.State.READY:
		return 1.0
	return _attack.committed_move_scale


## Can this entity start a swing right now?
func can_attack() -> bool:
	return is_armed() and _fsm.can_begin()


## Request a swing. Returns false when one is already in flight (the commitment rule) or the
## component is unarmed. A refusal is SILENT: a player mashing the attack key is normal play.
func request_attack() -> bool:
	if not is_armed():
		return false
	if not _fsm.try_begin():
		return false
	set_physics_process(true)
	attack_started.emit()
	return true


func _physics_process(delta: float) -> void:
	advance(delta)


## Advance the lifecycle and resolve the hit window if it opened. Public and delta-driven so a
## test can step combat with EXACT deltas instead of waiting on physics frames — the headless
## runner does not run `_physics_process` the way a game does (L-016), so a component that
## could only be advanced by the engine would be untestable.
func advance(delta: float) -> void:
	if _fsm == null:
		return
	var before := _fsm.state()
	_fsm.advance(delta)
	# Consume the window as an EDGE: once per swing, however the frames fell. Polling the
	# ACTIVE state instead would resolve the same swing once per frame, making frame rate
	# damage.
	if _fsm.consume_hit_window():
		_resolve_hit_window()
	if _fsm.state() == AttackStateMachine.State.READY \
			and before != AttackStateMachine.State.READY:
		# Back to idle: stop the clock again.
		set_physics_process(false)
		attack_finished.emit()


## Ask the service what this swing hit, apply it, and report.
##
## Damage is applied through each target's own hurtbox (which routes to the entity's
## `take_damage`), never by writing a HealthComponent directly: the entity owns its health and
## may have more to do than subtract a number — the player also syncs its authoritative
## `CharacterState`.
func _resolve_hit_window() -> void:
	var origin := _attacker_position()
	var results := _service.resolve_hit(
		origin, _facing, _attacker_attack(), _attack, _registry.targets(_attacker_id))
	for result in results:
		var target_id: StringName = result["target_id"]
		var hurtbox := _registry.get_hurtbox(target_id)
		if hurtbox == null:
			# Registered when the swing resolved, gone by the time it was applied. Not an
			# error: an entity freed mid-swing is normal, and the hit simply does not land.
			continue
		# The direction the blow travelled, attacker -> target (the facing when they overlap):
		# a semantic fact of the hit that the struck body's reaction pushes along.
		var push := origin.direction_to(hurtbox.world_position())
		if push == Vector2.ZERO:
			push = _facing
		_damage_dealt += hurtbox.apply_hit(
			int(result["damage"]), bool(result["is_critical"]), push)
	_swings_resolved += 1
	attack_resolved.emit(results)


## Where the swing originates. Read from the parent entity each swing, so a moving attacker
## swings from where it is rather than from where it was armed.
func _attacker_position() -> Vector2:
	var body := get_parent() as Node2D
	if body == null or not is_instance_valid(body):
		return Vector2.ZERO
	return body.global_position


## The attacker's attack stat, from the entity that owns this component. 0 when the entity
## exposes none — which still deals `DamageRules.MIN_DAMAGE`, so a mis-wired attacker is weak
## and visible rather than silently harmless.
func _attacker_attack() -> int:
	var body := get_parent()
	if body != null and is_instance_valid(body) and body.has_method("get_attack_power"):
		return int(body.call("get_attack_power"))
	return 0


## Swings whose hit window has been resolved since arming (whiffs included).
func swings_resolved() -> int:
	return _swings_resolved


## Total damage this component has actually applied.
func damage_dealt() -> int:
	return _damage_dealt


## Abandon a swing in flight. Used when the attacker stops being an attacker — death, a map
## change, session teardown. Drops any unconsumed hit window, so a swing cannot land after its
## attacker is gone (a phantom hit nobody can reproduce).
func cancel() -> void:
	if _fsm == null:
		return
	_fsm.cancel()
	set_physics_process(false)

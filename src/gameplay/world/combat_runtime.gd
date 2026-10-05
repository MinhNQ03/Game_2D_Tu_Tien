extends Node
class_name CombatRuntime
## CombatRuntime — Aetheria gameplay (the per-session combat seam, Phase 09, D-007).
##
## Owns the two things a fight needs and nothing else: the `CombatService` (bound to the
## session's seeded COMBAT stream) and the `CombatHurtboxRegistry` (who can be hit). Entities
## that fight are armed from here; it resolves no hit and holds no health itself.
##
## A NODE UNDER `Main/Systems`, NOT AN AUTOLOAD (D-017). The autoload budget is frozen at
## five, and combat is strictly per-session: a global combat seam would survive a return to
## the menu carrying the previous run's hurtbox registry and RNG position, which is precisely
## the class of bug the per-session runtimes exist to prevent. It is the sixth sibling of
## `WorldRuntime` / `RelationshipRuntime` / `SectRuntime` / `FactionRuntime` /
## `WorldSimulationRuntime` and is registered LAST in `Main.SESSION_START_ORDER`, so teardown
## (the exact reverse) ends combat FIRST — before the RNG seam it borrows and the entities it
## points at are gone.
##
## IT SHARES THE WORLD'S `RngService` RATHER THAN MAKING ONE. One world seed, two independent
## streams: `derive_state()` makes `world_sim` and `combat` start far apart, so a combat roll
## can never shift the simulation's sequence. A second `RngService` with its own seed would
## mean a save had two world identities, and "which seed is this world" would stop having one
## answer (`SAVE_FORMAT.md` §3b).
##
## FAIL CLOSED, LIKE EVERY OTHER SESSION STARTER (L-025). `start_session()` builds into LOCALS
## and commits only when every step succeeded, so a rejected start leaves nothing observable:
## `is_session_active()` stays false and every getter stays empty. There is no "warn and keep
## going" path — a half-built combat session would be a world where some entities can be hit
## and others silently cannot.

var _service: CombatService = null
var _registry: CombatHurtboxRegistry = null
var _session_active: bool = false

## Entities armed this session, by id, so teardown can cancel a swing in flight rather than
## leave a hit window pending on a node that is about to be freed.
var _armed: Dictionary = {}


## Start the combat session from the world's RNG seam.
##
## `rng` is the session's `RngService` — the SAME instance the world simulation uses, taken
## from `WorldSimulationState.rng()`. Returns true only when combat is actually live.
func start_session(rng: RngService) -> bool:
	if _session_active:
		push_error("[combat-rt] start_session called while a session is already active")
		return false
	if rng == null:
		return _fail_start("no RngService was supplied")
	if not rng.is_valid():
		return _fail_start("the supplied RngService has no valid world seed")
	var stream := rng.stream(RngService.STREAM_COMBAT)
	if stream == null:
		return _fail_start("the RngService refused to produce the '%s' stream"
			% RngService.STREAM_COMBAT)
	var service := CombatService.new(stream)
	if not service.is_ready():
		return _fail_start("the CombatService refused the combat stream")

	# Commit: every step succeeded, so the session becomes observable all at once.
	_service = service
	_registry = CombatHurtboxRegistry.new()
	_armed = {}
	_session_active = true
	return true


## Report a refused start and leave the runtime EXACTLY as it was.
##
## No partial state to unwind, by construction: nothing above assigns to a field until every
## check has passed, so this only has to report. That is the difference between failing closed
## and cleaning up after failing (L-025).
func _fail_start(reason: String) -> bool:
	push_error("[combat-rt] combat session NOT started: %s" % reason)
	return false


## End the session: cancel every swing in flight, drop the registry, drop the service.
##
## Cancelling FIRST is the point. A pending hit window on an entity that is about to be freed
## would resolve against a registry mid-teardown — a phantom hit on a half-dismantled world,
## which is the hardest kind of bug to reproduce because it needs a specific frame.
## Idempotent: ending a session that never started is a no-op, which is what makes the shared
## teardown path safe to run after an aborted boot.
func end_session() -> void:
	for key in _armed.keys():
		var component: AttackComponent = _armed[key]
		if component != null and is_instance_valid(component):
			component.cancel()
	_armed.clear()
	if _registry != null:
		_registry.clear()
	_registry = null
	_service = null
	_session_active = false


func is_session_active() -> bool:
	return _session_active


## The session's combat service, or null outside a session.
func get_service() -> CombatService:
	return _service


## The session's hurtbox registry, or null outside a session.
func get_registry() -> CombatHurtboxRegistry:
	return _registry


## Make `entity` targetable: bind its hurtbox to this session's registry.
##
## Returns false (loud) outside a session or without a hurtbox — an entity that silently is
## not targetable is a target the player can hit forever with no effect.
func register_target(entity: Node) -> bool:
	if not _session_active:
		push_error("[combat-rt] register_target outside a session")
		return false
	var hurtbox := _find_child_of_type(entity, "HurtboxComponent") as HurtboxComponent
	if hurtbox == null:
		push_error("[combat-rt] '%s' has no HurtboxComponent, so it cannot be hit"
			% (entity.name if entity != null else "<null>"))
		return false
	hurtbox.setup(entity, _registry)
	return true


## Arm `entity` to attack with `attack`, and make it targetable in the same call.
##
## One call for both sides on purpose: an attacker that is not itself a target is a one-way
## fight, and forgetting the second call is invisible until something tries to hit back.
## `attacker_id` is also what keeps the entity out of its own swing.
func arm_attacker(entity: Node, attack: AttackData, attacker_id: StringName) -> bool:
	if not _session_active:
		push_error("[combat-rt] arm_attacker outside a session")
		return false
	var component := _find_child_of_type(entity, "AttackComponent") as AttackComponent
	if component == null:
		push_error("[combat-rt] '%s' has no AttackComponent, so it cannot attack"
			% (entity.name if entity != null else "<null>"))
		return false
	if not register_target(entity):
		return false
	if not component.arm(attack, _service, _registry, attacker_id):
		return false
	_armed[String(attacker_id)] = component
	return true


## How many attackers this session has armed. A read-only window for tests and the debug
## overlay, like `Main.get_last_teardown_order()`.
func armed_count() -> int:
	return _armed.size()


## First direct child of `entity` whose class matches `type_name`.
##
## Direct children only, and matched by class rather than by node NAME: a scene is free to
## name its components whatever reads best, and matching on a name would make the wiring
## depend on a cosmetic choice (`04-coding-standards.md`: prefer composition over fixed paths).
func _find_child_of_type(entity: Node, type_name: String) -> Node:
	if entity == null or not is_instance_valid(entity):
		return null
	for child in entity.get_children():
		var script: Script = child.get_script()
		if script != null and script.get_global_name() == type_name:
			return child
	return null

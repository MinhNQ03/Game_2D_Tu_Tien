extends TestCase
## Unit tests for the Phase-09 gameplay side of combat: the hurtbox registry, the
## `HurtboxComponent`, the `AttackComponent` and the `CombatRuntime` session.
##
## These use FRESH `Script.new()` instances and never the live `/root` singletons (D-019), and
## every `Node` they create is freed by the test that created it — a `Node` built in the
## headless runner does not auto-release, and one unfreed node pins its script and its native
## class, surfacing as several leaked ObjectDB at exit (L-019).

const AttackDataScript := preload("res://src/data/combat/attack_data.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const AttackComponentScript := preload("res://src/gameplay/components/attack_component.gd")
const HurtboxComponentScript := preload("res://src/gameplay/components/hurtbox_component.gd")

const WORLD_SEED := 20261005


func _attack() -> AttackData:
	var attack: AttackData = AttackDataScript.new()
	attack.id = &"attack_test"
	attack.windup_seconds = 0.10
	attack.active_seconds = 0.05
	attack.recovery_seconds = 0.20
	attack.reach_pixels = 40.0
	attack.arc_degrees = 180.0
	attack.power_multiplier = 1.0
	attack.critical_chance_percent = 0
	attack.critical_multiplier = 2.0
	return attack


func _rng() -> RngService:
	return RngServiceScript.new(WORLD_SEED)


## A minimal fighter: a `Node2D` carrying the two combat components plus the stat/health API
## the components call through. Built in code rather than by loading `player.tscn`, so these
## tests stay about the components instead of about the player scene.
func _fighter(entity_id: StringName, hp: int, attack_power: int, defense: int) -> Node2D:
	var body := TestFighter.new()
	body.name = String(entity_id)
	body.configure(hp, attack_power, defense)
	var attack_component: AttackComponent = AttackComponentScript.new()
	attack_component.name = "AttackComponent"
	body.add_child(attack_component)
	var hurtbox: HurtboxComponent = HurtboxComponentScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = entity_id
	hurtbox.radius = 8.0
	body.add_child(hurtbox)
	return body


## A stand-in fighter. It implements exactly the contract the combat components rely on —
## `get_attack_power`, `get_defense`, `take_damage`, `is_dead`, `get_current_health` — which is
## also a statement of what that contract IS: anything satisfying this can fight, with no
## shared base class (`03-architecture.md`, composition over inheritance).
class TestFighter extends Node2D:
	var hp: int = 10
	var attack_power: int = 20
	var defense: int = 0

	func configure(max_hp: int, power: int, armour: int) -> void:
		hp = max_hp
		attack_power = power
		defense = armour

	func get_attack_power() -> int:
		return attack_power

	func get_defense() -> int:
		return defense

	func get_current_health() -> int:
		return hp

	func is_dead() -> bool:
		return hp <= 0

	func take_damage(amount: int) -> int:
		if hp <= 0 or amount <= 0:
			return 0
		var before := hp
		hp = maxi(0, hp - amount)
		return before - hp


# === CombatHurtboxRegistry ==================================================

func test_the_registry_rejects_an_idless_or_duplicate_registration() -> void:
	var registry := CombatHurtboxRegistry.new()
	assert_false(registry.register(null), "a null hurtbox is refused")

	var anonymous: HurtboxComponent = HurtboxComponentScript.new()
	assert_false(registry.register(anonymous),
		"a hurtbox with no entity_id is refused — a hit could not be mapped back to it")
	anonymous.free()

	var first: HurtboxComponent = HurtboxComponentScript.new()
	first.entity_id = &"same"
	var second: HurtboxComponent = HurtboxComponentScript.new()
	second.entity_id = &"same"
	assert_true(registry.register(first), "the first registration is accepted")
	assert_true(registry.register(first), "re-registering the SAME hurtbox is idempotent")
	# A duplicate id would make one entity take two hits per swing, which reads as random
	# double damage.
	assert_false(registry.register(second), "a DIFFERENT hurtbox with the same id is refused")
	assert_eq(registry.size(), 1, "only one entry exists")
	first.free()
	second.free()


## Target order must be DETERMINISTIC and id-sorted. `CombatService` draws one value per
## target it hits, so an order that depended on which entity entered the tree first would make
## the crit sequence depend on scene load order — and a replay would diverge from its run.
func test_targets_come_back_sorted_by_id_not_in_registration_order() -> void:
	var registry := CombatHurtboxRegistry.new()
	var created: Array[Node2D] = []
	for entity_id in [&"charlie", &"alpha", &"bravo"]:
		var fighter := _fighter(entity_id, 10, 5, 0)
		created.append(fighter)
		add_to_tree(fighter)
		var hurtbox := fighter.get_node("HurtboxComponent") as HurtboxComponent
		hurtbox.setup(fighter, registry)
	var ids: Array[String] = []
	for target in registry.targets():
		ids.append(String(target["id"]))
	assert_eq(str(ids), str(["alpha", "bravo", "charlie"]),
		"targets are id-sorted regardless of registration order, got %s" % str(ids))
	for fighter in created:
		free_node(fighter)


## An attacker must be excluded from its own swing — it is always inside its own reach.
func test_an_attacker_is_excluded_from_its_own_target_list() -> void:
	var registry := CombatHurtboxRegistry.new()
	var attacker := _fighter(&"attacker", 10, 5, 0)
	add_to_tree(attacker)
	(attacker.get_node("HurtboxComponent") as HurtboxComponent).setup(attacker, registry)
	assert_eq(registry.targets().size(), 1, "without exclusion the attacker is a target")
	assert_eq(registry.targets(&"attacker").size(), 0,
		"excluding its own id removes it, so an attack cannot hit itself")
	free_node(attacker)


func test_a_dead_entity_is_not_targetable() -> void:
	var registry := CombatHurtboxRegistry.new()
	var fighter := _fighter(&"victim", 10, 5, 0)
	add_to_tree(fighter)
	(fighter.get_node("HurtboxComponent") as HurtboxComponent).setup(fighter, registry)
	assert_eq(registry.targets().size(), 1, "a living entity is a target")
	fighter.take_damage(10)
	assert_eq(registry.targets().size(), 0, "a dead one is not")
	assert_eq(registry.size(), 1, "but it is still REGISTERED (it could be revived)")
	free_node(fighter)


## A hurtbox unregisters itself on leaving the tree, so an entity freed mid-swing cannot be
## hit afterwards.
func test_leaving_the_tree_unregisters_a_hurtbox() -> void:
	var registry := CombatHurtboxRegistry.new()
	var fighter := _fighter(&"leaver", 10, 5, 0)
	add_to_tree(fighter)
	(fighter.get_node("HurtboxComponent") as HurtboxComponent).setup(fighter, registry)
	assert_eq(registry.size(), 1, "registered while in the tree")
	free_node(fighter)
	assert_eq(registry.size(), 0, "and unregistered on the way out")


# === AttackComponent ========================================================

## An unarmed component must refuse to swing rather than swing into a world with no registry.
func test_an_unarmed_attack_component_refuses_to_swing() -> void:
	var fighter := _fighter(&"lone", 10, 20, 0)
	add_to_tree(fighter)
	var component := fighter.get_node("AttackComponent") as AttackComponent
	assert_false(component.is_armed(), "a component nobody armed is unarmed")
	assert_false(component.can_attack(), "so it cannot attack")
	assert_false(component.request_attack(), "and a request is refused")
	free_node(fighter)


## `arm()` must fail CLOSED on every missing dependency, naming each one.
func test_arming_fails_closed_on_each_missing_dependency() -> void:
	var fighter := _fighter(&"a", 10, 20, 0)
	add_to_tree(fighter)
	var component := fighter.get_node("AttackComponent") as AttackComponent
	var registry := CombatHurtboxRegistry.new()
	var service := CombatService.new(_rng().stream(RngService.STREAM_COMBAT))

	assert_false(component.arm(null, service, registry, &"a"), "no attack data: refused")
	var broken := _attack()
	broken.active_seconds = 0.0
	assert_false(component.arm(broken, service, registry, &"a"), "invalid attack: refused")
	assert_false(component.arm(_attack(), CombatService.new(), registry, &"a"),
		"an unseeded service: refused")
	assert_false(component.arm(_attack(), service, null, &"a"), "no registry: refused")
	assert_false(component.arm(_attack(), service, registry, &""),
		"no attacker id: refused, because it would hit itself")
	assert_true(component.arm(_attack(), service, registry, &"a"),
		"and with everything present it arms")
	free_node(fighter)


## The full gameplay path, stepped with EXACT deltas: a swing damages a target in range and
## leaves one out of range alone.
func test_a_swing_damages_a_target_in_range_and_misses_one_outside_it() -> void:
	var registry := CombatHurtboxRegistry.new()
	var service := CombatService.new(_rng().stream(RngService.STREAM_COMBAT))

	var attacker := _fighter(&"attacker", 100, 20, 0)
	add_to_tree(attacker)
	var near := _fighter(&"near", 100, 5, 5)
	add_to_tree(near)
	var far := _fighter(&"far", 100, 5, 5)
	add_to_tree(far)
	attacker.global_position = Vector2.ZERO
	near.global_position = Vector2(20, 0)
	far.global_position = Vector2(900, 0)
	for fighter in [attacker, near, far]:
		(fighter.get_node("HurtboxComponent") as HurtboxComponent).setup(fighter, registry)

	var component := attacker.get_node("AttackComponent") as AttackComponent
	assert_true(component.arm(_attack(), service, registry, &"attacker"), "the attacker arms")
	component.set_facing(Vector2.RIGHT)
	assert_true(component.request_attack(), "the swing starts")

	# Nothing may be damaged during WINDUP — a hit landing there is the commitment bug.
	component.advance(0.05)
	assert_eq(near.get_current_health(), 100, "no damage during windup")

	# Crossing into ACTIVE resolves the hit window exactly once.
	component.advance(0.06)
	assert_true(near.get_current_health() < 100,
		"the in-range target lost health (hp %d)" % near.get_current_health())
	assert_eq(far.get_current_health(), 100, "the out-of-range target was untouched")
	assert_eq(attacker.get_current_health(), 100, "and the attacker did not hit itself")
	assert_eq(component.swings_resolved(), 1, "one swing resolved")
	assert_true(component.damage_dealt() > 0,
		"and the component recorded what it applied (%d)" % component.damage_dealt())

	# A longer ACTIVE window must not deal more damage: the window is an edge, not a level.
	# Explicitly typed: `near` is a `Node2D`, so the compiler cannot see `TestFighter`'s
	# return type and `:=` would infer Variant — which this project promotes to a compile
	# error, and a file that fails to compile does not register its `class_name` (L-020).
	var after_first: int = near.get_current_health()
	component.advance(0.01)
	assert_eq(near.get_current_health(), after_first,
		"staying inside the hit window does not deal damage again")

	free_node(attacker)
	free_node(near)
	free_node(far)


## `cancel()` must drop a pending hit window, so a swing cannot land after its attacker is
## gone — a phantom hit nobody can reproduce.
func test_cancelling_a_swing_in_flight_lands_no_hit() -> void:
	var registry := CombatHurtboxRegistry.new()
	var service := CombatService.new(_rng().stream(RngService.STREAM_COMBAT))
	var attacker := _fighter(&"attacker", 100, 20, 0)
	var victim := _fighter(&"victim", 100, 5, 0)
	add_to_tree(attacker)
	add_to_tree(victim)
	attacker.global_position = Vector2.ZERO
	victim.global_position = Vector2(20, 0)
	for fighter in [attacker, victim]:
		(fighter.get_node("HurtboxComponent") as HurtboxComponent).setup(fighter, registry)
	var component := attacker.get_node("AttackComponent") as AttackComponent
	component.arm(_attack(), service, registry, &"attacker")
	component.set_facing(Vector2.RIGHT)
	component.request_attack()
	component.advance(0.05)   # mid-windup
	component.cancel()
	component.advance(1.0)    # plenty of time for a window that must no longer exist
	assert_eq(victim.get_current_health(), 100,
		"a cancelled swing never resolves, even after the time its window would have opened")
	free_node(attacker)
	free_node(victim)


# === CombatRuntime ==========================================================

func test_the_runtime_fails_closed_without_a_valid_rng_seam() -> void:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	assert_false(runtime.start_session(null), "no RngService: refused")
	assert_false(runtime.is_session_active(), "and nothing is observable afterwards")
	assert_null(runtime.get_service(), "no service")
	assert_null(runtime.get_registry(), "no registry")

	var invalid: RngService = RngServiceScript.new(-1)
	assert_false(runtime.start_session(invalid), "an invalid seed: refused")
	assert_false(runtime.is_session_active(), "still nothing observable")
	free_node(runtime)


func test_a_started_session_exposes_its_service_and_registry() -> void:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	assert_true(runtime.start_session(_rng()), "a valid seam starts the session")
	assert_true(runtime.is_session_active(), "the session is live")
	assert_not_null(runtime.get_service(), "the service exists")
	assert_true(runtime.get_service().is_ready(), "and it is seeded")
	assert_not_null(runtime.get_registry(), "the registry exists")
	assert_false(runtime.start_session(_rng()), "a second start is refused")
	free_node(runtime)


## Arming must do BOTH sides: an attacker that is not itself a target is a one-way fight,
## which stays invisible until something tries to hit back.
func test_arming_an_attacker_also_registers_it_as_a_target() -> void:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(_rng())
	var fighter := _fighter(&"hero", 100, 20, 0)
	add_to_tree(fighter)
	assert_true(runtime.arm_attacker(fighter, _attack(), &"hero"), "the fighter arms")
	assert_eq(runtime.armed_count(), 1, "the runtime counts it")
	assert_true(runtime.get_registry().has(&"hero"),
		"and it is a TARGET too, not only an attacker")
	var component := fighter.get_node("AttackComponent") as AttackComponent
	assert_true(component.is_armed(), "its component is armed")
	free_node(fighter)
	free_node(runtime)


## A node with no combat components cannot be armed or targeted, and says so.
func test_a_node_without_combat_components_cannot_be_armed() -> void:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(_rng())
	var plain := Node2D.new()
	add_to_tree(plain)
	assert_false(runtime.register_target(plain), "no hurtbox: cannot be a target")
	assert_false(runtime.arm_attacker(plain, _attack(), &"plain"), "no component: cannot arm")
	free_node(plain)
	free_node(runtime)


## Ending the session must cancel a swing in flight BEFORE the world is dismantled, or a
## pending hit window resolves against a half-torn-down session.
func test_ending_the_session_cancels_swings_and_clears_everything() -> void:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(_rng())
	var attacker := _fighter(&"attacker", 100, 20, 0)
	var victim := _fighter(&"victim", 100, 5, 0)
	add_to_tree(attacker)
	add_to_tree(victim)
	attacker.global_position = Vector2.ZERO
	victim.global_position = Vector2(20, 0)
	runtime.arm_attacker(attacker, _attack(), &"attacker")
	runtime.register_target(victim)
	var component := attacker.get_node("AttackComponent") as AttackComponent
	component.set_facing(Vector2.RIGHT)
	component.request_attack()
	component.advance(0.05)  # mid-windup, window not yet open

	runtime.end_session()
	assert_false(runtime.is_session_active(), "the session ended")
	assert_null(runtime.get_service(), "the service is dropped")
	assert_null(runtime.get_registry(), "the registry is dropped")
	assert_eq(runtime.armed_count(), 0, "and nothing is still armed")

	component.advance(1.0)
	assert_eq(victim.get_current_health(), 100,
		"the swing in flight was cancelled, so no hit landed on a torn-down session")

	# Idempotent: ending a session that is already over is a no-op, which is what makes the
	# shared teardown path safe to run after an aborted boot.
	runtime.end_session()
	assert_false(runtime.is_session_active(), "ending twice is harmless")
	free_node(attacker)
	free_node(victim)
	free_node(runtime)

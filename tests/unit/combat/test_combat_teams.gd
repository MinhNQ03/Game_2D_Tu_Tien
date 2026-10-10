extends TestCase
## Unit tests for combat TEAMS (Phase 16): a swing skips its own side. The smallest side model
## that lets a companion fight beside the player — two named teams and "none" — tested on the
## real registry, the real `AttackComponent` and the real `CombatRuntime`.

const AttackDataScript := preload("res://src/data/combat/attack_data.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const AttackComponentScript := preload("res://src/gameplay/components/attack_component.gd")
const HurtboxComponentScript := preload("res://src/gameplay/components/hurtbox_component.gd")


class Fighter extends Node2D:
	var hp: int = 100

	func get_attack_power() -> int:
		return 20

	func get_defense() -> int:
		return 0

	func get_current_health() -> int:
		return hp

	func is_dead() -> bool:
		return hp <= 0

	func take_damage(amount: int) -> int:
		var before := hp
		hp = maxi(0, hp - maxi(0, amount))
		return before - hp


func _attack() -> AttackData:
	var attack: AttackData = AttackDataScript.new()
	attack.id = &"attack_test"
	attack.windup_seconds = 0.1
	attack.active_seconds = 0.05
	attack.recovery_seconds = 0.2
	attack.reach_pixels = 60.0
	attack.arc_degrees = 360.0
	attack.power_multiplier = 1.0
	attack.critical_chance_percent = 0
	attack.critical_multiplier = 2.0
	return attack


func _fighter(id: StringName, at: Vector2) -> Fighter:
	var body := Fighter.new()
	body.name = String(id)
	var attack: AttackComponent = AttackComponentScript.new()
	attack.name = "AttackComponent"
	body.add_child(attack)
	var hurtbox: HurtboxComponent = HurtboxComponentScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = id
	hurtbox.radius = 8.0
	body.add_child(hurtbox)
	add_to_tree(body)
	body.global_position = at
	return body


func _swing(body: Fighter) -> void:
	var component := body.get_node("AttackComponent") as AttackComponent
	component.set_facing(Vector2.RIGHT)
	assert_true(component.request_attack(), "%s swings" % body.name)
	component.advance(0.12)
	component.advance(0.06)
	component.advance(0.3)


func test_a_swing_skips_its_own_team_and_hits_everyone_else() -> void:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(RngServiceScript.new(11))
	var player := _fighter(&"player", Vector2(0, 0))
	var pet := _fighter(&"pet", Vector2(10, 0))
	var wolf := _fighter(&"wolf", Vector2(20, 0))
	var wolf_two := _fighter(&"wolf_two", Vector2(30, 0))
	var post := _fighter(&"post", Vector2(15, 5))
	runtime.arm_attacker(player, _attack(), &"player", CombatRuntime.TEAM_PLAYER)
	runtime.arm_attacker(pet, _attack(), &"pet", CombatRuntime.TEAM_PLAYER)
	runtime.arm_attacker(wolf, _attack(), &"wolf", CombatRuntime.TEAM_HOSTILE)
	runtime.arm_attacker(wolf_two, _attack(), &"wolf_two", CombatRuntime.TEAM_HOSTILE)
	runtime.register_target(post)                      # no team: a training post

	_swing(pet)
	assert_eq(player.hp, 100, "the pet's swing never hurts its owner")
	assert_true(wolf.hp < 100 and wolf_two.hp < 100, "it hits every hostile in its arc")
	assert_true(post.hp < 100, "and a team-less post, as the player's swing does")

	var wolf_before := wolf.hp
	var post_before := post.hp
	_swing(wolf_two)
	assert_eq(wolf.hp, wolf_before, "a wolf's swing never hurts another wolf")
	assert_true(player.hp < 100 and pet.hp < 100, "it hits the player's whole side")
	assert_true(post.hp < post_before, "and the post")

	var registry := runtime.get_registry()
	assert_eq(registry.targets(&"player", CombatRuntime.TEAM_PLAYER).size(), 3,
		"the player's side may target: two wolves and the post")
	assert_eq(registry.targets(&"player").size(), 4,
		"with no team given, only the attacker itself is excluded (the Phase-09 behaviour)")
	assert_eq((pet.get_node("AttackComponent") as AttackComponent).team(),
		CombatRuntime.TEAM_PLAYER, "the component knows its side")

	runtime.disarm(pet, &"pet")
	assert_eq(registry.targets(&"wolf", CombatRuntime.TEAM_HOSTILE).size(), 2,
		"a disarmed companion is no longer targetable (player + post remain)")
	runtime.disarm(pet, &"pet")                        # idempotent
	runtime.disarm(null, &"nobody")                    # and safe on junk
	runtime.end_session()
	for node in [player, pet, wolf, wolf_two, post, runtime]:
		free_node(node)

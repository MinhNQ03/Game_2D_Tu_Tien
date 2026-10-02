extends TestCase
## Integration test for the Phase-02 bidirectional damage CONTRACT between Player and
## TrainingDummy, resolved through the domain `DamageRules` (exactly how the sandbox
## coordinator resolves it). Proves "player takes/returns damage against a dummy" (the
## ROADMAP Phase-02 exit) at the entity level.
##
## Isolation (D-019): fresh Player/Dummy instances in the tree; no /root autoload mutated.
## We call the entities' public damage API with amounts from the SAME domain rule the
## coordinator uses — no duplicated damage math, no combat system. The coordinator's own
## range/orchestration path is covered end-to-end by the dedicated E2E process.

const PlayerScene := preload("res://src/gameplay/entities/player.tscn")
const DummyScene := preload("res://src/gameplay/entities/training_dummy.tscn")
const DamageRulesScript := preload("res://src/domain/combat/damage_rules.gd")


func test_player_damages_dummy() -> void:
	var player: Node = PlayerScene.instantiate()
	var dummy: Node = DummyScene.instantiate()
	add_to_tree(player)
	add_to_tree(dummy)
	await scene_tree.process_frame

	var dummy_start: int = dummy.get_current_health()
	var expected: int = DamageRulesScript.compute_hit(player.get_attack_power(), dummy.get_defense())
	assert_true(expected > 0, "a hit deals positive damage")

	var applied: int = dummy.take_damage(expected)
	assert_eq(applied, expected, "dummy takes the computed hit")
	assert_eq(dummy.get_current_health(), dummy_start - expected, "dummy HP dropped by exactly the hit")

	free_node(player)
	free_node(dummy)


func test_dummy_damages_player() -> void:
	var player: Node = PlayerScene.instantiate()
	var dummy: Node = DummyScene.instantiate()
	add_to_tree(player)
	add_to_tree(dummy)
	await scene_tree.process_frame

	var player_start: int = player.get_current_health()
	var expected: int = DamageRulesScript.compute_hit(dummy.get_attack_power(), player.get_defense())
	assert_true(expected > 0, "the dummy's retaliation deals positive damage")

	var applied: int = player.take_damage(expected)
	assert_eq(applied, expected, "player takes the dummy's hit (bidirectional)")
	assert_eq(player.get_current_health(), player_start - expected, "player HP dropped by exactly the hit")

	free_node(player)
	free_node(dummy)


func test_dummy_reset_restores_full_health() -> void:
	var dummy: Node = DummyScene.instantiate()
	add_to_tree(dummy)
	await scene_tree.process_frame

	var full: int = dummy.get_max_health()
	dummy.take_damage(10)
	assert_true(dummy.get_current_health() < full, "dummy damaged")
	dummy.reset_dummy()
	assert_eq(dummy.get_current_health(), full, "reset restores full health (fresh sandbox run)")

	free_node(dummy)


func test_dummy_dies_from_lethal_damage() -> void:
	var dummy: Node = DummyScene.instantiate()
	add_to_tree(dummy)
	await scene_tree.process_frame

	var died := {"n": 0}
	dummy.died.connect(func() -> void: died["n"] += 1)
	dummy.take_damage(999999)
	assert_true(dummy.is_dead(), "dummy dies on lethal damage")
	assert_eq(died["n"], 1, "dummy died once")
	assert_eq(dummy.get_current_health(), 0, "clamped to zero")

	free_node(dummy)

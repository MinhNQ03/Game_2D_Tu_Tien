extends TestCase
## Integration tests for the Player ↔ CharacterState binding (Phase 04, D-023,
## `docs/CHARACTER_SYSTEM.md` §6). Proves the ONE-source-of-truth contract in the live tree:
##   - the Player's StatsComponent reads stats from the bound CharacterState (not a copy),
##   - HealthComponent initializes current HP from the state and syncs HP changes back,
##   - a death transitions the authoritative life_state to DEAD,
##   - composition is kept (components still present; no inheritance).
##
## Isolation (D-019): fresh instances + a fresh CharacterState; NEVER mutates a /root autoload.

const PlayerScene := preload("res://src/gameplay/entities/player.tscn")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")


func _state(max_hp: int = 60, attack: int = 15, move_speed: float = 130.0) -> RefCounted:
	var stats := StatBlockScript.new()
	stats.max_hp = max_hp
	stats.attack = attack
	stats.defense = 4
	stats.move_speed = move_speed
	var t := TemplateScript.new()
	t.id = &"char_test"
	t.name_key = &"NAME_TEST"
	t.base_stats = stats
	return StateScript.create_from_template(t, &"inst_test")


## Stats come from the bound state, overriding the scene's authored StatBlock (player_stats
## has max_hp 100; the bound state uses 60).
func test_player_reads_stats_from_bound_state() -> void:
	var player: Node = PlayerScene.instantiate()
	var state := _state(60, 15)
	player.bind_character_state(state)
	add_to_tree(player)
	await scene_tree.process_frame

	assert_eq(player.get_max_health(), 60, "max HP from bound state, not the scene StatBlock")
	assert_eq(player.get_current_health(), 60, "starts at the state's current_hp (full)")
	assert_eq(player.get_attack_power(), 15, "attack from bound state")
	assert_true(player.get_character_state() == state, "player exposes the bound state instance")

	# Composition is kept: components still present.
	assert_not_null(player.get_node_or_null("StatsComponent"), "StatsComponent present")
	assert_not_null(player.get_node_or_null("HealthComponent"), "HealthComponent present")
	assert_not_null(player.get_node_or_null("MovementComponent"), "MovementComponent present")

	free_node(player)


## HP changes on the runtime HealthComponent sync back into the authoritative state, so the
## domain stays the single source of truth (a future save reads current_hp from the state).
func test_damage_syncs_back_to_state() -> void:
	var player: Node = PlayerScene.instantiate()
	var state := _state(60, 15)
	player.bind_character_state(state)
	add_to_tree(player)
	await scene_tree.process_frame

	player.take_damage(25)
	assert_eq(player.get_current_health(), 35, "runtime HP reduced")
	assert_eq(state.current_hp, 35, "authoritative state HP synced from the health view")

	free_node(player)


## A lethal hit transitions the authoritative life_state to DEAD (ALIVE→DEAD once).
func test_death_marks_state_dead() -> void:
	var player: Node = PlayerScene.instantiate()
	var state := _state(60, 15)
	player.bind_character_state(state)
	add_to_tree(player)
	await scene_tree.process_frame

	assert_true(state.is_alive(), "alive before")
	player.take_damage(1000)
	assert_true(player.is_dead(), "runtime health reports dead")
	assert_true(state.is_dead(), "authoritative life_state is DEAD")

	free_node(player)


## Starting HP is restored from the state's current_hp (so a loaded-wounded character is
## wounded in the realized node, not reset to full).
func test_wounded_state_restores_current_hp() -> void:
	var player: Node = PlayerScene.instantiate()
	var state := _state(60, 15)
	state.set_current_hp(20)  # pretend a save loaded a wounded character
	player.bind_character_state(state)
	add_to_tree(player)
	await scene_tree.process_frame

	assert_eq(player.get_max_health(), 60, "max from state")
	assert_eq(player.get_current_health(), 20, "current HP initialized from the state, not full")

	free_node(player)

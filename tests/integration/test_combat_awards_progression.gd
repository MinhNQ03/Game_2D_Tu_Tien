extends TestCase
## Integration test for the Phase-11 reward path: a REAL enemy, spawned from a REAL spawn
## table by the REAL `CombatRuntime`, dying for real — and the player's XP moving as a result.
##
## WHAT THIS COVERS THAT THE UNIT TESTS CANNOT. The unit tests drive `ProgressionRuntime` by
## emitting combat's signal by hand, which proves the progression side in isolation but says
## nothing about whether anything ever emits it. This file wires the two runtimes together the
## way `Main` does and kills a creature through its own health component, so it fails if the
## announcement is never made, is made with the wrong payload, or is made for a creature whose
## authored reward was never read. That is the seam L-029 is about: every piece correct, and
## the path between them never exercised.
##
## It stops short of real INPUT — the player does not swing here. That boundary belongs to the
## real-app E2E (L-017: a test must drive the boundary it advertises, and this one advertises
## the combat→progression wiring, not the input pipeline).

const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const ProgressionRuntimeScript := preload("res://src/gameplay/world/progression_runtime.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const SpawnTableScript := preload("res://src/data/enemies/enemy_spawn_table_data.gd")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

const ENEMY_PATH := "res://data/enemies/enemy_mist_wolf.tres"
const CURVE_PATH := "res://data/progression/player_progression_curve.tres"
const WORLD_SEED := 20261105

var _combat: CombatRuntime = null
var _progression: Node = null
var _character: CharacterState = null
var _xp_events: Array = []
var _level_events: Array = []


func before_each() -> void:
	_xp_events = []
	_level_events = []
	_character = _build_character()
	_combat = CombatRuntimeScript.new()
	add_to_tree(_combat)
	_combat.start_session(RngServiceScript.new(WORLD_SEED))
	_progression = Node.new()
	_progression.name = "ProgressionRuntime"
	_progression.set_script(ProgressionRuntimeScript)
	add_to_tree(_progression)
	_progression.call("start_session", _character, _combat, RewardLedger.new())
	_progression.connect("xp_gained", func(amount: int, reward_id: StringName) -> void:
		_xp_events.append({"amount": amount, "id": reward_id}))
	_progression.connect("level_changed", func(previous: int, current: int) -> void:
		_level_events.append({"previous": previous, "current": current}))


func after_each() -> void:
	# Progression FIRST, exactly as `Main.SESSION_START_ORDER` reversed requires: it must stop
	# listening before the emitter it listens to is torn down.
	if _progression != null and is_instance_valid(_progression):
		_progression.call("end_session")
	if _combat != null and is_instance_valid(_combat):
		_combat.end_session()
	free_node(_progression)
	free_node(_combat)
	_progression = null
	_combat = null
	_character = null


func _build_character() -> CharacterState:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 50
	stats.attack = 5
	stats.defense = 0
	stats.move_speed = 60.0
	var template: CharacterTemplateData = TemplateScript.new()
	template.id = &"char_player_test"
	template.name_key = &"NAME_TEST"
	template.base_stats = stats
	return StateScript.create_from_template(template, &"player")


func _table(rows: int) -> EnemySpawnTableData:
	var table: EnemySpawnTableData = SpawnTableScript.new()
	table.map_id = &"map_field"
	var data := load(ENEMY_PATH) as EnemyData
	var enemies: Array[EnemyData] = []
	var positions := PackedVector2Array()
	for i in rows:
		enemies.append(data)
		positions.append(Vector2(200 + i * 80, 200))
	table.enemies = enemies
	table.positions = positions
	return table


## Kill `enemy` through its own health component — the same path a real hit takes once
## `CombatService` has computed the damage. Not a direct `mark_dead`, so the entity's real
## death chain (`HealthComponent.died` → `Enemy._on_health_died` → `died`) actually runs.
func _kill(enemy: Enemy) -> void:
	for _i in 100:
		if enemy.is_dead():
			return
		enemy.take_damage(enemy.get_max_health())


func _authored_reward() -> int:
	var data := load(ENEMY_PATH) as EnemyData
	return data.xp_reward


# --- The fixture -------------------------------------------------------------

func test_the_two_sessions_are_wired() -> void:
	assert_true(_combat.is_session_active(), "combat is live")
	assert_true(bool(_progression.call("is_session_active")), "progression is live")
	assert_true(_combat.is_connected("enemy_defeated",
		Callable(_progression, "grant_for_defeat")),
		"and progression is listening to combat's defeat announcement")
	assert_true(_authored_reward() > 0,
		"the authored creature is worth something (got %d)" % _authored_reward())


# --- The reward path, end to end --------------------------------------------

func test_killing_a_real_spawned_creature_grants_its_authored_xp() -> void:
	assert_eq(_combat.spawn_from_table(_table(1), _combat), 1, "one creature spawned")
	var enemies := _combat.enemies()
	assert_eq(enemies.size(), 1, "and it is in the session's list")
	if enemies.is_empty():
		return
	var enemy := enemies[0]
	assert_eq(_character.xp, 0, "the player starts with no XP")

	_kill(enemy)

	assert_true(enemy.is_dead(), "the creature died")
	assert_eq(_character.xp, _authored_reward(),
		("the player's XP is exactly the creature's authored `xp_reward` — read from content, "
			+ "not from a formula or a branch on the creature's id"))
	assert_eq(_xp_events.size(), 1, "one xp_gained was published")
	assert_eq(_xp_events[0]["amount"], _authored_reward(), "carrying the authored amount")


func test_the_first_kill_reaches_the_first_level_up() -> void:
	# A game-feel contract with a wiring consequence: if one authored kill did not level, the
	# real-app E2E and the playtest harness would have nothing to observe from a single
	# reproducible encounter.
	_combat.spawn_from_table(_table(1), _combat)
	_kill(_combat.enemies()[0])
	assert_eq(_level_events.size(), 1,
		"the first authored kill produces a level-up (xp=%d)" % _character.xp)
	assert_eq(_level_events[0]["previous"], 1, "from level 1")
	assert_eq(_level_events[0]["current"], 2, "to level 2")


func test_each_distinct_creature_pays_once() -> void:
	assert_eq(_combat.spawn_from_table(_table(3), _combat), 3, "three creatures")
	for enemy in _combat.enemies():
		_kill(enemy)
	assert_eq(_character.xp, _authored_reward() * 3, "three kills, three rewards")
	assert_eq(_xp_events.size(), 3, "three events")
	assert_eq(int(_progression.call("granted_count")), 3, "three ledger entries")


## The reward identity must be unique per SPAWN, not per spawn-table row.
##
## This is the case that made the composed `id#serial` necessary, and it is only observable
## here: clearing the field, leaving, and coming back re-populates from the SAME table with
## the same row ids. Keyed on the row id alone, the progression ledger would have silently
## become a "this row has ever been killed" flag and the second clear would pay nothing —
## which reads as a balance bug, not a wiring bug.
func test_a_recleared_population_rewards_again() -> void:
	_combat.spawn_from_table(_table(1), _combat)
	var first_id := _combat.reward_id_of(_combat.enemies()[0].instance_id())
	_kill(_combat.enemies()[0])
	var after_first := _character.xp
	assert_eq(after_first, _authored_reward(), "the first clear paid")

	# Leaving and returning: the world despawns the old population and repopulates.
	_combat.despawn_enemies()
	_combat.spawn_from_table(_table(1), _combat)
	var second_id := _combat.reward_id_of(_combat.enemies()[0].instance_id())
	assert_ne(str(first_id), str(second_id),
		"the respawned creature has a DIFFERENT reward id (%s vs %s)"
			% [str(first_id), str(second_id)])
	_kill(_combat.enemies()[0])
	assert_eq(_character.xp, after_first + _authored_reward(),
		"and clearing the field a second time pays again")


func test_a_corpse_announced_twice_still_pays_once() -> void:
	_combat.spawn_from_table(_table(1), _combat)
	var enemy := _combat.enemies()[0]
	_kill(enemy)
	var after := _character.xp
	# Re-emit the entity's own death signal, as a double-connected signal or a repeated
	# `died` would. Both ledgers (the emitter's and the owner's) stand between this and a
	# second payout.
	enemy.emit_signal("died")
	enemy.emit_signal("died")
	assert_eq(_character.xp, after, "a re-announced death pays nothing further")
	assert_eq(_xp_events.size(), 1, "and publishes nothing further")


# --- Lifecycle ---------------------------------------------------------------

func test_a_kill_after_progression_ends_grants_nothing() -> void:
	_combat.spawn_from_table(_table(1), _combat)
	_progression.call("end_session")
	_kill(_combat.enemies()[0])
	assert_eq(_character.xp, 0,
		("with progression torn down, combat still announces and nothing is granted — the "
			+ "disconnect is what stops a defeat landing in a CharacterState the world "
			+ "session is freeing"))


func test_progression_survives_a_map_change_and_keeps_the_players_total() -> void:
	# A map transition despawns and repopulates combat but does NOT end the progression
	# session, so the player's accumulated XP must carry across. The authority is the
	# CharacterState, which the world session owns for the whole run.
	_combat.spawn_from_table(_table(1), _combat)
	_kill(_combat.enemies()[0])
	var carried := _character.xp
	_combat.despawn_enemies()
	assert_true(bool(_progression.call("is_session_active")),
		"a map change does not end the progression session")
	assert_eq(_character.xp, carried, "and the player's total is untouched by the swap")
	var view: ProgressionView = _progression.call("build_view")
	assert_eq(view.level, 2, "the view still reports the level reached before the swap")


# --- The forbidden combination ----------------------------------------------

## The state Phase 11 must make unreachable: a live combat session announcing defeats while
## nothing owns the XP they are worth.
##
## Named and asserted rather than only avoided, because "start returned true" is not a test of
## what a session contains (L-025). `Main` makes a progression failure fatal for New Game, so
## the only way to reach "combat live, progression dead" is the teardown order — and in that
## order progression is already disconnected.
func test_combat_cannot_be_live_while_progression_silently_owns_nothing() -> void:
	assert_true(_combat.is_session_active() and bool(_progression.call("is_session_active")),
		"the normal state is BOTH live")
	_progression.call("end_session")
	_combat.spawn_from_table(_table(1), _combat)
	_kill(_combat.enemies()[0])
	# With progression down, the defeat is announced into nothing — and crucially the player's
	# state is NOT silently half-updated.
	assert_eq(_character.xp, 0, "no XP was granted")
	assert_eq(_xp_events.size(), 0, "and nothing was published")
	assert_false(bool(_progression.call("build_view").available),
		"and the view reports unavailable, so the HUD hides the row rather than showing a "
		+ "stale level")

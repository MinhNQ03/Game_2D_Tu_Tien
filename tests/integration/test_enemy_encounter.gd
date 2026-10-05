extends TestCase
## Integration tests for the Phase-10 encounter: AI + movement + combat + hurtbox registry +
## death cleanup + spawn/despawn + frame-timing behaviour.
##
## These build a REAL `CombatRuntime` session with a REAL seeded `RngService`, spawn REAL
## enemies from a REAL spawn table, and step the AI with EXACT deltas. They do not boot the
## app (the world E2E does that) and they never touch the live `/root` singletons (D-019).
##
## Every `Node` created here is freed by the test that created it: a `Node` built in the
## headless runner does not auto-release, and one unfreed node pins its script and its native
## class, surfacing as several leaked ObjectDB at exit (L-019).

const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const SpawnTableScript := preload("res://src/data/enemies/enemy_spawn_table_data.gd")
const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")

const ENEMY_PATH := "res://data/enemies/enemy_mist_wolf.tres"
const FIELD_TABLE_PATH := "res://data/enemies/spawn_table_field.tres"
const WORLD_SEED := 20261005

## Decision interval of the shipped profile. Stepping by exactly this guarantees one decision
## per `tick()` call, which is what makes these tests read as a sequence of decisions.
const STEP := 0.2


func _rng() -> RngService:
	return RngServiceScript.new(WORLD_SEED)


func _runtime() -> CombatRuntime:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(_rng())
	return runtime


func _enemy_data() -> EnemyData:
	return load(ENEMY_PATH) as EnemyData


## A one-row table at `position`, built in code so a test controls the geometry.
func _table(position: Vector2, rows: int = 1) -> EnemySpawnTableData:
	var table: EnemySpawnTableData = SpawnTableScript.new()
	table.map_id = &"map_field"
	var data := _enemy_data()
	var enemies: Array[EnemyData] = []
	var positions := PackedVector2Array()
	for i in rows:
		enemies.append(data)
		positions.append(position + Vector2(i * 200, 0))
	table.enemies = enemies
	table.positions = positions
	return table


## A stand-in player: the minimum contract combat reaches an entity through.
class TestPlayer extends CharacterBody2D:
	var hp: int = 100

	func get_attack_power() -> int:
		return 20

	func get_defense() -> int:
		return 3

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


## A stand-in player that can actually BE HIT.
##
## The hurtbox is the point: `register_target()` looks for a `HurtboxComponent`, so a bare
## body registers nothing and every enemy swing finds no target — which is how the first
## version of these tests reported "the enemy did not damage the player" while the real game
## damaged it correctly. A fixture that cannot be hit proves nothing about combat.
func _player(position: Vector2) -> TestPlayer:
	var player := TestPlayer.new()
	player.name = "TestPlayer"
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"test_player"
	hurtbox.radius = 10.0
	player.add_child(hurtbox)
	add_to_tree(player)
	player.global_position = position
	return player


# === The shipped content ====================================================

## The shipped creature and table must be VALID, because a combat system with nothing in the
## world to fight is a no-op with documentation (L-029). An invalid `.tres` would leave the
## field empty and nothing else would notice.
func test_the_shipped_enemy_and_field_table_are_valid() -> void:
	var data := _enemy_data()
	assert_not_null(data, "the shipped enemy loads as EnemyData")
	if data != null:
		assert_true(data.is_valid(), "and its authored values pass validation")
		assert_eq(data.id, &"enemy_mist_wolf", "with its documented id")
		# The creature must be able to reach what it stops at, or it swings at the air.
		assert_true(data.engage_distance <= data.attack.reach_pixels,
			"it stops inside its own reach (%.1f <= %.1f)"
				% [data.engage_distance, data.attack.reach_pixels])
	var table := load(FIELD_TABLE_PATH) as EnemySpawnTableData
	assert_not_null(table, "the field spawn table loads")
	if table != null:
		assert_true(table.is_valid(), "and is valid")
		assert_eq(table.map_id, &"map_field", "it populates the field")
		assert_true(table.size() >= 1, "with at least one creature (got %d)" % table.size())


## Instance ids are DERIVED from the map and row, not from a counter, so the same table always
## names the same creature the same way — which is what a save, a replay and a future
## authoritative server all need.
func test_instance_ids_are_stable_and_unique() -> void:
	var table := _table(Vector2(100, 100), 3)
	var seen := {}
	for i in table.size():
		var id := table.instance_id_for(i)
		assert_ne(String(id), "", "row %d has an id" % i)
		assert_false(seen.has(String(id)), "row %d's id is unique" % i)
		seen[String(id)] = true
	assert_eq(table.instance_id_for(0), _table(Vector2.ZERO, 3).instance_id_for(0),
		"the id depends on the map and row, not on where the creature stands")
	assert_eq(String(table.instance_id_for(99)), "", "an out-of-range row has no id")


## A length mismatch must be REJECTED rather than spawning the shorter prefix: a table that
## silently drops its last row is a map quietly emptier than it was authored to be. This is
## also the bug that actually happened — a `PackedVector2Array` authored into an
## `Array[Vector2]` left positions empty, and only this check caught it (L-026).
func test_a_mismatched_table_is_rejected_not_truncated() -> void:
	var table := _table(Vector2(100, 100), 2)
	table.positions = PackedVector2Array([Vector2(1, 1)])
	assert_false(table.is_valid(), "two creatures and one position is refused")
	var runtime := _runtime()
	assert_eq(runtime.spawn_from_table(table, runtime), 0, "and nothing spawns")
	free_node(runtime)


# === Spawning ===============================================================

func test_spawning_populates_arms_and_registers_every_row() -> void:
	var runtime := _runtime()
	var spawned := runtime.spawn_from_table(_table(Vector2(400, 300), 2), runtime)
	assert_eq(spawned, 2, "both rows spawned")
	assert_eq(runtime.enemy_count(), 2, "the session tracks both")
	assert_eq(runtime.living_enemy_count(), 2, "both are alive")
	var registry := runtime.get_registry()
	for enemy in runtime.enemies():
		assert_true(registry.has(enemy.instance_id()),
			"'%s' is registered as a combat target" % enemy.instance_id())
		assert_eq(enemy.get_max_health(), _enemy_data().stats.max_hp,
			"its health came from the authored StatBlock")
		assert_true(enemy.ai().is_armed(), "and its AI is armed")
	free_node(runtime)


func test_spawning_outside_a_session_is_refused() -> void:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	assert_eq(runtime.spawn_from_table(_table(Vector2.ZERO), runtime), 0,
		"no session means nothing spawns")
	free_node(runtime)


## Despawning must leave the registry clean, or the next map's player keeps swinging at
## hurtboxes belonging to creatures that no longer exist.
func test_despawning_clears_the_registry_and_stops_the_tick() -> void:
	var runtime := _runtime()
	runtime.spawn_from_table(_table(Vector2(400, 300), 2), runtime)
	var ids: Array[StringName] = []
	for enemy in runtime.enemies():
		ids.append(enemy.instance_id())
	runtime.despawn_enemies()
	assert_eq(runtime.enemy_count(), 0, "no enemies remain")
	for id in ids:
		assert_false(runtime.get_registry().has(id),
			"'%s' is no longer a combat target" % id)
	assert_false(runtime.is_physics_processing(),
		"and the AI tick stops entirely rather than iterating an empty list")
	free_node(runtime)


# === AI driving real movement and combat ====================================

## It notices the player and CLOSES. Asserts perception and motion only.
##
## Deliberately does NOT assert damage. Travel distance depends on `move_and_slide()`, which
## integrates against the ENGINE's physics delta rather than the delta this test passes — so
## how far the creature gets per tick is not under the test's control, and requiring a hit
## here made the test depend on machine load. The next test asserts the hit from inside reach,
## where no travel is needed. One mechanism per test.
func test_an_enemy_notices_the_player_and_closes() -> void:
	var runtime := _runtime()
	var player := _player(Vector2(500, 300))
	runtime.register_target(player)
	runtime.set_hunt_target(player)
	runtime.spawn_from_table(_table(Vector2(600, 300)), runtime)
	var enemy := runtime.enemies()[0]
	var start_distance := enemy.global_position.distance_to(player.global_position)

	var states := {}
	for _i in 40:
		runtime.tick_enemies(STEP)
		states[enemy.ai_state_name()] = true

	assert_true(states.has("ALERT"),
		"it telegraphed noticing the player, got %s" % str(states.keys()))
	assert_true(states.has("CHASE"), "it chased, got %s" % str(states.keys()))
	assert_true(enemy.global_position.distance_to(player.global_position) < start_distance,
		"and it closed the distance (%.0f -> %.0f)" % [
			start_distance, enemy.global_position.distance_to(player.global_position)])
	free_node(runtime)
	free_node(player)


## From inside its reach it BITES — damaging the player through `AttackComponent` →
## `CombatService` → `DamageRules`, with no combat code of its own.
##
## Spawned already within `engage_distance`, so the assertion is about the attack path rather
## than about how fast the creature can walk.
func test_an_enemy_in_reach_damages_the_player() -> void:
	var runtime := _runtime()
	var player := _player(Vector2(400, 300))
	runtime.register_target(player)
	runtime.set_hunt_target(player)
	runtime.spawn_from_table(_table(Vector2(418, 300)), runtime)
	var enemy := runtime.enemies()[0]
	var components := _attack_components(enemy)
	var hp_before := player.hp

	# Bounded: the chain is ALERT (0.35s) -> CHASE -> SWING, then a 0.26s windup, so ~20
	# steps of 0.2s is several times what it needs.
	for _i in 40:
		runtime.tick_enemies(STEP)
		# The attack lifecycle runs on the same clock, so a requested swing can actually land
		# (the headless runner does not run `_physics_process` the way a game does, L-016).
		for component in components:
			component.advance(STEP)
		if player.hp < hp_before:
			break

	assert_true(player.hp < hp_before,
		"the enemy bit the player (%d -> %d)" % [hp_before, player.hp])
	# The damage must be the FORMULA's, not an invented number: 9 attack against 3 defense is
	# round(9 * 100/103) = 9. Asserting the value is what proves combat went through
	# `DamageRules` rather than through a creature-specific path.
	var dealt := hp_before - player.hp
	var expected := DamageRules.compute_hit(
		enemy.get_attack_power(), player.get_defense(),
		enemy.data().attack.power_multiplier)
	assert_true(dealt == expected or dealt == int(round(
			float(expected) * enemy.data().attack.critical_multiplier)),
		("the damage is DamageRules' output, normal (%d) or critical (%d) — got %d"
			% [expected, int(round(float(expected)
				* enemy.data().attack.critical_multiplier)), dealt]))
	free_node(runtime)
	free_node(player)


## An enemy must be damageable by the same machinery the player is — no creature-specific path.
func test_an_enemy_takes_damage_and_dies() -> void:
	var runtime := _runtime()
	runtime.spawn_from_table(_table(Vector2(400, 300)), runtime)
	var enemy := runtime.enemies()[0]
	var full := enemy.get_max_health()
	assert_eq(enemy.get_current_health(), full, "it starts at full health")
	enemy.take_damage(5)
	assert_eq(enemy.get_current_health(), full - 5, "damage lands")
	assert_false(enemy.is_dead(), "and it is still alive")
	while not enemy.is_dead():
		enemy.take_damage(10)
	assert_true(enemy.is_dead(), "enough damage kills it")
	free_node(runtime)


## DEATH CLEANUP, all four properties at once (C11). Each one alone leaves a visible wrong:
## a corpse that keeps hunting, keeps sliding, stays targetable, or lands a hit from beyond
## the grave.
func test_a_dead_enemy_stops_everything() -> void:
	var runtime := _runtime()
	var player := _player(Vector2(410, 300))
	runtime.register_target(player)
	runtime.set_hunt_target(player)
	runtime.spawn_from_table(_table(Vector2(400, 300)), runtime)
	var enemy := runtime.enemies()[0]
	# Get it hunting first, so there is something live to stop.
	for _i in 6:
		runtime.tick_enemies(STEP)
	while not enemy.is_dead():
		enemy.take_damage(10)

	assert_false(runtime.get_registry().has(enemy.instance_id()),
		"a corpse is no longer targetable, so the player stops swinging at nothing")
	assert_eq(runtime.living_enemy_count(), 0, "nothing is alive")
	assert_false(runtime.is_physics_processing(),
		"the AI tick stops rather than iterating corpses every frame")
	assert_eq(enemy.ai().brain_state_name(), "IDLE", "its brain was reset")
	assert_null(enemy.ai().target(), "it forgot its target")

	var hp_before := player.hp
	var position_at_death := enemy.global_position
	# Keep ticking: a dead creature must do NOTHING, however long the world runs.
	for _i in 40:
		runtime.tick_enemies(STEP)
		for component in _attack_components(enemy):
			component.advance(STEP)
	assert_eq(enemy.global_position, position_at_death, "it does not move after death")
	assert_eq(player.hp, hp_before, "and it cannot land a hit from beyond the grave")
	free_node(runtime)
	free_node(player)


## A hit must MARK the creature, and a kill must leave the corpse look standing.
##
## This spawns the REAL `enemy.tscn` from the REAL shipped table, so it proves the scene is
## actually wired with a `DamageFeedback` — a unit test against a hand-built stub would pass
## with the node missing from the scene entirely, which is the gap L-029 is about. Damage goes
## through the REAL `HurtboxComponent.apply_hit()`, because that is what emits `damaged`;
## `enemy.take_damage()` bypasses the hurtbox and would silently prove nothing.
##
## It also pins the SEAM the review pass moved: the corpse look now comes from the presentation
## node and the palette, not from a literal inside `Enemy`.
func test_a_damaged_enemy_flashes_and_a_dead_one_wears_the_corpse_look() -> void:
	var runtime := _runtime()
	runtime.spawn_from_table(_table(Vector2(400, 300)), runtime)
	var enemy := runtime.enemies()[0]
	var feedback := enemy.get_node_or_null("DamageFeedback") as DamageFeedback
	assert_not_null(feedback, "the shipped enemy scene carries a DamageFeedback")
	var hurtbox := enemy.get_node("HurtboxComponent") as HurtboxComponent
	var resting := feedback.resting_tint()

	hurtbox.apply_hit(4, false)
	assert_true(feedback.is_flashing(), "a landed hit flashes the creature")
	assert_ne(enemy.modulate, resting, "so the player can see WHAT they hit, on the creature")
	feedback.advance(UIPalette.HIT_FLASH_SECONDS * 1.5)
	assert_eq(enemy.modulate, resting, "and it returns to its normal colour")

	# Kill it through the hurtbox so the real ordering happens: health applied -> `died`
	# (the corpse look) -> `damaged` emitted.
	while not enemy.is_dead():
		hurtbox.apply_hit(10, false)
	assert_false(feedback.is_flashing(), "the killing blow starts no flash")
	assert_true(feedback.is_corpse(), "the creature wears its corpse look")
	assert_eq(enemy.modulate, UIPalette.CORPSE_TINT,
		"which is the palette token, applied by presentation and not by the entity (%s)"
			% str(enemy.modulate))
	feedback.advance(UIPalette.HIT_FLASH_SECONDS * 4.0)
	assert_eq(enemy.modulate, UIPalette.CORPSE_TINT,
		"and nothing restores a living colour over it, however long the world runs")
	free_node(runtime)


## Ending the session must stop every creature BEFORE the world it reasons about disappears.
func test_ending_the_session_stops_and_clears_enemies() -> void:
	var runtime := _runtime()
	var player := _player(Vector2(450, 300))
	runtime.register_target(player)
	runtime.set_hunt_target(player)
	runtime.spawn_from_table(_table(Vector2(400, 300), 2), runtime)
	assert_eq(runtime.enemy_count(), 2, "two creatures are live")
	runtime.end_session()
	assert_false(runtime.is_session_active(), "the session ended")
	assert_eq(runtime.enemy_count(), 0, "and took its creatures with it")
	assert_null(runtime.get_registry(), "the registry is gone")
	assert_false(runtime.is_physics_processing(), "and nothing is still ticking")
	free_node(runtime)
	free_node(player)


# === Tick rate and frame timing =============================================

## DECISIONS are throttled to the profile's interval; MOVEMENT is not. That separation is the
## Phase-10 requirement, and it is asserted by counting decisions over a known span rather
## than by trusting the interval was honoured.
func test_decisions_are_throttled_but_movement_is_not() -> void:
	var runtime := _runtime()
	runtime.spawn_from_table(_table(Vector2(400, 300)), runtime)
	var ai := runtime.enemies()[0].ai()
	# Two seconds in 60fps frames: 120 ticks, but only ~10 decisions at a 0.2s interval.
	for _i in 120:
		runtime.tick_enemies(1.0 / 60.0)
	var decisions := ai.decisions()
	assert_true(decisions >= 8 and decisions <= 12,
		("2s at 60fps is ~10 decisions at a 0.2s interval, not 120 (got %d). A count near "
			+ "120 means the AI is thinking every frame.") % decisions)
	free_node(runtime)


## A LONG FRAME must not break the interaction between the brain and the attack lifecycle:
## no double swing, no stuck ATTACK, no resurrection.
func test_a_long_frame_does_not_double_swing_or_stick() -> void:
	var runtime := _runtime()
	var player := _player(Vector2(415, 300))
	runtime.register_target(player)
	runtime.set_hunt_target(player)
	runtime.spawn_from_table(_table(Vector2(400, 300)), runtime)
	var enemy := runtime.enemies()[0]
	var components := _attack_components(enemy)

	# One absurd 5-second frame, repeatedly. The brain sees a huge delta and the attack
	# lifecycle consumes it state by state.
	for _i in 10:
		runtime.tick_enemies(5.0)
		for component in components:
			component.advance(5.0)

	assert_false(enemy.is_dead(), "the enemy is unharmed by frame timing alone")
	assert_ne(enemy.ai_state_name(), "ATTACK",
		"it is not stuck in ATTACK (which would mean the swing never completed)")
	# Each swing resolves at most one hit pass, so damage stays proportional to swings rather
	# than to how long a frame happened to be.
	for component in components:
		assert_true(component.swings_resolved() <= 10,
			"at most one resolution per swing (%d swings over 10 frames)"
				% component.swings_resolved())
	free_node(runtime)
	free_node(player)


## Determinism at the integration level: the same seed and the same stepping produce the same
## positions and the same states. This is what makes an encounter reproducible.
func test_the_same_seed_reproduces_the_same_encounter() -> void:
	var first := _run_encounter(WORLD_SEED)
	var second := _run_encounter(WORLD_SEED)
	assert_eq(str(first), str(second),
		"two runs on one seed produce an identical state/position trace")
	var other := _run_encounter(WORLD_SEED + 7)
	assert_ne(str(other), str(first), "a different seed produces a different trace")


## Run a fixed encounter and return a trace of (state, rounded position) per step.
func _run_encounter(world_seed: int) -> Array:
	var runtime: CombatRuntime = CombatRuntimeScript.new()
	add_to_tree(runtime)
	runtime.start_session(RngServiceScript.new(world_seed))
	runtime.spawn_from_table(_table(Vector2(400, 300)), runtime)
	var enemy := runtime.enemies()[0]
	var trace: Array = []
	for _i in 30:
		runtime.tick_enemies(STEP)
		trace.append("%s@%d,%d" % [
			enemy.ai_state_name(), int(enemy.global_position.x),
			int(enemy.global_position.y)])
	free_node(runtime)
	return trace


## Every `AttackComponent` under `node`. The tests drive these on the same clock as the AI,
## because the headless runner does not run `_physics_process` the way a game does (L-016) —
## so a swing requested by the brain only lands if the test advances the lifecycle too.
func _attack_components(node: Node) -> Array[AttackComponent]:
	var out: Array[AttackComponent] = []
	for child in node.get_children():
		var component := child as AttackComponent
		if component != null:
			out.append(component)
	return out

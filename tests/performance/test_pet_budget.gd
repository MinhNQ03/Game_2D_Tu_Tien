extends TestCase
## Performance budget for the companion (Phase 16).
##
## The claims, each one a number a test can hold to account:
##   1. **The pet runs no frame callback of its own.** Its brain is ticked by the ONE combat
##      session callback that ticks every enemy.
##   2. **Target choice is on a cadence, not per frame**: `ALLY_RETARGET_SECONDS`, so the count
##      of retarget passes over a span is ~`span / cadence`, never ~`frames`.
##   3. **A retarget pass is linear in the hostiles** (one scan of the spawn-ordered array per
##      ally): 10x the wolves may cost ~10x, not ~100x.
##
## The ceilings are generous on purpose (shared CI hardware); the measured figures are printed
## so `docs/PERFORMANCE.md` quotes a real run.

const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const SpawnTableScript := preload("res://src/data/enemies/enemy_spawn_table_data.gd")
const PetScene := preload("res://src/gameplay/entities/pet.tscn")

const ENEMY_PATH := "res://data/enemies/enemy_mist_wolf.tres"
const PET_PATH := "res://data/pets/pet_hoang_khuyen.tres"
const WORLD_SEED := 20261010

const SMALL_CAST := 4
const LARGE_CAST := 40
const FRAMES := 1800
const FRAME_DELTA := 1.0 / 60.0
const CEILING_MSEC := 6000
const MAX_SCALING := 13.0


class Owner extends Node2D:
	func is_dead() -> bool:
		return false


class Rig extends RefCounted:
	var runtime: CombatRuntime
	var owner_body: Node2D
	var pet: Pet


func _rig(rows: int) -> Rig:
	var rig := Rig.new()
	rig.runtime = CombatRuntimeScript.new()
	add_to_tree(rig.runtime)
	rig.runtime.start_session(RngServiceScript.new(WORLD_SEED))
	var table: EnemySpawnTableData = SpawnTableScript.new()
	table.map_id = &"map_field"
	var data := load(ENEMY_PATH) as EnemyData
	var enemies: Array[EnemyData] = []
	var positions := PackedVector2Array()
	for i in rows:
		enemies.append(data)
		# Far from the owner: the measurement is of FOLLOW + RETARGET SCANS over a full cast,
		# not of a fight that would thin the cast out part-way through.
		positions.append(Vector2(2000 + (i % 8) * 90, 2000 + int(i / 8.0) * 90))
	table.enemies = enemies
	table.positions = positions
	rig.runtime.spawn_from_table(table, rig.runtime)
	rig.owner_body = Owner.new()
	add_to_tree(rig.owner_body)
	var pet_data := load(PET_PATH) as PetData
	rig.pet = PetScene.instantiate() as Pet
	rig.pet.setup(pet_data, &"pet_perf#1", pet_data.stats_at(1))
	add_to_tree(rig.pet)
	rig.runtime.arm_attacker(rig.pet, pet_data.attack, &"pet_perf#1", CombatRuntime.TEAM_PLAYER)
	rig.runtime.arm_ally(rig.pet, pet_data.ai_profile, pet_data.engage_distance,
		pet_data.stats.move_speed, rig.owner_body)
	return rig


func _free(rig: Rig) -> void:
	rig.runtime.end_session()
	free_node(rig.pet)
	free_node(rig.owner_body)
	free_node(rig.runtime)


func _measure(rows: int) -> float:
	var rig := _rig(rows)
	var started := Time.get_ticks_usec()
	for i in FRAMES:
		# The owner keeps walking, so the companion really follows for the whole span.
		rig.owner_body.global_position.x += 2.0
		rig.runtime.tick_allies(FRAME_DELTA)
	var msec := float(Time.get_ticks_usec() - started) / 1000.0
	_free(rig)
	return msec


func test_the_pet_runs_no_frame_callback_of_its_own() -> void:
	var rig := _rig(SMALL_CAST)
	assert_false(rig.pet.is_physics_processing(), "the pet body has no physics callback")
	assert_false(rig.pet.is_processing(), "nor an idle one")
	assert_false(rig.pet.ai().is_physics_processing(), "nor does its AIComponent")
	assert_true(rig.runtime.is_physics_processing(), "the one session callback drives it")
	assert_eq(rig.runtime.ally_count(), 1, "one ally is ticked")
	rig.runtime.despawn_enemies()
	assert_true(rig.runtime.is_physics_processing(),
		"with no enemy left the session still ticks: a companion follows outside a fight")
	rig.runtime.remove_ally(rig.pet.ai())
	assert_false(rig.runtime.is_physics_processing(),
		"and with neither enemy nor ally it stops entirely")
	_free(rig)


func test_targets_are_chosen_on_a_cadence_not_per_frame() -> void:
	var rig := _rig(SMALL_CAST)
	for i in FRAMES:
		rig.runtime.tick_allies(FRAME_DELTA)
	var passes := rig.runtime.retarget_passes()
	var expected := int((FRAMES * FRAME_DELTA) / CombatRuntime.ALLY_RETARGET_SECONDS)
	var decisions := rig.pet.ai().decisions()
	var interval: float = rig.pet.data().ai_profile.decision_interval
	var expected_decisions := int((FRAMES * FRAME_DELTA) / interval)
	print("[perf][pet] %d retarget passes and %d decisions over %d frames (expected ~%d / ~%d)"
		% [passes, decisions, FRAMES, expected, expected_decisions])
	assert_true(absi(passes - expected) <= 2,
		"%d passes over %.0fs at a %.2fs cadence must be ~%d, not ~%d frames"
			% [passes, FRAMES * FRAME_DELTA, CombatRuntime.ALLY_RETARGET_SECONDS, expected,
				FRAMES])
	assert_true(absi(decisions - expected_decisions) <= 2,
		"and its brain decides on its profile's interval (%d vs ~%d)"
			% [decisions, expected_decisions])
	_free(rig)


func test_the_companion_tick_is_linear_in_the_hostiles() -> void:
	var small_msec := _measure(SMALL_CAST)
	var large_msec := _measure(LARGE_CAST)
	print("[perf][pet] %d frames, 1 pet | %d hostiles: %.2f ms | %d hostiles: %.2f ms" % [
		FRAMES, SMALL_CAST, small_msec, LARGE_CAST, large_msec])
	assert_true(large_msec < float(CEILING_MSEC),
		"%d frames with a pet and %d hostiles stay under the ceiling (%.2f ms)"
			% [FRAMES, LARGE_CAST, large_msec])
	var scaling := large_msec / maxf(small_msec, 0.5)
	print("[perf][pet] scaling factor for 10x the hostiles: %.2fx" % scaling)
	assert_true(scaling < MAX_SCALING,
		"10x the hostiles must stay linear (got %.2fx, limit %.2fx)" % [scaling, MAX_SCALING])
	var usec_per_frame := (large_msec * 1000.0) / float(FRAMES)
	print("[perf][pet] %.3f us per frame for the companion among %d hostiles"
		% [usec_per_frame, LARGE_CAST])
	assert_true(usec_per_frame < 200.0,
		"the companion is cheap per frame (got %.3f us)" % usec_per_frame)

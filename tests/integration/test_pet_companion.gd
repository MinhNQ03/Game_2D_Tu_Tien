extends TestCase
## Integration tests for the Phase-16 companion: `PetRuntime` + a REAL `CombatRuntime` session
## (real service, registry, seeded RNG, real wolves) + the real `Pet` scene.
##
## The world is a stand-in (`FakeWorld`): the three things `PetRuntime` asks a world for — the
## active map, the player, and the two map signals. Everything the pet itself does is real.
## No live `/root` singleton is touched (D-019) and every node is freed by its test (L-019).

const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const PetRuntimeScript := preload("res://src/gameplay/world/pet_runtime.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const SpawnTableScript := preload("res://src/data/enemies/enemy_spawn_table_data.gd")
const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")
const AttackComponentScript := preload("res://src/gameplay/components/attack_component.gd")
const PetCatalogScript := preload("res://src/data/pets/pet_catalog_data.gd")
const PetEncounterScript := preload("res://src/gameplay/pets/pet_encounter.gd")

const ENEMY_PATH := "res://data/enemies/enemy_mist_wolf.tres"
const CATALOG_PATH := "res://data/pets/pet_catalog.tres"
const HOUND := &"pet_hoang_khuyen"
const WORLD_SEED := 20261010
const FRAME := 1.0 / 60.0


class FakeWorld extends Node:
	signal active_map_leaving()
	signal active_map_ready()
	var map: Node2D = null
	var player: Node2D = null

	func get_active_map() -> Node:
		return map

	func get_player() -> Node:
		return player


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


## Everything one test needs, built and torn down together.
class Rig extends RefCounted:
	var world: FakeWorld
	var combat: CombatRuntime
	var pets: PetRuntime
	var player: TestPlayer


func _map(with_encounter: bool = false) -> Node2D:
	var map := Node2D.new()
	map.name = "TestMap"
	var host := Node2D.new()
	host.name = "PlayerHost"
	map.add_child(host)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	map.add_child(enemies)
	var interactables := Node2D.new()
	interactables.name = "Interactables"
	map.add_child(interactables)
	if with_encounter:
		var stray: PetEncounter = PetEncounterScript.new()
		stray.name = "Stray"
		stray.pet = (load(CATALOG_PATH) as PetCatalogData).entry(HOUND)
		interactables.add_child(stray)
	return map


func _rig(catalog: PetCatalogData = null, with_encounter: bool = false) -> Rig:
	var rig := Rig.new()
	rig.world = FakeWorld.new()
	rig.world.name = "FakeWorld"
	add_to_tree(rig.world)
	rig.world.map = _map(with_encounter)
	rig.world.add_child(rig.world.map)
	rig.player = TestPlayer.new()
	rig.player.name = "Player"
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"player"
	hurtbox.radius = 10.0
	rig.player.add_child(hurtbox)
	rig.world.map.get_node("PlayerHost").add_child(rig.player)
	rig.player.global_position = Vector2(400, 300)
	rig.world.player = rig.player
	rig.combat = CombatRuntimeScript.new()
	add_to_tree(rig.combat)
	rig.combat.start_session(RngServiceScript.new(WORLD_SEED))
	rig.combat.register_target(rig.player, CombatRuntime.TEAM_PLAYER)
	rig.pets = PetRuntimeScript.new()
	add_to_tree(rig.pets)
	assert_true(rig.pets.start_session(rig.world, rig.combat, catalog), "the pet session starts")
	return rig


func _free(rig: Rig) -> void:
	rig.pets.end_session()
	rig.combat.end_session()
	free_node(rig.pets)
	free_node(rig.combat)
	free_node(rig.world)


func _wolves(rig: Rig, positions: Array[Vector2]) -> void:
	var table: EnemySpawnTableData = SpawnTableScript.new()
	table.map_id = &"map_field"
	var data := load(ENEMY_PATH) as EnemyData
	var enemies: Array[EnemyData] = []
	var points := PackedVector2Array()
	for position in positions:
		enemies.append(data)
		points.append(position)
	table.enemies = enemies
	table.positions = points
	rig.combat.spawn_from_table(table, rig.world.map.get_node("Enemies"))


## One simulated frame of everything the game's physics tick would drive.
func _step(rig: Rig, frames: int = 1) -> void:
	for i in frames:
		rig.combat.tick_enemies(FRAME)
		rig.combat.tick_allies(FRAME)
		rig.pets.tick(FRAME)
		var pet := rig.pets.active_pet()
		if pet != null:
			(pet.get_node("AttackComponent") as AttackComponent).advance(FRAME)


func _bodies(rig: Rig) -> int:
	var count := 0
	for child in rig.world.map.get_node("PlayerHost").get_children():
		if child is Pet and not child.is_queued_for_deletion():
			count += 1
	return count


# === Ownership and summoning ================================================

func test_with_no_pet_the_summon_key_is_refused_and_nothing_spawns() -> void:
	var rig := _rig()
	var refusals: Array[StringName] = []
	rig.pets.pet_refused.connect(func(key: StringName) -> void: refusals.append(key))
	assert_eq(rig.pets.summon(), PetRuntime.REFUSE_NONE_OWNED, "there is no pet to call")
	assert_eq(refusals, [PetRuntime.REFUSE_NONE_OWNED] as Array[StringName], "the refusal is said")
	assert_eq(_bodies(rig), 0, "and no body appeared")
	assert_eq(rig.combat.ally_count(), 0, "nor an ally")
	assert_false(rig.pets.build_view().available, "the HUD view shows nothing about pets")
	_free(rig)


func test_befriending_a_stray_owns_it_once_and_hides_the_encounter() -> void:
	var rig := _rig(null, true)
	var stray := rig.world.map.get_node("Interactables/Stray") as PetEncounter
	assert_true(stray.is_available(), "the stray is offered")
	assert_eq(rig.pets.befriend(stray.interaction_id()), &"", "befriending succeeds")
	assert_true(rig.pets.get_service().store().owns(HOUND), "the pet is owned")
	assert_eq(rig.pets.get_service().store().active_id(), HOUND, "and active")
	assert_true(rig.pets.is_out(), "it walks with the player from that moment")
	assert_false(stray.is_available(), "the stray is no longer offered")
	assert_eq(rig.pets.befriend(HOUND), PetService.REFUSE_ALREADY_OWNED,
		"befriending it again is refused")
	assert_eq(rig.pets.get_service().store().owned_count(), 1, "and never duplicates it")
	assert_eq(_bodies(rig), 1, "one body")
	assert_eq(rig.pets.befriend(&"pet_nobody"), PetService.REFUSE_UNKNOWN_PET,
		"an unknown creature is refused")
	_free(rig)


func test_summon_and_dismiss_are_idempotent() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var armed_with_pet := rig.combat.armed_count()
	for i in 3:
		assert_eq(rig.pets.summon(), &"", "summon %d succeeds" % i)
	assert_eq(_bodies(rig), 1, "three summons made ONE body")
	assert_eq(rig.combat.ally_count(), 1, "one ally")
	assert_eq(rig.combat.armed_count(), armed_with_pet, "one armed attacker")
	var pet := rig.pets.active_pet()
	assert_true(pet.global_position.distance_to(rig.player.global_position) < 48.0,
		"it appears beside the player (%.1f px)"
			% pet.global_position.distance_to(rig.player.global_position))
	var view := rig.pets.build_view()
	assert_true(view.available and view.out, "the view says it is out")
	assert_eq(view.level, 1, "at its derived first level")
	for i in 3:
		assert_eq(rig.pets.dismiss(), &"", "dismiss %d succeeds" % i)
	assert_eq(_bodies(rig), 0, "the body is gone")
	assert_eq(rig.combat.ally_count(), 0, "the ally entry is gone")
	assert_eq(rig.combat.armed_count(), armed_with_pet - 1, "and so is its attacker entry")
	assert_false(rig.pets.build_view().out, "the view says it is away")
	assert_eq(rig.pets.toggle(), &"", "the key calls it again")
	assert_true(rig.pets.is_out(), "and it is out")
	rig.pets.toggle()
	assert_false(rig.pets.is_out(), "and the key sends it away")
	await scene_tree.process_frame
	_free(rig)


# === Following ==============================================================

func test_it_follows_gradually_and_never_teleports() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var pet := rig.pets.active_pet()
	var speed := pet.get_move_speed()
	# The player is suddenly far away (a dash, a knockback, a long stride).
	rig.player.global_position += Vector2(260, 0)
	var start_gap := pet.global_position.distance_to(rig.player.global_position)
	var worst_step := 0.0
	var previous := pet.global_position
	for i in 240:
		_step(rig)
		worst_step = maxf(worst_step, pet.global_position.distance_to(previous))
		previous = pet.global_position
	var end_gap := pet.global_position.distance_to(rig.player.global_position)
	assert_true(worst_step <= speed * FRAME * 1.05 + 0.01,
		"no frame moved it further than its speed allows (worst %.2f px, limit %.2f)"
			% [worst_step, speed * FRAME * 1.05])
	assert_true(end_gap < start_gap * 0.25,
		"and it closed the gap by walking (%.1f -> %.1f px)" % [start_gap, end_gap])
	assert_true(end_gap <= pet.data().ai_profile.follow_radius + 2.0,
		"to within its follow radius (%.1f px)" % end_gap)
	# Beside a standing owner it idles and ambles (its authored patrol), but never drifts off:
	# five seconds on, it is still inside the radius that would send it back.
	var widest := 0.0
	var fastest := 0.0
	previous = pet.global_position
	for i in 300:
		_step(rig)
		widest = maxf(widest, pet.global_position.distance_to(rig.player.global_position))
		fastest = maxf(fastest, pet.global_position.distance_to(previous))
		previous = pet.global_position
	var profile := pet.data().ai_profile
	assert_true(widest <= profile.follow_radius + speed * profile.decision_interval,
		"beside a standing owner it stays close (widest %.1f px)" % widest)
	assert_true(fastest <= speed * profile.patrol_speed_scale * FRAME * 1.05 + 0.01
			or fastest <= speed * FRAME * 1.05 + 0.01,
		"and only ever ambles or walks (fastest step %.2f px)" % fastest)
	_free(rig)


# === Fighting ===============================================================

func test_it_targets_only_a_living_hostile_and_drops_a_dead_one() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var pet := rig.pets.active_pet()
	_step(rig, 30)
	assert_null(pet.ai().target(), "with no hostile about it has no target (never the player)")
	_wolves(rig, [rig.player.global_position + Vector2(70, 0),
		rig.player.global_position + Vector2(900, 0)])
	_step(rig, 20)
	var near := rig.combat.enemies()[0]
	assert_eq(pet.ai().target(), near, "it takes the hostile near its owner")
	assert_ne(pet.ai().target(), rig.combat.enemies()[1],
		"never the one far outside its owner's ground")
	near.take_damage(9999)
	assert_true(near.is_dead(), "the wolf is dead")
	_step(rig, 20)
	assert_null(pet.ai().target(), "a corpse is not a target")
	_free(rig)


func test_a_kill_pays_the_enemy_reward_once_and_the_pet_its_share_once() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var pet := rig.pets.active_pet()
	_wolves(rig, [rig.player.global_position + Vector2(60, 0)])
	var wolf := rig.combat.enemies()[0]
	var defeats: Array = []
	rig.combat.enemy_defeated.connect(func(reward_id: StringName, xp: int) -> void:
		defeats.append([reward_id, xp]))
	var player_hp := rig.player.hp
	var frames := 0
	while not wolf.is_dead() and frames < 60 * 40:
		_step(rig)
		frames += 1
	assert_true(wolf.is_dead(), "the pet killed the wolf through real swings (%d frames)" % frames)
	assert_true((pet.get_node("AttackComponent") as AttackComponent).swings_resolved() > 0,
		"its hits were resolved by the session's CombatService")
	assert_eq(rig.player.hp, player_hp, "its swings never touched its owner (same team)")
	assert_eq(defeats.size(), 1, "combat announced the defeat exactly once")
	var share := int(floor(float(defeats[0][1]) * pet.data().xp_share_percent / 100.0))
	var store := rig.pets.get_service().store()
	assert_eq(store.xp_of(HOUND), share, "the pet earned its authored share (%d)" % share)
	# The same reward id announced again (a replay, a duplicate signal) pays nothing more.
	rig.combat.enemy_defeated.emit(defeats[0][0], defeats[0][1])
	assert_eq(store.xp_of(HOUND), share, "one kill never pays the pet twice")
	# A kill while the pet is away pays it nothing.
	rig.pets.dismiss()
	rig.combat.enemy_defeated.emit(&"reward_other", 1000)
	assert_eq(store.xp_of(HOUND), share, "a pet that was not out earns nothing")
	await scene_tree.process_frame
	_free(rig)


func test_levelling_up_while_out_applies_the_derived_stats() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var pet := rig.pets.active_pet()
	var levels: Array[int] = []
	rig.pets.pet_level_changed.connect(func(_id: StringName, level: int) -> void:
		levels.append(level))
	var attack_before := pet.get_attack_power()
	var hp_before := pet.get_max_health()
	rig.combat.enemy_defeated.emit(&"reward_big", 60)     # 50% -> 30 XP = level 2
	assert_eq(levels, [2] as Array[int], "the level change is announced once")
	assert_eq(pet.get_attack_power(), attack_before + pet.data().growth.attack,
		"the body adopts the grown attack")
	assert_eq(pet.get_max_health(), hp_before + pet.data().growth.max_hp, "and maximum health")
	assert_eq(rig.pets.build_view().level, 2, "the view shows the derived level")
	_free(rig)


# === Cleanup ================================================================

func test_a_fallen_pet_withdraws_and_cannot_be_recalled_at_once() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var pet := rig.pets.active_pet()
	var reasons: Array[StringName] = []
	rig.pets.pet_dismissed.connect(func(_id: StringName, reason: StringName) -> void:
		reasons.append(reason))
	pet.take_damage(9999)
	assert_eq(reasons, [PetRuntime.REASON_FELL] as Array[StringName], "it fell, once")
	assert_false(rig.pets.is_out(), "its body is withdrawn")
	assert_eq(rig.combat.ally_count(), 0, "and no longer ticked")
	assert_true(rig.pets.get_service().store().owns(HOUND), "falling never loses the pet")
	assert_eq(rig.pets.summon(), PetRuntime.REFUSE_RECOVERING, "it cannot be called while hurt")
	assert_true(rig.pets.build_view().recovering, "the view says so")
	rig.pets.tick(pet.data().recall_seconds + 0.1)
	assert_eq(rig.pets.summon(), &"", "after the recall time it comes back")
	assert_eq(rig.pets.active_pet().get_current_health(), rig.pets.active_pet().get_max_health(),
		"whole again (health is runtime, not saved)")
	await scene_tree.process_frame
	_free(rig)


func test_a_map_change_frees_the_body_and_brings_it_back_on_arrival() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var old_body := rig.pets.active_pet()
	rig.world.active_map_leaving.emit()
	assert_false(rig.pets.is_out(), "the body does not outlive its map")
	assert_eq(rig.combat.ally_count(), 0, "nothing stale is ticked")
	# The world swaps maps: the player is carried over, the old scene freed.
	rig.world.map.get_node("PlayerHost").remove_child(rig.player)
	var old_map := rig.world.map
	rig.world.remove_child(old_map)
	old_map.free()
	assert_false(is_instance_valid(old_body), "the old body went with the old map")
	rig.world.map = _map()
	rig.world.add_child(rig.world.map)
	rig.world.map.get_node("PlayerHost").add_child(rig.player)
	rig.player.global_position = Vector2(120, 80)
	rig.world.active_map_ready.emit()
	assert_true(rig.pets.is_out(), "it is beside the player again in the new map")
	assert_eq(_bodies(rig), 1, "exactly one body")
	assert_true(rig.pets.active_pet().global_position.distance_to(Vector2(120, 80)) < 48.0,
		"spawned at the player's new place, not carried across")
	# A dismissed pet stays away across a map change.
	rig.pets.dismiss()
	rig.world.active_map_leaving.emit()
	rig.world.active_map_ready.emit()
	assert_false(rig.pets.is_out(), "a pet sent away is not re-summoned by a map change")
	await scene_tree.process_frame
	_free(rig)


func test_the_pet_withdraws_when_its_owner_falls() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	rig.player.hp = 0
	_step(rig)
	assert_false(rig.pets.is_out(), "it does not fight on beside a fallen owner")
	assert_eq(rig.pets.summon(), PetRuntime.REFUSE_OWNER_DOWN, "nor can it be called")
	assert_eq(rig.combat.ally_count(), 0, "nothing is left ticking")
	await scene_tree.process_frame
	_free(rig)


func test_ending_the_session_leaves_nothing_behind() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	var body := rig.pets.active_pet()
	var armed := rig.combat.armed_count()
	rig.pets.end_session()
	assert_false(rig.pets.is_session_active(), "the session is over")
	assert_eq(rig.combat.ally_count(), 0, "combat ticks no ally")
	assert_eq(rig.combat.armed_count(), armed - 1, "and holds no attacker entry for it")
	for connection in rig.combat.enemy_defeated.get_connections():
		assert_ne((connection["callable"] as Callable).get_object(), rig.pets,
			"the defeat subscription is dropped")
	assert_eq(rig.pets.summon(), PetRuntime.REFUSE_UNAVAILABLE, "nothing can be summoned after")
	rig.pets.end_session()                           # idempotent
	await scene_tree.process_frame
	assert_false(is_instance_valid(body), "the body was freed")
	_free(rig)


func test_a_session_refuses_to_start_without_its_dependencies() -> void:
	var pets: PetRuntime = PetRuntimeScript.new()
	add_to_tree(pets)
	assert_false(pets.start_session(null, null), "no world, no combat: no session")
	assert_false(pets.is_session_active(), "and nothing half-started")
	var broken: PetCatalogData = PetCatalogScript.new()
	var rig := _rig()
	assert_false(pets.start_session(rig.world, rig.combat, broken),
		"an invalid catalog refuses the session")
	assert_false(pets.is_session_active(), "still nothing half-started")
	free_node(pets)
	_free(rig)


# === Persistence boundary ===================================================

func test_the_runtime_round_trips_its_store_and_rejects_bad_payloads_atomically() -> void:
	var rig := _rig()
	rig.pets.befriend(HOUND)
	rig.combat.enemy_defeated.emit(&"reward_a", 20)
	var saved := rig.pets.to_dict()
	assert_false(rig.pets.from_dict({"schema": 1, "owned": [{"pet_id": "pet_nobody", "xp": 1}],
		"active_pet": ""}), "a bad payload is refused")
	assert_eq(rig.pets.to_dict(), saved, "and changed nothing")
	assert_true(rig.pets.is_out(), "nor sent the pet away")
	var other := _rig()
	assert_true(other.pets.from_dict(saved), "a fresh session accepts the payload")
	assert_eq(other.pets.to_dict(), saved, "and holds the same state")
	assert_false(other.pets.is_out(), "being out is runtime: it is not restored as out")
	assert_eq(other.pets.summon(), &"", "but the restored pet can be called")
	await scene_tree.process_frame
	_free(other)
	_free(rig)


# === A second pet is content ================================================

func test_a_second_pet_works_through_the_same_code() -> void:
	var shipped := (load(CATALOG_PATH) as PetCatalogData).entry(HOUND)
	var crane := shipped.duplicate() as PetData
	crane.id = &"pet_test_crane"
	crane.name_key = &"PET_TEST_CRANE_NAME"
	crane.stats = shipped.stats.duplicate() as StatBlock
	crane.stats.attack = 15
	crane.xp_share_percent = 100
	var catalog: PetCatalogData = PetCatalogScript.new()
	var entries: Array[PetData] = [shipped, crane]
	catalog.entries = entries
	var rig := _rig(catalog)
	assert_eq(rig.pets.befriend(&"pet_test_crane"), &"", "the second pet is befriended")
	var body := rig.pets.active_pet()
	assert_eq(body.data().id, &"pet_test_crane", "its own definition drives the body")
	assert_eq(body.get_attack_power(), 15, "with its own stats")
	rig.combat.enemy_defeated.emit(&"reward_c", 10)
	assert_eq(rig.pets.get_service().store().xp_of(&"pet_test_crane"), 10,
		"and its own XP share (100%)")
	assert_eq(rig.pets.build_view().name_key, &"PET_TEST_CRANE_NAME", "and its own name")
	_free(rig)

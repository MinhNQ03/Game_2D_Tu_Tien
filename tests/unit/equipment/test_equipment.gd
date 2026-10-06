extends TestCase
## Phase 14 — equipment. Exit (`ROADMAP.md`): equipment changes damage deterministically, through
## the damage formula; covered by tests. Plus: equipping MOVES an item between satchel and slot,
## a weapon brings its own attack, the realm gate reads `CultivationService.meets`, and nothing
## changes in the middle of a swing.

const CATALOG := "res://data/items/item_catalog.tres"
const KnowledgeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")
const CultivationScript := preload("res://src/gameplay/world/cultivation_runtime.gd")
const InventoryScript := preload("res://src/gameplay/world/inventory_runtime.gd")
const EquipmentScript := preload("res://src/gameplay/world/equipment_runtime.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")


class StubPlayer extends Node2D:
	var applied: Array = []

	func apply_equipment(attack_bonus: int, defense_bonus: int, attack: AttackData,
			body_visual: CharacterVisualProfileData) -> bool:
		applied.append([attack_bonus, defense_bonus, attack.id if attack != null else &"",
			body_visual.id if body_visual != null else &""])
		return true


class StubWorld extends Node:
	var player: Node = null

	func get_active_map() -> Node:
		return null

	func get_player() -> Node:
		return player


func test_shipped_equipment_is_valid_and_canon() -> void:
	var catalog: ItemCatalogData = load(CATALOG)
	assert_true(catalog.is_valid(), "catalog: %s" % str(catalog.validation_errors()))
	var sword := catalog.entry(&"item_kiem_thanh_thiet").equipment as EquipmentData
	assert_true(sword.is_valid(), "the jian validates")
	assert_eq(sword.attack.weapon_family, &"weapon_kiem", "a canon Kiếm (CL-10)")
	var bad: AttackData = sword.attack.duplicate()
	bad.weapon_family = &"weapon_quat"
	assert_false(bad.is_valid(), "a fan is not a canon weapon family")


## The bonus enters the EXISTING damage formula: the same hit with and without the sword differs
## deterministically, and only by what the formula makes of the bonus.
func test_equipment_changes_damage_deterministically() -> void:
	var stats := StatsComponent.new()
	var state := CharacterState.new()
	state.attack = 10
	state.defense = 2
	stats.bind_character_state(state)
	var bare := DamageRules.compute_hit(stats.get_attack(), 4, 1.0)
	stats.set_equipment_bonus(3, 4)
	var armed := DamageRules.compute_hit(stats.get_attack(), 4, 1.3)
	assert_eq(stats.get_attack(), 13, "attack 10 + the jian's 3")
	assert_eq(stats.get_defense(), 6, "defense 2 + the robe's 4")
	assert_true(armed > bare, "the armed hit is harder (%d vs %d)" % [armed, bare])
	assert_eq(DamageRules.compute_hit(stats.get_attack(), 4, 1.3), armed,
		"and the same inputs always give the same damage")
	assert_eq(state.attack, 10, "the body's base attack is untouched: a save never bakes it in")
	stats.free()


func test_a_weapon_swaps_the_attack_but_never_mid_swing() -> void:
	var component := AttackComponent.new()
	add_to_tree(component)
	var rng: RngService = RngServiceScript.new(3)
	component.arm(load("res://data/combat/attack_player_basic.tres"),
		CombatService.new(rng.stream(RngService.STREAM_COMBAT)), CombatHurtboxRegistry.new(), &"p")
	component.set_facing(Vector2.RIGHT)
	component.request_attack()
	assert_false(component.swap_attack(load("res://data/combat/attack_player_kiem.tres")),
		"refused while a swing is in flight")
	component.advance(2.0)
	assert_true(component.swap_attack(load("res://data/combat/attack_player_kiem.tres")),
		"accepted at rest")
	assert_eq(component.attack_data().id, &"attack_player_kiem", "the jian's thrust is armed")
	free_node(component)


func _session() -> Array:
	var world := StubWorld.new()
	var player := StubPlayer.new()
	world.player = player
	world.add_child(player)
	add_to_tree(world)
	var knowledge: KnowledgeRuntime = KnowledgeScript.new()
	add_to_tree(knowledge)
	knowledge.start_session()
	var state := CharacterState.new()
	state.instance_id = &"p"
	state.realm_id = &"realm_pham"
	var cultivation: CultivationRuntime = CultivationScript.new()
	add_to_tree(cultivation)
	cultivation.start_session(state, knowledge, world)
	var inventory: InventoryRuntime = InventoryScript.new()
	add_to_tree(inventory)
	inventory.start_session(state, world, knowledge, cultivation)
	var equipment: EquipmentRuntime = EquipmentScript.new()
	add_to_tree(equipment)
	assert_true(equipment.start_session(state, world, inventory, cultivation), "session")
	return [world, knowledge, cultivation, inventory, equipment, player]


func _end(parts: Array) -> void:
	for i in [4, 3, 2, 1]:
		parts[i].call("end_session")
	for i in [4, 3, 2, 1, 0]:
		free_node(parts[i])


func test_equipping_moves_items_and_tells_the_body_once() -> void:
	var parts := _session()
	var inventory: InventoryRuntime = parts[3]
	var equipment: EquipmentRuntime = parts[4]
	var player: StubPlayer = parts[5]
	inventory.give(&"item_kiem_thanh_thiet", 1)
	inventory.give(&"item_dao_bao_thanh_van", 1)
	assert_eq(equipment.equip(&"item_kiem_thanh_thiet"), &"", "the jian is wielded")
	assert_eq(inventory.count_of(&"item_kiem_thanh_thiet"), 0, "it left the satchel")
	assert_true(equipment.is_worn(&"item_kiem_thanh_thiet"), "and is worn")
	assert_eq(player.applied[-1], [3, 0, &"attack_player_kiem", &""],
		"the body gets +3 attack and the jian's thrust")
	assert_eq(equipment.equip(&"item_dao_bao_thanh_van"), &"", "the robe is put on")
	assert_eq(player.applied[-1], [3, 4, &"attack_player_kiem", &"vis_player_daobao"],
		"bonuses sum, and the body is drawn in the robe")
	assert_eq(equipment.unequip_item(&"item_kiem_thanh_thiet"), &"", "the jian comes off")
	assert_eq(inventory.count_of(&"item_kiem_thanh_thiet"), 1, "back into the satchel")
	assert_eq(player.applied[-1], [0, 4, &"attack_player_basic", &"vis_player_daobao"],
		"bare-handed again: the palm strike")
	var saved := equipment.to_dict()
	assert_eq(saved["slots"], {"1": "item_dao_bao_thanh_van"}, "slots persist as ids")
	assert_false(equipment.get_state().from_dict({"slots": {"0": "item_dao_bao_thanh_van"}},
		inventory.get_catalog()), "a robe in the weapon slot is refused")
	_end(parts)


func test_the_realm_gate_reads_cultivation() -> void:
	var parts := _session()
	var inventory: InventoryRuntime = parts[3]
	var equipment: EquipmentRuntime = parts[4]
	var gated: EquipmentData = (inventory.get_catalog().entry(&"item_kiem_thanh_thiet")
		.equipment as EquipmentData)
	var before := gated.required_realm
	gated.required_realm = &"realm_hau_thien"
	gated.required_layer = 1
	inventory.give(&"item_kiem_thanh_thiet", 1)
	assert_eq(equipment.equip(&"item_kiem_thanh_thiet"), EquipmentRuntime.REFUSE_REALM,
		"a mortal cannot wield a Hậu Thiên weapon")
	assert_eq(inventory.count_of(&"item_kiem_thanh_thiet"), 1, "and keeps it")
	gated.required_realm = before
	gated.required_layer = 0
	_end(parts)

extends TestCase
## Phase 13 — items and the bag. Exit (`ROADMAP.md`): add / use / drop via data; inventory ops
## unit-tested; serializes / restores. Plus the honesty rule: a use that does nothing burns
## nothing, and every effect goes through the system that owns it.

const CATALOG := "res://data/items/item_catalog.tres"
const KnowledgeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")
const CultivationScript := preload("res://src/gameplay/world/cultivation_runtime.gd")
const InventoryScript := preload("res://src/gameplay/world/inventory_runtime.gd")
const WorldItemScript := preload("res://src/gameplay/items/world_item.gd")


class StubPlayer extends Node2D:
	var hp := 60
	var max_hp := 100

	func heal(amount: int) -> int:
		var before := hp
		hp = mini(max_hp, hp + amount)
		return hp - before

	func get_current_health() -> int:
		return hp

	func get_max_health() -> int:
		return max_hp


class StubWorld extends Node:
	var map: Node = null
	var player: Node = null

	func get_active_map() -> Node:
		return map

	func get_player() -> Node:
		return player


func _item(id: StringName) -> ItemData:
	return (load(CATALOG) as ItemCatalogData).entry(id)


func test_the_catalog_is_valid() -> void:
	var catalog: ItemCatalogData = load(CATALOG)
	assert_true(catalog.is_valid(), "item catalog validates: %s" % str(catalog.validation_errors()))


func test_stacks_respect_their_maximum_and_the_bag_its_capacity() -> void:
	var bag := InventoryState.new()
	bag.capacity = 2
	var pill := _item(&"item_bo_huyet_dan")  # stack 10
	assert_eq(bag.add(pill, 14), 14, "14 pills fit in two stacks")
	assert_eq(bag.stack_count(), 2, "split 10 + 4")
	assert_eq(bag.add(pill, 10), 6, "only the room left in the second stack fits")
	assert_eq(bag.count_of(&"item_bo_huyet_dan"), 20, "20 held")
	assert_false(bag.remove(&"item_bo_huyet_dan", 21), "removing more than held is refused")
	assert_true(bag.remove(&"item_bo_huyet_dan", 15), "removing 15 works")
	assert_eq(bag.stack_count(), 1, "an emptied stack disappears")


func test_the_bag_round_trips_and_rejects_corrupt_saves() -> void:
	var bag := InventoryState.new()
	bag.add(_item(&"item_linh_thach"), 7)
	bag.add(_item(&"item_bo_huyet_dan"), 2)
	var restored := InventoryState.new()
	assert_true(restored.from_dict(bag.to_dict(), load(CATALOG)), "round trip")
	assert_eq(restored.count_of(&"item_linh_thach"), 7, "stones restored")
	assert_eq(restored.item_ids(), bag.item_ids(), "order restored")
	assert_false(restored.from_dict({"items": [{"item_id": "item_fake", "count": 1}]},
		load(CATALOG)), "an unknown item is refused")
	assert_false(restored.from_dict({"items": [{"item_id": "item_bo_huyet_dan", "count": 99}]},
		load(CATALOG)), "a stack over its maximum is refused")
	assert_false(restored.from_dict({"items": [{"item_id": "item_bo_huyet_dan", "count": 1.0}]},
		load(CATALOG)), "a float count is refused (L-024)")
	assert_eq(restored.count_of(&"item_linh_thach"), 7, "and the bag was left as it was")


func _session() -> Array:
	var world := StubWorld.new()
	var map := Node2D.new()
	var pickups := Node2D.new()
	pickups.name = "Pickups"
	map.add_child(pickups)
	var player := StubPlayer.new()
	map.add_child(player)
	world.map = map
	world.player = player
	world.add_child(map)
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
	assert_true(inventory.start_session(state, world, knowledge, cultivation), "inventory session")
	return [world, knowledge, cultivation, inventory, state, player, pickups]


func _end(parts: Array) -> void:
	(parts[3] as InventoryRuntime).end_session()
	(parts[2] as CultivationRuntime).end_session()
	(parts[1] as KnowledgeRuntime).end_session()
	for i in [3, 2, 1, 0]:
		free_node(parts[i])


func test_a_pickup_is_collected_once_for_the_whole_run() -> void:
	var parts := _session()
	var inventory: InventoryRuntime = parts[3]
	var player: StubPlayer = parts[5]
	var pickup: WorldItem = WorldItemScript.new()
	pickup.item = _item(&"item_linh_thach")
	pickup.count = 3
	pickup.pickup_id = &"pickup_test"
	pickup.position = Vector2(200, 0)
	(parts[6] as Node).add_child(pickup)
	inventory.tick()
	assert_eq(inventory.count_of(&"item_linh_thach"), 0, "out of reach: nothing")
	player.position = Vector2(205, 0)
	inventory.tick()
	inventory.tick()
	assert_eq(inventory.count_of(&"item_linh_thach"), 3, "walked onto it: collected ONCE")
	assert_false(pickup.visible, "it is gone from the world")
	assert_true(inventory.is_collected(&"pickup_test"), "and remembered by id")
	var saved := inventory.to_dict()
	assert_eq(saved["collected"], ["pickup_test"], "the collected ids persist with the bag")
	_end(parts)


func test_uses_go_through_their_owners_and_a_wasted_use_burns_nothing() -> void:
	var parts := _session()
	var knowledge: KnowledgeRuntime = parts[1]
	var inventory: InventoryRuntime = parts[3]
	var state: CharacterState = parts[4]
	var player: StubPlayer = parts[5]
	inventory.give(&"item_bo_huyet_dan", 2)
	inventory.give(&"item_linh_thach", 2)
	inventory.give(&"item_manual_phong", 1)
	assert_eq(inventory.use(&"item_bo_huyet_dan"), &"", "a pill heals the hurt body")
	assert_eq(player.hp, 95, "through the body's own heal")
	player.hp = player.max_hp
	assert_eq(inventory.use(&"item_bo_huyet_dan"), InventoryRuntime.REFUSE_FULL_HEALTH,
		"at full health it is refused")
	assert_eq(inventory.count_of(&"item_bo_huyet_dan"), 1, "and NOT consumed")
	assert_eq(inventory.use(&"item_linh_thach"), InventoryRuntime.REFUSE_NO_METHOD,
		"a stone without the method is refused")
	knowledge.grant(&"know_dan_khi_quyet", &"t")
	assert_eq(inventory.use(&"item_linh_thach"), &"", "with the method it is absorbed")
	assert_eq(state.cultivation_progress, 7, "12 tu vi x 0.6 mortal efficiency, via the service")
	assert_eq(inventory.use(&"item_manual_phong"), &"", "reading the manual teaches")
	assert_true(knowledge.get_service().knows(&"know_thanh_phong_chuong"),
		"through the Knowledge Core")
	assert_eq(inventory.count_of(&"item_manual_phong"), 0, "a read manual is consumed")
	inventory.give(&"item_manual_phong", 1)
	assert_eq(inventory.use(&"item_manual_phong"), InventoryRuntime.REFUSE_ALREADY_KNOWN,
		"a second copy teaches nothing")
	assert_eq(inventory.count_of(&"item_manual_phong"), 1, "and is kept")
	_end(parts)

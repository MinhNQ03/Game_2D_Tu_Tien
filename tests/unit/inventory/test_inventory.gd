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


func _pickup(parts: Array, id: StringName, item_id: StringName, count: int,
		at: Vector2) -> WorldItem:
	var pickup: WorldItem = WorldItemScript.new()
	pickup.item = _item(item_id)
	pickup.count = count
	pickup.pickup_id = id
	pickup.position = at
	(parts[6] as Node).add_child(pickup)
	return pickup


## A pickup is taken WHOLE or left WHOLE (D-073 follow-up, FG-3). It used to be marked
## collected as soon as ANY of it fit: five pills onto a bag with room for two put two in the
## bag and destroyed three, with the pickup gone for the rest of the run.
func test_a_pickup_that_does_not_all_fit_stays_whole_in_the_world() -> void:
	var parts := _session()
	var inventory: InventoryRuntime = parts[3]
	var player: StubPlayer = parts[5]
	inventory.get_bag().capacity = 1
	assert_eq(inventory.give(&"item_bo_huyet_dan", 8), 8, "eight pills: one stack of ten")
	var pickup := _pickup(parts, &"pickup_five", &"item_bo_huyet_dan", 5, Vector2(200, 0))
	player.position = Vector2(202, 0)
	inventory.tick()
	assert_eq(inventory.count_of(&"item_bo_huyet_dan"), 8, "room for two of five: none taken")
	assert_true(pickup.visible, "the five are still lying there")
	assert_false(inventory.is_collected(&"pickup_five"), "and not remembered as collected")
	# Make room and it is taken, all of it, on the same visit.
	assert_true(inventory.take(&"item_bo_huyet_dan", 3), "three pills leave the bag")
	inventory.tick()
	assert_eq(inventory.count_of(&"item_bo_huyet_dan"), 10, "now all five fit: all five taken")
	assert_false(pickup.visible, "and it is gone from the world")
	assert_true(inventory.is_collected(&"pickup_five"), "collected once")
	_end(parts)


## A full bag is SAID once per approach. `give()` reported "bag full" on every physics tick
## the player stood there: sixty refusals a second into the HUD's answer lane.
func test_a_full_bag_is_said_once_per_approach_not_every_tick() -> void:
	var parts := _session()
	var inventory: InventoryRuntime = parts[3]
	var player: StubPlayer = parts[5]
	inventory.get_bag().capacity = 1
	inventory.give(&"item_kiem_thanh_thiet", 1)
	var said: Array[StringName] = []
	var on_refused := func(_item_id: StringName, reason: StringName) -> void:
		said.append(reason)
	inventory.use_refused.connect(on_refused)
	var pickup := _pickup(parts, &"pickup_stone", &"item_linh_thach", 1, Vector2(200, 0))
	player.position = Vector2(202, 0)
	for _i in 30:
		inventory.tick()
	assert_eq(said, [InventoryRuntime.REFUSE_BAG_FULL] as Array[StringName],
		"thirty ticks standing on it: said once (got %d)" % said.size())
	assert_true(pickup.visible, "and it waits")
	player.position = Vector2(400, 0)
	inventory.tick()
	player.position = Vector2(202, 0)
	for _i in 30:
		inventory.tick()
	assert_eq(said.size(), 2, "walking away and back is a new approach: said again, once")
	inventory.use_refused.disconnect(on_refused)
	_end(parts)


## TWO things that are somebody's, both underfoot — the outpost's coat and primer lie 12.8 px
## apart with a 14 px reach each, so one step stands on both. The "said once per approach"
## memory held ONE id, so each tick the first of the pair looked new and was said again.
func test_two_held_things_underfoot_are_each_said_once() -> void:
	var parts := _session()
	var inventory: InventoryRuntime = parts[3]
	var player: StubPlayer = parts[5]
	inventory.set_pickup_gate(func(_flag: StringName) -> bool: return false)
	# Strings: a StringName array sorts by identity, not by spelling (seen flip in the suite).
	var said: Array[String] = []
	var on_withheld := func(pickup_id: StringName, _reason: StringName) -> void:
		said.append(String(pickup_id))
	inventory.pickup_withheld.connect(on_withheld)
	for entry: Array in [[&"pickup_primer", Vector2(520, 276)], [&"pickup_coat",
			Vector2(530, 268)]]:
		var pickup := _pickup(parts, entry[0], &"item_manual_phong", 1, entry[1])
		pickup.held_by_flag = &"flag_outpost_issue"
		pickup.held_reason_key = &"UI_PICKUP_HELD_OUTPOST"
	player.position = Vector2(525, 272)
	for _i in 30:
		inventory.tick()
	said.sort()
	assert_eq(said, ["pickup_coat", "pickup_primer"] as Array[String],
		"thirty ticks on both: each said once (got %d)" % said.size())
	inventory.pickup_withheld.disconnect(on_withheld)
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

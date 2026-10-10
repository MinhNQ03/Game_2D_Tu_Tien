extends TestCase
## Integration tests for Phase 17: `NpcRuntime` with a REAL `InventoryRuntime`, a REAL
## `RelationshipRuntime` (the shipped dimension config), a REAL `CharacterRegistry`, the real
## `WorldNpc` body and the shipped shop catalog. The world is a stand-in (`StubWorld`): the
## five things `NpcRuntime` asks a world for. No live `/root` singleton is driven (D-019) and
## every node is freed by its test (L-019).

const KnowledgeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")
const CultivationScript := preload("res://src/gameplay/world/cultivation_runtime.gd")
const InventoryScript := preload("res://src/gameplay/world/inventory_runtime.gd")
const RelationshipScript := preload("res://src/gameplay/world/relationship_runtime.gd")
const NpcRuntimeScript := preload("res://src/gameplay/world/npc_runtime.gd")
const WorldNpcScript := preload("res://src/gameplay/npcs/world_npc.gd")
const RegistryScript := preload("res://src/domain/character/character_registry.gd")
const ShopCatalogScript := preload("res://src/data/shops/shop_catalog_data.gd")
const ShopDataScript := preload("res://src/data/shops/shop_data.gd")
const ShopEntryScript := preload("res://src/data/shops/shop_entry_data.gd")

const KO_TEMPLATE := "res://data/characters/npc_scout_ko.tres"
const SHEN_TEMPLATE := "res://data/characters/npc_elder_shen.tres"
const LIN_TEMPLATE := "res://data/characters/npc_disciple_lin.tres"
const SHIPPED := "res://data/shops/shop_catalog.tres"
const KO := &"actor_scout_ko"
const SHEN := &"actor_elder_shen"
const LIN := &"actor_disciple_lin"
const SHOP := &"shop_ko_than_packs"
const PILL := &"item_bo_huyet_dan"
const SWORD := &"item_kiem_thanh_thiet"
const COIN := &"item_linh_thach"
const PLAYER := &"player"


class StubWorld extends Node:
	signal active_map_leaving()
	signal active_map_ready()
	var map: Node2D = null
	var player: Node2D = null
	var character: CharacterState = null
	var registry: CharacterRegistry = null

	func get_active_map() -> Node:
		return map

	func get_player() -> Node:
		return player

	func get_player_character() -> CharacterState:
		return character

	func get_character_registry() -> CharacterRegistry:
		return registry


class Rig extends RefCounted:
	var world: StubWorld
	var knowledge: KnowledgeRuntime
	var cultivation: CultivationRuntime
	var inventory: InventoryRuntime
	var relationship: RelationshipRuntime
	var npcs: NpcRuntime
	var ko: WorldNpc


func _npc(host: Node, id: StringName, template_path: String, at: Vector2) -> WorldNpc:
	var npc: WorldNpc = WorldNpcScript.new()
	npc.name = String(id)
	npc.character_id = id
	npc.character_template = load(template_path) as CharacterTemplateData
	host.add_child(npc)
	npc.global_position = at
	return npc


func _rig(catalog: ShopCatalogData = null, start: bool = true) -> Rig:
	var rig := Rig.new()
	rig.world = StubWorld.new()
	add_to_tree(rig.world)
	rig.world.map = Node2D.new()
	rig.world.add_child(rig.world.map)
	var pickups := Node2D.new()
	pickups.name = "Pickups"
	rig.world.map.add_child(pickups)
	var host := Node2D.new()
	host.name = "Interactables"
	rig.world.map.add_child(host)
	rig.ko = _npc(host, KO, KO_TEMPLATE, Vector2(200, 200))
	rig.world.player = Node2D.new()
	rig.world.map.add_child(rig.world.player)
	rig.world.player.global_position = Vector2(200, 220)
	rig.world.character = CharacterState.new()
	rig.world.character.instance_id = PLAYER
	rig.world.character.realm_id = &"realm_pham"
	rig.world.registry = RegistryScript.new()
	rig.world.registry.add(rig.world.character)
	rig.knowledge = KnowledgeScript.new()
	add_to_tree(rig.knowledge)
	rig.knowledge.start_session()
	rig.cultivation = CultivationScript.new()
	add_to_tree(rig.cultivation)
	rig.cultivation.start_session(rig.world.character, rig.knowledge, rig.world)
	rig.inventory = InventoryScript.new()
	add_to_tree(rig.inventory)
	rig.inventory.start_session(rig.world.character, rig.world, rig.knowledge, rig.cultivation)
	rig.relationship = RelationshipScript.new()
	add_to_tree(rig.relationship)
	rig.relationship.start_session()
	rig.npcs = NpcRuntimeScript.new()
	add_to_tree(rig.npcs)
	if start:
		assert_true(rig.npcs.start_session(rig.world, rig.inventory, rig.relationship, catalog),
			"the NPC session starts")
	return rig


func _free(rig: Rig) -> void:
	rig.npcs.end_session()
	rig.relationship.end_session()
	rig.inventory.end_session()
	rig.cultivation.end_session()
	rig.knowledge.end_session()
	for node: Node in [rig.npcs, rig.relationship, rig.inventory, rig.cultivation,
			rig.knowledge, rig.world]:
		free_node(node)


## How Kha Thản regards the player: a directed edge keeper -> customer.
func _regard(rig: Rig, keeper: StringName, dimension: StringName, value: int) -> void:
	var service := rig.relationship.get_service()
	var edge_id := StringName("edge_%s_player" % keeper)
	if not rig.relationship.get_store().has_edge(edge_id):
		service.create_edge(edge_id, RelationshipEndpoint.for_character(keeper),
			RelationshipEndpoint.for_character(PLAYER))
	service.set_dimension(edge_id, dimension, value, &"test")


func _state_of(rig: Rig) -> String:
	return var_to_str([rig.npcs.to_dict(), rig.inventory.to_dict()])


# === An NPC is a character ==================================================

func test_an_npc_body_binds_to_a_character_state_in_the_registry() -> void:
	var rig := _rig()
	var state := rig.world.registry.get_character(KO)
	assert_not_null(state, "binding realized Kha Thản as a CharacterState in the registry")
	assert_true(state is CharacterState, "the SAME class the player is — no NPC state model")
	assert_eq(state.template_id, &"char_scout_ko", "built from his authored template")
	assert_eq(rig.ko.character(), state, "and the body holds that state")
	assert_true(rig.ko.is_available(), "so he can be spoken to")
	assert_true(rig.ko.visual() != null, "and is drawn from his template's visual profile")
	assert_eq(rig.ko.interaction_kind(), WorldNpc.KIND, "he is selected as an NPC")
	assert_eq(rig.ko.interaction_id(), KO, "by his character id")
	assert_eq(rig.ko.prompt_args(), {"name": state.name_key}, "and the prompt names him")
	assert_eq(rig.world.registry.count(), 2, "the registry holds the player and him, once each")
	# Arriving again binds the SAME state: nobody is realized twice.
	rig.world.active_map_leaving.emit()
	assert_false(rig.ko.is_available(), "leaving the map unbinds the body")
	rig.world.active_map_ready.emit()
	assert_eq(rig.ko.character(), state, "arriving binds the same CharacterState")
	assert_eq(rig.world.registry.count(), 2, "and adds nobody")
	_free(rig)


func test_an_actor_the_world_already_realized_is_reused_not_rebuilt() -> void:
	var rig := _rig(null, false)
	var existing := CharacterState.create_from_template(
		load(KO_TEMPLATE) as CharacterTemplateData, KO)
	rig.world.registry.add(existing)
	assert_true(rig.npcs.start_session(rig.world, rig.inventory, rig.relationship), "starts")
	assert_eq(rig.ko.character(), existing, "the body binds the state that already existed")
	assert_eq(rig.world.registry.count(), 2, "no second state for one id")
	_free(rig)


func test_a_body_with_no_resolvable_character_stays_hidden() -> void:
	var rig := _rig(null, false)
	var host := rig.world.map.get_node("Interactables")
	var nameless: WorldNpc = WorldNpcScript.new()
	nameless.name = "Nameless"
	host.add_child(nameless)
	var no_template: WorldNpc = WorldNpcScript.new()
	no_template.name = "NoTemplate"
	no_template.character_id = &"char_ghost"
	host.add_child(no_template)
	assert_true(rig.npcs.start_session(rig.world, rig.inventory, rig.relationship), "starts")
	assert_false(nameless.is_available(), "a body with no character id is not offered")
	assert_false(no_template.is_available(), "nor one whose character cannot be realized")
	assert_false(rig.world.registry.has(&"char_ghost"), "and nothing was invented for it")
	assert_true(rig.ko.is_available(), "a bad neighbour does not break a good body")
	_free(rig)


# === Talking ================================================================

func test_talking_is_range_validated_and_opens_the_shop_once() -> void:
	var rig := _rig()
	var opened: Array[StringName] = []
	var refused: Array[StringName] = []
	rig.npcs.shop_opened.connect(func(id: StringName) -> void: opened.append(id))
	rig.npcs.interaction_refused.connect(func(key: StringName) -> void: refused.append(key))
	rig.world.player.global_position = rig.ko.global_position + Vector2(rig.ko.reach_px + 6, 0)
	assert_eq(rig.npcs.interact(KO), NpcRuntime.REFUSE_TOO_FAR,
		"out of his reach the talk is refused, whatever the caller claims")
	assert_false(rig.npcs.is_shop_open(), "and nothing opens")
	assert_eq(rig.npcs.interact(&"char_nobody"), NpcRuntime.REFUSE_NOBODY,
		"someone who is not in this map cannot be spoken to")
	assert_eq(refused, [NpcRuntime.REFUSE_TOO_FAR, NpcRuntime.REFUSE_NOBODY] as Array[StringName],
		"each refusal is answered")
	rig.world.player.global_position = rig.ko.global_position + Vector2(-20, 0)
	assert_eq(rig.npcs.interact(KO), &"", "in reach, the talk succeeds")
	assert_eq(rig.npcs.open_shop_id(), SHOP, "and his shop is open")
	assert_eq(rig.ko.visual().get_direction(), CharacterVisualProfileData.Direction.LEFT,
		"he turned to face the player (who stands to his left)")
	rig.npcs.interact(KO)
	rig.npcs.interact(KO)
	assert_eq(opened, [SHOP] as Array[StringName], "repeated presses opened it exactly once")
	rig.npcs.close_shop()
	rig.npcs.close_shop()
	assert_false(rig.npcs.is_shop_open(), "closing is idempotent")
	assert_false(rig.npcs.build_shop_view().open, "and the view says closed")
	_free(rig)


## The talk gesture goes through the SHARED action layer (`play_action` / `drive_action` /
## `end_action`) and is not a strike: nothing is armed, nothing is hit.
func test_the_talk_gesture_is_a_shared_action_and_never_a_strike() -> void:
	var rig := _rig()
	var visual := rig.ko.visual()
	assert_false(CharacterVisualComponent.is_strike_action(CharacterVisualComponent.ACTION_TALK),
		"talk is not one of the strike actions")
	assert_false(rig.ko.is_greeting(), "at rest he is not gesturing")
	rig.world.player.global_position = rig.ko.global_position + Vector2(20, 0)
	rig.npcs.interact(KO)
	assert_true(rig.ko.is_greeting(), "spoken to, he gestures")
	assert_eq(visual.current_action(), CharacterVisualComponent.ACTION_TALK,
		"through the visual component's action layer")
	assert_eq(visual.current_anim(), CharacterVisualProfileData.ANIM_TALK,
		"drawing his authored talk sheet")
	var first := visual.get_column()
	rig.ko.advance(WorldNpc.TALK_SECONDS * 0.5)
	assert_true(visual.get_column() > first,
		"the gesture advances with its clock (column %d -> %d)" % [first, visual.get_column()])
	assert_true(visual.action_progress() > 0.4 and visual.action_progress() < 0.6,
		"driven by progress, like every other action")
	rig.ko.advance(WorldNpc.TALK_SECONDS)
	assert_false(rig.ko.is_greeting(), "it ends")
	assert_false(visual.is_action_playing(), "and he returns to his idle")
	assert_false(rig.ko.is_processing(), "with no frame callback left running")
	for child in rig.ko.get_children():
		assert_false(child is AttackComponent or child is HurtboxComponent,
			"an NPC body carries no combat component: a greeting can hit nothing")
	# A look with no talk sheet degrades to its idle; the conversation is unaffected.
	var lin := _npc(rig.world.map.get_node("Interactables"), LIN, LIN_TEMPLATE,
		Vector2(400, 200))
	rig.world.active_map_ready.emit()
	rig.world.player.global_position = lin.global_position + Vector2(0, 18)
	assert_eq(rig.npcs.interact(LIN), &"", "someone without the sheet can still be spoken to")
	assert_false(lin.is_greeting(), "she simply keeps her idle")
	_free(rig)


func test_someone_who_keeps_no_shop_only_greets() -> void:
	var rig := _rig(null, false)
	var lin := _npc(rig.world.map.get_node("Interactables"), LIN, LIN_TEMPLATE,
		Vector2(400, 200))
	assert_true(rig.npcs.start_session(rig.world, rig.inventory, rig.relationship), "starts")
	var greeted: Array[StringName] = []
	rig.npcs.npc_greeted.connect(func(id: StringName) -> void: greeted.append(id))
	rig.world.player.global_position = lin.global_position + Vector2(0, 18)
	assert_eq(rig.npcs.interact(LIN), &"", "she can be spoken to")
	assert_eq(greeted, [LIN] as Array[StringName], "she acknowledges the player")
	assert_false(rig.npcs.is_shop_open(), "and no shop opens")
	_free(rig)


# === Trading ================================================================

func test_buying_and_selling_go_through_the_inventory_owner() -> void:
	var rig := _rig()
	rig.inventory.give(COIN, 20)
	rig.inventory.give(PILL, 2)
	rig.npcs.interact(KO)
	var gained: Array = []
	var changes: Array = [0]
	var trades: Array = []
	rig.inventory.item_gained.connect(func(id: StringName, n: int) -> void: gained.append([id, n]))
	rig.inventory.inventory_changed.connect(func() -> void: changes[0] += 1)
	rig.npcs.trade_done.connect(
		func(kind: StringName, id: StringName, n: int, total: int) -> void:
			trades.append([kind, id, n, total]))
	var view := rig.npcs.build_shop_view()
	assert_true(view.open, "the view is open")
	assert_eq(view.balance, 20, "it shows the customer's linh thạch")
	assert_eq(view.modifier_percent, 0, "a stranger trades at the base price")
	assert_eq(view.keeper_name_key, &"CHARACTER_SCOUT_KO_NAME", "and names the keeper")

	var bought := rig.npcs.buy(SWORD)
	assert_true(bool(bought["ok"]), "the sword is bought")
	assert_eq(rig.inventory.count_of(COIN), 6, "14 linh thạch paid")
	assert_eq(rig.inventory.count_of(SWORD), 1, "the sword is in the bag")
	assert_eq(rig.npcs.get_service().state().remaining(SHOP, SWORD), 0, "his one sword is gone")
	assert_eq(changes[0], 1, "the bag announced ONE change for the whole trade")
	assert_eq(gained, [], "a purchase is not a pickup: no 'gained' notice from the bag")

	var sold := rig.npcs.sell(PILL)
	assert_true(bool(sold["ok"]), "a pill is sold")
	assert_eq(rig.inventory.count_of(PILL), 1, "one pill left")
	assert_eq(rig.inventory.count_of(COIN), 7, "one linh thạch earned (40% of 3, rounded down)")
	assert_eq(trades, [[ShopService.KIND_BUY, SWORD, 1, 14], [ShopService.KIND_SELL, PILL, 1, 1]],
		"each trade was announced once, with its total")
	view = rig.npcs.build_shop_view()
	assert_eq(view.status_key, NpcRuntime.STATUS_SOLD, "the view carries the last outcome")
	assert_false(view.status_is_refusal, "as a result, not a refusal")
	for row in view.buy_rows:
		assert_ne(row["item_id"], SWORD, "a sold-out item is no longer offered")
	_free(rig)


func test_a_refused_trade_changes_nothing_and_says_why() -> void:
	var rig := _rig()
	rig.inventory.give(COIN, 2)
	var refusals: Array[StringName] = []
	rig.npcs.trade_refused.connect(func(key: StringName) -> void: refusals.append(key))
	var before := _state_of(rig)
	assert_eq(rig.npcs.buy(PILL)["reason"], NpcRuntime.REFUSE_SHOP_CLOSED,
		"with no shop open nothing can be bought")
	rig.npcs.interact(KO)
	assert_eq(rig.npcs.buy(SWORD)["reason"], ShopService.REFUSE_NO_FUNDS, "2 cannot buy 14")
	assert_eq(rig.npcs.buy(&"item_nothing")["reason"], ShopService.REFUSE_NOT_TRADED,
		"an unknown item is refused")
	assert_eq(rig.npcs.buy(PILL, 0)["reason"], ShopService.REFUSE_QUANTITY, "zero is refused")
	assert_eq(rig.npcs.buy(PILL, -3)["reason"], ShopService.REFUSE_QUANTITY, "negative too")
	assert_eq(rig.npcs.sell(SWORD)["reason"], ShopService.REFUSE_NOT_HELD,
		"something not carried cannot be sold")
	assert_eq(rig.npcs.sell(COIN)["reason"], ShopService.REFUSE_NOT_BOUGHT,
		"the currency itself is not for sale")
	var view := rig.npcs.build_shop_view()
	assert_true(view.status_is_refusal, "the view marks the last outcome as a refusal")
	assert_eq(view.status_key, ShopService.REFUSE_NOT_BOUGHT, "with its reason")
	rig.world.player.global_position = rig.ko.global_position + Vector2(300, 0)
	assert_eq(rig.npcs.buy(PILL)["reason"], NpcRuntime.REFUSE_TOO_FAR,
		"a trade is range-checked again: walking away ends it")
	assert_eq(_state_of(rig), before, "none of the eight refusals changed the bag or the stock")
	assert_eq(refusals.size(), 8, "and each one was answered")
	# The bag is full of other things: the purchase is refused whole.
	rig.world.player.global_position = rig.ko.global_position + Vector2(0, 18)
	rig.inventory.give(COIN, 30)
	rig.inventory.get_bag().capacity = rig.inventory.get_bag().stack_count()
	var full := _state_of(rig)
	assert_eq(rig.npcs.buy(PILL)["reason"], ShopService.REFUSE_NO_ROOM, "no room: refused")
	assert_eq(_state_of(rig), full, "no coin was taken")
	_free(rig)


# === Standing ===============================================================

func test_prices_follow_the_relationship_graph_and_no_edge_is_neutral() -> void:
	var rig := _rig()
	rig.inventory.give(COIN, 60)
	rig.npcs.interact(KO)
	var shop := rig.npcs.get_service().catalog().entry(SHOP)
	assert_eq(rig.npcs.standing_for(shop).value, 0, "no edge: neutral")
	assert_eq(_price(rig, SWORD), 14, "a stranger pays the base price")
	_regard(rig, KO, &"affinity", 50)
	assert_eq(rig.npcs.build_shop_view().modifier_percent, -10, "affinity 50: 10% off")
	assert_eq(_price(rig, SWORD), 13, "14 less 10%, rounded up")
	_regard(rig, KO, &"affinity", 100)
	assert_eq(_price(rig, SWORD), 12, "the best regard: 20% off, rounded up")
	_regard(rig, KO, &"affinity", -100)
	assert_eq(rig.npcs.build_shop_view().modifier_percent, 30, "the worst regard: 30% more")
	assert_eq(_price(rig, SWORD), 19, "14 plus 30%, rounded up")
	var plan := rig.npcs.buy(SWORD)
	assert_eq(int(plan["total"]), 19, "the price charged is the price shown")
	assert_eq(rig.inventory.count_of(COIN), 41, "exactly that was paid")
	# Another dimension on the same edge moves nothing: the shop prices on affinity only.
	_regard(rig, KO, &"affinity", 0)
	_regard(rig, KO, &"respect", 100)
	assert_eq(_price(rig, PILL), 3, "respect is not this shop's pricing dimension")
	# Someone ELSE's regard for the player is not the keeper's.
	_regard(rig, SHEN, &"affinity", 100)
	assert_eq(_price(rig, PILL), 3, "another character's affinity does not discount this shop")
	_free(rig)


func _price(rig: Rig, item_id: StringName) -> int:
	for row in rig.npcs.build_shop_view().buy_rows:
		if row["item_id"] == item_id:
			return int(row["price"])
	return -1


# === A second shop is content ===============================================

func test_a_second_shop_works_through_the_same_code() -> void:
	var items := load("res://data/items/item_catalog.tres") as ItemCatalogData
	var stores: ShopData = ShopDataScript.new()
	stores.id = &"shop_test_outpost_stores"
	stores.name_key = &"SHOP_TEST_NAME"
	stores.keeper_id = SHEN
	var entry: ShopEntryData = ShopEntryScript.new()
	entry.item = items.entry(PILL)
	entry.base_price = 20
	entry.stock = 3
	var entries: Array[ShopEntryData] = [entry]
	stores.entries = entries
	stores.price_dimension = &"respect"        # 0..100: it can only ever discount
	stores.max_discount_percent = 50
	stores.sell_percent = 25
	var catalog: ShopCatalogData = ShopCatalogScript.new()
	catalog.currency_item = items.entry(COIN)
	var shops: Array[ShopData] = [(load(SHIPPED) as ShopCatalogData).entries[0], stores]
	catalog.entries = shops
	var rig := _rig(catalog, false)
	var shen := _npc(rig.world.map.get_node("Interactables"), SHEN, SHEN_TEMPLATE,
		Vector2(500, 200))
	assert_true(rig.npcs.start_session(rig.world, rig.inventory, rig.relationship, catalog),
		"a two-shop catalog starts")
	rig.inventory.give(COIN, 50)
	rig.world.player.global_position = shen.global_position + Vector2(0, 18)
	assert_eq(rig.npcs.interact(SHEN), &"", "the elder is spoken to")
	assert_eq(rig.npcs.open_shop_id(), &"shop_test_outpost_stores", "HIS shop opens")
	assert_eq(_price(rig, PILL), 20, "at his own base price")
	_regard(rig, SHEN, &"respect", 100)
	assert_eq(_price(rig, PILL), 10, "moved by his own dimension and his own discount")
	assert_true(bool(rig.npcs.buy(PILL)["ok"]), "and it trades")
	assert_eq(rig.npcs.get_service().state().remaining(&"shop_test_outpost_stores", PILL), 2,
		"from his own finite stock")
	assert_eq(rig.npcs.get_service().state().remaining(SHOP, SWORD), 1,
		"leaving the other shop's stock alone")
	rig.npcs.close_shop()
	rig.world.player.global_position = rig.ko.global_position + Vector2(0, 18)
	rig.npcs.interact(KO)
	assert_eq(rig.npcs.open_shop_id(), SHOP, "and the first shop still opens for its keeper")
	_free(rig)


# === Lifecycle and persistence ==============================================

func test_leaving_the_map_or_the_session_closes_the_shop() -> void:
	var rig := _rig()
	var closed: Array[StringName] = []
	rig.npcs.shop_closed.connect(func(id: StringName) -> void: closed.append(id))
	rig.npcs.interact(KO)
	rig.world.active_map_leaving.emit()
	assert_false(rig.npcs.is_shop_open(), "a map change closes the shop")
	rig.world.active_map_ready.emit()
	rig.npcs.interact(KO)
	rig.npcs.end_session()
	assert_eq(closed, [SHOP, SHOP] as Array[StringName], "each closing was announced once")
	assert_false(rig.npcs.is_session_active(), "the session is over")
	assert_eq(rig.npcs.interact(KO), NpcRuntime.REFUSE_UNAVAILABLE, "nobody answers after it")
	for connection in rig.inventory.inventory_changed.get_connections():
		assert_ne((connection["callable"] as Callable).get_object(), rig.npcs,
			"the bag subscription is dropped")
	rig.npcs.end_session()                           # idempotent
	_free(rig)


func test_a_session_refuses_to_start_on_bad_dependencies_or_content() -> void:
	var rig := _rig(null, false)
	assert_false(rig.npcs.start_session(null, rig.inventory, rig.relationship), "no world")
	assert_false(rig.npcs.start_session(rig.world, null, rig.relationship), "no inventory")
	assert_false(rig.npcs.start_session(rig.world, rig.inventory, null), "no relationship graph")
	var empty: ShopCatalogData = ShopCatalogScript.new()
	assert_false(rig.npcs.start_session(rig.world, rig.inventory, rig.relationship, empty),
		"an invalid catalog")
	var odd := (load(SHIPPED) as ShopCatalogData).duplicate(true) as ShopCatalogData
	odd.entries[0].price_dimension = &"gratitude"
	assert_false(rig.npcs.start_session(rig.world, rig.inventory, rig.relationship, odd),
		"a pricing dimension the relationship graph does not define")
	assert_false(rig.npcs.is_session_active(), "and nothing half-started")
	assert_false(rig.ko.is_available(), "nor was anyone bound")
	_free(rig)


func test_shop_stock_round_trips_through_the_runtime() -> void:
	var rig := _rig()
	rig.inventory.give(COIN, 30)
	rig.npcs.interact(KO)
	rig.npcs.buy(SWORD)
	var saved := rig.npcs.to_dict()
	assert_false(rig.npcs.from_dict({"schema": 1, "stock": {}}), "a bad payload is refused")
	assert_eq(rig.npcs.to_dict(), saved, "and changed nothing")
	var other := _rig()
	assert_eq(other.npcs.get_service().state().remaining(SHOP, SWORD), 1, "a fresh shop is full")
	assert_true(other.npcs.from_dict(saved), "the saved stock is accepted")
	assert_eq(other.npcs.get_service().state().remaining(SHOP, SWORD), 0,
		"and the sword is still sold")
	_free(other)
	_free(rig)

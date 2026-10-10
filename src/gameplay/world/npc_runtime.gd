extends Node
class_name NpcRuntime
## NpcRuntime — Aetheria gameplay (people in the world and what they offer, Phase 17).
##
## Per-session node under `Main/Systems` (no autoload). It owns:
##   * the binding of every `WorldNpc` body in the active map to its `CharacterState` in the
##     session's `CharacterRegistry` (an NPC IS a character — no parallel model);
##   * the `ShopState` (what each shop has left) through `ShopService`, and which shop — at most
##     one — is open.
##
## AUTHORITY. It decides whether a talk or a trade happens. The bag is `InventoryRuntime`'s:
## coin and goods move through its all-or-nothing `exchange`, never by a write from here. The
## player's funds are the count of the catalog's currency item in that bag — no wallet number
## exists anywhere (D-065). Standing is READ from the relationship graph (`RelationshipRuntime`)
## and never written here.
##
## RANGE. The map reports "the player used this"; this node does not take its word for it —
## `interact` and every trade re-check that the keeper's body is in the active map and within
## its reach of the player.
##
## FAIL CLOSED. Every refusal emits a reason key and changes nothing.
##
## PERSISTENCE. `to_dict()` / `from_dict()` are `ShopState`'s plain-data boundary (SAVE_FORMAT
## `shops`). No file is written here.

signal npc_greeted(character_id: StringName)
signal shop_opened(shop_id: StringName)
signal shop_closed(shop_id: StringName)
signal trade_done(kind: StringName, item_id: StringName, quantity: int, total: int)
signal trade_refused(reason_key: StringName)
signal interaction_refused(reason_key: StringName)
## The open shop's view changed (opened, traded, closed, the bag changed).
signal view_changed()

const SHOP_CATALOG_PATH := "res://data/shops/shop_catalog.tres"

const REFUSE_NOBODY := &"UI_NPC_NOBODY"
const REFUSE_TOO_FAR := &"UI_NPC_TOO_FAR"
const REFUSE_SHOP_CLOSED := &"UI_SHOP_CLOSED"
const REFUSE_UNAVAILABLE := &"UI_NPC_UNAVAILABLE"

const STATUS_BOUGHT := &"UI_SHOP_BOUGHT"
const STATUS_SOLD := &"UI_SHOP_SOLD"

## Slack on the reach re-check: the map selects on the same distance, and a float compared
## twice must not refuse a talk the prompt just offered.
const REACH_SLACK := 0.5

var _world: Node = null
var _inventory: InventoryRuntime = null
var _relationship: RelationshipRuntime = null
var _service: ShopService = null
var _session_active: bool = false

var _open_shop: StringName = &""
var _status_key: StringName = &""
var _status_args: Dictionary = {}
var _status_is_refusal: bool = false


## Start the session. Builds into locals and commits only when every check passed: the catalog
## is valid, every traded item and the currency are real items, and every pricing dimension is
## one the relationship graph defines. `catalog` is the content seam (null = the shipped one).
func start_session(world: Node, inventory: InventoryRuntime, relationship: RelationshipRuntime,
		catalog: ShopCatalogData = null) -> bool:
	if _session_active:
		push_error("[npc-rt] start_session while a session is active")
		return false
	if world == null or inventory == null or not inventory.is_session_active() \
			or relationship == null or not relationship.is_session_active():
		push_error("[npc-rt] session NOT started: a dependency is missing or inactive")
		return false
	if catalog == null:
		catalog = load(SHOP_CATALOG_PATH) as ShopCatalogData
	if catalog == null:
		push_error("[npc-rt] session NOT started: %s did not load" % SHOP_CATALOG_PATH)
		return false
	var errors := catalog.validation_errors()
	var items := inventory.get_catalog()
	if catalog.currency_item != null and items.entry(catalog.currency_item.id) == null:
		errors.append("the currency '%s' is not in the item catalog" % catalog.currency_item.id)
	for shop in catalog.entries:
		if shop == null:
			continue
		if shop.price_dimension != &"" \
				and not relationship.get_service().has_dimension(shop.price_dimension):
			errors.append("%s prices on '%s', which the relationship graph does not define"
				% [shop.id, shop.price_dimension])
		for entry in shop.entries:
			if entry != null and entry.item != null and items.entry(entry.item.id) == null:
				errors.append("%s trades '%s', which is not in the item catalog"
					% [shop.id, entry.item.id])
	if not errors.is_empty():
		push_error("[npc-rt] session NOT started: %s" % str(errors))
		return false
	var state := ShopState.new()
	state.seed_from(catalog)
	var service := ShopService.new(catalog, state)
	if not service.is_ready():
		push_error("[npc-rt] session NOT started: the ShopService refused its catalog")
		return false
	_world = world
	_inventory = inventory
	_relationship = relationship
	_service = service
	_open_shop = &""
	_clear_status()
	_session_active = true
	_inventory.inventory_changed.connect(_on_inventory_changed)
	if _world.has_signal("active_map_leaving"):
		_world.connect("active_map_leaving", _on_map_leaving)
	if _world.has_signal("active_map_ready"):
		_world.connect("active_map_ready", _on_map_ready)
	_bind_npcs()
	return true


## End the session: close the shop, drop every connection. Idempotent.
func end_session() -> void:
	if _session_active:
		close_shop()
		_unbind_npcs()
	if _inventory != null and is_instance_valid(_inventory) \
			and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)
	if _world != null and is_instance_valid(_world):
		if _world.has_signal("active_map_leaving") \
				and _world.is_connected("active_map_leaving", _on_map_leaving):
			_world.disconnect("active_map_leaving", _on_map_leaving)
		if _world.has_signal("active_map_ready") \
				and _world.is_connected("active_map_ready", _on_map_ready):
			_world.disconnect("active_map_ready", _on_map_ready)
	_world = null
	_inventory = null
	_relationship = null
	_service = null
	_open_shop = &""
	_clear_status()
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_service() -> ShopService:
	return _service


func open_shop_id() -> StringName:
	return _open_shop


func is_shop_open() -> bool:
	return _open_shop != &""


# --- Talking ------------------------------------------------------------------

## The player turns to `character_id`. THE range authority for every way of addressing a
## person: the body must be in this map, bound, and within its reach of the player. On success
## the person turns to face the player and &"" is returned; otherwise the refusal key (also
## emitted). A conversation (Phase 18) starts here too — nobody else decides who is in reach.
func engage(character_id: StringName) -> StringName:
	var refusal := reach_refusal(character_id)
	if refusal != &"":
		return _refuse_interaction(refusal)
	_find_npc(character_id).face_toward(_player().global_position)
	return &""


## Why `character_id` cannot be addressed right now, or &"" when they can. A pure query.
func reach_refusal(character_id: StringName) -> StringName:
	if not _session_active:
		return REFUSE_UNAVAILABLE
	if _npc_in_reach(character_id) != null:
		return &""
	return REFUSE_NOBODY if _find_npc(character_id) == null else REFUSE_TOO_FAR


## Have `character_id`'s body play a gesture of the shared action layer. Presentation only.
func gesture(character_id: StringName, action: StringName) -> bool:
	var npc := _find_npc(character_id)
	return npc != null and npc.gesture(action)


## Where `character_id` stands in this map, or `Vector2.INF` when they have no body here.
func position_of(character_id: StringName) -> Vector2:
	var npc := _find_npc(character_id)
	return npc.global_position if npc != null else Vector2.INF


## The template the body of `character_id` in this map was authored with (their look, their
## portrait), or null when they have no body here.
func template_of(character_id: StringName) -> CharacterTemplateData:
	var npc := _find_npc(character_id)
	return npc.character_template if npc != null else null


## The player addresses `character_id` with nothing more specific to say — the behaviour of
## someone who has NO authored conversation (`DialogueRuntime` handles those who do): they turn
## and gesture, and their shop opens if they keep one. Returns &"" on success, else the refusal
## key (also emitted).
func interact(character_id: StringName) -> StringName:
	var refusal := engage(character_id)
	if refusal != &"":
		return refusal
	_find_npc(character_id).greet()
	if _service.catalog().shop_of_keeper(character_id) == null:
		npc_greeted.emit(character_id)
		return &""
	return open_shop_of(character_id)


## Open the shop `character_id` keeps (a conversation's "trade" choice hands over to this).
## Range is re-checked here; someone who keeps no shop refuses. A shop already open stays as
## it is. Returns &"" on success, else the refusal key (also emitted).
func open_shop_of(character_id: StringName) -> StringName:
	var refusal := reach_refusal(character_id)
	if refusal != &"":
		return _refuse_interaction(refusal)
	var shop := _service.catalog().shop_of_keeper(character_id)
	if shop == null:
		return _refuse_interaction(REFUSE_SHOP_CLOSED)
	if _open_shop == shop.id:
		return &""  # already open: a repeated press opens nothing twice
	_open_shop = shop.id
	_clear_status()
	shop_opened.emit(shop.id)
	view_changed.emit()
	return &""


## Close the open shop. Safe (and silent) when none is.
func close_shop() -> void:
	if _open_shop == &"":
		return
	var shop_id := _open_shop
	_open_shop = &""
	_clear_status()
	shop_closed.emit(shop_id)
	view_changed.emit()


# --- Trading ------------------------------------------------------------------

## Buy `quantity` of `item_id` from the open shop. Returns the transaction's plan Dictionary
## (`ok`, `reason`, `unit_price`, `total`, …).
func buy(item_id: StringName, quantity: int = 1) -> Dictionary:
	return _trade(ShopService.KIND_BUY, item_id, quantity)


## Sell `quantity` of `item_id` to the open shop.
func sell(item_id: StringName, quantity: int = 1) -> Dictionary:
	return _trade(ShopService.KIND_SELL, item_id, quantity)


func _trade(kind: StringName, item_id: StringName, quantity: int) -> Dictionary:
	var shop := _service.catalog().entry(_open_shop) if _session_active else null
	if shop == null:
		return _refuse_trade({"ok": false, "reason": REFUSE_SHOP_CLOSED})
	if _npc_in_reach(shop.keeper_id) == null:
		return _refuse_trade({"ok": false, "reason": REFUSE_TOO_FAR})
	var standing := standing_for(shop)
	var plan: Dictionary
	if kind == ShopService.KIND_BUY:
		plan = _service.plan_buy(shop.id, item_id, quantity,
			_inventory.count_of(_service.currency_id()), standing)
	else:
		plan = _service.plan_sell(shop.id, item_id, quantity, _inventory.count_of(item_id),
			standing)
	plan = _service.transact(plan, _inventory.exchange)
	if not bool(plan["ok"]):
		return _refuse_trade(plan)
	var item := _inventory.get_catalog().entry(item_id)
	_status_key = STATUS_BOUGHT if kind == ShopService.KIND_BUY else STATUS_SOLD
	_status_args = {"name": item.name_key if item != null else &"",
		"count": int(plan["quantity"]), "total": int(plan["total"])}
	_status_is_refusal = false
	trade_done.emit(kind, item_id, int(plan["quantity"]), int(plan["total"]))
	view_changed.emit()
	return plan


func _refuse_trade(plan: Dictionary) -> Dictionary:
	_status_key = plan["reason"]
	_status_args = {}
	_status_is_refusal = true
	trade_refused.emit(plan["reason"])
	view_changed.emit()
	return plan


func _refuse_interaction(reason: StringName) -> StringName:
	interaction_refused.emit(reason)
	return reason


# --- Standing -----------------------------------------------------------------

## How `shop`'s keeper regards the player, on the shop's pricing dimension, read from the
## relationship graph. NO EDGE between them (or no pricing dimension) is neutral: a stranger
## pays the base price.
func standing_for(shop: ShopData) -> ShopStanding:
	if shop == null or shop.price_dimension == &"" or _relationship == null:
		return ShopStanding.make_neutral()
	var config := _relationship.get_config()
	var dimension := shop.price_dimension
	var neutral := config.get_default(dimension)
	var standing := ShopStanding.new(neutral, neutral, config.get_min(dimension),
		config.get_max(dimension))
	var character: CharacterState = _world.call("get_player_character")
	if character == null:
		return standing
	var keeper := RelationshipEndpoint.for_character(shop.keeper_id)
	var customer := RelationshipEndpoint.for_character(character.instance_id)
	# The KEEPER's regard for the customer: their directed edge, or the pair's symmetric one.
	var edge := _relationship.get_store().find_between(keeper, customer, true)
	if edge != null:
		standing.value = _relationship.get_service().read_dimension_as(edge.id, keeper,
			dimension)
	return standing


# --- View ---------------------------------------------------------------------

## The read-only snapshot the shop panel shows (closed when no shop is open).
func build_shop_view() -> ShopView:
	var view := ShopView.make_closed()
	var shop := _service.catalog().entry(_open_shop) if _session_active else null
	if shop == null:
		return view
	var standing := standing_for(shop)
	var currency := _service.catalog().currency_item
	var funds := _inventory.count_of(currency.id)
	view.open = true
	view.shop_id = shop.id
	view.name_key = shop.name_key
	var keeper := _registry().get_character(shop.keeper_id) if _registry() != null else null
	view.keeper_name_key = keeper.name_key if keeper != null else &""
	view.currency_name_key = currency.name_key
	view.currency_icon = currency.icon
	view.balance = funds
	view.modifier_percent = roundi(ShopService.modifier_basis(shop, standing) / 100.0)
	for entry in shop.entries:
		var item := entry.item
		var remaining := _service.state().remaining(shop.id, item.id)
		if remaining != 0:
			var price := ShopService.buy_price(shop, entry, standing)
			var probe := _service.plan_buy(shop.id, item.id, 1, funds, standing)
			view.buy_rows.append({"item_id": item.id, "name_key": item.name_key,
				"desc_key": item.desc_key, "icon": item.icon, "base_price": entry.base_price,
				"price": price, "stock": remaining,
				"reason_key": &"" if bool(probe["ok"]) else probe["reason"]})
		var held := _inventory.count_of(item.id)
		if entry.buys and held > 0:
			view.sell_rows.append({"item_id": item.id, "name_key": item.name_key,
				"desc_key": item.desc_key, "icon": item.icon,
				"base_price": ShopService.sell_price(shop, entry, ShopStanding.make_neutral()),
				"price": ShopService.sell_price(shop, entry, standing), "held": held})
	view.status_key = _status_key
	view.status_args = _status_args.duplicate()
	view.status_is_refusal = _status_is_refusal
	return view


# --- The world moving ---------------------------------------------------------

func _on_map_leaving() -> void:
	close_shop()
	_unbind_npcs()


func _on_map_ready() -> void:
	_bind_npcs()


func _on_inventory_changed() -> void:
	if _open_shop != &"":
		view_changed.emit()


## Bind every `WorldNpc` in the active map to its character, realizing it from the body's
## template only when the session has not already (a world-simulation actor already is).
func _bind_npcs() -> void:
	var registry := _registry()
	for npc in _npcs():
		if registry == null or npc.character_id == &"":
			push_error("[npc-rt] '%s' has no character id or there is no registry" % npc.name)
			npc.unbind()
			continue
		if not registry.has(npc.character_id):
			var made := CharacterState.create_from_template(npc.character_template,
				npc.character_id) if npc.character_template != null else null
			if made == null or not registry.add(made):
				push_error("[npc-rt] '%s': could not realize character '%s'"
					% [npc.name, npc.character_id])
				npc.unbind()
				continue
		if not npc.bind(registry.get_character(npc.character_id)):
			npc.unbind()
	_refresh_map()


func _unbind_npcs() -> void:
	for npc in _npcs():
		npc.unbind()


func _npcs() -> Array[WorldNpc]:
	var out: Array[WorldNpc] = []
	if _world == null or not is_instance_valid(_world):
		return out
	var map: Node = _world.call("get_active_map")
	var host := map.get_node_or_null("Interactables") if map != null else null
	if host == null:
		return out
	for child in host.get_children():
		if child is WorldNpc:
			out.append(child)
	return out


func _find_npc(character_id: StringName) -> WorldNpc:
	for npc in _npcs():
		if npc.character_id == character_id:
			return npc
	return null


## The body of `character_id` if it is bound and the player stands within its reach.
func _npc_in_reach(character_id: StringName) -> WorldNpc:
	var npc := _find_npc(character_id)
	var player := _player()
	if npc == null or player == null or not npc.is_available():
		return null
	if npc.global_position.distance_to(player.global_position) > npc.reach_px + REACH_SLACK:
		return null
	return npc


func _refresh_map() -> void:
	var map: Node = _world.call("get_active_map") if _world != null else null
	if map != null and map.has_method("refresh_interactables"):
		map.call("refresh_interactables")


func _registry() -> CharacterRegistry:
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.call("get_character_registry") as CharacterRegistry


func _player() -> Node2D:
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.call("get_player") as Node2D


func _clear_status() -> void:
	_status_key = &""
	_status_args = {}
	_status_is_refusal = false


# --- Persistence boundary -------------------------------------------------------

func to_dict() -> Dictionary:
	return _service.state().to_dict() if _service != null else {}


## Restore shop stock. Atomic: a rejected payload changes nothing.
func from_dict(data: Dictionary) -> bool:
	if not _session_active or not _service.state().from_dict(data, _service.catalog()):
		return false
	view_changed.emit()
	return true

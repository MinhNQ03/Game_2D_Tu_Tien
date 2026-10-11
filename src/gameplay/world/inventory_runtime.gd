extends Node
class_name InventoryRuntime
## InventoryRuntime — Aetheria gameplay (the bag in a running session, Phase 13).
##
## Per-session node under `Main/Systems` (no autoload). It owns the player's `InventoryState` and
## the authored `ItemCatalogData`, collects `WorldItem`s the player walks onto, and USES items by
## asking the system that owns each effect:
##
##   HEAL      → the player's own `heal()` (the body owns its health);
##   ABSORB_QI → `CultivationService.gather()` through the cultivation runtime (the cultivation
##               authority decides the tu vi; a body without a method absorbs nothing);
##   READ      → `KnowledgeRuntime.grant()` (the Knowledge Core owns what is known).
##
## An item is consumed only when its effect actually happened: a pill at full health, a stone
## on a full step, a manual already understood — each is REFUSED with a reason the HUD can say,
## and kept. That is the sink rule kept honest (`ECONOMY_CRAFTING_DESIGN.md`): a use that does
## nothing must not burn the item.
##
## PERSISTENCE: `to_dict()` = SAVE_FORMAT `inventory.items` plus the collected pickup ids.

signal item_gained(item_id: StringName, count: int)
signal item_used(item_id: StringName)
signal use_refused(item_id: StringName, reason_key: StringName)
signal inventory_changed()
## The player stepped onto something that is not theirs to take yet. Emitted once per
## approach, not every tick they stand there.
signal pickup_withheld(pickup_id: StringName, reason_key: StringName)

const CATALOG_PATH := "res://data/items/item_catalog.tres"

const REFUSE_NOT_HELD := &"UI_ITEM_NOT_HELD"
const REFUSE_NOT_USABLE := &"UI_ITEM_NOT_USABLE"
const REFUSE_FULL_HEALTH := &"UI_ITEM_FULL_HEALTH"
const REFUSE_NO_METHOD := &"UI_ITEM_NO_METHOD"
const REFUSE_STEP_FULL := &"UI_ITEM_STEP_FULL"
const REFUSE_ALREADY_KNOWN := &"UI_ITEM_ALREADY_KNOWN"
const REFUSE_BAG_FULL := &"UI_ITEM_BAG_FULL"

## The knowledge a body needs to absorb qi from a stone: the same breathing method a vein needs.
const ABSORB_METHOD := &"know_dan_khi_quyet"

var _catalog: ItemCatalogData = null
var _bag: InventoryState = null
var _character: CharacterState = null
var _world: Node = null
var _knowledge: KnowledgeRuntime = null
var _cultivation: CultivationRuntime = null
var _collected: Dictionary = {}
## `flag_id -> bool`: has the story handed this over? Given by the session once the story
## runs. FAIL CLOSED: with nobody to ask, a held item stays held.
var _flag_holds: Callable = Callable()
## The held pickup the player is standing on (so the refusal is said once per approach).
var _standing_on_held: StringName = &""
var _session_active: bool = false


func _ready() -> void:
	set_physics_process(false)


func start_session(character: CharacterState, world: Node, knowledge: KnowledgeRuntime,
		cultivation: CultivationRuntime) -> bool:
	if _session_active:
		push_error("[inventory-rt] start_session while a session is active")
		return false
	if character == null or world == null or knowledge == null or cultivation == null:
		push_error("[inventory-rt] inventory session NOT started: a dependency is missing")
		return false
	var catalog := load(CATALOG_PATH) as ItemCatalogData
	if catalog == null or not catalog.is_valid():
		push_error("[inventory-rt] inventory session NOT started: the item catalog is invalid: %s"
			% (str(catalog.validation_errors()) if catalog != null else "missing"))
		return false
	_catalog = catalog
	_bag = InventoryState.new()
	_character = character
	_world = world
	_knowledge = knowledge
	_cultivation = cultivation
	_collected = {}
	_session_active = true
	set_physics_process(true)
	return true


func end_session() -> void:
	set_physics_process(false)
	_flag_holds = Callable()
	_standing_on_held = &""
	_catalog = null
	_bag = null
	_character = null
	_world = null
	_knowledge = null
	_cultivation = null
	_collected.clear()
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_catalog() -> ItemCatalogData:
	return _catalog


func get_bag() -> InventoryState:
	return _bag


func count_of(item_id: StringName) -> int:
	return _bag.count_of(item_id) if _bag != null else 0


func is_collected(pickup_id: StringName) -> bool:
	return _collected.has(pickup_id)


## Add `count` of `item_id` (a pickup, a reward). Returns how many fit.
func give(item_id: StringName, count: int) -> int:
	if not _session_active:
		return 0
	var item := _catalog.entry(item_id)
	if item == null:
		push_error("[inventory-rt] refusing to give unknown item '%s'" % item_id)
		return 0
	var added := _bag.add(item, count)
	if added > 0:
		item_gained.emit(item_id, added)
		inventory_changed.emit()
	if added < count:
		use_refused.emit(item_id, REFUSE_BAG_FULL)
	return added


## Remove `count` of `item_id` WITHOUT using it (equipping moves an item out of the bag).
func take(item_id: StringName, count: int) -> bool:
	if not _session_active or not _bag.remove(item_id, count):
		return false
	inventory_changed.emit()
	return true


## Remove `take` and add `give` ({ item_id -> count } each) as ONE all-or-nothing change of the
## bag (a trade: coin out and goods in, or neither). False — and nothing changed, nothing
## emitted — for an unknown id, a shortfall or a full bag. A trade is not a pickup: the party
## that asked reports it, so only `inventory_changed` is emitted here.
func exchange(take: Dictionary, give: Dictionary) -> bool:
	if not _session_active:
		return false
	var resolved: Dictionary = {}
	for item_id: Variant in give:
		var item := _catalog.entry(item_id)
		if item == null:
			push_error("[inventory-rt] refusing an exchange giving unknown item '%s'" % item_id)
			return false
		resolved[item] = give[item_id]
	if not _bag.exchange(take, resolved):
		return false
	inventory_changed.emit()
	return true


## Use one `item_id`. Returns &"" on success, else the refusal's localization key (also emitted).
func use(item_id: StringName) -> StringName:
	if not _session_active:
		return REFUSE_NOT_HELD
	var item := _catalog.entry(item_id)
	if item == null or _bag.count_of(item_id) < 1:
		return _refuse(item_id, REFUSE_NOT_HELD)
	var reason := &""
	match item.use_kind:
		ItemData.UseKind.HEAL:
			reason = _use_heal(item)
		ItemData.UseKind.ABSORB_QI:
			reason = _use_absorb(item)
		ItemData.UseKind.READ:
			reason = _use_read(item)
		_:
			reason = REFUSE_NOT_USABLE
	if reason != &"":
		return _refuse(item_id, reason)
	_bag.remove(item_id, 1)
	item_used.emit(item_id)
	inventory_changed.emit()
	return &""


func _use_heal(item: ItemData) -> StringName:
	var player: Node = _world.call("get_player")
	if player == null or not player.has_method("heal"):
		return REFUSE_NOT_USABLE
	if int(player.call("get_current_health")) >= int(player.call("get_max_health")):
		return REFUSE_FULL_HEALTH
	player.call("heal", item.use_amount)
	return &""


func _use_absorb(item: ItemData) -> StringName:
	if not _knowledge.get_service().knows(ABSORB_METHOD):
		return REFUSE_NO_METHOD
	var service := _cultivation.get_service()
	var efficiency := service.gather_efficiency(_character)
	var amount := maxi(1, int(round(float(item.use_amount) * efficiency)))
	var result := service.gather(_character, amount)
	if not result.accepted:
		return REFUSE_STEP_FULL
	_cultivation.view_changed.emit()
	return &""


func _use_read(item: ItemData) -> StringName:
	var learned := _knowledge.read_source(item.id, item.teaches)
	return &"" if not learned.is_empty() else REFUSE_ALREADY_KNOWN


func _refuse(item_id: StringName, reason: StringName) -> StringName:
	use_refused.emit(item_id, reason)
	return reason


func _physics_process(_delta: float) -> void:
	tick()


## Who answers "has story flag X been set" for held pickups (`WorldItem.held_by_flag`).
func set_pickup_gate(flag_holds: Callable) -> void:
	_flag_holds = flag_holds


func _flag_is_set(flag_id: StringName) -> bool:
	return _flag_holds.is_valid() and bool(_flag_holds.call(flag_id))


func _is_held(pickup: WorldItem) -> bool:
	return pickup.held_by_flag != &"" and not _flag_is_set(pickup.held_by_flag)


## Collect every pickup of the active map the player stands on (public for tests).
func tick() -> void:
	if not _session_active:
		return
	var map: Node = _world.call("get_active_map")
	var player := _world.call("get_player") as Node2D
	if map == null or player == null:
		return
	var host := map.get_node_or_null("Pickups")
	if host == null:
		return
	var held_under: StringName = &""
	for child in host.get_children():
		var pickup := child as WorldItem
		if pickup == null:
			continue
		if pickup.appears_with_flag != &"" and not _collected.has(pickup.pickup_id):
			pickup.visible = _flag_is_set(pickup.appears_with_flag)
		if not pickup.visible:
			continue
		if _collected.has(pickup.pickup_id):
			pickup.visible = false
			continue
		if pickup.appears_with_flag != &"" and not _flag_is_set(pickup.appears_with_flag):
			continue  # not in the world yet
		if pickup.reaches(player.global_position) and pickup.item != null:
			if _is_held(pickup):
				held_under = pickup.pickup_id
				if _standing_on_held != pickup.pickup_id:
					pickup_withheld.emit(pickup.pickup_id, pickup.held_reason_key)
				continue
			if give(pickup.item.id, pickup.count) > 0:
				_collected[pickup.pickup_id] = true
				pickup.visible = false
	_standing_on_held = held_under


func to_dict() -> Dictionary:
	if _bag == null:
		return {}
	var out := _bag.to_dict()
	var ids: Array = []
	for key: StringName in _collected:
		ids.append(String(key))
	out["collected"] = ids
	return out


func from_dict(data: Dictionary) -> bool:
	if not _session_active or not _bag.from_dict(data, _catalog):
		return false
	_collected = {}
	for raw: Variant in data.get("collected", []):
		if typeof(raw) == TYPE_STRING:
			_collected[StringName(raw)] = true
	inventory_changed.emit()
	return true

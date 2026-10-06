extends Node
class_name EquipmentRuntime
## EquipmentRuntime — Aetheria gameplay (wearing and wielding in a running session, Phase 14).
##
## Per-session node after `InventoryRuntime` in the start order. Equipping MOVES an item from the
## satchel into its slot (whatever was there goes back into the satchel), and the player is told
## what it now wears through ONE call (`Player.apply_equipment`): the summed stat bonus (which
## enters the existing damage formula), the weapon's attack, the garment's drawing. A realm gate
## on the equipment is read through `CultivationService.meets` — the same comparison every gate
## uses.

signal equipment_changed()
signal equip_refused(item_id: StringName, reason_key: StringName)

const REFUSE_NOT_EQUIPMENT := &"UI_EQUIP_NOT_EQUIPMENT"
const REFUSE_REALM := &"UI_EQUIP_REALM"
const REFUSE_BAG_FULL := &"UI_ITEM_BAG_FULL"
const REFUSE_BUSY := &"UI_EQUIP_BUSY"

var _state: EquipmentState = null
var _inventory: InventoryRuntime = null
var _cultivation: CultivationRuntime = null
var _character: CharacterState = null
var _world: Node = null
var _session_active: bool = false


func start_session(character: CharacterState, world: Node, inventory: InventoryRuntime,
		cultivation: CultivationRuntime) -> bool:
	if _session_active or character == null or world == null or inventory == null \
			or cultivation == null or not inventory.is_session_active():
		push_error("[equipment-rt] equipment session NOT started: a dependency is missing")
		return false
	_state = EquipmentState.new()
	_inventory = inventory
	_cultivation = cultivation
	_character = character
	_world = world
	_session_active = true
	return true


func end_session() -> void:
	_state = null
	_inventory = null
	_cultivation = null
	_character = null
	_world = null
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_state() -> EquipmentState:
	return _state


func is_worn(item_id: StringName) -> bool:
	return _session_active and _state.is_worn(item_id)


## Equip `item_id` from the satchel. Returns &"" or the refusal's key (also emitted).
func equip(item_id: StringName) -> StringName:
	if not _session_active:
		return REFUSE_NOT_EQUIPMENT
	var item := _inventory.get_catalog().entry(item_id)
	if item == null or item.category != ItemData.Category.EQUIPMENT \
			or _inventory.count_of(item_id) < 1:
		return _refuse(item_id, REFUSE_NOT_EQUIPMENT)
	var equipment := item.equipment as EquipmentData
	if not _cultivation.get_service().meets(_character, equipment.required_realm,
			equipment.required_layer):
		return _refuse(item_id, REFUSE_REALM)
	if _player_busy():
		return _refuse(item_id, REFUSE_BUSY)
	var previous := _state.item_in(equipment.slot)
	_inventory.take(item_id, 1)
	if previous != &"":
		_inventory.give(previous, 1)
	_state.set_slot(equipment.slot, item_id)
	_apply()
	return &""


## Take off what is in `slot`, back into the satchel. Refused if the satchel has no room.
func unequip(slot: int) -> StringName:
	if not _session_active:
		return REFUSE_NOT_EQUIPMENT
	var item_id := _state.item_in(slot)
	if item_id == &"":
		return &""
	if _player_busy():
		return _refuse(item_id, REFUSE_BUSY)
	if _inventory.give(item_id, 1) < 1:
		return _refuse(item_id, REFUSE_BAG_FULL)
	_state.set_slot(slot, &"")
	_apply()
	return &""


## Unequip whichever slot holds `item_id`.
func unequip_item(item_id: StringName) -> StringName:
	for slot in [EquipmentData.Slot.WEAPON, EquipmentData.Slot.BODY]:
		if _state.item_in(slot) == item_id:
			return unequip(slot)
	return &""


## The equipment worn, as data (for presentation and tests).
func worn(slot: int) -> EquipmentData:
	var item_id := _state.item_in(slot) if _session_active else &""
	if item_id == &"":
		return null
	var item := _inventory.get_catalog().entry(item_id)
	return item.equipment as EquipmentData if item != null else null


func _apply() -> void:
	var attack_bonus := 0
	var defense_bonus := 0
	for slot in [EquipmentData.Slot.WEAPON, EquipmentData.Slot.BODY]:
		var equipment := worn(slot)
		if equipment != null:
			attack_bonus += equipment.attack_bonus
			defense_bonus += equipment.defense_bonus
	var weapon := worn(EquipmentData.Slot.WEAPON)
	var body := worn(EquipmentData.Slot.BODY)
	var attack: AttackData = weapon.attack if weapon != null else load(
		"res://data/combat/attack_player_basic.tres")
	var player: Node = _world.call("get_player")
	if player != null and player.has_method("apply_equipment"):
		player.call("apply_equipment", attack_bonus, defense_bonus, attack,
			body.body_visual if body != null else null)
	equipment_changed.emit()


func _player_busy() -> bool:
	var player: Node = _world.call("get_player")
	if player == null:
		return false
	var attack := player.get_node_or_null("AttackComponent") as AttackComponent
	return attack != null and attack.state() != AttackStateMachine.State.READY


func _refuse(item_id: StringName, reason: StringName) -> StringName:
	equip_refused.emit(item_id, reason)
	return reason


func to_dict() -> Dictionary:
	return _state.to_dict() if _state != null else {}


func from_dict(data: Dictionary) -> bool:
	if not _session_active or not _state.from_dict(data, _inventory.get_catalog()):
		return false
	_apply()
	return true

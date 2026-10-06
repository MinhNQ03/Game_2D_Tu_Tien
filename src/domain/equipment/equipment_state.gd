extends RefCounted
class_name EquipmentState
## EquipmentState — Aetheria domain (what the player wears, Phase 14).
##
## One item id per slot (`EquipmentData.Slot`), SAVE_FORMAT `equipment.slots`. Pure data and its
## persistence boundary; `EquipmentRuntime` decides what goes in.

var _slots: Dictionary = {}  # Slot (int) -> item id (StringName)


func item_in(slot: int) -> StringName:
	return _slots.get(slot, &"")


func set_slot(slot: int, item_id: StringName) -> void:
	if item_id == &"":
		_slots.erase(slot)
	else:
		_slots[slot] = item_id


func is_worn(item_id: StringName) -> bool:
	return item_id != &"" and _slots.values().has(item_id)


func worn_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for slot: int in _slots:
		out.append(_slots[slot])
	return out


func to_dict() -> Dictionary:
	var slots := {}
	for slot: int in _slots:
		slots[str(slot)] = String(_slots[slot])
	return {"slots": slots}


## Validated against `catalog`: each slot must hold an EQUIPMENT item made for that slot.
func from_dict(data: Dictionary, catalog: ItemCatalogData) -> bool:
	var slots: Variant = data.get("slots", {})
	if typeof(slots) != TYPE_DICTIONARY:
		return false
	var staged := {}
	for key: Variant in slots:
		if typeof(key) != TYPE_STRING or not String(key).is_valid_int():
			return false
		var raw: Variant = slots[key]
		if typeof(raw) != TYPE_STRING:
			return false
		var item := catalog.entry(StringName(raw)) if catalog != null else null
		if item == null or item.category != ItemData.Category.EQUIPMENT:
			return false
		var equipment := item.equipment as EquipmentData
		if equipment == null or int(equipment.slot) != int(String(key)):
			return false
		staged[int(String(key))] = item.id
	_slots = staged
	return true

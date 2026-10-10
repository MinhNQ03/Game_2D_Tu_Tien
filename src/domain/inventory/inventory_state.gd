extends RefCounted
class_name InventoryState
## InventoryState — Aetheria domain (what the player carries, Phase 13).
##
## Ordered stacks of `{item_id, count}` in a bounded bag (`capacity` stacks). Every change goes
## through `add` / `remove`, which keep the invariants: a stack never exceeds its item's
## `stack_max`, never holds 0, and the bag never holds more than `capacity` stacks. Pure data and
## its persistence boundary (SAVE_FORMAT `inventory.items`); `InventoryRuntime` decides WHEN.

const DEFAULT_CAPACITY := 24

var capacity: int = DEFAULT_CAPACITY
## Array of { "item_id": StringName, "count": int }, in the order they were first acquired.
var _stacks: Array[Dictionary] = []


## Add up to `count` of `item`, topping up existing stacks first. Returns how many fit (0 when
## the bag is full) — the caller decides what to do with the rest.
func add(item: ItemData, count: int) -> int:
	if item == null or count <= 0:
		return 0
	var left := count
	for stack in _stacks:
		if stack["item_id"] == item.id and int(stack["count"]) < item.stack_max:
			var room := item.stack_max - int(stack["count"])
			var put := mini(room, left)
			stack["count"] = int(stack["count"]) + put
			left -= put
			if left == 0:
				return count
	while left > 0 and _stacks.size() < capacity:
		var put := mini(item.stack_max, left)
		_stacks.append({"item_id": item.id, "count": put})
		left -= put
	return count - left


## Remove `count` of `item_id`, from the LAST stacks first. All-or-nothing: false (and no
## change) when fewer are held.
func remove(item_id: StringName, count: int) -> bool:
	if count <= 0 or count_of(item_id) < count:
		return false
	var left := count
	for i in range(_stacks.size() - 1, -1, -1):
		if _stacks[i]["item_id"] != item_id:
			continue
		var take := mini(int(_stacks[i]["count"]), left)
		_stacks[i]["count"] = int(_stacks[i]["count"]) - take
		left -= take
		if int(_stacks[i]["count"]) == 0:
			_stacks.remove_at(i)
		if left == 0:
			break
	return true


## Remove `take` and add `give` as ONE change, or change nothing (Phase 17: a purchase is coin
## out and goods in; half of it must never happen). `take` is { item_id -> count }, `give` is
## { ItemData -> count }. Staged on a copy of the stacks — removals first, so coin leaving the
## bag can free the slot the goods need — and committed only when every removal was held and
## every addition fitted. False (and no change) for a non-positive count, a null item, a
## shortfall or a full bag.
func exchange(take: Dictionary, give: Dictionary) -> bool:
	var committed := _stacks
	_stacks = _stacks.duplicate(true)
	var ok := true
	for item_id: Variant in take:
		if typeof(take[item_id]) != TYPE_INT or not remove(item_id, int(take[item_id])):
			ok = false
			break
	if ok:
		for item: Variant in give:
			var data := item as ItemData
			if data == null or typeof(give[item]) != TYPE_INT or int(give[item]) <= 0 \
					or add(data, int(give[item])) != int(give[item]):
				ok = false
				break
	if not ok:
		_stacks = committed
	return ok


func count_of(item_id: StringName) -> int:
	var total := 0
	for stack in _stacks:
		if stack["item_id"] == item_id:
			total += int(stack["count"])
	return total


## The distinct item ids held, in first-acquired order (what an inventory panel lists).
func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for stack in _stacks:
		if not out.has(stack["item_id"]):
			out.append(stack["item_id"])
	return out


func stack_count() -> int:
	return _stacks.size()


func to_dict() -> Dictionary:
	var items: Array = []
	for stack in _stacks:
		items.append({"item_id": String(stack["item_id"]), "count": int(stack["count"])})
	return {"items": items}


## Hydrate from `to_dict()` output, validated against `catalog` (L-024 type checks; unknown ids,
## a stack over its maximum or a count < 1 reject the WHOLE payload, leaving the bag unchanged).
func from_dict(data: Dictionary, catalog: ItemCatalogData) -> bool:
	var rows: Variant = data.get("items", [])
	if typeof(rows) != TYPE_ARRAY:
		push_error("[inventory] from_dict: 'items' must be an Array")
		return false
	var staged: Array[Dictionary] = []
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			push_error("[inventory] from_dict: a row is not a Dictionary")
			return false
		var raw_id: Variant = (row as Dictionary).get("item_id")
		var raw_count: Variant = (row as Dictionary).get("count")
		if typeof(raw_id) != TYPE_STRING or typeof(raw_count) != TYPE_INT:
			push_error("[inventory] from_dict: item_id must be a String and count an int")
			return false
		var item := catalog.entry(StringName(raw_id)) if catalog != null else null
		if item == null:
			push_error("[inventory] from_dict: '%s' is not in the item catalog" % raw_id)
			return false
		if int(raw_count) < 1 or int(raw_count) > item.stack_max:
			push_error("[inventory] from_dict: '%s' count %d outside [1, %d]"
				% [raw_id, raw_count, item.stack_max])
			return false
		staged.append({"item_id": item.id, "count": int(raw_count)})
	if staged.size() > capacity:
		push_error("[inventory] from_dict: %d stacks exceed the capacity %d"
			% [staged.size(), capacity])
		return false
	_stacks = staged
	return true

extends RefCounted
class_name InventoryView
## InventoryView — Aetheria presentation DTO (what the bag shows, Phase 13). Built by
## `WorldRuntime` from the `InventoryRuntime` and pushed to the HUD; keys, icons and numbers only.

## One row per distinct item held, in first-acquired order:
## { "item_id": StringName, "name_key": StringName, "desc_key": StringName,
##   "icon": Texture2D, "count": int, "usable": bool }
var rows: Array[Dictionary] = []


static func make(runtime: InventoryRuntime) -> InventoryView:
	var view := InventoryView.new()
	if runtime == null or not runtime.is_session_active():
		return view
	var catalog := runtime.get_catalog()
	for item_id in runtime.get_bag().item_ids():
		var item := catalog.entry(item_id)
		if item == null:
			continue
		view.rows.append({
			"item_id": item.id, "name_key": item.name_key, "desc_key": item.desc_key,
			"icon": item.icon, "count": runtime.count_of(item.id),
			"usable": item.use_kind != ItemData.UseKind.NONE
				or item.category == ItemData.Category.EQUIPMENT,
		})
	return view

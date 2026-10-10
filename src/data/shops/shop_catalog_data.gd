extends Resource
class_name ShopCatalogData
## ShopCatalogData — Aetheria data (every shop, and what they are paid in, Phase 17).
##
## THE CURRENCY IS AN ITEM. `currency_item` is the one item shops price in — linh thạch, which
## the player already carries in the bag (Phase 13). The player's funds are therefore the
## count of that item in `InventoryState`: there is no separate wallet number to keep in step
## with a stack the player can also pick up, absorb and count (D-065).

@export var currency_item: ItemData = null
@export var entries: Array[ShopData] = []


func entry(shop_id: StringName) -> ShopData:
	for shop in entries:
		if shop != null and shop.id == shop_id:
			return shop
	return null


func has(shop_id: StringName) -> bool:
	return entry(shop_id) != null


## The shop `keeper_id` keeps, or null. One keeper keeps at most one shop (validated).
func shop_of_keeper(keeper_id: StringName) -> ShopData:
	for shop in entries:
		if shop != null and shop.keeper_id == keeper_id:
			return shop
	return null


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if currency_item == null or currency_item.id == &"":
		errors.append("currency_item is missing")
	if entries.is_empty():
		errors.append("the shop catalog is empty")
	var ids: Dictionary = {}
	var keepers: Dictionary = {}
	for i in entries.size():
		var shop := entries[i]
		if shop == null:
			errors.append("entry %d is null" % i)
			continue
		for problem in shop.validation_errors():
			errors.append("%s: %s" % [shop.id, problem])
		if ids.has(shop.id):
			errors.append("duplicate shop id '%s'" % shop.id)
		ids[shop.id] = true
		if keepers.has(shop.keeper_id):
			errors.append("'%s' keeps two shops" % shop.keeper_id)
		keepers[shop.keeper_id] = true
		if currency_item != null and shop.entry_for(currency_item.id) != null:
			errors.append("%s trades the currency itself" % shop.id)
	return errors

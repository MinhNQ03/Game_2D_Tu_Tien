extends RefCounted
class_name ShopState
## ShopState — Aetheria domain (what the shops have LEFT, Phase 17).
##
## The only thing about a shop that changes: the remaining count of each FINITE-stock entry.
## Unlimited entries are not stored (there is nothing to remember). Separate from `ShopData`
## on purpose — content is authored, this is saved (SAVE_FORMAT `shops`). `ShopService` is its
## only writer.

const SCHEMA := 1

## shop_id(StringName) -> { item_id(StringName) -> remaining(int) }, finite entries only.
var _stock: Dictionary = {}


## Start every finite entry at its authored stock.
func seed_from(catalog: ShopCatalogData) -> void:
	_stock = _authored(catalog)


## Remaining count of a finite entry; `ShopEntryData.UNLIMITED` for one that is not tracked.
func remaining(shop_id: StringName, item_id: StringName) -> int:
	var shop: Dictionary = _stock.get(shop_id, {})
	return int(shop.get(item_id, ShopEntryData.UNLIMITED))


func set_remaining(shop_id: StringName, item_id: StringName, count: int) -> void:
	if not _stock.has(shop_id):
		_stock[shop_id] = {}
	(_stock[shop_id] as Dictionary)[item_id] = count


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for shop_id: StringName in _stock:
		var row: Dictionary = {}
		for item_id: StringName in _stock[shop_id]:
			row[String(item_id)] = int(_stock[shop_id][item_id])
		out[String(shop_id)] = row
	return {"schema": SCHEMA, "stock": out}


## Hydrate from `to_dict()` output, validated against `catalog`. Staged and atomic: the payload
## must name exactly the finite entries the catalog authors (an unknown shop or item, a missing
## one, an unlimited entry given a count, a non-int or out-of-range count all reject it) and a
## rejected payload leaves this state untouched.
func from_dict(data: Dictionary, catalog: ShopCatalogData) -> bool:
	if catalog == null:
		return _reject("no shop catalog to validate against")
	if typeof(data.get("schema")) != TYPE_INT or int(data["schema"]) != SCHEMA:
		return _reject("schema must be the int %d" % SCHEMA)
	var raw: Variant = data.get("stock")
	if typeof(raw) != TYPE_DICTIONARY:
		return _reject("'stock' must be a Dictionary")
	var expected := _authored(catalog)
	var staged: Dictionary = {}
	for raw_shop: Variant in (raw as Dictionary):
		if typeof(raw_shop) != TYPE_STRING:
			return _reject("a shop key is not a String")
		var shop_id := StringName(String(raw_shop))
		if not expected.has(shop_id):
			return _reject("'%s' is not a shop with finite stock" % shop_id)
		var rows: Variant = (raw as Dictionary)[raw_shop]
		if typeof(rows) != TYPE_DICTIONARY:
			return _reject("the stock of '%s' is not a Dictionary" % shop_id)
		var staged_shop: Dictionary = {}
		for raw_item: Variant in (rows as Dictionary):
			if typeof(raw_item) != TYPE_STRING:
				return _reject("an item key in '%s' is not a String" % shop_id)
			var item_id := StringName(String(raw_item))
			if not (expected[shop_id] as Dictionary).has(item_id):
				return _reject("'%s' has no finite entry '%s'" % [shop_id, item_id])
			var count: Variant = (rows as Dictionary)[raw_item]
			if typeof(count) != TYPE_INT or int(count) < 0 \
					or int(count) > ShopEntryData.MAX_STOCK:
				return _reject("'%s'/'%s' has an invalid count (%s)"
					% [shop_id, item_id, str(count)])
			staged_shop[item_id] = int(count)
		if staged_shop.size() != (expected[shop_id] as Dictionary).size():
			return _reject("'%s' is missing a finite entry" % shop_id)
		staged[shop_id] = staged_shop
	if staged.size() != expected.size():
		return _reject("a shop with finite stock is missing")
	_stock = staged
	return true


static func _authored(catalog: ShopCatalogData) -> Dictionary:
	var out: Dictionary = {}
	if catalog == null:
		return out
	for shop in catalog.entries:
		if shop == null:
			continue
		var row: Dictionary = {}
		for entry in shop.entries:
			if entry != null and entry.item != null and not entry.is_unlimited():
				row[entry.item.id] = entry.stock
		if not row.is_empty():
			out[shop.id] = row
	return out


func _reject(reason: String) -> bool:
	push_error("[shop-state] from_dict rejected: %s" % reason)
	return false

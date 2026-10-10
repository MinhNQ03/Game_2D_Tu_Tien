extends Resource
class_name ShopData
## ShopData — Aetheria data (one shop's authored definition, Phase 17).
##
## CONTENT: who keeps it, what it trades, at what base prices, and how the keeper's regard for
## the customer moves those prices. A new shop is a new `.tres` in the `ShopCatalogData` — never
## a branch in a runtime. It holds nothing that changes: remaining stock is `ShopState`.
##
## PRICING BY STANDING. `price_dimension` names ONE dimension of the relationship graph (the
## keeper's edge with the customer, `docs/RELATIONSHIP_SYSTEM.md`). At that dimension's neutral
## value — which is also what a customer the keeper has no edge with gets — prices are the base
## prices. Above neutral they fall linearly to `max_discount_percent` at the dimension's
## maximum; below neutral they rise linearly to `max_markup_percent` at its minimum (a
## dimension that cannot go below neutral, such as `trust`, can only ever discount).
## What the shop PAYS for goods is `sell_percent` of base, moved the opposite way (a friend is
## paid more). `validation_errors` rejects any setting under which a customer could sell an
## item for more than it costs to buy back, at any standing.

@export var id: StringName = &""
@export var name_key: StringName = &""
## The CHARACTER who keeps it: an `instance_id` in the session's `CharacterRegistry`.
@export var keeper_id: StringName = &""
@export var entries: Array[ShopEntryData] = []

## The relationship dimension that moves prices. Empty = prices never move.
@export var price_dimension: StringName = &"affinity"
## Percent off at the dimension's maximum.
@export_range(0, 90) var max_discount_percent: int = 20
## Percent added at the dimension's minimum.
@export_range(0, 200) var max_markup_percent: int = 30
## What the shop pays for an item it buys, as a percent of base price, at neutral standing.
@export_range(1, 100) var sell_percent: int = 40


func entry_for(item_id: StringName) -> ShopEntryData:
	for entry in entries:
		if entry != null and entry.item != null and entry.item.id == item_id:
			return entry
	return null


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	elif not String(id).begins_with("shop_"):
		errors.append("id '%s' must use the shop_ prefix" % id)
	if name_key == &"":
		errors.append("name_key is empty")
	if keeper_id == &"":
		errors.append("keeper_id is empty (a shop is kept by a character)")
	if entries.is_empty():
		errors.append("a shop with no entries trades nothing")
	var seen: Dictionary = {}
	for i in entries.size():
		var entry := entries[i]
		if entry == null:
			errors.append("entry %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("entry %d: %s" % [i, problem])
		if entry.item != null:
			if seen.has(entry.item.id):
				errors.append("item '%s' is listed twice" % entry.item.id)
			seen[entry.item.id] = true
	if max_discount_percent < 0 or max_discount_percent > 90:
		errors.append("max_discount_percent must be in [0, 90] (got %d)" % max_discount_percent)
	if max_markup_percent < 0 or max_markup_percent > 200:
		errors.append("max_markup_percent must be in [0, 200] (got %d)" % max_markup_percent)
	if sell_percent < 1 or sell_percent > 100:
		errors.append("sell_percent must be in [1, 100] (got %d)" % sell_percent)
	# NO ARBITRAGE at the best standing: paid = base*sell*(100+D)/10000 must stay strictly
	# under the price = base*(100-D)/100, for every base.
	elif sell_percent * (100 + max_discount_percent) >= 100 * (100 - max_discount_percent):
		errors.append(("sell_percent %d with max_discount_percent %d lets a well-liked customer "
			+ "sell for at least what it costs to buy back") % [sell_percent, max_discount_percent])
	return errors

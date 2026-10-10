extends Resource
class_name ShopEntryData
## ShopEntryData — Aetheria data (one line of a shop's ledger, Phase 17).
##
## What a shop will trade and at what BASE price. The price a player actually pays is the base
## adjusted by standing (`ShopData`, `ShopService`); nothing here changes at runtime — the
## shop's remaining stock lives in `ShopState`.

## Stock value meaning "never runs out".
const UNLIMITED := -1
## A sanity ceiling on authored numbers, far below any integer overflow of price x quantity.
const MAX_PRICE := 100000
const MAX_STOCK := 9999

@export var item: ItemData = null
## What the item is worth before standing: whole units of the shop's currency, > 0.
@export var base_price: int = 1
## What the shop starts with: `UNLIMITED`, or a finite count >= 0 (0 = it only buys this).
@export var stock: int = UNLIMITED
## The shop buys this item from the player.
@export var buys: bool = true


func is_unlimited() -> bool:
	return stock == UNLIMITED


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if item == null:
		errors.append("item is null")
	elif item.id == &"":
		errors.append("item has no id")
	if base_price <= 0:
		errors.append("base_price must be > 0 (got %d)" % base_price)
	elif base_price > MAX_PRICE:
		errors.append("base_price %d exceeds the ceiling %d" % [base_price, MAX_PRICE])
	if stock < UNLIMITED:
		errors.append("stock must be %d (unlimited) or >= 0 (got %d)" % [UNLIMITED, stock])
	elif stock > MAX_STOCK:
		errors.append("stock %d exceeds the ceiling %d" % [stock, MAX_STOCK])
	if stock == 0 and not buys:
		errors.append("an entry with no stock that the shop does not buy can never trade")
	return errors

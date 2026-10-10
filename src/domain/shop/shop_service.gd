extends RefCounted
class_name ShopService
## ShopService — Aetheria domain (the rules of trading with a shop, Phase 17).
##
## Node-free and scene-free. It PRICES (base price moved by standing), PLANS a purchase or a
## sale (every check that can refuse it, with no mutation at all) and COMMITS one (the only
## writer of `ShopState`). It never touches the player's bag itself: a transaction's goods and
## coin move through an `exchange` the inventory's owner provides, which is all-or-nothing.
##
## ATOMICITY. `transact(plan, exchange)`:
##   1. the plan was fully validated by `plan_buy` / `plan_sell` (ids, quantity, stock, funds or
##      holdings) — a refused plan stops here, nothing touched;
##   2. the plan is re-checked against the stock it was made from (a stale plan is refused);
##   3. `exchange(take, give)` moves coin and goods in the bag atomically, or returns false
##      (no room) having changed nothing — then the shop's stock is not touched either;
##   4. only after the bag has changed is the stock written, which cannot fail.
## A plan can be transacted once: a second attempt is refused, so a repeated confirm can never
## charge or pay twice.

const REFUSE_UNKNOWN_SHOP := &"UI_SHOP_UNKNOWN"
const REFUSE_NOT_TRADED := &"UI_SHOP_NOT_TRADED"
const REFUSE_NOT_BOUGHT := &"UI_SHOP_NOT_BOUGHT"
const REFUSE_QUANTITY := &"UI_SHOP_BAD_QUANTITY"
const REFUSE_OUT_OF_STOCK := &"UI_SHOP_OUT_OF_STOCK"
const REFUSE_NO_FUNDS := &"UI_SHOP_NO_FUNDS"
const REFUSE_NOT_HELD := &"UI_SHOP_NOT_HELD"
const REFUSE_NO_ROOM := &"UI_SHOP_NO_ROOM"
const REFUSE_STOCK_FULL := &"UI_SHOP_STOCK_FULL"
const REFUSE_STALE := &"UI_SHOP_STALE"

const KIND_BUY := &"buy"
const KIND_SELL := &"sell"

## The most of one item a single transaction may move. Keeps `price x quantity` far inside the
## integer range (100 000 x 99) and matches the largest stack an item may have.
const MAX_QUANTITY := 99
## Basis points in a whole (percent x 100): standing is interpolated at this precision so a
## small regard still moves a large price.
const BASIS := 10000

var _catalog: ShopCatalogData = null
var _state: ShopState = null


func _init(catalog: ShopCatalogData = null, state: ShopState = null) -> void:
	if catalog == null or state == null:
		return
	if not catalog.is_valid():
		push_error("[shop] refusing an invalid shop catalog: %s"
			% str(catalog.validation_errors()))
		return
	_catalog = catalog
	_state = state


func is_ready() -> bool:
	return _catalog != null and _state != null


func catalog() -> ShopCatalogData:
	return _catalog


func state() -> ShopState:
	return _state


func currency_id() -> StringName:
	return _catalog.currency_item.id if is_ready() else &""


# --- Pricing ------------------------------------------------------------------

## How standing moves this shop's prices, in basis points: negative = cheaper, positive =
## dearer, 0 at neutral or with no `price_dimension`. Linear from neutral to each bound and
## CLAMPED there — a value outside the dimension's range prices as the bound, never beyond.
static func modifier_basis(shop: ShopData, standing: ShopStanding) -> int:
	if shop == null or standing == null or shop.price_dimension == &"":
		return 0
	var value := clampi(standing.value, standing.minimum, standing.maximum)
	if value > standing.neutral and standing.maximum > standing.neutral:
		return -(shop.max_discount_percent * 100 * (value - standing.neutral)) \
			/ (standing.maximum - standing.neutral)
	if value < standing.neutral and standing.minimum < standing.neutral:
		return (shop.max_markup_percent * 100 * (standing.neutral - value)) \
			/ (standing.neutral - standing.minimum)
	return 0


## What ONE of an entry costs the customer: base moved by standing, rounded UP, never under 1.
static func buy_price(shop: ShopData, entry: ShopEntryData, standing: ShopStanding) -> int:
	var basis := BASIS + modifier_basis(shop, standing)
	return maxi(1, (entry.base_price * basis + BASIS - 1) / BASIS)


## What the shop PAYS for one: `sell_percent` of base moved the opposite way, rounded DOWN,
## never under 1 and never above what buying it back costs.
static func sell_price(shop: ShopData, entry: ShopEntryData, standing: ShopStanding) -> int:
	var basis := BASIS - modifier_basis(shop, standing)
	var paid := (entry.base_price * shop.sell_percent * basis) / (100 * BASIS)
	return clampi(paid, 1, buy_price(shop, entry, standing))


# --- Planning (no mutation) -----------------------------------------------------

## Plan buying `quantity` of `item_id` with `funds` coin in hand. Returns a plan Dictionary:
## `ok`, `reason` (a refusal key when not ok), `kind`, `shop_id`, `item_id`, `quantity`,
## `unit_price`, `total`, `take` / `give` ({ item_id -> count } for the bag), `stock_before`.
func plan_buy(shop_id: StringName, item_id: StringName, quantity: int, funds: int,
		standing: ShopStanding) -> Dictionary:
	var plan := _blank(KIND_BUY, shop_id, item_id, quantity)
	var shop := _catalog.entry(shop_id) if is_ready() else null
	if shop == null:
		return _refuse(plan, REFUSE_UNKNOWN_SHOP)
	var entry := shop.entry_for(item_id)
	if entry == null:
		return _refuse(plan, REFUSE_NOT_TRADED)
	plan["unit_price"] = buy_price(shop, entry, standing)
	if quantity <= 0 or quantity > MAX_QUANTITY:
		return _refuse(plan, REFUSE_QUANTITY)
	var remaining := _state.remaining(shop_id, item_id)
	plan["stock_before"] = remaining
	if remaining != ShopEntryData.UNLIMITED and remaining < quantity:
		return _refuse(plan, REFUSE_OUT_OF_STOCK)
	plan["total"] = int(plan["unit_price"]) * quantity
	if funds < int(plan["total"]):
		return _refuse(plan, REFUSE_NO_FUNDS)
	plan["take"] = {currency_id(): int(plan["total"])}
	plan["give"] = {item_id: quantity}
	plan["ok"] = true
	return plan


## Plan selling `quantity` of `item_id`, of which the customer holds `held`.
func plan_sell(shop_id: StringName, item_id: StringName, quantity: int, held: int,
		standing: ShopStanding) -> Dictionary:
	var plan := _blank(KIND_SELL, shop_id, item_id, quantity)
	var shop := _catalog.entry(shop_id) if is_ready() else null
	if shop == null:
		return _refuse(plan, REFUSE_UNKNOWN_SHOP)
	var entry := shop.entry_for(item_id)
	if entry == null or not entry.buys:
		return _refuse(plan, REFUSE_NOT_BOUGHT)
	plan["unit_price"] = sell_price(shop, entry, standing)
	if quantity <= 0 or quantity > MAX_QUANTITY:
		return _refuse(plan, REFUSE_QUANTITY)
	if held < quantity:
		return _refuse(plan, REFUSE_NOT_HELD)
	var remaining := _state.remaining(shop_id, item_id)
	plan["stock_before"] = remaining
	if remaining != ShopEntryData.UNLIMITED \
			and remaining + quantity > ShopEntryData.MAX_STOCK:
		return _refuse(plan, REFUSE_STOCK_FULL)
	plan["total"] = int(plan["unit_price"]) * quantity
	plan["take"] = {item_id: quantity}
	plan["give"] = {currency_id(): int(plan["total"])}
	plan["ok"] = true
	return plan


# --- Committing -----------------------------------------------------------------

## Carry out an accepted plan. `exchange` is `func(take: Dictionary, give: Dictionary) -> bool`,
## the bag owner's all-or-nothing move. Returns the plan, with `ok` false and a `reason` when it
## was refused (and then NOTHING changed, in the bag or the shop).
func transact(plan: Dictionary, exchange: Callable) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return plan
	if bool(plan.get("done", false)):
		return _refuse(plan, REFUSE_STALE)
	var shop_id: StringName = plan["shop_id"]
	var item_id: StringName = plan["item_id"]
	if not is_ready() or _state.remaining(shop_id, item_id) != int(plan["stock_before"]):
		return _refuse(plan, REFUSE_STALE)
	if not exchange.is_valid() or not bool(exchange.call(plan["take"], plan["give"])):
		return _refuse(plan, REFUSE_NO_ROOM)
	# The bag has changed; the stock write below cannot fail.
	plan["done"] = true
	var remaining := int(plan["stock_before"])
	if remaining != ShopEntryData.UNLIMITED:
		var quantity := int(plan["quantity"])
		_state.set_remaining(shop_id, item_id,
			remaining - quantity if plan["kind"] == KIND_BUY else remaining + quantity)
	return plan


static func _blank(kind: StringName, shop_id: StringName, item_id: StringName,
		quantity: int) -> Dictionary:
	return {"ok": false, "reason": &"", "kind": kind, "shop_id": shop_id, "item_id": item_id,
		"quantity": quantity, "unit_price": 0, "total": 0, "take": {}, "give": {},
		"stock_before": ShopEntryData.UNLIMITED, "done": false}


static func _refuse(plan: Dictionary, reason: StringName) -> Dictionary:
	plan["ok"] = false
	plan["reason"] = reason
	return plan

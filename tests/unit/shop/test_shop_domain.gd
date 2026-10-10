extends TestCase
## Unit tests for the Phase-17 shop DATA and DOMAIN: `ShopEntryData`, `ShopData`,
## `ShopCatalogData`, `ShopState`, `ShopService`, and the bag's atomic `exchange`.
## No scene tree, no node, no autoload: pricing and transactions are plain objects.

const ShopEntryScript := preload("res://src/data/shops/shop_entry_data.gd")
const ShopDataScript := preload("res://src/data/shops/shop_data.gd")
const ShopCatalogScript := preload("res://src/data/shops/shop_catalog_data.gd")
const ShopStateScript := preload("res://src/domain/shop/shop_state.gd")
const ShopServiceScript := preload("res://src/domain/shop/shop_service.gd")
const InventoryStateScript := preload("res://src/domain/inventory/inventory_state.gd")

const SHIPPED_PATH := "res://data/shops/shop_catalog.tres"
const ITEMS_PATH := "res://data/items/item_catalog.tres"
const SHOP := &"shop_test_stall"
const PILL := &"item_bo_huyet_dan"
const SWORD := &"item_kiem_thanh_thiet"
const COIN := &"item_linh_thach"


func _items() -> ItemCatalogData:
	return load(ITEMS_PATH) as ItemCatalogData


func _entry(item_id: StringName, price: int, stock: int, buys: bool = true) -> ShopEntryData:
	var entry: ShopEntryData = ShopEntryScript.new()
	entry.item = _items().entry(item_id)
	entry.base_price = price
	entry.stock = stock
	entry.buys = buys
	return entry


## A known-GOOD shop: pills (10, unlimited), one sword (40, finite). Each negative case differs
## from this in exactly one field.
func _shop(id: StringName = SHOP, keeper: StringName = &"char_test_keeper") -> ShopData:
	var shop: ShopData = ShopDataScript.new()
	shop.id = id
	shop.name_key = &"SHOP_TEST_NAME"
	shop.keeper_id = keeper
	var entries: Array[ShopEntryData] = [_entry(PILL, 10, ShopEntryData.UNLIMITED),
		_entry(SWORD, 40, 1)]
	shop.entries = entries
	shop.price_dimension = &"affinity"
	shop.max_discount_percent = 20
	shop.max_markup_percent = 30
	shop.sell_percent = 40
	return shop


func _catalog(shops: Array[ShopData] = []) -> ShopCatalogData:
	var catalog: ShopCatalogData = ShopCatalogScript.new()
	catalog.currency_item = _items().entry(COIN)
	if shops.is_empty():
		shops = [_shop()]
	catalog.entries = shops
	return catalog


func _service(catalog: ShopCatalogData = null) -> ShopService:
	if catalog == null:
		catalog = _catalog()
	var state: ShopState = ShopStateScript.new()
	state.seed_from(catalog)
	return ShopServiceScript.new(catalog, state)


## Affinity as configured: -100..100, neutral 0.
func _affinity(value: int) -> ShopStanding:
	return ShopStanding.new(value, 0, -100, 100)


func _bag(coins: int, capacity: int = 24) -> InventoryState:
	var bag: InventoryState = InventoryStateScript.new()
	bag.capacity = capacity
	if coins > 0:
		bag.add(_items().entry(COIN), coins)
	return bag


## The bag owner's all-or-nothing move, as `InventoryRuntime.exchange` performs it.
func _exchange(bag: InventoryState) -> Callable:
	var items := _items()
	return func(take: Dictionary, give: Dictionary) -> bool:
		var resolved: Dictionary = {}
		for item_id: Variant in give:
			resolved[items.entry(item_id)] = give[item_id]
		return bag.exchange(take, resolved)


func _snapshot(service: ShopService, bag: InventoryState) -> String:
	return var_to_str([service.state().to_dict(), bag.to_dict()])


# === Data ====================================================================

func test_the_shipped_catalog_is_valid_and_priced_in_linh_thach() -> void:
	var catalog := load(SHIPPED_PATH) as ShopCatalogData
	assert_not_null(catalog, "the shipped shop catalog loads")
	if catalog == null:
		return
	assert_eq(catalog.validation_errors(), [] as Array[String], "and is valid")
	assert_eq(catalog.currency_item.id, COIN, "shops are paid in linh thạch")
	var shop := catalog.shop_of_keeper(&"actor_scout_ko")
	assert_not_null(shop, "Kha Thản keeps a shop")
	if shop != null:
		assert_true(String(shop.id).begins_with("shop_"), "ids use the shop_ prefix")
		for entry in shop.entries:
			assert_not_null(_items().entry(entry.item.id),
				"'%s' is a real item" % entry.item.id)
			assert_true(entry.base_price > 0, "with a positive base price")


func test_shop_data_rejects_each_broken_field() -> void:
	var cases := {
		"id without the prefix": func(s: ShopData) -> void: s.id = &"stall",
		"empty name": func(s: ShopData) -> void: s.name_key = &"",
		"no keeper": func(s: ShopData) -> void: s.keeper_id = &"",
		"no entries": func(s: ShopData) -> void:
			var none: Array[ShopEntryData] = []
			s.entries = none,
		"a null entry": func(s: ShopData) -> void:
			var holed: Array[ShopEntryData] = [null]
			s.entries = holed,
		"an item listed twice": func(s: ShopData) -> void:
			var twice: Array[ShopEntryData] = [_entry(PILL, 5, -1), _entry(PILL, 6, -1)]
			s.entries = twice,
		"a zero price": func(s: ShopData) -> void: s.entries[0].base_price = 0,
		"a negative price": func(s: ShopData) -> void: s.entries[0].base_price = -4,
		"a price over the ceiling": func(s: ShopData) -> void:
			s.entries[0].base_price = ShopEntryData.MAX_PRICE + 1,
		"a stock below unlimited": func(s: ShopData) -> void: s.entries[0].stock = -2,
		"a stock over the ceiling": func(s: ShopData) -> void:
			s.entries[0].stock = ShopEntryData.MAX_STOCK + 1,
		"an entry that can never trade": func(s: ShopData) -> void:
			s.entries[0].stock = 0
			s.entries[0].buys = false,
		"an entry with no item": func(s: ShopData) -> void: s.entries[0].item = null,
		"sell percent zero": func(s: ShopData) -> void: s.sell_percent = 0,
		"arbitrage at the best standing": func(s: ShopData) -> void:
			s.sell_percent = 90
			s.max_discount_percent = 20,
	}
	for label in cases:
		var shop := _shop()
		assert_true(shop.is_valid(), "the fixture starts valid (%s)" % label)
		(cases[label] as Callable).call(shop)
		assert_false(shop.is_valid(), "rejected: %s" % label)


func test_the_catalog_rejects_bad_sets() -> void:
	assert_true(_catalog().is_valid(), "the fixture catalog is valid")
	var no_coin := _catalog()
	no_coin.currency_item = null
	assert_false(no_coin.is_valid(), "a catalog with no currency is rejected")
	var empty: ShopCatalogData = ShopCatalogScript.new()
	empty.currency_item = _items().entry(COIN)
	assert_false(empty.is_valid(), "an empty catalog is rejected")
	var same_id: Array[ShopData] = [_shop(), _shop(SHOP, &"char_other")]
	assert_false(_catalog(same_id).is_valid(), "duplicate shop ids are rejected")
	var same_keeper: Array[ShopData] = [_shop(), _shop(&"shop_test_two")]
	assert_false(_catalog(same_keeper).is_valid(), "one keeper keeping two shops is rejected")
	var coin_shop := _shop()
	coin_shop.entries.append(_entry(COIN, 1, -1))
	var trades_coin: Array[ShopData] = [coin_shop]
	assert_false(_catalog(trades_coin).is_valid(), "a shop trading the currency is rejected")
	assert_null(_catalog().entry(&"shop_nowhere"), "an unknown shop resolves to null")
	assert_null(_catalog().shop_of_keeper(&"char_nobody"), "as does an unknown keeper")


# === Pricing =================================================================

func test_no_edge_is_neutral_and_pays_the_base_price() -> void:
	var shop := _shop()
	var pill := shop.entry_for(PILL)
	assert_eq(ShopService.modifier_basis(shop, ShopStanding.make_neutral()), 0,
		"a customer with no edge to the keeper is neutral")
	assert_eq(ShopService.buy_price(shop, pill, ShopStanding.make_neutral()), 10,
		"and pays the base price")
	assert_eq(ShopService.buy_price(shop, pill, _affinity(0)), 10, "as does affinity 0")
	assert_eq(ShopService.sell_price(shop, pill, _affinity(0)), 4, "and is paid 40% of base")
	shop.price_dimension = &""
	assert_eq(ShopService.buy_price(shop, pill, _affinity(100)), 10,
		"a shop with no pricing dimension never moves its prices")


func test_standing_moves_prices_linearly_and_is_bounded_at_the_extremes() -> void:
	var shop := _shop()
	var sword := shop.entry_for(SWORD)                   # base 40
	assert_eq(ShopService.buy_price(shop, sword, _affinity(50)), 36, "half way up: 10% off")
	assert_eq(ShopService.buy_price(shop, sword, _affinity(100)), 32, "the maximum: 20% off")
	assert_eq(ShopService.buy_price(shop, sword, _affinity(100000)), 32,
		"beyond the maximum it prices AS the maximum, never lower")
	assert_eq(ShopService.buy_price(shop, sword, _affinity(-50)), 46, "half way down: 15% more")
	assert_eq(ShopService.buy_price(shop, sword, _affinity(-100)), 52, "the minimum: 30% more")
	assert_eq(ShopService.buy_price(shop, sword, _affinity(-100000)), 52,
		"beyond the minimum it prices AS the minimum, never higher")
	assert_eq(ShopService.sell_price(shop, sword, _affinity(100)), 19,
		"a friend is PAID more (40% of 40, +20%, rounded down)")
	assert_eq(ShopService.sell_price(shop, sword, _affinity(-100)), 11,
		"and someone disliked is paid less (-30%, rounded down)")
	# A dimension that cannot fall below neutral (trust: 0..100) can only discount.
	var trust_low := ShopStanding.new(0, 0, 0, 100)
	var trust_high := ShopStanding.new(100, 0, 0, 100)
	assert_eq(ShopService.buy_price(shop, sword, trust_low), 40, "trust 0 is the base price")
	assert_eq(ShopService.buy_price(shop, sword, trust_high), 32, "trust 100 is the discount")


func test_no_standing_lets_a_customer_profit_from_buying_and_selling_back() -> void:
	var shop := _shop()
	for base in [1, 2, 3, 7, 10, 40, 999, ShopEntryData.MAX_PRICE]:
		var entry := _entry(PILL, base, -1)
		for value in [-100, -37, 0, 1, 50, 99, 100]:
			var standing := _affinity(value)
			var cost := ShopService.buy_price(shop, entry, standing)
			var paid := ShopService.sell_price(shop, entry, standing)
			assert_true(cost >= 1 and paid >= 1, "prices are never below 1")
			assert_true(paid <= cost,
				"base %d at affinity %d: paid %d never exceeds cost %d" % [base, value, paid, cost])


# === Transactions ============================================================

func test_buying_moves_coin_goods_and_stock_together() -> void:
	var service := _service()
	var bag := _bag(50)
	var plan := service.plan_buy(SHOP, SWORD, 1, bag.count_of(COIN), _affinity(0))
	assert_true(bool(plan["ok"]), "the purchase is planned")
	assert_eq(_snapshot(service, bag), _snapshot(service, bag), "planning changed nothing")
	var done := service.transact(plan, _exchange(bag))
	assert_true(bool(done["ok"]), "and carried out")
	assert_eq(bag.count_of(COIN), 10, "40 coin left the bag")
	assert_eq(bag.count_of(SWORD), 1, "the sword arrived")
	assert_eq(service.state().remaining(SHOP, SWORD), 0, "the shop's one sword is gone")
	var pills := service.transact(
		service.plan_buy(SHOP, PILL, 1, bag.count_of(COIN), _affinity(0)), _exchange(bag))
	assert_true(bool(pills["ok"]), "an unlimited item is bought the same way")
	assert_eq(service.state().remaining(SHOP, PILL), ShopEntryData.UNLIMITED,
		"and its stock stays unlimited")
	assert_eq(bag.count_of(COIN), 0, "the last 10 coin paid for it")


func test_selling_moves_goods_coin_and_stock_together() -> void:
	var service := _service()
	var bag := _bag(0)
	bag.add(_items().entry(SWORD), 1)
	bag.add(_items().entry(PILL), 3)
	var sold := service.transact(
		service.plan_sell(SHOP, SWORD, 1, bag.count_of(SWORD), _affinity(0)), _exchange(bag))
	assert_true(bool(sold["ok"]), "the sword is sold")
	assert_eq(int(sold["total"]), 16, "for 40% of its base price")
	assert_eq(bag.count_of(SWORD), 0, "it left the bag")
	assert_eq(bag.count_of(COIN), 16, "the coin arrived")
	assert_eq(service.state().remaining(SHOP, SWORD), 2, "and the shop now has two")
	var pills := service.transact(
		service.plan_sell(SHOP, PILL, 2, bag.count_of(PILL), _affinity(0)), _exchange(bag))
	assert_eq(int(pills["total"]), 8, "two pills at 4 each")
	assert_eq(bag.count_of(PILL), 1, "one pill is kept")


## Every refusal names its reason and changes NOTHING — in the bag or the shop.
func test_every_refusal_changes_nothing() -> void:
	var service := _service()
	var bag := _bag(15)
	bag.add(_items().entry(PILL), 2)
	var before := _snapshot(service, bag)
	var funds := bag.count_of(COIN)
	var neutral := _affinity(0)
	var plans := {
		ShopService.REFUSE_UNKNOWN_SHOP: service.plan_buy(&"shop_nowhere", PILL, 1, funds, neutral),
		ShopService.REFUSE_NOT_TRADED: service.plan_buy(SHOP, &"item_nothing", 1, funds, neutral),
		ShopService.REFUSE_NO_FUNDS: service.plan_buy(SHOP, SWORD, 1, funds, neutral),
		ShopService.REFUSE_OUT_OF_STOCK: service.plan_buy(SHOP, SWORD, 2, 1000, neutral),
		ShopService.REFUSE_NOT_HELD: service.plan_sell(SHOP, PILL, 3, 2, neutral),
		ShopService.REFUSE_NOT_BOUGHT: service.plan_sell(SHOP, &"item_nothing", 1, 5, neutral),
	}
	for reason: StringName in plans:
		var plan: Dictionary = plans[reason]
		assert_false(bool(plan["ok"]), "%s is refused" % reason)
		assert_eq(plan["reason"], reason, "with its own reason")
		var result := service.transact(plan, _exchange(bag))
		assert_false(bool(result["ok"]), "and transacting a refused plan stays refused")
		assert_eq(_snapshot(service, bag), before, "nothing changed (%s)" % reason)
	for quantity in [0, -1, ShopService.MAX_QUANTITY + 1, 9223372036854775807]:
		var buy := service.plan_buy(SHOP, PILL, quantity, 9223372036854775807, neutral)
		assert_eq(buy["reason"], ShopService.REFUSE_QUANTITY,
			"buying %d is not an amount" % quantity)
		var sell := service.plan_sell(SHOP, PILL, quantity, 9223372036854775807, neutral)
		assert_eq(sell["reason"], ShopService.REFUSE_QUANTITY,
			"selling %d is not an amount" % quantity)
	assert_eq(_snapshot(service, bag), before, "invalid amounts changed nothing")
	var mine := _catalog()
	mine.entries[0].entries[0].buys = false
	var picky := _service(mine)
	assert_eq(picky.plan_sell(SHOP, PILL, 1, 2, neutral)["reason"], ShopService.REFUSE_NOT_BOUGHT,
		"a shop that sells an item need not buy it")


func test_a_full_bag_refuses_the_whole_purchase() -> void:
	var service := _service()
	# One slot: the coin. Buying the sword needs a second slot while 10 coin remain.
	var bag := _bag(50, 1)
	var before := _snapshot(service, bag)
	var result := service.transact(
		service.plan_buy(SHOP, SWORD, 1, bag.count_of(COIN), _affinity(0)), _exchange(bag))
	assert_false(bool(result["ok"]), "the purchase is refused")
	assert_eq(result["reason"], ShopService.REFUSE_NO_ROOM, "for want of room")
	assert_eq(_snapshot(service, bag), before,
		"no coin was taken and the shop still has its sword")
	# Spending EVERY coin frees the slot the goods need: the staged order allows it.
	var exact := _bag(40, 1)
	var fits := service.transact(
		service.plan_buy(SHOP, SWORD, 1, exact.count_of(COIN), _affinity(0)), _exchange(exact))
	assert_true(bool(fits["ok"]), "a purchase that empties the purse can use its slot")
	assert_eq(exact.count_of(SWORD), 1, "the sword is in the freed slot")


func test_a_full_purse_refuses_the_whole_sale() -> void:
	var service := _service()
	var bag := _bag(99, 2)                       # slot 1: 99 coin (a full stack)
	bag.add(_items().entry(PILL), 2)             # slot 2: two pills
	var before := _snapshot(service, bag)
	var result := service.transact(
		service.plan_sell(SHOP, PILL, 1, bag.count_of(PILL), _affinity(0)), _exchange(bag))
	assert_eq(result["reason"], ShopService.REFUSE_NO_ROOM,
		"the coin has nowhere to go while a pill still holds the second slot")
	assert_eq(_snapshot(service, bag), before, "and the pill was not taken")


func test_a_plan_transacts_once_and_a_stale_plan_is_refused() -> void:
	var service := _service()
	var bag := _bag(200)
	var plan := service.plan_buy(SHOP, PILL, 1, bag.count_of(COIN), _affinity(0))
	assert_true(bool(service.transact(plan, _exchange(bag))["ok"]), "the first confirm trades")
	var after_one := _snapshot(service, bag)
	var again := service.transact(plan, _exchange(bag))
	assert_false(bool(again["ok"]), "confirming the SAME plan again is refused")
	assert_eq(again["reason"], ShopService.REFUSE_STALE, "as stale")
	assert_eq(_snapshot(service, bag), after_one, "and charged nothing a second time")
	# Two plans made from the same stock: the second is stale once the first has traded.
	var first := service.plan_buy(SHOP, SWORD, 1, bag.count_of(COIN), _affinity(0))
	var second := service.plan_buy(SHOP, SWORD, 1, bag.count_of(COIN), _affinity(0))
	assert_true(bool(service.transact(first, _exchange(bag))["ok"]), "the first buys the sword")
	var late := service.transact(second, _exchange(bag))
	assert_eq(late["reason"], ShopService.REFUSE_STALE, "the second sees the stock changed")
	assert_eq(bag.count_of(SWORD), 1, "one sword, paid for once")
	assert_eq(service.state().remaining(SHOP, SWORD), 0, "and the stock never went below zero")
	var no_exchange := service.transact(
		service.plan_buy(SHOP, PILL, 1, bag.count_of(COIN), _affinity(0)), Callable())
	assert_false(bool(no_exchange["ok"]), "with no bag to move the goods nothing trades")


func test_a_shop_cannot_be_sold_more_than_it_can_hold() -> void:
	var service := _service()
	service.state().set_remaining(SHOP, SWORD, ShopEntryData.MAX_STOCK)
	var plan := service.plan_sell(SHOP, SWORD, 1, 1, _affinity(0))
	assert_eq(plan["reason"], ShopService.REFUSE_STOCK_FULL, "a full shelf refuses the sale")


# === The bag's atomic exchange ==============================================

func test_exchange_is_all_or_nothing() -> void:
	var items := _items()
	var bag := _bag(10)
	var before := var_to_str(bag.to_dict())
	assert_false(bag.exchange({COIN: 11}, {items.entry(PILL): 1}), "a shortfall refuses it")
	assert_false(bag.exchange({COIN: 0}, {items.entry(PILL): 1}), "a zero removal refuses it")
	assert_false(bag.exchange({COIN: 1}, {items.entry(PILL): 0}), "a zero addition refuses it")
	assert_false(bag.exchange({COIN: 1}, {null: 1}), "a null item refuses it")
	assert_false(bag.exchange({COIN: 1.0}, {items.entry(PILL): 1}), "a float count refuses it")
	assert_false(bag.exchange({&"item_nothing": 1}, {}), "an item not held refuses it")
	assert_eq(var_to_str(bag.to_dict()), before, "and every refusal left the bag untouched")
	assert_true(bag.exchange({COIN: 4}, {items.entry(PILL): 2}), "a valid exchange succeeds")
	assert_eq(bag.count_of(COIN), 6, "coin out")
	assert_eq(bag.count_of(PILL), 2, "goods in")


# === Stock serialization =====================================================

func test_stock_round_trips_and_hydration_is_atomic() -> void:
	var catalog := _catalog()
	var service := _service(catalog)
	var bag := _bag(100)
	service.transact(service.plan_buy(SHOP, SWORD, 1, 100, _affinity(0)), _exchange(bag))
	var data := service.state().to_dict()
	assert_true(JSON.stringify(data) != "", "stock is plain data")
	assert_false((data["stock"][String(SHOP)] as Dictionary).has(String(PILL)),
		"an unlimited entry is not stored: there is nothing to remember")
	var restored: ShopState = ShopStateScript.new()
	restored.seed_from(catalog)
	assert_true(restored.from_dict(str_to_var(var_to_str(data)), catalog), "it is accepted")
	assert_eq(restored.to_dict(), data, "and re-serializes identically")
	assert_eq(restored.remaining(SHOP, SWORD), 0, "the sold-out sword is still sold out")
	var shop := String(SHOP)
	var bad := {
		"no schema": {"stock": {shop: {String(SWORD): 1}}},
		"future schema": {"schema": 2, "stock": {shop: {String(SWORD): 1}}},
		"stock not a dictionary": {"schema": 1, "stock": []},
		"unknown shop": {"schema": 1, "stock": {"shop_nowhere": {String(SWORD): 1}}},
		"unknown item": {"schema": 1, "stock": {shop: {"item_nothing": 1}}},
		"an unlimited entry given a count": {"schema": 1,
			"stock": {shop: {String(SWORD): 1, String(PILL): 3}}},
		"missing finite entry": {"schema": 1, "stock": {shop: {}}},
		"missing shop": {"schema": 1, "stock": {}},
		"negative count": {"schema": 1, "stock": {shop: {String(SWORD): -1}}},
		"float count": {"schema": 1, "stock": {shop: {String(SWORD): 1.0}}},
		"count over the ceiling": {"schema": 1,
			"stock": {shop: {String(SWORD): ShopEntryData.MAX_STOCK + 1}}},
		"rows not a dictionary": {"schema": 1, "stock": {shop: 3}},
	}
	for label in bad:
		var before := restored.to_dict()
		assert_false(restored.from_dict(bad[label], catalog), "rejected: %s" % label)
		assert_eq(restored.to_dict(), before, "and the stock is untouched (%s)" % label)
	assert_false(restored.from_dict(data, null), "with no catalog nothing can be validated")

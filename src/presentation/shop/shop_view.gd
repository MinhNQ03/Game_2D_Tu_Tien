extends RefCounted
class_name ShopView
## ShopView — Aetheria presentation DTO (what the shop panel shows, Phase 17).
##
## A read-only snapshot built by `NpcRuntime.build_shop_view()` and pushed through
## `WorldRuntime` → `MapBase` → `GameplayHUD` → `ShopPanel`. Localization KEYS, textures and
## plain numbers — never a `ShopState`, an `InventoryState` or a `CharacterState`. The panel
## decides nothing from it: a row's price is the price `ShopService` quoted.

## A shop is open (false = the panel should be closed).
var open: bool = false
var shop_id: StringName = &""
var name_key: StringName = &""
var keeper_name_key: StringName = &""

var currency_name_key: StringName = &""
var currency_icon: Texture2D = null
## The customer's funds: how much of the currency item they carry.
var balance: int = 0

## How standing moves this shop's prices, in whole percent (negative = cheaper). 0 = base.
var modifier_percent: int = 0

## What the shop sells: { item_id, name_key, desc_key, icon, base_price, price, stock
## (`ShopEntryData.UNLIMITED` = never runs out), reason_key (&"" = buyable now) }.
var buy_rows: Array[Dictionary] = []
## What the customer could sell here: { item_id, name_key, desc_key, icon, base_price (paid at
## neutral standing), price (paid now), held }.
var sell_rows: Array[Dictionary] = []

## The outcome of the last request: a refusal's key, or the result line's key, with its args.
var status_key: StringName = &""
var status_args: Dictionary = {}
var status_is_refusal: bool = false


static func make_closed() -> ShopView:
	return ShopView.new()

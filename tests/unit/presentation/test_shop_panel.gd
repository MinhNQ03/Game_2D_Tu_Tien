extends TestCase
## Unit tests for the Phase-17 shop presentation: `ShopPanel`, the HUD's modal handling of a
## `ShopView`, and the interact prompt that names a person. Presentation only — every price in
## these views is a number the test wrote, because the panel must show what it is given and
## decide nothing.

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const PILL := &"item_bo_huyet_dan"
const SWORD := &"item_kiem_thanh_thiet"


func _hud() -> GameplayHUD:
	var hud: GameplayHUD = HUDScript.new()
	add_to_tree(hud)
	return hud


func _use_language(code: String) -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", code)


func _view(modifier: int = 0) -> ShopView:
	var view := ShopView.new()
	view.open = true
	view.shop_id = &"shop_ko_than_packs"
	view.name_key = &"SHOP_KO_THAN_PACKS_NAME"
	view.keeper_name_key = &"CHARACTER_SCOUT_KO_NAME"
	view.currency_name_key = &"ITEM_LINH_THACH_NAME"
	view.balance = 12
	view.modifier_percent = modifier
	var buy: Array[Dictionary] = [
		{"item_id": PILL, "name_key": &"ITEM_BO_HUYET_DAN_NAME",
			"desc_key": &"ITEM_BO_HUYET_DAN_DESC", "icon": null, "base_price": 3,
			"price": 3 if modifier == 0 else 4, "stock": ShopEntryData.UNLIMITED,
			"reason_key": &""},
		{"item_id": SWORD, "name_key": &"ITEM_KIEM_THANH_THIET_NAME",
			"desc_key": &"ITEM_KIEM_THANH_THIET_DESC", "icon": null, "base_price": 14,
			"price": 14 if modifier == 0 else 19, "stock": 1,
			"reason_key": &"UI_SHOP_NO_FUNDS"},
	]
	view.buy_rows = buy
	var sell: Array[Dictionary] = [
		{"item_id": PILL, "name_key": &"ITEM_BO_HUYET_DAN_NAME",
			"desc_key": &"ITEM_BO_HUYET_DAN_DESC", "icon": null, "base_price": 1, "price": 1,
			"held": 2},
	]
	view.sell_rows = sell
	return view


func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	_collect(node, out)
	return out


func _collect(node: Node, out: Array[String]) -> void:
	var label := node as Label
	if label != null and label.is_visible_in_tree() and label.text != "":
		out.append(label.text)
	for child in node.get_children():
		if not child.is_queued_for_deletion():
			_collect(child, out)


## The shop is MODAL and the VIEW is the authority on whether it is open.
func test_the_shop_takes_and_returns_input_with_its_view() -> void:
	var hud := _hud()
	var input := scene_tree.root.get_node_or_null("InputService")
	if input == null:
		free_node(hud)
		return
	input.call("set_gameplay_context")
	assert_false(hud.is_shop_open(), "closed until a view says a shop is open")
	hud.set_shop_view(_view())
	assert_true(hud.is_shop_open(), "an open view opens the panel")
	assert_false(bool(input.call("is_gameplay_active")), "gameplay input is suspended")
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL),
		"the context is UI_MODAL")
	hud.set_shop_view(_view())                       # a trade pushes a new view
	hud.set_shop_view(_view())
	hud.set_shop_view(ShopView.make_closed())
	assert_false(hud.is_shop_open(), "a closed view closes it")
	assert_true(bool(input.call("is_gameplay_active")),
		"and ONE pop restores gameplay: repeated views never stacked contexts")
	hud.set_shop_view(ShopView.make_closed())        # closing twice is safe
	assert_true(bool(input.call("is_gameplay_active")), "closing twice pops nothing extra")
	hud.set_shop_view(_view())
	free_node(hud)
	assert_true(bool(input.call("is_gameplay_active")), "freeing the HUD never strands the modal")
	input.call("set_menu_context")


func test_opening_the_shop_closes_the_other_reading_surfaces() -> void:
	var hud := _hud()
	var input := scene_tree.root.get_node_or_null("InputService")
	if input == null:
		free_node(hud)
		return
	input.call("set_gameplay_context")
	hud.open_inventory()
	hud.set_shop_view(_view())
	assert_false(hud.is_inventory_open(), "the satchel gives way to the shop")
	hud.set_interact_available(true, &"UI_HUD_TALK_ACTION", {"name": &"CHARACTER_SCOUT_KO_NAME"})
	assert_false((hud.find_child("InteractPrompt", true, false) as Control).visible,
		"while the shop holds the keys the strip does not advertise 'talk' for the trade key")
	assert_true(hud.is_shop_open(), "one reading surface at a time")
	hud.set_shop_view(ShopView.make_closed())
	assert_true((hud.find_child("InteractPrompt", true, false) as Control).visible,
		"and the prompt returns with the shop closed")
	assert_true(bool(input.call("is_gameplay_active")), "and both modal contexts are returned")
	free_node(hud)
	input.call("set_menu_context")


func test_rows_show_the_price_now_and_the_base_price_when_standing_moved_it() -> void:
	var hud := _hud()
	_use_language("en")
	hud.set_shop_view(_view())
	var panel := hud.shop_panel()
	var texts := _texts(panel)
	assert_true(texts.has("The Scout's Packs"), "the shop is named")
	assert_true(texts.has("Ko Than"), "and its keeper")
	assert_true(texts.has("Spirit Stone: 12") or texts.has("%s: 12" % _loc("ITEM_LINH_THACH_NAME")),
		"the customer's funds are shown in the currency's own name (%s)" % str(texts))
	assert_true(texts.has("plain prices"), "neutral standing says so")
	assert_true(texts.has("∞"), "an unlimited item shows no count")
	assert_true(texts.has("×1"), "a finite one shows what is left")
	assert_true(texts.has("14"), "the price is shown")
	assert_false(texts.has("(14)"), "with no base beside it when they are the same")
	hud.set_shop_view(_view(30))
	texts = _texts(panel)
	assert_true(texts.has("19") and texts.has("(14)"),
		"when standing moves a price the adjusted AND the base price are both shown")
	assert_true(texts.has("dislikes you: +30%"),
		"and the panel says which way and how much")
	hud.set_shop_view(_view(-20))
	assert_true(_texts(panel).has("likes you: −20%"), "a discount likewise")
	hud.set_shop_view(ShopView.make_closed())
	free_node(hud)


func test_keyboard_choices_request_trades_and_decide_nothing() -> void:
	var hud := _hud()
	_use_language("en")
	hud.set_shop_view(_view())
	var panel := hud.shop_panel()
	var bought: Array[StringName] = []
	var sold: Array[StringName] = []
	hud.shop_buy_requested.connect(func(id: StringName) -> void: bought.append(id))
	hud.shop_sell_requested.connect(func(id: StringName) -> void: sold.append(id))
	assert_eq(panel.tab(), ShopPanel.Tab.BUY, "it opens on buying")
	assert_eq(panel.selected_item_id(), PILL, "with the first row selected")
	assert_eq(panel.status_text(), "", "a buyable row has nothing to explain")
	panel.move_selection(1)
	assert_eq(panel.selected_item_id(), SWORD, "down moves to the next row")
	assert_eq(panel.status_text(), "You cannot afford it.",
		"an unaffordable row says WHY before the player even presses")
	panel.move_selection(1)
	assert_eq(panel.selected_item_id(), PILL, "and the selection wraps")
	panel.request_trade()
	assert_eq(bought, [PILL] as Array[StringName], "interact REQUESTS buying the selected row")
	panel.set_tab(ShopPanel.Tab.SELL)
	assert_eq(panel.selected_item_id(), PILL, "the sell side lists what the customer carries")
	assert_true(_texts(panel).has("×2"), "with how many are held")
	panel.request_trade()
	assert_eq(sold, [PILL] as Array[StringName], "and interact there requests a sale")
	assert_eq(bought.size(), 1, "never both")
	# The outcome comes back in the view and is shown as given.
	var refused := _view()
	refused.status_key = &"UI_SHOP_NO_ROOM"
	refused.status_is_refusal = true
	hud.set_shop_view(refused)
	assert_eq(panel.status_text(), "Your satchel has no room for the trade.",
		"a refusal's reason is shown in the panel")
	assert_eq(panel.tab(), ShopPanel.Tab.SELL, "and a new view of the SAME shop keeps the tab")
	var done := _view()
	done.status_key = &"UI_SHOP_BOUGHT"
	done.status_args = {"name": &"ITEM_BO_HUYET_DAN_NAME", "count": 1, "total": 3}
	hud.set_shop_view(done)
	assert_true("3" in panel.status_text() and "×1" in panel.status_text(),
		"a result names what was traded and for how much ('%s')" % panel.status_text())
	var empty := _view()
	var none: Array[Dictionary] = []
	empty.sell_rows = none
	hud.set_shop_view(empty)
	assert_eq(panel.selected_item_id(), &"", "an empty side has no selection")
	panel.request_trade()
	assert_eq(sold.size(), 1, "and requests nothing")
	assert_true(_texts(panel).has("You carry nothing they would buy."), "it says why it is empty")
	hud.set_shop_view(ShopView.make_closed())
	free_node(hud)


func test_the_panel_reads_in_vietnamese() -> void:
	var hud := _hud()
	_use_language("vi")
	hud.set_shop_view(_view(30))
	var texts := _texts(hud.shop_panel())
	assert_true(texts.has("Túi hàng trinh sát"), "the shop's name")
	assert_true(texts.has("Kha Thản"), "the keeper's name")
	assert_true(texts.has("không ưa ngươi: +30%"), "the terms")
	assert_true(texts.has("▸ Mua"), "the active tab")
	_use_language("en")
	hud.set_shop_view(ShopView.make_closed())
	free_node(hud)


## The interact prompt NAMES the person, and still fits the strip in the longest language.
func test_the_interact_prompt_names_the_person() -> void:
	var hud := _hud()
	_use_language("en")
	hud.set_interact_available(true, &"UI_HUD_TALK_ACTION", {"name": &"CHARACTER_SCOUT_KO_NAME"})
	assert_eq(hud.interact_prompt_text(), "Talk to Ko Than", "the prompt names who")
	var strip := hud.find_child("PromptStrip", true, false) as Control
	assert_not_null(strip, "the prompt strip is found")
	var authored := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	for code: String in ["en", "vi"]:
		_use_language(code)
		await scene_tree.process_frame
		if code == "vi":
			assert_eq(hud.interact_prompt_text(), "Gặp Kha Thản", "in Vietnamese too")
		if strip != null:
			var width := strip.get_combined_minimum_size().x
			assert_true(width < authored * 0.5,
				"[%s] the strip with a named prompt (%dpx) stays in the left half (%d)"
					% [code, int(width), int(authored)])
	hud.set_interact_available(true)
	assert_eq(hud.interact_prompt_text(), _loc("UI_HUD_INTERACT_ACTION"),
		"a prompt with no arguments is the plain verb again")
	hud.set_interact_available(false)
	assert_eq(hud.interact_prompt_text(), "", "and nothing when there is nothing to use")
	_use_language("en")
	free_node(hud)


func _loc(key: String) -> String:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	return String(loc.call("t", key)) if loc != null else key

extends TestCase
## Unit tests for the session prompt (D-068, audit AUD-01 / AUD-02): the HUD's one centred box
## for "leave?" and "you have fallen", and what yields to a threat. Key handling itself is
## driven with real key events in the world and NPC E2E flows; here the HUD's own state.

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")


func _hud() -> GameplayHUD:
	var hud: GameplayHUD = HUDScript.new()
	add_to_tree(hud)
	return hud


func _use_language(code: String) -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", code)


func test_defeat_shows_the_box_modally_and_says_what_it_means() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	_use_language("vi")
	var hud := _hud()
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_NONE, "nothing asked at rest")
	assert_false(hud.session_prompt().visible, "and the box is hidden")
	hud.open_inventory()
	hud.show_defeat()
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_DEFEAT, "defeat is shown")
	assert_true(hud.session_prompt().visible, "in the box")
	assert_false(hud.is_inventory_open(), "and the satchel closed under it")
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL), "modally")
	assert_eq(hud.session_prompt().title_text(), "Ngươi đã gục ngã", "it says what happened")
	assert_true(hud.session_prompt().body_text().contains("Chưa có gì được lưu"),
		"and, truthfully, that nothing was saved")
	assert_true(hud.session_prompt().keys_text().contains("E"), "and names the key that goes on")
	assert_false((hud.find_child("PromptStrip", true, false) as Control).visible,
		"the prompt strip stands down: it must not advertise 'attack' to the fallen")
	await scene_tree.process_frame
	await scene_tree.process_frame
	assert_true(hud.session_prompt().global_position.y >= 360.0 + 24.0,
		"the box hangs below the screen centre, clear of the figure standing there (top %.0f)"
			% hud.session_prompt().global_position.y)
	hud.show_defeat()
	hud.close_reading_panels()
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_DEFEAT,
		"a threat does not dismiss a defeat")
	free_node(hud)
	assert_eq(int(input.call("current_context")), int(input.Context.GAMEPLAY),
		"freeing the HUD gives back exactly the one context it took")
	input.call("set_menu_context")


func test_a_threat_closes_every_reading_surface_and_asks_the_owners_to_close() -> void:
	var input: Node = scene_tree.root.get_node("InputService")
	input.call("set_gameplay_context")
	var hud := _hud()
	var asked: Array[String] = []
	var on_shop := func() -> void: asked.append("shop")
	var on_talk := func() -> void: asked.append("talk")
	hud.shop_close_requested.connect(on_shop)
	hud.dialogue_close_requested.connect(on_talk)
	hud.open_inventory()
	hud.close_reading_panels()
	assert_false(hud.is_inventory_open(), "the satchel closes")
	assert_true(bool(input.call("is_gameplay_active")), "and gives the keys back")
	var shop := ShopView.new()
	shop.open = true
	shop.shop_id = &"shop_ko_than_packs"
	shop.name_key = &"SHOP_KO_THAN_PACKS_NAME"
	shop.keeper_name_key = &"CHARACTER_SCOUT_KO_NAME"
	shop.currency_name_key = &"ITEM_LINH_THACH_NAME"
	hud.set_shop_view(shop)
	hud.close_reading_panels()
	assert_eq(asked, ["shop"] as Array[String],
		"an open shop is ASKED to close through its owner — every time, not once per fight")
	hud.close_reading_panels()
	assert_eq(asked, ["shop", "shop"] as Array[String], "a second threat asks again")
	hud.set_shop_view(ShopView.make_closed())
	hud.shop_close_requested.disconnect(on_shop)
	hud.dialogue_close_requested.disconnect(on_talk)
	free_node(hud)
	input.call("set_menu_context")


func test_the_prompt_fits_and_reads_in_both_languages() -> void:
	var hud := _hud()
	for code: String in ["vi", "en"]:
		_use_language(code)
		hud.show_defeat()
		await scene_tree.process_frame
		await scene_tree.process_frame
		var box := hud.session_prompt()
		for text: String in [box.title_text(), box.body_text(), box.keys_text()]:
			assert_false(text.begins_with("UI_") or text == "", "[%s] '%s' is real text"
				% [code, text])
		assert_true(box.size.x <= 1280.0 * 0.5,
			"[%s] the box (%.0f px) stays a question, not a screen" % [code, box.size.x])
		assert_true(box.size.y <= 720.0 * 0.3, "[%s] and is short (%.0f px)" % [code, box.size.y])
	_use_language("vi")
	free_node(hud)

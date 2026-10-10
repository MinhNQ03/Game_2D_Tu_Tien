extends TestCase
## Phase-17 NPC / Interaction / Shop E2E case (D-019 isolation: run by `run_npc_flow.gd` in its
## OWN process, against the real autoloads).
##
## It boots the real application and plays it: every ACTION is a real key event or a held
## semantic action; only placement (standing on a pickup, standing near someone) is setup, as
## in the world flow. The loop it proves:
##
##   pick up pills and spirit stones  →  WALK into reach of Kha Thản  →  the prompt names him  →
##   interact starts his conversation (Phase 18), whose "Trade" answer hands over to his shop
##   (UI_MODAL: the move keys no longer walk; neither press buys anything)  →  switch to SELL with a
##   move key, sell pills  →  switch to BUY, buy one  →  a purchase the purse cannot cover is
##   refused with its reason and changes nothing  →  Esc closes the SHOP (not the game) and
##   gameplay input returns  →  walk away  →  Esc returns to the menu, NpcRuntime first down.

const MAIN_SCENE_PATH := "res://main.tscn"
const INTERACT := &"interact"
const OPEN_MENU := &"open_menu"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_DOWN := &"move_down"
const KO := &"actor_scout_ko"
const SHOP := &"shop_ko_than_packs"
const PILL := &"item_bo_huyet_dan"
const SWORD := &"item_kiem_thanh_thiet"
const COIN := &"item_linh_thach"


func test_real_npc_shop_flow() -> void:
	var gs: Node = scene_tree.root.get_node_or_null("GameState")
	var router: Node = scene_tree.root.get_node_or_null("SceneRouter")
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if gs == null or router == null or input == null or loc == null:
		assert_true(false, "core autoloads missing")
		return

	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	scene_tree.root.add_child(main)
	await scene_tree.process_frame
	main.get_node("UI").get_child(0).emit_signal("new_game_pressed")
	await scene_tree.process_frame
	assert_eq(router.call("get_current_key"), "map_hub", "New Game loads the hub")

	var npcs := main.get_node_or_null("Systems/NpcRuntime") as NpcRuntime
	var inventory := main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	var world: Node = main.get_node_or_null("Systems/WorldRuntime")
	assert_not_null(npcs, "NpcRuntime exists under Main/Systems")
	if npcs == null or inventory == null or world == null:
		_teardown(main)
		return
	assert_true(npcs.is_session_active(), "its session is live in a running game")
	assert_eq(_count_root("NpcRuntime"), 0, "NpcRuntime is NOT an autoload (budget stays five)")
	var player := world.call("get_player") as Node2D
	var registry: CharacterRegistry = world.call("get_character_registry")

	# --- 1. goods to trade: real pickups (standing on them is setup) -----------------
	var hub: Node = router.call("get_current_scene")
	await _stand_on(player, hub.get_node("Pickups/HubPill1") as Node2D)
	assert_eq(inventory.count_of(PILL), 2, "two pills picked up in the hub")
	await _interact_to_transition(player, "map_hub")
	assert_eq(router.call("get_current_key"), "map_field", "the player travelled to the field")
	var map: Node = router.call("get_current_scene")
	await _stand_on(player, map.get_node("Pickups/FieldStone1") as Node2D)
	await _stand_on(player, map.get_node("Pickups/FieldStone2") as Node2D)
	assert_eq(inventory.count_of(COIN), 3, "three linh thạch picked up in the field")

	# --- 2. Kha Thản is a CHARACTER, standing in the world ---------------------------
	var ko := map.get_node_or_null("Interactables/KoThan") as WorldNpc
	assert_not_null(ko, "the field has Kha Thản's body")
	if ko == null:
		_teardown(main)
		return
	var ko_state := registry.get_character(KO)
	assert_not_null(ko_state, "he is a CharacterState in the session's registry")
	assert_eq(ko.character(), ko_state, "and his body is bound to THAT state (no NPC model)")
	assert_true(ko.is_available(), "he can be spoken to")
	var hud := _find_hud(map)

	# --- 3. walk into reach: the prompt names him --------------------------------------
	player.global_position = ko.global_position + Vector2(78, 4)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	assert_null(map.call("active_interactable"), "78 px away he is out of reach")
	await _fire_action(INTERACT)
	assert_false(npcs.is_shop_open(), "and interact out of reach opens nothing")
	var before_walk := player.global_position
	Input.action_press(MOVE_LEFT)
	await _wait_until(func() -> bool: return map.call("active_interactable") == ko, 180)
	Input.action_release(MOVE_LEFT)
	await scene_tree.physics_frame
	assert_true(player.global_position.x < before_walk.x - 20.0,
		"the player WALKED into reach with a real move key (%.1f px)"
			% (before_walk.x - player.global_position.x))
	assert_eq(map.call("active_interactable"), ko, "in reach, he is the interactable")
	var prompt := String(loc.call("t_args", "UI_HUD_TALK_ACTION",
		{"name": String(loc.call("t", String(ko_state.name_key)))}))
	assert_eq(hud.interact_prompt_text(), prompt, "the prompt names him ('%s')" % prompt)

	# --- 4. interact opens the shop, modally --------------------------------------------
	var early: Array = []
	var on_early_done := func(kind: StringName, id: StringName, _n: int, _total: int) -> void:
		early.append([kind, id])
	var on_early_refused := func(key: StringName) -> void: early.append([key])
	npcs.trade_done.connect(on_early_done)
	npcs.trade_refused.connect(on_early_refused)
	# Since Phase 18 a person with an authored conversation is TALKED to first; his shop is
	# the conversation's "Trade" answer. One press per step, each step's effect awaited.
	var dialogue := main.get_node_or_null("Systems/DialogueRuntime") as DialogueRuntime
	assert_not_null(dialogue, "DialogueRuntime exists under Main/Systems")
	await _fire_until(INTERACT, func() -> bool: return dialogue.is_open())
	assert_true(dialogue.is_open(), "a REAL interact key started his conversation")
	assert_false(npcs.is_shop_open(), "which is not his shop: nothing can be bought yet")
	await _fire_until(INTERACT,
		func() -> bool: return dialogue.current_node_id() == &"ko_hub" or not dialogue.is_open())
	assert_eq(hud.dialogue_panel().selected_choice_id(), &"ko_trade",
		"past his greeting, 'Trade' is the selected answer")
	await _fire_until(INTERACT, func() -> bool: return npcs.is_shop_open())
	assert_eq(npcs.open_shop_id(), SHOP, "a REAL interact key on 'Trade' opened his shop")
	assert_false(dialogue.is_open(), "and the conversation closed as it did")
	assert_false(hud.is_dialogue_open(), "no dialogue box is left behind the shop")
	for _i in 4:
		await scene_tree.process_frame
	npcs.trade_done.disconnect(on_early_done)
	npcs.trade_refused.disconnect(on_early_refused)
	# The purse can afford the first row, so a press that also traded would show here.
	assert_eq(early, [], "the key press that OPENED the shop did not also trade (%s)" % str(early))
	assert_eq(inventory.count_of(COIN), 3, "no coin left the purse on opening")
	assert_eq(inventory.count_of(PILL), 2, "and nothing was bought")
	assert_true(hud.is_shop_open(), "the shop panel is shown")
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL),
		"the input context is UI_MODAL")
	assert_eq(ko.visual().get_direction(), CharacterVisualProfileData.Direction.RIGHT,
		"he turned to face the player")
	var panel := hud.shop_panel()
	var held_still := player.global_position
	Input.action_press(MOVE_DOWN)
	for _i in 20:
		await scene_tree.physics_frame
	Input.action_release(MOVE_DOWN)
	await scene_tree.physics_frame
	assert_true(player.global_position.distance_to(held_still) < 0.5,
		"while the shop is open the move keys do not walk the player")
	var view := npcs.build_shop_view()
	assert_eq(view.balance, 3, "the panel's funds are the linh thạch in the bag")

	# --- 5. SELL: a move key switches side, interact sells --------------------------------
	await _fire_until(MOVE_RIGHT, func() -> bool: return panel.tab() == ShopPanel.Tab.SELL)
	assert_eq(panel.tab(), ShopPanel.Tab.SELL, "a real move_right key switched to selling")
	assert_eq(panel.selected_item_id(), PILL, "the pills are offered for sale")
	await _fire_until(INTERACT, func() -> bool: return inventory.count_of(PILL) == 1)
	assert_eq(inventory.count_of(PILL), 1, "a real interact key sold ONE pill")
	assert_eq(inventory.count_of(COIN), 4, "for one linh thạch")
	assert_true(String(loc.call("t", "ITEM_BO_HUYET_DAN_NAME")) in hud.notice_text(),
		"the HUD says what was sold ('%s')" % hud.notice_text())
	assert_ne(panel.status_text(), "", "and so does the panel")
	await _fire_until(INTERACT, func() -> bool: return inventory.count_of(PILL) == 0)
	assert_eq(inventory.count_of(COIN), 5, "the second pill: five linh thạch in hand")

	# --- 6. BUY ----------------------------------------------------------------------------
	await _fire_until(MOVE_LEFT, func() -> bool: return panel.tab() == ShopPanel.Tab.BUY)
	assert_eq(panel.tab(), ShopPanel.Tab.BUY, "a real move_left key switched to buying")
	assert_eq(panel.selected_item_id(), PILL, "the first thing for sale is the pill")
	await _fire_until(INTERACT, func() -> bool: return inventory.count_of(PILL) == 1)
	assert_eq(inventory.count_of(PILL), 1, "a real interact key bought ONE pill")
	assert_eq(inventory.count_of(COIN), 2, "for three linh thạch (the price the row showed)")

	# --- 7. a refusal says why and changes nothing ------------------------------------------
	var stock_before := npcs.to_dict()
	var bag_before := inventory.to_dict()
	var refusals: Array[StringName] = []
	var on_refused := func(key: StringName) -> void: refusals.append(key)
	npcs.trade_refused.connect(on_refused)
	await _fire_until(INTERACT, func() -> bool: return not refusals.is_empty())
	npcs.trade_refused.disconnect(on_refused)
	assert_true(refusals.has(ShopService.REFUSE_NO_FUNDS),
		"buying a pill with two linh thạch is refused for want of funds (%s)" % str(refusals))
	assert_eq(panel.status_text(), String(loc.call("t", "UI_SHOP_NO_FUNDS")),
		"the panel says why")
	assert_eq(npcs.to_dict(), stock_before, "the shop's stock did not move")
	assert_eq(inventory.to_dict(), bag_before, "nor did the bag")

	# --- 8. Esc closes the SHOP, not the game ------------------------------------------------
	await _fire_until(OPEN_MENU, func() -> bool: return not npcs.is_shop_open())
	await scene_tree.process_frame
	assert_false(npcs.is_shop_open(), "a real Esc closed the shop")
	assert_false(hud.is_shop_open(), "the panel is gone")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "and the game is still running")
	assert_true(bool(input.call("is_gameplay_active")), "gameplay input is restored")
	var before_leave := player.global_position
	Input.action_press(MOVE_RIGHT)
	for _i in 40:
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	await scene_tree.physics_frame
	assert_true(player.global_position.x > before_leave.x + 30.0,
		"the player walks again (%.1f px)" % (player.global_position.x - before_leave.x))
	assert_null(map.call("active_interactable"), "and out of reach he is no longer offered")

	# --- 9. return to menu -------------------------------------------------------------------
	await _fire_action(OPEN_MENU)
	await scene_tree.process_frame
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.MENU, "Esc with no shop open returns to the menu")
	assert_false(npcs.is_session_active(), "the NPC session ended")
	var trace: Array = main.call("get_last_teardown_order")
	assert_true(trace.size() > 2 and trace[0] == &"DialogueRuntime" and trace[1] == &"NpcRuntime",
		"DialogueRuntime then NpcRuntime were torn down first (%s)" % str(trace))

	_teardown(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(main), "Main freed after cleanup (no orphan)")


# --- helpers -----------------------------------------------------------------

func _find_hud(node: Node) -> GameplayHUD:
	if node == null:
		return null
	if node is GameplayHUD:
		return node as GameplayHUD
	for child in node.get_children():
		var found: GameplayHUD = _find_hud(child)
		if found != null:
			return found
	return null


func _count_root(node_name: String) -> int:
	var count := 0
	for child in scene_tree.root.get_children():
		if child.name == node_name:
			count += 1
	return count


## SETUP: stand the player on a pickup and let the real inventory tick collect it.
func _stand_on(player: Node2D, pickup: Node2D) -> void:
	assert_not_null(pickup, "the pickup exists")
	if pickup == null:
		return
	player.global_position = pickup.global_position
	for _i in 6:
		await scene_tree.physics_frame


func _wait_until(predicate: Callable, frames: int) -> void:
	for _i in frames:
		if predicate.call():
			return
		await scene_tree.physics_frame


## Fire `action` through the real input pipeline until `done` holds (bounded): a synthetic
## press can land between two reads (L-016), so the EFFECT is polled, never assumed.
func _fire_until(action: StringName, done: Callable) -> void:
	for _attempt in 8:
		if done.call():
			return
		await _fire_action(action)
		await scene_tree.process_frame


func _fire_action(action: StringName) -> void:
	var press := _key_event_for(action, true)
	if press == null:
		Input.action_press(action)
		await scene_tree.process_frame
		Input.action_release(action)
		return
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await scene_tree.process_frame
	var release := _key_event_for(action, false)
	if release != null:
		Input.parse_input_event(release)
		Input.flush_buffered_events()
	await scene_tree.process_frame


func _key_event_for(action: StringName, pressed: bool) -> InputEventKey:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := InputEventKey.new()
			k.physical_keycode = (e as InputEventKey).physical_keycode
			k.keycode = (e as InputEventKey).keycode
			k.pressed = pressed
			return k
	return null


func _interact_to_transition(player: Node2D, from_key: String) -> void:
	var router := scene_tree.root.get_node_or_null("SceneRouter")
	var active: Node = router.call("get_current_scene")
	var exits := active.get_node_or_null("Exits")
	var zone: Node2D = null
	if exits != null:
		for child in exits.get_children():
			if child is MapExitZone:
				zone = child
				break
	assert_not_null(zone, "the active map has an exit zone")
	if zone == null:
		return
	player.global_position = zone.global_position
	zone.emit_signal("body_entered", player)
	await scene_tree.process_frame
	for _attempt in 8:
		await _fire_action(INTERACT)
		await scene_tree.process_frame
		if str(router.call("get_current_key")) != from_key:
			break
	await scene_tree.process_frame


func _teardown(main: Node) -> void:
	for a in [MOVE_LEFT, MOVE_RIGHT, MOVE_DOWN, INTERACT, OPEN_MENU]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

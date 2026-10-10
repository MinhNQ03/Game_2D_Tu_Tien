extends TestCase
## Phase-18 Dialogue E2E case (D-019 isolation: run by `run_dialogue_flow.gd` in its OWN
## process, against the real autoloads).
##
## It boots the real application and plays it: every ACTION is a real key event or a held
## semantic action; only placement (standing near someone, on a pickup) is setup, as in the
## other flows. Each step is ONE press whose effect is awaited — a press is repeated only while
## nothing has changed, so a lost synthetic press (L-016) can never become a second answer.
##
##   HUB   walk to Thẩm Bất Kỳ → the prompt names him → interact opens HIS conversation,
##         modally (the opening press answers nothing; move / attack do nothing) → with the
##         stele unread his only answer is the door → Esc leaves the TALK, not the game →
##         read the stele (real key) → talk again: a new answer is offered → it earns respect
##         in the real relationship graph, once → respect opens a second answer → he teaches,
##         through the Knowledge Core → leave by choosing it.
##   FIELD walk to Kha Thản → the same box, his own lines and reaction → tell him the stele's
##         news: affinity in the graph → "Trade" hands over to his shop, which opens with the
##         price that affinity gives, and the press that chose it buys nothing → Esc closes
##         the shop → with a conversation open, returning to the menu tears everything down.

const MAIN_SCENE_PATH := "res://main.tscn"
const INTERACT := &"interact"
const ATTACK := &"attack"
const PET_SUMMON := &"pet_summon"
const OPEN_MENU := &"open_menu"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_UP := &"move_up"
const MOVE_DOWN := &"move_down"
const KO := &"actor_scout_ko"
const SHEN := &"actor_elder_shen"
const SHOP := &"shop_ko_than_packs"
const SWORD := &"item_kiem_thanh_thiet"
const COIN := &"item_linh_thach"
const STELE := &"know_lac_ha_stele_record"
const PRECEPT := &"know_thanh_dai_precept"

var _passed: int = 0


func test_real_dialogue_flow() -> void:
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

	var dialogue := main.get_node_or_null("Systems/DialogueRuntime") as DialogueRuntime
	var npcs := main.get_node_or_null("Systems/NpcRuntime") as NpcRuntime
	var knowledge := main.get_node_or_null("Systems/KnowledgeRuntime") as KnowledgeRuntime
	var relationship := main.get_node_or_null("Systems/RelationshipRuntime") \
		as RelationshipRuntime
	var inventory := main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	var world: Node = main.get_node_or_null("Systems/WorldRuntime")
	assert_not_null(dialogue, "DialogueRuntime exists under Main/Systems")
	if dialogue == null or npcs == null or knowledge == null or relationship == null \
			or inventory == null or world == null:
		_teardown(main)
		return
	assert_true(dialogue.is_session_active(), "its session is live in a running game")
	assert_eq(_count_root("DialogueRuntime"), 0,
		"DialogueRuntime is NOT an autoload (the budget stays five)")
	assert_false(dialogue.is_processing(), "and it runs nothing per frame")
	var player := world.call("get_player") as Node2D
	var player_id: StringName = (world.call("get_player_character") as CharacterState).instance_id
	var service := dialogue.get_service()
	var store := relationship.get_store()
	var edges_at_start := store.edge_count()
	_step("1. new game: the dialogue session is live, not an autoload")

	var made: Array = []
	var on_made := func(outcome: DialogueOutcome) -> void: made.append(outcome.choice_id)
	dialogue.choice_made.connect(on_made)

	# --- 2. the elder, in the hub ------------------------------------------------------
	var hub: Node = router.call("get_current_scene")
	var hud := _find_hud(hub)
	var shen := hub.get_node_or_null("Interactables/ShenBuqi") as WorldNpc
	assert_not_null(shen, "the hub has Thẩm Bất Kỳ's body")
	if shen == null:
		_teardown(main)
		return
	var registry: CharacterRegistry = world.call("get_character_registry")
	assert_eq(shen.character(), registry.get_character(SHEN),
		"bound to the CharacterState the world simulation realized (no second elder)")
	await _walk_into_reach(player, hub, shen, Vector2(70, 6), MOVE_LEFT)
	assert_eq(hub.call("active_interactable"), shen, "in reach, he is the interactable")
	var prompt := String(loc.call("t_args", "UI_HUD_TALK_ACTION",
		{"name": String(loc.call("t", String(shen.character().name_key)))}))
	assert_eq(hud.interact_prompt_text(), prompt, "the prompt names him ('%s')" % prompt)
	_step("2. walked to the elder; the prompt names him")

	# --- 3. interact opens HIS conversation; the opening press answers nothing ---------
	await _press_until(INTERACT, func() -> bool: return dialogue.is_open())
	assert_eq(dialogue.open_dialogue_id(), &"dlg_elder_shen", "a REAL interact key opened it")
	for _i in 4:
		await scene_tree.process_frame
	assert_eq(dialogue.current_node_id(), &"shen_greet",
		"the press that opened it did not also acknowledge the first line")
	assert_eq(made, [], "and no intent was accepted yet")
	assert_true(hud.is_dialogue_open(), "the dialogue box is shown")
	var panel := hud.dialogue_panel()
	assert_eq(panel.speaker_text(), String(loc.call("t", "CHARACTER_ELDER_SHEN_NAME")),
		"it names the speaker")
	assert_eq(panel.line_text(), String(loc.call("t", "DLG_SHEN_GREET")), "and shows his line")
	assert_true(panel.has_portrait(), "with his portrait")
	assert_eq(panel.mood_text(), String(loc.call("t", "UI_DIALOGUE_MOOD_STERN")), "stern")
	assert_false(shen.is_greeting(), "he greets WITHOUT a gesture (his authored reaction)")
	assert_eq(hud.interact_prompt_text() != "" and hud.find_child("PromptStrip", true,
		false).visible, false, "the prompt strip stands down while they talk")
	_step("3. interact opened the elder's conversation; the opening press was not reused")

	# --- 4. modal: move / attack / pet-summon do nothing --------------------------------
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL),
		"the input context is UI_MODAL")
	var swings := [0]
	var on_swing := func() -> void: swings[0] += 1
	var attack := player.get_node_or_null("AttackComponent") as AttackComponent
	attack.attack_started.connect(on_swing)
	var held := player.global_position
	Input.action_press(MOVE_RIGHT)
	for _i in 20:
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	await _fire_action(ATTACK)
	await _fire_action(PET_SUMMON)
	for _i in 4:
		await scene_tree.physics_frame
	attack.attack_started.disconnect(on_swing)
	assert_true(player.global_position.distance_to(held) < 0.5,
		"while they talk the move keys do not walk the player")
	assert_eq(swings[0], 0, "the attack key swings nothing")
	assert_eq(dialogue.current_node_id(), &"shen_greet", "and none of it answered the line")
	_step("4. movement, attack and pet-summon are blocked by the modal context")

	# --- 5. an answer that needs the stele is not offered -------------------------------
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"shen_hub")
	assert_eq(panel.choice_ids(), [&"shen_leave"] as Array[StringName],
		"with the stele unread, recounting it is NOT offered")
	_step("5. continue reached his answers; the knowledge-gated one is absent")

	# --- 6. Esc leaves the TALK, not the game --------------------------------------------
	await _press_until(OPEN_MENU, func() -> bool: return not dialogue.is_open())
	await scene_tree.process_frame
	assert_false(hud.is_dialogue_open(), "a real Esc closed the dialogue box")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "and the game is still running")
	assert_true(bool(input.call("is_gameplay_active")), "gameplay input is restored")
	assert_true((hud.find_child("PromptStrip", true, false) as Control).visible,
		"and the prompt strip is back")
	for _i in 6:
		await scene_tree.process_frame
	assert_false(dialogue.is_open(), "the closing press did not reopen it")
	assert_eq(store.edge_count(), edges_at_start, "nothing was said: no edge was made")
	_step("6. Esc closed the conversation and returned control")

	# --- 7. read the stele with a real key -------------------------------------------------
	var stele := hub.get_node_or_null("KnowledgeSources/LacHaStele") as Node2D
	player.global_position = stele.global_position + Vector2(0, 20)  # setup: at the stele
	await _wait_until(func() -> bool: return hub.call("active_knowledge_source") != null, 30)
	await _press_until(INTERACT, func() -> bool: return knowledge.get_service().knows(STELE))
	assert_true(knowledge.get_service().knows(STELE), "the stele was read (Knowledge Core)")
	_step("7. the stele was read through the real knowledge path")

	# --- 8. now he has something to hear: respect, once ------------------------------------
	await _walk_into_reach(player, hub, shen, Vector2(70, 6), MOVE_LEFT)
	await _press_until(INTERACT, func() -> bool: return dialogue.is_open())
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"shen_hub")
	assert_eq(panel.choice_ids(), [&"shen_report", &"shen_leave"] as Array[StringName],
		"having read the stele, recounting it IS offered")
	assert_eq(panel.selected_choice_id(), &"shen_report", "and is the selected answer")
	await _press_until(INTERACT,
		func() -> bool: return dialogue.current_node_id() == &"shen_approve")
	assert_eq(service.regard(SHEN, player_id, &"respect"), 15,
		"his respect for the player is 15 in the relationship graph")
	assert_eq(store.edge_count(), edges_at_start + 1, "on exactly one new edge")
	assert_true(shen.is_greeting(), "and now he gestures: his own talk sheet, the shared seam")
	assert_true(String(loc.call("t", "CHARACTER_ELDER_SHEN_NAME")) in hud.notice_text(),
		"the HUD says whose regard moved ('%s')" % hud.notice_text())
	assert_eq(panel.mood_text(), String(loc.call("t", "UI_DIALOGUE_MOOD_WARM")), "he warms")
	_step("8. a knowledge-gated answer raised respect through RelationshipService, once")

	# --- 9. respect opens the next answer; he teaches through the Knowledge Core -----------
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"shen_hub")
	assert_eq(panel.choice_ids(), [&"shen_ask", &"shen_leave"] as Array[StringName],
		"respect closed one answer and opened another")
	var learned: Array[StringName] = []
	var on_learned := func(id: StringName, _source: StringName) -> void: learned.append(id)
	knowledge.knowledge_gained.connect(on_learned)
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"shen_teach")
	knowledge.knowledge_gained.disconnect(on_learned)
	assert_true(knowledge.get_service().knows(PRECEPT), "the Knowledge Core holds the precept")
	assert_eq(learned, [PRECEPT] as Array[StringName],
		"announced once, through knowledge_gained")
	assert_true(String(loc.call("t", "KNOW_THANH_DAI_PRECEPT_NAME")) in hud.notice_text(),
		"and shown by the existing knowledge notice ('%s')" % hud.notice_text())
	assert_eq(service.regard(SHEN, player_id, &"respect"), 15, "respect did not move again")
	_step("9. a relationship-gated answer granted knowledge through the Knowledge Core")

	# --- 10. leave by CHOOSING it -----------------------------------------------------------
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"shen_hub")
	await _press_until(MOVE_DOWN,
		func() -> bool: return panel.selected_choice_id() == &"shen_leave")
	assert_eq(panel.selected_choice_id(), &"shen_leave", "a real move key selected 'leave'")
	await _press_until(INTERACT, func() -> bool: return not dialogue.is_open())
	assert_true(bool(input.call("is_gameplay_active")), "the leave answer returned control")
	for _i in 6:
		await scene_tree.process_frame
	assert_false(dialogue.is_open(), "and the press that chose it did not start a new talk")
	_step("10. the leave answer ended the conversation")

	# --- 11. the field: Kha Thản, the same box, his own lines -------------------------------
	await _interact_to_transition(player, "map_hub")
	assert_eq(router.call("get_current_key"), "map_field", "the player travelled to the field")
	var field: Node = router.call("get_current_scene")
	hud = _find_hud(field)
	panel = hud.dialogue_panel()
	await _stand_on(player, field.get_node("Pickups/FieldStone1") as Node2D)
	await _stand_on(player, field.get_node("Pickups/FieldStone2") as Node2D)
	assert_eq(inventory.count_of(COIN), 3, "three linh thạch: enough for the shop's first row")
	var ko := field.get_node_or_null("Interactables/KoThan") as WorldNpc
	await _walk_into_reach(player, field, ko, Vector2(78, 4), MOVE_LEFT)
	await _press_until(INTERACT, func() -> bool: return dialogue.is_open())
	assert_eq(dialogue.open_dialogue_id(), &"dlg_scout_ko", "the SAME key opens HIS conversation")
	assert_false(npcs.is_shop_open(), "not his shop")
	assert_eq(panel.speaker_text(), String(loc.call("t", "CHARACTER_SCOUT_KO_NAME")), "his name")
	assert_eq(panel.line_text(), String(loc.call("t", "DLG_KO_GREET")), "his line")
	assert_eq(panel.mood_text(), String(loc.call("t", "UI_DIALOGUE_MOOD_WARY")), "wary")
	assert_true(ko.is_greeting(), "he greets WITH a gesture (a different authored reaction)")
	assert_eq(ko.visual().get_direction(), CharacterVisualProfileData.Direction.RIGHT,
		"and has turned to the player")
	_step("11. the second NPC speaks through the same seam with his own content")

	# --- 12. tell him the stele's news: affinity, in the graph -------------------------------
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"ko_hub")
	assert_eq(panel.choice_ids().size(), 4, "four answers")
	await _press_until(MOVE_DOWN,
		func() -> bool: return panel.selected_choice_id() == &"ko_ask_woods")
	await _press_until(MOVE_DOWN,
		func() -> bool: return panel.selected_choice_id() == &"ko_talk_price")
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"ko_price")
	assert_eq(panel.selected_choice_id(), &"ko_share_stele",
		"knowing the stele's record, its news is the first answer")
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"ko_pleased")
	assert_eq(service.regard(KO, player_id, &"affinity"), 40, "his affinity is 40 in the graph")
	assert_eq(store.edge_count(), edges_at_start + 2, "one edge per person spoken to")
	await _press_until(INTERACT, func() -> bool: return dialogue.current_node_id() == &"ko_hub")
	_step("12. a branch through two nodes raised the shopkeeper's affinity once")

	# --- 13. Trade: the existing shop, at the price affinity gives, and nothing bought --------
	var early: Array = []
	var on_trade := func(kind: StringName, id: StringName, _n: int, _t: int) -> void:
		early.append([kind, id])
	var on_trade_refused := func(key: StringName) -> void: early.append([key])
	npcs.trade_done.connect(on_trade)
	npcs.trade_refused.connect(on_trade_refused)
	assert_eq(panel.selected_choice_id(), &"ko_trade", "'Trade' is selected")
	await _press_until(INTERACT, func() -> bool: return npcs.is_shop_open())
	for _i in 4:
		await scene_tree.process_frame
	npcs.trade_done.disconnect(on_trade)
	npcs.trade_refused.disconnect(on_trade_refused)
	assert_eq(npcs.open_shop_id(), SHOP, "'Trade' opened his existing shop")
	assert_false(dialogue.is_open(), "the conversation is closed")
	assert_false(hud.is_dialogue_open(), "no dialogue box is left behind the shop panel")
	assert_true(hud.is_shop_open(), "the shop panel is shown")
	assert_eq(early, [], "the press that chose 'Trade' did not also trade (%s)" % str(early))
	assert_eq(inventory.count_of(COIN), 3, "no coin left the purse")
	var shop_view := npcs.build_shop_view()
	assert_eq(shop_view.modifier_percent, -8, "the shop reads the affinity the talk just raised")
	var sword_price := -1
	for row in shop_view.buy_rows:
		if row["item_id"] == SWORD:
			sword_price = int(row["price"])
	assert_eq(sword_price, 13, "so the sword costs 13, not its base 14")
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL), "still modal")
	await _press_until(OPEN_MENU, func() -> bool: return not npcs.is_shop_open())
	await scene_tree.process_frame
	assert_true(bool(input.call("is_gameplay_active")),
		"ONE close restored gameplay: the handoff never stacked two modal contexts")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "and the game is still running")
	_step("13. Trade handed over to the shop at the adjusted price; no accidental purchase")

	# --- 14. a map change closes an open conversation -----------------------------------------
	await _press_until(INTERACT, func() -> bool: return dialogue.is_open())
	var closed: Array[StringName] = []
	var on_closed := func(_id: StringName, reason: StringName) -> void: closed.append(reason)
	dialogue.dialogue_closed.connect(on_closed)
	world.emit_signal("active_map_leaving")  # what every map change announces first
	await scene_tree.process_frame
	assert_eq(closed, [DialogueRuntime.REASON_MAP] as Array[StringName],
		"the map going away closed the conversation")
	assert_false(hud.is_dialogue_open(), "and its box")
	assert_true(bool(input.call("is_gameplay_active")), "with the modal context released")
	world.emit_signal("active_map_ready")
	await scene_tree.process_frame
	_step("14. a map change closes the conversation and releases input")

	# --- 15. return to the menu WITH a conversation open ---------------------------------------
	await _press_until(INTERACT, func() -> bool: return dialogue.is_open())
	assert_true(hud.is_dialogue_open(), "a conversation is open")
	closed.clear()
	field.emit_signal("return_to_menu_requested")  # the session ending under an open talk
	await scene_tree.process_frame
	await scene_tree.process_frame
	dialogue.dialogue_closed.disconnect(on_closed)
	dialogue.choice_made.disconnect(on_made)
	assert_eq(gs.get_phase(), gs.Phase.MENU, "the game returned to the menu")
	assert_eq(closed, [DialogueRuntime.REASON_SESSION] as Array[StringName],
		"ending the session closed the conversation")
	assert_false(dialogue.is_session_active(), "the dialogue session ended")
	assert_false(dialogue.is_open(), "with nothing open")
	assert_eq(int(input.call("current_context")), int(input.Context.MENU),
		"the input context is MENU: no modal context survived the teardown")
	var trace: Array = main.call("get_last_teardown_order")
	assert_true(not trace.is_empty() and trace[0] == &"DialogueRuntime",
		"DialogueRuntime was torn down FIRST (%s)" % str(trace))
	assert_eq(made.count(&"shen_report"), 1, "the respect answer was accepted exactly once")
	assert_eq(made.count(&"ko_share_stele"), 1, "and so was the news")
	assert_eq(_count_root("GameState"), 1, "one GameState autoload")
	_step("15. return to menu closed the conversation; DialogueRuntime ended first")

	_teardown(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(main), "Main freed after cleanup (no orphan)")


# --- helpers -----------------------------------------------------------------

## A named step: printed PASS when no assertion has failed since the previous step.
func _step(step_name: String) -> void:
	var failed := get_failures().size()
	print("[e2e-dialogue] [%s] %s" % ["PASS" if failed == _passed else "FAIL", step_name])
	_passed = failed


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


## SETUP then a REAL walk: stand `offset` from `npc` (out of reach) and hold `move` until the
## map offers them.
func _walk_into_reach(player: Node2D, map: Node, npc: WorldNpc, offset: Vector2,
		move: StringName) -> void:
	player.global_position = npc.global_position + offset
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	assert_null(map.call("active_interactable"), "%.0f px away they are out of reach" % offset.x)
	var before := player.global_position
	Input.action_press(move)
	await _wait_until(func() -> bool: return map.call("active_interactable") == npc, 180)
	Input.action_release(move)
	await scene_tree.physics_frame
	assert_true(player.global_position.distance_to(before) > 20.0,
		"the player WALKED into reach with a real move key (%.1f px)"
			% player.global_position.distance_to(before))


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


## Press `action` ONCE through the real input pipeline and wait for `done`. Only if nothing at
## all changed is the press repeated (bounded): a synthetic press can be lost between two reads
## (L-016), but a press that landed is never sent twice.
func _press_until(action: StringName, done: Callable) -> void:
	for _attempt in 6:
		if done.call():
			return
		await _fire_action(action)
		for _i in 3:
			if done.call():
				return
			await scene_tree.process_frame
	assert_true(done.call(), "pressing '%s' had its effect" % action)


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
	for a in [MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN, INTERACT, OPEN_MENU, ATTACK]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

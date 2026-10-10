extends TestCase
## Phase-19 Quest E2E case (D-019 isolation: run by `run_quest_flow.gd` in its OWN process,
## against the real autoloads).
##
## It boots the real application and plays it: every ACTION is a real key event or a held
## semantic action; only placement (standing near someone, on a pickup, beside a creature) and
## filling the bag are setup, and each says so. Each step is ONE press whose effect is
## awaited — a press is repeated only while nothing has changed (L-016).
##
##   HUB    at spawn the place plaque says where to go, and nothing was taken for the player →
##          the elder offers nothing to one who has not read → read the stele → hear the ask →
##          DECLINE: nothing changed → ask again → ACCEPT, by a press of its own → the journal
##          opens on its key, does not hold the keys, closes on its key and on Esc (which then
##          only ASKS about leaving) → give the task back (a second, explicit answer; the
##          default keeps it) → take it again.
##   FIELD  the scout's errand, taken → his word about the woods makes the elder's task ready
##          (the knowledge route) → a real kill is counted by the quest through real combat.
##   HUB    a full bag REFUSES the reward: the talk stays, nothing is paid → with room, it is
##          paid once: pills, XP, respect → those very pills make the scout's errand ready.
##   FIELD  hand them over: two pills out, three stones in, his affinity up → it is over.
##          Return to the menu: conversations end first, then quests.

const MAIN_SCENE_PATH := "res://main.tscn"
const INTERACT := &"interact"
const ATTACK := &"attack"
const OPEN_MENU := &"open_menu"
const JOURNAL := &"quest_journal"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_UP := &"move_up"
const MOVE_DOWN := &"move_down"
const KO := &"actor_scout_ko"
const SHEN := &"actor_elder_shen"
const VEIN := &"quest_unquiet_vein"
const PILLS := &"quest_treeline_pills"
const STELE := &"know_lac_ha_stele_record"
const WORD := &"know_vu_lang_hunting_ground"
const PILL := &"item_bo_huyet_dan"
const STONE := &"item_linh_thach"
const SWORD := &"item_kiem_thanh_thiet"

var _passed: int = 0
var _dialogue: DialogueRuntime = null
var _panel: DialoguePanel = null


func test_real_quest_flow() -> void:
	var gs: Node = scene_tree.root.get_node_or_null("GameState")
	var router: Node = scene_tree.root.get_node_or_null("SceneRouter")
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if gs == null or router == null or input == null or loc == null:
		assert_true(false, "core autoloads missing")
		return
	loc.call("set_language", "vi")

	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	scene_tree.root.add_child(main)
	await scene_tree.process_frame
	main.get_node("UI").get_child(0).emit_signal("new_game_pressed")
	await scene_tree.process_frame
	assert_eq(router.call("get_current_key"), "map_hub", "New Game loads the hub")

	var quests := main.get_node_or_null("Systems/QuestRuntime") as QuestRuntime
	var rewards := main.get_node_or_null("Systems/RewardRuntime") as RewardRuntime
	_dialogue = main.get_node_or_null("Systems/DialogueRuntime") as DialogueRuntime
	var knowledge := main.get_node_or_null("Systems/KnowledgeRuntime") as KnowledgeRuntime
	var relationship := main.get_node_or_null("Systems/RelationshipRuntime") \
		as RelationshipRuntime
	var inventory := main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	var progression := main.get_node_or_null("Systems/ProgressionRuntime")
	var combat := main.get_node_or_null("Systems/CombatRuntime")
	var npcs := main.get_node_or_null("Systems/NpcRuntime") as NpcRuntime
	var world: Node = main.get_node_or_null("Systems/WorldRuntime")
	assert_not_null(quests, "QuestRuntime exists under Main/Systems")
	assert_not_null(rewards, "RewardRuntime exists under Main/Systems")
	if quests == null or rewards == null or _dialogue == null or knowledge == null \
			or relationship == null or inventory == null or progression == null \
			or combat == null or npcs == null or world == null:
		_teardown(main)
		return
	var service := quests.get_service()
	var player := world.call("get_player") as Node2D
	var character := world.call("get_player_character") as CharacterState
	var graph := relationship.get_service()
	var config := relationship.get_config()

	# --- 1. spawn: a line of purpose, nothing taken, nothing modal --------------------------
	assert_true(quests.is_session_active(), "the quest session is live in a running game")
	assert_true(rewards.is_session_active(), "and so is the reward ledger's")
	assert_eq(_count_root("QuestRuntime") + _count_root("RewardRuntime"), 0,
		"neither is an autoload (the budget stays five)")
	assert_false(quests.is_processing() or rewards.is_processing(), "neither runs per frame")
	var hub: Node = router.call("get_current_scene")
	var hud := _find_hud(hub)
	_panel = hud.dialogue_panel()
	assert_eq(hud.purpose_text(), _t(loc, "QUEST_UNQUIET_VEIN_LEAD"),
		"at spawn the place plaque says where to go ('%s')" % hud.purpose_text())
	assert_eq([service.phase_of(VEIN), service.phase_of(PILLS)],
		[QuestService.Phase.AVAILABLE, QuestService.Phase.AVAILABLE],
		"and nothing was taken on the player's behalf")
	assert_true(bool(input.call("is_gameplay_active")), "no modal greeted the player")
	assert_false(hud.is_quest_journal_open() or hud.is_dialogue_open(), "nothing is open")
	var here := player.global_position
	Input.action_press(MOVE_RIGHT)
	for _i in 12:
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	assert_true(player.global_position.distance_to(here) > 5.0, "the player can simply walk")
	_step("1. spawn: the plaque states a lead; nothing accepted, nothing modal")

	# --- 2. the elder offers nothing to one who has not read ---------------------------------
	var shen := hub.get_node_or_null("Interactables/ShenBuqi") as WorldNpc
	await _talk_to(player, hub, shen, Vector2(70, 6))
	await _advance_to(&"shen_hub")
	assert_eq(_panel.choice_ids(), [&"shen_leave"] as Array[StringName],
		"with the stele unread there is no task to ask about")
	await _press_until(OPEN_MENU, func() -> bool: return not _dialogue.is_open())
	_step("2. unread: the elder offers no task")

	# --- 3. read the stele; hear the ask; DECLINE ------------------------------------------
	var stele := hub.get_node_or_null("KnowledgeSources/LacHaStele") as Node2D
	player.global_position = stele.global_position + Vector2(0, 20)  # setup: at the stele
	await _wait_until(func() -> bool: return hub.call("active_knowledge_source") != null, 30)
	await _press_until(INTERACT, func() -> bool: return knowledge.get_service().knows(STELE))
	await _talk_to(player, hub, shen, Vector2(70, 6))
	await _advance_to(&"shen_hub")
	assert_true(_panel.choice_ids().has(&"shen_task_ask"), "a reader may ask what weighs on him")
	await _say(&"shen_task_ask", &"shen_task_why")
	for _i in 4:
		await scene_tree.process_frame
	assert_eq(_dialogue.current_node_id(), &"shen_task_why",
		"the press that asked did not also skip his reason")
	await _advance_to(&"shen_task_offer")
	for _i in 4:
		await scene_tree.process_frame
	assert_eq(service.phase_of(VEIN), QuestService.Phase.AVAILABLE,
		"hearing the ask — and the press that reached it — accepted nothing")
	assert_eq(_panel.choice_ids(), [&"shen_task_accept", &"shen_task_decline"]
		as Array[StringName], "the ask is an explicit choice")
	await _say(&"shen_task_decline", &"shen_hub")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.AVAILABLE, "declined: still on offer")
	assert_eq(quests.to_dict()["quests"], {}, "with no record anywhere")
	assert_eq(hud.purpose_text(), _t(loc, "QUEST_UNQUIET_VEIN_LEAD"), "the lead still stands")
	_step("3. the ask was heard and DECLINED with real keys; nothing changed")

	# --- 4. ask again; ACCEPT ---------------------------------------------------------------
	await _say(&"shen_task_ask", &"shen_task_why")
	await _advance_to(&"shen_task_offer")
	assert_eq(_panel.selected_choice_id(), &"shen_task_accept", "accepting is under the cursor")
	await _say(&"shen_task_accept", &"shen_task_taken")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.ACTIVE, "a REAL key accepted the task")
	assert_true(_t(loc, "QUEST_UNQUIET_VEIN_TITLE") in hud.notice_text(),
		"the band says what was taken on ('%s')" % hud.notice_text())
	assert_true("Q " in hud.notice_text(), "and names the journal's key there")
	assert_eq(hud.purpose_text(), _t(loc, "QUEST_UNQUIET_VEIN_GOAL"),
		"the plaque now says what to do ('%s')" % hud.purpose_text())
	await _press_until(INTERACT, func() -> bool: return not _dialogue.is_open())
	assert_true(bool(input.call("is_gameplay_active")), "the talk ended and control returned")
	_step("4. asked again and ACCEPTED; announced; the plaque states the goal")

	# --- 5. the journal: its key, not modal, Esc steps back ONE level -------------------------
	await _press_until(JOURNAL, func() -> bool: return hud.is_quest_journal_open())
	assert_true(hud.is_quest_journal_open(), "a REAL key opened the journal")
	assert_true(bool(input.call("is_gameplay_active")), "it holds no keys: gameplay stays active")
	var journal := hud.quest_journal_panel()
	assert_eq(journal.shown_quest_ids(), [VEIN, PILLS] as Array[StringName],
		"what is under way comes first, then what is on offer")
	assert_true(journal.block_text(VEIN).contains(_t(loc, "UI_QUEST_PHASE_ACTIVE")),
		"the elder's task reads as under way")
	here = player.global_position
	Input.action_press(MOVE_RIGHT)
	for _i in 12:
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	assert_true(player.global_position.distance_to(here) > 5.0,
		"the player walks with the journal open")
	for _i in 6:
		await scene_tree.process_frame
	assert_true(hud.is_quest_journal_open(), "and it stays open while they do")
	await _press_until(JOURNAL, func() -> bool: return not hud.is_quest_journal_open())
	for _i in 6:
		await scene_tree.process_frame
	assert_false(hud.is_quest_journal_open(),
		"its key closes it, and the same press does not reopen it")
	await _press_until(JOURNAL, func() -> bool: return hud.is_quest_journal_open())
	await _press_until(OPEN_MENU, func() -> bool: return not hud.is_quest_journal_open())
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_NONE,
		"Esc closed the journal and asked nothing about leaving")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "the game is still running")
	await _press_until(OPEN_MENU,
		func() -> bool: return hud.session_prompt_kind() == GameplayHUD.PROMPT_LEAVE)
	await _press_until(OPEN_MENU,
		func() -> bool: return hud.session_prompt_kind() == GameplayHUD.PROMPT_NONE)
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "Esc again only ASKED; Esc once more stayed")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.ACTIVE, "and no progress was lost")
	_step("5. the journal opens and closes on its key, is not modal, and Esc steps back one level")

	# --- 6. give the task back, by a second explicit answer; then take it again ---------------
	await _talk_to(player, hub, shen, Vector2(70, 6))
	await _advance_to(&"shen_hub")
	assert_false(_panel.choice_ids().has(&"shen_task_ask"), "it is not offered twice")
	assert_false(_panel.choice_ids().has(&"shen_task_report_word")
		or _panel.choice_ids().has(&"shen_task_report_fight"), "and there is nothing to report")
	await _say(&"shen_task_about", &"shen_task_waiting")
	await _say(&"shen_task_giveup", &"shen_task_confirm")
	for _i in 4:
		await scene_tree.process_frame
	assert_eq(service.phase_of(VEIN), QuestService.Phase.ACTIVE,
		"asking to be released — and the press that asked — gave nothing up")
	assert_eq(_panel.selected_choice_id(), &"shen_task_stay",
		"the answer under the cursor KEEPS the task")
	await _say(&"shen_task_abandon", &"shen_task_released")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.AVAILABLE, "given back with real keys")
	assert_true(_t(loc, "QUEST_UNQUIET_VEIN_TITLE") in hud.notice_text(), "and said so")
	assert_eq(hud.purpose_text(), _t(loc, "QUEST_UNQUIET_VEIN_LEAD"), "the plaque is a lead again")
	await _press_until(INTERACT, func() -> bool: return not _dialogue.is_open())
	await _talk_to(player, hub, shen, Vector2(70, 6))
	await _advance_to(&"shen_hub")
	await _say(&"shen_task_ask", &"shen_task_why")
	await _advance_to(&"shen_task_offer")
	await _say(&"shen_task_accept", &"shen_task_taken")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.ACTIVE, "and taken again")
	await _press_until(INTERACT, func() -> bool: return not _dialogue.is_open())
	_step("6. the task was given back (default: keep it) and taken again")

	# --- 7. the field: the scout's errand ---------------------------------------------------
	await _interact_to_transition(player, "map_hub")
	assert_eq(router.call("get_current_key"), "map_field", "the player travelled to the field")
	var field: Node = router.call("get_current_scene")
	hud = _find_hud(field)
	_panel = hud.dialogue_panel()
	assert_eq(hud.purpose_text(), _t(loc, "QUEST_UNQUIET_VEIN_GOAL"),
		"the new map's HUD shows the purpose at once: a map change lost nothing")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.ACTIVE, "the task is still under way")
	var ko := field.get_node_or_null("Interactables/KoThan") as WorldNpc
	await _talk_to(player, field, ko, Vector2(78, 4))
	await _advance_to(&"ko_hub")
	assert_eq(_panel.choice_ids().size(), 5, "his four answers and the errand he has")
	await _say(&"ko_pills_ask", &"ko_pills_offer")
	await _say(&"ko_pills_accept", &"ko_pills_taken")
	assert_eq(service.phase_of(PILLS), QuestService.Phase.ACTIVE, "the scout's errand is taken")
	assert_true(_t(loc, "DLG_KO_PILLS_TAKEN") == _panel.line_text(),
		"and he says where the hall leaves its pills")
	_step("7. in the field the scout's errand was taken; two quests are under way")

	# --- 8. the knowledge route: his word answers the elder's question ------------------------
	await _advance_to(&"")
	await _talk_to(player, field, ko, Vector2(78, 4))
	await _advance_to(&"ko_hub")
	await _say(&"ko_ask_woods", &"ko_woods")
	assert_true(knowledge.get_service().knows(WORD), "the Knowledge Core holds the scout's word")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.READY,
		"which makes the elder's task READY — with no wolf fought")
	assert_eq(service.state().progress_of(VEIN, &"fight"), 0, "no defeat was counted")
	assert_eq(hud.purpose_text(), _t(loc, "QUEST_UNQUIET_VEIN_RETURN"),
		"the plaque says who to return to ('%s')" % hud.purpose_text())
	await _press_until(INTERACT, func() -> bool: return _dialogue.current_node_id() == &"ko_hub")
	await _press_until(OPEN_MENU, func() -> bool: return not _dialogue.is_open())
	await _wait_until(func() -> bool:
		return _t(loc, "QUEST_UNQUIET_VEIN_RETURN") in hud.notice_text(), 600)
	assert_true(_t(loc, "QUEST_UNQUIET_VEIN_RETURN") in hud.notice_text(),
		"and the band said it was ready ('%s')" % hud.notice_text())
	_step("8. the scout's word (knowledge) made the elder's task ready without a fight")

	# --- 9. real combat reaches the quest: a kill is counted, and a threat closes the journal -
	await _press_until(JOURNAL, func() -> bool: return hud.is_quest_journal_open())
	var enemies: Array = combat.call("enemies")
	var wolf := enemies[0] as Node2D
	player.global_position = wolf.global_position + Vector2(60, 0)  # setup: beside a den
	await _wait_until(func() -> bool: return bool(combat.call("is_player_threatened")), 240)
	assert_true(bool(combat.call("is_player_threatened")), "a Vụ Lang turned on the player")
	assert_false(hud.is_quest_journal_open(),
		"and the journal yielded at once, like every reading surface")
	var attack := player.get_node_or_null("AttackComponent") as AttackComponent
	for _round in 40:
		if bool(wolf.call("is_dead")):
			break
		player.global_position = wolf.global_position - Vector2(16, 0)
		attack.set_facing(Vector2.RIGHT)
		await _fire_action(ATTACK)
		for _i in 24:
			await scene_tree.process_frame
			if bool(wolf.call("is_dead")):
				break
	assert_true(bool(wolf.call("is_dead")), "real attack keys killed it")
	assert_eq(service.state().progress_of(VEIN, &"fight"), 1,
		"and the quest counted that defeat through the real combat session")
	var xp_after_kill := character.xp
	assert_true(xp_after_kill > 0, "the same defeat paid its XP through the shared ledger")
	var ledger := rewards.get_ledger()
	assert_eq(ledger.count(), 1, "one entry in the ONE ledger: the defeat (no quest is paid yet)")
	_step("9. a real kill was counted by the quest; the journal closed when the wolf engaged")

	# --- 10. a FULL BAG refuses the reward; nothing is paid; the talk stays -------------------
	await _interact_to_transition(player, "map_field")
	assert_eq(router.call("get_current_key"), "map_hub", "back in the hub")
	hub = router.call("get_current_scene")
	hud = _find_hud(hub)
	_panel = hud.dialogue_panel()
	shen = hub.get_node_or_null("Interactables/ShenBuqi") as WorldNpc
	var bag := inventory.get_bag()
	inventory.give(SWORD, bag.capacity)  # SETUP: fill every slot (a blade does not stack)
	assert_eq(bag.stack_count(), bag.capacity, "setup: the satchel is full")
	assert_eq(inventory.count_of(PILL), 0, "and holds no pill a reward could top up")
	var swords := inventory.count_of(SWORD)
	await _talk_to(player, hub, shen, Vector2(70, 6))
	await _advance_to(&"shen_hub")
	assert_true(_panel.choice_ids().has(&"shen_task_report_word"),
		"he can be told what the scout says")
	assert_false(_panel.choice_ids().has(&"shen_task_report_fight"),
		"the word outranks the fight: one report, not two")
	await _select(&"shen_task_report_word")
	await _fire_action(INTERACT)
	await _wait_until(func() -> bool:
		return _t(loc, "UI_QUEST_REWARD_NO_ROOM") in hud.notice_text(), 60)
	assert_true(_t(loc, "UI_QUEST_REWARD_NO_ROOM") in hud.notice_text(),
		"the band says WHY: no room in the satchel ('%s')" % hud.notice_text())
	assert_eq(_dialogue.current_node_id(), &"shen_hub",
		"the conversation did not move on as though it had worked")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.READY, "the task is still ready")
	assert_eq([inventory.count_of(PILL), character.xp, _respect(graph, config, character)],
		[0, xp_after_kill, 0], "no pill, no XP and no respect were paid")
	assert_eq(ledger.count(), 1, "and nothing was recorded as paid")
	_step("10. a full satchel refused the reward: said why, nothing paid, the talk stayed")

	# --- 11. with room made, the SAME answer pays in full, once ------------------------------
	await _press_until(OPEN_MENU, func() -> bool: return not _dialogue.is_open())
	inventory.take(SWORD, swords)  # SETUP: empty the satchel again
	await _talk_to(player, hub, shen, Vector2(70, 6))
	await _advance_to(&"shen_hub")
	await _say(&"shen_task_report_word", &"shen_task_done_word")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.COMPLETED, "completed")
	assert_eq(inventory.count_of(PILL), 2, "two pills from the hall's store are in the satchel")
	assert_eq(character.xp, xp_after_kill + 10, "10 XP through the progression owner")
	assert_eq(_respect(graph, config, character), 10, "his respect, in the relationship graph")
	assert_true(ledger.has(&"quest:quest_unquiet_vein"), "and the ledger records it as paid")
	await _wait_until(func() -> bool:
		return _t(loc, "ITEM_BO_HUYET_DAN_NAME") in hud.notice_text(), 900)
	assert_true(_t(loc, "ITEM_BO_HUYET_DAN_NAME") in hud.notice_text(),
		"the band names what was received ('%s')" % hud.notice_text())
	assert_eq(service.phase_of(PILLS), QuestService.Phase.READY,
		"and those very pills are what the scout is owed: his errand is READY")
	assert_eq(hud.purpose_text(), _t(loc, "QUEST_TREELINE_PILLS_RETURN"),
		"the plaque moves on to it ('%s')" % hud.purpose_text())
	await _press_until(INTERACT, func() -> bool: return not _dialogue.is_open())
	await _talk_to(player, hub, shen, Vector2(70, 6))
	await _advance_to(&"shen_hub")
	assert_false(_panel.choice_ids().has(&"shen_task_report_word")
		or _panel.choice_ids().has(&"shen_task_ask"), "the elder's task is over: he offers no more")
	assert_eq(quests.turn_in(VEIN, SHEN).reason, QuestService.REFUSE_ALREADY_DONE,
		"and asked again by any path it is refused")
	assert_eq(inventory.count_of(PILL), 2, "nothing was paid twice")
	await _press_until(OPEN_MENU, func() -> bool: return not _dialogue.is_open())
	_step("11. with room made the reward was paid once: pills, XP, respect")

	# --- 12. carry the pills to the scout ---------------------------------------------------
	await _interact_to_transition(player, "map_hub")
	field = router.call("get_current_scene")
	hud = _find_hud(field)
	_panel = hud.dialogue_panel()
	ko = field.get_node_or_null("Interactables/KoThan") as WorldNpc
	var stones := inventory.count_of(STONE)
	var affinity := RegardRules.read(graph, config, KO, character.instance_id, &"affinity")
	await _talk_to(player, field, ko, Vector2(78, 4))
	await _advance_to(&"ko_hub")
	assert_true(_panel.choice_ids().has(&"ko_pills_give"), "handing over is offered")
	await _say(&"ko_pills_give", &"ko_pills_done")
	assert_eq(service.phase_of(PILLS), QuestService.Phase.COMPLETED, "the errand is done")
	assert_eq([inventory.count_of(PILL), inventory.count_of(STONE)], [0, stones + 3],
		"two pills left the satchel and three stones came in, as one exchange")
	assert_eq(RegardRules.read(graph, config, KO, character.instance_id, &"affinity"),
		affinity + 15, "his affinity moved in the relationship graph")
	assert_eq(npcs.standing_for(npcs.get_service().catalog().shop_of_keeper(KO)).value,
		affinity + 15, "the very number his shop prices on")
	assert_eq(hud.purpose_text(), "", "nothing is left to be about: the plaque line is gone")
	await _press_until(INTERACT, func() -> bool: return not _dialogue.is_open())
	await _talk_to(player, field, ko, Vector2(78, 4))
	await _advance_to(&"ko_hub")
	assert_eq(_panel.choice_ids().size(), 4, "he is back to his four answers")
	assert_eq(ledger.count(), 8, ("the ONE ledger holds exactly: the defeat (1), the elder's "
		+ "bag / xp / regard parts and the quest itself (4), the scout's bag / regard parts "
		+ "and the quest itself (3) — got %s") % str(ledger.to_dict()["claimed"]))
	_step("12. the pills changed hands for three stones and his regard; both quests are done")

	# --- 13. return to the menu with a conversation open -------------------------------------
	assert_true(_dialogue.is_open(), "a conversation is open")
	field.emit_signal("return_to_menu_requested")
	await scene_tree.process_frame
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.MENU, "the game returned to the menu")
	assert_false(quests.is_session_active() or rewards.is_session_active(),
		"the quest and reward sessions ended")
	var trace: Array = main.call("get_last_teardown_order")
	assert_eq([trace[0], trace[1]], [&"DialogueRuntime", &"QuestRuntime"],
		"conversations ended first, then quests (%s)" % str(trace))
	assert_true(trace.find(&"RewardRuntime") > trace.find(&"ProgressionRuntime"),
		"and the ledger outlived progression, which records in it")
	assert_eq(int(input.call("current_context")), int(input.Context.MENU),
		"no modal context survived the teardown")
	_step("13. return to menu: Dialogue ended first, then Quest; the ledger after progression")
	_teardown(main)
	await scene_tree.process_frame


func _t(loc: Node, key: String) -> String:
	return String(loc.call("t", key))


func _respect(graph: RelationshipService, config: RelationshipConfigData,
		character: CharacterState) -> int:
	return RegardRules.read(graph, config, SHEN, character.instance_id, &"respect")


func _step(step_name: String) -> void:
	var failed := get_failures().size()
	print("[e2e-quest] [%s] %s" % ["PASS" if failed == _passed else "FAIL", step_name])
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


## SETUP then a REAL walk and a REAL key: stand `offset` from `npc` (out of reach), hold
## move-left until the map offers them, then press interact until their conversation opens.
func _talk_to(player: Node2D, map: Node, npc: WorldNpc, offset: Vector2) -> void:
	assert_not_null(npc, "the person is in this map")
	if npc == null:
		return
	player.global_position = npc.global_position + offset
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	var before := player.global_position
	Input.action_press(MOVE_LEFT)
	await _wait_until(func() -> bool: return map.call("active_interactable") == npc, 180)
	Input.action_release(MOVE_LEFT)
	await scene_tree.physics_frame
	assert_true(player.global_position.distance_to(before) > 20.0,
		"the player WALKED into reach with a held move key")
	await _press_until(INTERACT, func() -> bool: return _dialogue.is_open())


## Acknowledge the current line until the conversation is at `node_id` ("" = closed).
func _advance_to(node_id: StringName) -> void:
	await _press_until(INTERACT, func() -> bool:
		return (not _dialogue.is_open()) if node_id == &"" \
			else _dialogue.current_node_id() == node_id)


## Move the cursor to `choice_id` with real move keys.
func _select(choice_id: StringName) -> void:
	assert_true(_panel.choice_ids().has(choice_id), "'%s' is offered (%s)"
		% [choice_id, str(_panel.choice_ids())])
	for _i in 8:
		if _panel.selected_choice_id() == choice_id:
			return
		await _fire_action(MOVE_DOWN)
		for _j in 3:
			await scene_tree.process_frame
	assert_eq(_panel.selected_choice_id(), choice_id, "real move keys selected '%s'" % choice_id)


## Select `choice_id` and say it with ONE real interact; the conversation must reach `then`.
func _say(choice_id: StringName, then: StringName) -> void:
	await _select(choice_id)
	await _press_until(INTERACT, func() -> bool: return _dialogue.current_node_id() == then)
	assert_eq(_dialogue.current_node_id(), then, "saying '%s' led to '%s'" % [choice_id, then])


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
	for a in [MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN, INTERACT, OPEN_MENU, ATTACK, JOURNAL]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

extends TestCase
## Real-application STORY E2E (Phase 20, D-072) — its own Godot process (D-019).
##
## Boots the real `main.tscn` against the live autoloads and plays the opening with REAL key
## events: the menu's New Game, the identity screen (moved through, backed out of, reopened,
## confirmed with a doubled press), the run that starts, the vignette and the arrival, a walk,
## leaving, and a second run as someone else.
##
## NOTHING HERE REACHES PAST THE PLAYER'S BOUNDARY. No story flag is set, no knowledge
## granted, no session started and no scene skipped by calling an owner: every state change
## below is the consequence of a key. What IS read directly is the authoritative state, to
## check that what the screen says is what the owners hold.

const MAIN_SCENE_PATH := "res://main.tscn"
const UI_ACCEPT := &"ui_accept"
const UI_CANCEL := &"ui_cancel"
const UI_UP := &"ui_up"
const UI_DOWN := &"ui_down"
const UI_LEFT := &"ui_left"
const UI_RIGHT := &"ui_right"
const INTERACT := &"interact"
const OPEN_MENU := &"open_menu"
const MOVE_RIGHT := &"move_right"
const SHEN := &"actor_elder_shen"
const LIN := &"actor_disciple_lin"
const MOVE_LEFT := &"move_left"
const MOVE_DOWN := &"move_down"
const MOVE_UP := &"move_up"
const STELE := &"know_lac_ha_stele_record"
const ISSUE := &"flag_outpost_issue"
const KO := &"actor_scout_ko"
const ATTACK := &"attack"
const CULTIVATE := &"cultivate"
const NIGHT_PREFIX := "map_field__night__"
const CHRONICLE := &"chronicle"

var _passed: int = 0
var _dialogue: DialogueRuntime = null
var _panel: DialoguePanel = null
var _withheld: Array[StringName] = []


func test_real_story_flow() -> void:
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
	var world: Node = main.get_node("Systems/WorldRuntime")
	var story := main.get_node("Systems/StoryRuntime") as StoryRuntime
	var sects: Node = main.get_node("Systems/SectRuntime")
	var knowledge := main.get_node("Systems/KnowledgeRuntime") as KnowledgeRuntime
	var inventory := main.get_node("Systems/InventoryRuntime") as InventoryRuntime
	var relationship := main.get_node("Systems/RelationshipRuntime") as RelationshipRuntime
	# FG-4: every arrival in this whole walk — three runs, two Origins, both answers to the
	# Night — is held to "what the map shows is what the story says" before a frame is drawn.
	world.connect("active_map_ready", func() -> void:
		_arrivals += 1
		_judge_arrival.call_deferred(main, _arrivals))

	# --- 1. the menu's New Game opens the identity screen — and starts nothing ----------------
	assert_not_null(RunKit.menu_of(main), "the menu is up")
	await _press_until(UI_ACCEPT, func() -> bool: return RunKit.identity_of(main) != null)
	var identity := RunKit.identity_of(main) as IdentityScreen
	assert_not_null(identity, "a real accept on New Game opened the identity screen")
	if identity == null:
		_teardown(main)
		return
	assert_false(RunKit.menu_of(main).visible, "the menu stands aside for it")
	assert_eq(gs.get_phase(), gs.Phase.MENU, "the lifecycle is still MENU: no run exists")
	assert_false(gs.is_session_active() or bool(world.call("is_session_active"))
		or story.is_session_active(), "no session of any kind has started")
	assert_null(world.call("get_player"), "and there is no player")
	_step("1. New Game opened the identity screen; nothing was started")

	# --- 2. move through it with real keys; the screen says what is being chosen --------------
	assert_eq(identity.selected_origin_id(), &"origin_ho_tieu", "it opens on the first Origin")
	await _fire_action(UI_DOWN)
	await _fire_action(UI_DOWN)
	assert_eq(identity.shown_origin_id(), &"origin_lang_y", "two downs: the cursor is on the third")
	assert_eq((identity.find_child("OriginProblem", true, false) as Label).text,
		String(loc.call("t", "ORIGIN_LANG_Y_PROBLEM")), "whose problem is described")
	assert_eq(identity.selected_origin_id(), &"origin_ho_tieu",
		"but LOOKING chose nothing: the first Origin is still the chosen one")
	await _fire_action(UI_ACCEPT)
	assert_eq(identity.selected_origin_id(), &"origin_lang_y", "accept chose it")
	await _fire_action(UI_LEFT)
	assert_eq(identity.shown_appearance_id(), &"appearance_wanderer_m",
		"left: the cursor lands on the look already chosen")
	await _fire_action(UI_DOWN)
	assert_eq(identity.shown_appearance_id(), &"appearance_wanderer_f", "down: the next look")
	assert_true((identity.find_child("Portrait", true, false) as TextureRect).texture
		.resource_path.ends_with("medallion_player_f_proto.png"), "which is on the stage")
	assert_eq(identity.selected_appearance_id(), &"appearance_wanderer_m", "and not yet chosen")
	await _fire_action(UI_ACCEPT)
	assert_eq(identity.selected_appearance_id(), &"appearance_wanderer_f", "accept chose it")
	await _fire_action(UI_RIGHT)
	assert_eq(identity.shown_origin_id(), &"origin_lang_y",
		"right: back on the Origin that was chosen, still chosen")
	var summary := (identity.find_child("Summary", true, false) as Label).text
	assert_true(summary.contains(String(loc.call("t", "ORIGIN_LANG_Y_NAME")))
		and summary.contains(String(loc.call("t", "APPEARANCE_WANDERER_F_NAME"))),
		"and the choice is stated in words above the buttons ('%s')" % summary)
	_step("2. the cursor looked, accept chose; the stage, detail and summary followed")

	# --- 3. Esc backs out: the menu again, and STILL nothing started --------------------------
	await _press_until(UI_CANCEL, func() -> bool: return RunKit.identity_of(main) == null)
	assert_null(RunKit.identity_of(main), "a real Esc closed the identity screen")
	assert_true(RunKit.menu_of(main) != null and RunKit.menu_of(main).visible,
		"the menu is back")
	assert_eq(gs.get_phase(), gs.Phase.MENU, "still MENU")
	assert_false(gs.is_session_active() or bool(world.call("is_session_active"))
		or story.is_session_active() or knowledge.is_session_active(),
		"backing out left no session behind")
	assert_null(world.call("get_player"), "and no player")
	assert_eq(int(input.call("current_context")), int(input.Context.MENU), "input is the menu's")
	_step("3. Esc backed out: no run, no session, no player")

	# --- 4. reopen, choose, and confirm with a DOUBLED press: exactly one run ----------------
	await scene_tree.process_frame
	await _press_until(UI_ACCEPT, func() -> bool: return RunKit.identity_of(main) != null)
	identity = RunKit.identity_of(main) as IdentityScreen
	assert_not_null(identity, "New Game opens it again")
	if identity == null:
		_teardown(main)
		return
	assert_eq([identity.selected_appearance_id(), identity.selected_origin_id()],
		[&"appearance_wanderer_m", &"origin_ho_tieu"],
		"a fresh screen: what was moved to last time was never committed")
	for _i in 4:
		await _fire_action(UI_DOWN)
	await _fire_action(UI_ACCEPT)
	assert_eq(identity.selected_origin_id(), &"origin_thu_thu", "the fifth Origin, chosen")
	await _fire_action(UI_LEFT)
	await _fire_action(UI_DOWN)
	await _fire_action(UI_ACCEPT)
	assert_eq(identity.selected_appearance_id(), &"appearance_wanderer_f", "the woman's look")
	await _fire_action(UI_RIGHT)
	await _fire_action(UI_DOWN)
	assert_true((identity.find_child("Begin", true, false) as Button).has_focus(),
		"down from the last Origin is the Begin button")
	# Two accepts in consecutive frames: a held key, a double tap.
	var first := _key_event_for(UI_ACCEPT, true)
	Input.parse_input_event(first)
	Input.flush_buffered_events()
	await scene_tree.process_frame
	Input.parse_input_event(_key_event_for(UI_ACCEPT, false))
	Input.parse_input_event(_key_event_for(UI_ACCEPT, true))
	Input.flush_buffered_events()
	await scene_tree.process_frame
	Input.parse_input_event(_key_event_for(UI_ACCEPT, false))
	Input.flush_buffered_events()
	await _wait_until(func() -> bool: return gs.get_phase() == gs.Phase.RUNNING, 30)
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "the run started")
	assert_eq(router.call("get_current_key"), "map_hub", "in the village")
	assert_null(RunKit.identity_of(main), "the identity screen is gone")
	assert_eq(_count_players(main), 1, "ONE player exists: the doubled press started one run")
	_step("4. confirmed with a doubled press: one run, in the hub")

	# --- 5. the run is what was chosen — in the OWNERS, not just on screen -------------------
	var character: CharacterState = world.call("get_player_character")
	var player := world.call("get_player") as Node2D
	assert_true(story.is_session_active(), "the story session is live")
	assert_true(story.get_service().origin_is(&"origin_thu_thu"), "as the Origin confirmed")
	assert_eq(character.gender, int(CharacterTemplateData.Gender.FEMALE),
		"the character is the look confirmed")
	assert_eq(player.call("get_base_visual_id"), &"vis_player_f", "and is DRAWN as it")
	assert_true(knowledge.get_service().knows(&"know_survey_notation"),
		"the Origin's knowledge is held, in the Knowledge Core")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), SHEN,
		character.instance_id, &"affinity"), -15,
		"its first impression is in the relationship graph, once")
	assert_eq(inventory.get_bag().stack_count(), 0, "and this Origin carries nothing")
	assert_eq(sects.call("get_player_sect_id"), &"", "the player belongs to no sect")
	assert_eq([character.sect_id, character.sect_rank, character.faction_id], [&"", &"", &""],
		"and the character's own record agrees")
	var hub: Node = router.call("get_current_scene")
	var hud := _find_hud(hub)
	assert_not_null(hud, "the hub has its HUD")
	if hud == null:
		_teardown(main)
		return
	assert_true(hud.player_portrait_path().ends_with("medallion_player_f_proto.png"),
		"the plaque shows the chosen look's own portrait")
	var hud_text := _all_label_text(hud)
	assert_true(String(loc.call("t", "UI_HUD_SECT_NONE")) in hud_text,
		"and says, in words, that the player has no sect")
	_step("5. Origin, look, kit and NO sect are what the owners hold")

	# --- 6. the run opens on the Origin's vignette, over a covered map ------------------------
	var panel := hud.story_scene_panel()
	assert_true(hud.is_story_scene_open(), "a scene is on screen")
	assert_eq(int(input.call("current_context")), int(input.Context.UI_MODAL),
		"and holds the keys")
	assert_true(panel.covers_the_map(), "it is somewhere else: the village is covered")
	assert_eq(panel.place_text(), String(loc.call("t", "STORY_SCENE_VIGNETTE_THU_THU_PLACE")),
		"it is THIS Origin's vignette, opening on where and when")
	assert_eq(panel.pips_text(), "1 / 4", "step 1 of 4")
	assert_eq(hud.notice_text(), "",
		"what the Origin already knew is not announced as something just learned")
	var at := player.global_position
	await _fire_action(MOVE_RIGHT)
	await scene_tree.physics_frame
	assert_eq(player.global_position, at, "the player cannot walk under a scene")
	await _press_until(INTERACT, func() -> bool: return panel.pips_text() != "1 / 4")
	assert_eq(panel.pips_text(), "2 / 4", "ONE real interact showed ONE more step")
	assert_eq(panel.body_text(), String(loc.call("t", "STORY_SCENE_VIGNETTE_THU_THU_1")),
		"the first line of the memory")
	assert_eq(story.get_service().state().beat_id, &"beat_road", "the beat has not moved yet")
	_step("6. the vignette opened, modal, over a covered map; interact showed one step")

	# --- 7. Esc SKIPS the scene (never leaves the game); the arrival follows ------------------
	await _press_until(OPEN_MENU, func() -> bool:
		return story.get_service().state().beat_id != &"beat_road")
	assert_eq(story.get_service().state().beat_id, &"beat_arrival",
		"skipping the vignette completed its beat exactly as watching it would")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "Esc skipped the SCENE, not the session")
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_NONE,
		"and the same press asked no question about leaving")
	assert_true(hud.is_story_scene_open(), "the arrival scene follows")
	assert_false(panel.covers_the_map(), "it is here: the village shows behind it")
	assert_eq(panel.place_text(), String(loc.call("t", "STORY_SCENE_ARRIVAL_PLACE")),
		"it names the village")
	for expected: String in ["2 / 3", "3 / 3"]:
		await _press_until(INTERACT, func() -> bool: return panel.pips_text() == expected)
		assert_eq(panel.pips_text(), expected, "one step per press")
	await _press_until(INTERACT, func() -> bool: return not hud.is_story_scene_open())
	assert_false(hud.is_story_scene_open(), "the last step's interact ended the scene")
	assert_true(bool(input.call("is_gameplay_active")), "and control is the player's")
	assert_eq(story.get_service().state().beat_id, &"beat_arrival", "on the arrival beat")
	assert_eq(story.get_service().state().completed_beats, [&"beat_road"] as Array[StringName],
		"with exactly one beat completed: no step, skipped or watched, completed another")
	_step("7. Esc skipped the vignette; the arrival was read through; control returned")

	# --- 8. the player walks; the strip sells no sect to a nobody -----------------------------
	var before := player.global_position
	Input.parse_input_event(_key_event_for(MOVE_RIGHT, true))
	Input.flush_buffered_events()
	await _wait_until(func() -> bool: return player.global_position.x > before.x + 4.0, 60)
	Input.parse_input_event(_key_event_for(MOVE_RIGHT, false))
	Input.flush_buffered_events()
	assert_true(player.global_position.x > before.x + 4.0, "a real move key walks the player")
	var strip := hud.find_child("PromptStrip", true, false) as Control
	assert_true(strip.visible, "the prompt strip is back")
	for row_name: String in ["SectPrompt", "PoliticsPrompt"]:
		assert_false((hud.find_child(row_name, true, false) as Control).visible,
			"and does not advertise '%s' to someone with no sect" % row_name)
	_step("8. the player walks with real keys; no sect is advertised")

	# --- 8a. arrival: the west road, a first person, a line only this Origin gets -------------
	_dialogue = main.get_node("Systems/DialogueRuntime") as DialogueRuntime
	_panel = hud.dialogue_panel()
	var service := story.get_service()
	assert_true(hub.get_node("Spawns/from_road").global_position.distance_to(before) < 4.0,
		"the run began on the west road, where the cart let the player down")
	assert_eq(service.state().beat_id, &"beat_arrival", "the story waits for a first meeting")
	assert_eq([hud.purpose_source(), hud.purpose_text()], [GameplayHUD.PURPOSE_FROM_STORY,
		String(loc.call("t", "STORY_BEAT_ARRIVAL_OBJECTIVE"))],
		"the plaque says what the STORY asks next, not a quest nobody has taken on")
	assert_false((hub.get_node("KnowledgeSources/SurveySheet") as Node2D).visible,
		"nothing is hidden under the stele yet: the Night has not happened")
	# The Chronicle's key is TAUGHT (D-073 §4, H21-10): once, when the book first has
	# something in it, in the label InputService reports — and not before, and not while the
	# player is reading someone's line.
	var chronicle_hint := String(loc.call("t_args", "UI_CHRONICLE_HINT",
		{"key": input.call("get_action_display_label", CHRONICLE)}))
	assert_false(chronicle_hint.contains("{key}") or chronicle_hint.contains("chronicle"),
		"the hint names a real key label ('%s')" % chronicle_hint)
	assert_ne(hud.notice_text(), chronicle_hint, "nothing is taught before there is a book")
	var lin := hub.get_node_or_null("Interactables/LinYue") as WorldNpc
	await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
	assert_eq(_dialogue.current_node_id(), &"lin_greet", "a stranger's greeting")
	assert_ne(hud.notice_text(), chronicle_hint, "nor over the line she is saying")
	assert_true(service.state().has_met(LIN), "the story records the meeting")
	assert_eq(service.state().beat_id, &"beat_contacts", "and the arrival beat is complete")
	await _advance_to(&"lin_hub")
	assert_false(_panel.choice_ids().has(&"lin_press"),
		"she confides nothing to someone who has taken no part in the village")
	await _say(&"lin_notation", &"lin_notation_line")
	await _advance_to(&"lin_hub")
	assert_false(_panel.choice_ids().has(&"lin_notation"),
		"a line said once is not offered again")
	await _say(&"lin_leave", &"")
	await _wait_until(func() -> bool: return hud.notice_text() == chronicle_hint, 600)
	assert_eq(hud.notice_text(), chronicle_hint,
		"when she has finished, the player is told the book exists and which key opens it")
	assert_false(hud.is_chronicle_open(), "being told opens nothing")
	assert_eq(int(input.call("current_context")), int(input.Context.GAMEPLAY),
		"and takes no key from the player")
	_step("8a. arrived by the road; met Lâm Nguyệt; this Origin's line was said once")

	# --- 8b. nothing lies free: the outpost's blade is held until the elder issues it ---------
	inventory.pickup_withheld.connect(_on_withheld)
	var sword := hub.get_node("Pickups/HubSword") as WorldItem
	player.global_position = sword.global_position - Vector2(40, 0)  # setup: beside the rack
	await scene_tree.physics_frame
	Input.action_press(MOVE_RIGHT)
	await _wait_until(func() -> bool: return not _withheld.is_empty(), 120)
	Input.action_release(MOVE_RIGHT)
	for _i in 20:
		await scene_tree.physics_frame  # keep standing on it: it is said once, not every tick
	assert_eq(_withheld, [&"pickup_hubsword"] as Array[StringName],
		"walking onto the blade says whose it is - once")
	assert_eq(inventory.count_of(&"item_kiem_thanh_thiet"), 0, "and takes nothing")
	assert_true(sword.visible, "the blade is still on the rack")

	# the carter and the elder: three people met completes the contacts beat
	var carter := hub.get_node_or_null("Interactables/QiMu") as WorldNpc
	await _talk_to(player, hub, carter, Vector2(30, 0))
	await _advance_to(&"te_hub")
	assert_eq(_panel.choice_ids(), [&"te_ask_load", &"te_ask_road", &"te_ledger", &"te_leave"]
		as Array[StringName], "the carter offers this Origin its own question, and no other's")
	await _say(&"te_ledger", &"te_ledger_line")
	await _advance_to(&"te_hub")
	await _say(&"te_leave", &"")
	assert_eq(service.state().beat_id, &"beat_contacts", "two met: still getting to know them")
	var shen := hub.get_node_or_null("Interactables/ShenBuqi") as WorldNpc
	await _talk_to(player, hub, shen, Vector2(30, 0))
	assert_eq(service.state().beat_id, &"beat_village_business",
		"three met: the story moves on to the village's own business")
	await _advance_to(&"shen_hub")
	await _say(&"shen_issue_ask", &"shen_issue")
	assert_true(service.flag_at_least(ISSUE, 1), "the elder issued the blade, in words")
	await _advance_to(&"shen_hub")
	await _say(&"shen_leave", &"")
	player.global_position = sword.global_position - Vector2(40, 0)
	await scene_tree.physics_frame
	Input.action_press(MOVE_RIGHT)
	await _wait_until(func() -> bool:
		return inventory.count_of(&"item_kiem_thanh_thiet") == 1, 120)
	Input.action_release(MOVE_RIGHT)
	assert_eq(inventory.count_of(&"item_kiem_thanh_thiet"), 1, "now the same walk takes it")
	assert_eq(_withheld.size(), 1, "with no second refusal")
	inventory.pickup_withheld.disconnect(_on_withheld)
	_step("8b. the blade was held, the elder issued it, and only then was it the player's")

	# --- 8c. the village's business, then whom to trust ---------------------------------------
	var stele := hub.get_node("KnowledgeSources/LacHaStele") as Node2D
	player.global_position = stele.global_position + Vector2(0, 20)  # setup: at the stele
	await scene_tree.physics_frame
	await _press_until(INTERACT, func() -> bool: return knowledge.get_service().knows(STELE))
	await _talk_to(player, hub, shen, Vector2(30, 0))
	await _advance_to(&"shen_hub")
	await _say(&"shen_task_ask", &"shen_task_why")
	assert_true(service.flag_at_least(&"flag_heard_village_business", 1), "heard out")
	assert_eq(service.state().beat_id, &"beat_confidence", "the story turns to Lâm Nguyệt")
	_dialogue.leave()
	await scene_tree.process_frame
	await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
	await _advance_to(&"lin_hub")
	await _say(&"lin_press", &"lin_confide")
	var trust_before := RegardRules.read(relationship.get_service(), relationship.get_config(),
		LIN, character.instance_id, &"trust")
	await _say(&"lin_keep", &"lin_kept")
	assert_eq(service.state().option_of(&"choice_lam_readings"), &"kept",
		"the decision is recorded")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), LIN,
		character.instance_id, &"trust"), trust_before + 15, "and her trust moved once, by 15")
	assert_eq(service.state().beat_id, &"beat_warning", "the Night is now due")
	assert_false(story.is_scene_playing(),
		"but its warning waits: she is still speaking, and two surfaces never hold the player")
	await _advance_to(&"")
	assert_true(story.is_scene_playing(), "the moment she is done, the warning plays")
	assert_eq(story.build_scene_view().scene_id, &"scene_night_warning",
		"where the player stands")
	assert_false(hud.story_scene_panel().covers_the_map(), "over the village, not instead of it")
	await _press_until(INTERACT, func() -> bool: return not story.is_scene_playing())
	assert_eq(service.state().beat_id, &"beat_warning", "reading it changed nothing")
	await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
	assert_eq(_dialogue.current_node_id(), &"lin_after_kept",
		"she now greets the player as someone who kept faith")
	await _advance_to(&"lin_hub")
	assert_false(_panel.choice_ids().has(&"lin_press"), "and does not ask twice")
	await _say(&"lin_leave", &"")
	assert_eq(_count_players(main), 1, "one player throughout")
	var hub_light := hub.get_node(MapBase.AMBIENCE_PATH) as MapAmbience
	assert_eq(hub_light.ambience_id(), &"dusk", "and the village is at dusk: the warning is SEEN")
	assert_true((hub_light.get_node("LanternN") as AmbienceLight).enabled,
		"the east road's lanterns are lit")
	_step("8c. heard the village's business; kept Lâm Nguyệt's confidence; the Night is due")

	# --- 8d. the Night: arrival in the woods, the rupture, creatures only after the scene -----
	var combat := main.get_node("Systems/CombatRuntime") as CombatRuntime
	await _go_through_exit(player)
	var field: Node = router.call("get_current_scene")
	assert_eq(str(world.call("get_current_map_id")), "map_field",
		"the player walked into the woods")
	assert_eq(service.state().beat_id, &"beat_night", "arriving there is what breaks the vein")
	assert_eq(story.build_scene_view().scene_id, &"scene_night_rupture", "the rupture is shown")
	assert_false(bool(world.call("is_story_encounter_live")),
		"and nothing of the Night moves while the scene holds the player")
	var wreck := field.get_node("Visual/Decor/CartWreck") as Node2D
	var stake := field.get_node("Visual/Decor/SurveyStake") as Node2D
	assert_true(stake.visible and not wreck.visible, "before: a survey stake, and no wreck")
	hud = _find_hud(field)
	await _press_until(INTERACT, func() -> bool: return not story.is_scene_playing())
	await scene_tree.process_frame
	assert_true(bool(world.call("is_story_encounter_live")),
		"the scene over, the Night's wave is here")
	assert_eq(int(world.call("story_encounter_remaining")), 2, "two creatures, with their own ids")
	assert_true(service.flag_at_least(&"flag_vein_broke", 1), "the story records the rupture")
	assert_true(wreck.visible, "and the carter's cart stands wrecked among the trees")
	assert_true((field.get_node("Pickups/FieldManualLoi") as WorldItem).visible,
		"what spilled from its crates is on the ground")
	var night_wolves: Array[Node2D] = []
	for enemy in combat.enemies():
		if String(enemy.name).begins_with(NIGHT_PREFIX):
			night_wolves.append(enemy)
	assert_eq(night_wolves.size(), 2, "they are the Night's own, apart from the woods' wolves")
	assert_true(night_wolves[0].global_position.distance_to(player.global_position) > 300.0,
		"and they begin far from where the player came in: there is room to choose")
	# The Night LOOKS like night (D-073 §3): derived from the beat, worn by the map.
	var field_light := field.get_node(MapBase.AMBIENCE_PATH) as MapAmbience
	assert_eq(field_light.ambience_id(), &"night", "the woods wear the night")
	# The player walked in at dusk; the dark comes down as the vein gives way (it eases).
	var night_tint := (load(MapAmbience.PROFILE_PATH % "night") as AmbienceProfileData).tint
	await _wait_until(func() -> bool: return field_light.tint().is_equal_approx(night_tint), 180)
	assert_true(field_light.tint().get_luminance() < 0.75 and field_light.tint().b
		> field_light.tint().r, "a cool, darker playfield (tint %s)" % str(field_light.tint()))
	var vein_light := field_light.get_node("Vein") as AmbienceLight
	assert_true(vein_light.enabled and vein_light.energy > 0.0, "the broken vein gives light")
	assert_true(field_light.is_pulsing(), "and it flared as the wave came: the rupture is SEEN")
	assert_true(hud is CanvasLayer, "the HUD is its own layer: the tint is not drawn over it")
	_step("8d. the vein broke on arrival; the wave came only after the scene; the way back is open")

	# --- 8e. standing: real attack keys, until the last of the Night's creatures is down ------
	var attack := player.get_node_or_null("AttackComponent") as AttackComponent
	var respect_before := RegardRules.read(relationship.get_service(),
		relationship.get_config(), KO, character.instance_id, &"respect")
	for wolf in night_wolves:
		for _round in 40:
			if bool(wolf.call("is_dead")):
				break
			player.global_position = wolf.global_position - Vector2(16, 0)  # setup: in reach
			attack.set_facing(Vector2.RIGHT)
			await _fire_action(ATTACK)
			for _i in 24:
				await scene_tree.process_frame
				if bool(wolf.call("is_dead")):
					break
		assert_true(bool(wolf.call("is_dead")), "real attack keys brought it down")
	assert_false(bool(player.call("is_dead")), "a new character with the starting kit survives it")
	assert_eq(service.state().option_of(&"choice_night_stand"), &"stood",
		"the last one down is the decision: recorded once, with no menu")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), KO,
		character.instance_id, &"respect"), respect_before + 10, "the watchman saw it")
	assert_false(bool(world.call("is_story_encounter_live")), "the encounter is over")
	assert_eq(service.state().beat_id, &"beat_aftermath", "it is morning")
	assert_true(hud.story_scene_panel().covers_the_map(),
		"told over a covered map: time has passed")
	await _press_until(INTERACT, func() -> bool: return not story.is_scene_playing())
	assert_false(stake.visible, "by morning the survey stake is gone")
	assert_eq(field_light.ambience_id(), &"", "and it is day again: no night is left behind")
	assert_true(field_light.tint().is_equal_approx(Color.WHITE) or field_light.is_processing(),
		"the woods are as authored (or easing back to it)")
	assert_true(wreck.visible, "and the wreck is not")
	_step("8e. stood through the Night with real keys; morning came; the stake was removed")

	# --- 8f. the elder's account, the first deliberate cultivation, the sheet ------------------
	await _go_through_exit(player)
	hub = router.call("get_current_scene")
	hud = _find_hud(hub)
	_panel = hud.dialogue_panel()
	shen = hub.get_node("Interactables/ShenBuqi") as WorldNpc
	await _talk_to(player, hub, shen, Vector2(30, 0))
	assert_eq(_dialogue.current_node_id(), &"shen_night", "the elder opens with his account")
	await _say(&"shen_night_stake", &"shen_night_stake_line")
	assert_eq(service.state().beat_id, &"beat_settle", "heard: the story turns inward")
	await _advance_to(&"")
	var sheet := hub.get_node("KnowledgeSources/SurveySheet") as Node2D
	assert_true(sheet.visible, "something is weighted under a stone by the stele now")
	var spring := hub.get_node("CultivationSites/LacHaSpring") as Node2D
	player.global_position = spring.global_position + Vector2(0, 26)  # setup: at the spring
	await scene_tree.physics_frame
	# THE RULE A PLAYER MEETS (D-073, H21-12): a swing is committed, so `cultivate` pressed
	# inside one is answered in words and nothing starts — it used to sit and stand in one
	# tick, silently. (This step used to WAIT for the swing to end, which hid exactly that.)
	var cultivation := main.get_node("Systems/CultivationRuntime") as CultivationRuntime
	await _wait_until(func() -> bool:
		return attack.state() == AttackStateMachine.State.READY, 120)
	var sittings: Array = []
	var on_sat := func(site_id: StringName) -> void: sittings.append(site_id)
	cultivation.meditation_started.connect(on_sat)
	Input.action_press(ATTACK)  # held across a physics tick: the player reads it there
	await _wait_until(func() -> bool:
		return attack.state() != AttackStateMachine.State.READY, 30)
	Input.action_release(ATTACK)
	assert_ne(attack.state(), AttackStateMachine.State.READY, "a real swing is in flight")
	Input.action_press(CULTIVATE)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	Input.action_release(CULTIVATE)
	await scene_tree.process_frame
	assert_eq(sittings, [], "a real cultivate key mid-swing starts no sitting")
	assert_eq(cultivation.phase(), CultivationRuntime.Phase.IDLE, "nobody sat")
	assert_eq(hud.notice_text(), String(loc.call("t", "UI_CULTIVATE_MID_SWING")),
		"and the player is told why, at once")
	assert_eq(service.state().beat_id, &"beat_settle", "the story did not move")
	await _wait_until(func() -> bool:
		return attack.state() == AttackStateMachine.State.READY, 240)
	assert_eq(attack.state(), AttackStateMachine.State.READY, "the swing ends by itself")
	Input.action_press(CULTIVATE)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	Input.action_release(CULTIVATE)
	await _wait_until(func() -> bool: return service.state().beat_id != &"beat_settle", 900)
	assert_eq(service.state().beat_id, &"beat_sheet_told",
		"tu vi gathered by sitting completes the beat; she kept faith, so she tells where to look")
	assert_true(character.cultivation_progress > 0, "through the cultivation owner, for real")
	assert_eq(sittings.size(), 1, "the next press, after the swing, sat — once")
	cultivation.meditation_started.disconnect(on_sat)
	Input.action_press(MOVE_RIGHT)  # moving is how one stands up
	for _i in 6:
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	player.global_position = sheet.global_position + Vector2(0, 6)  # setup: at the sheet
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	await _press_until(INTERACT, func() -> bool:
		return knowledge.get_service().knows(&"know_survey_fragment"))
	assert_true(knowledge.get_service().knows(&"know_survey_fragment"),
		"a real interact read the sheet: information, held by the Knowledge Core")
	assert_eq(service.state().beat_id, &"beat_leaving", "the mystery is in hand")
	_step("8f. the elder's account; a first deliberate cultivation; the suppressed sheet")

	# --- 8g. the Chronicle: one book, a real key, never modal ----------------------------------
	var book := hud.chronicle_panel()
	assert_false(hud.is_chronicle_open(), "the book is closed until asked for")
	await _press_until(CHRONICLE, func() -> bool: return hud.is_chronicle_open())
	assert_eq(book.page_id(), ChroniclePanel.PAGE_STORY, "it opens on the road so far")
	var story_page := book.page_lines()
	assert_true(story_page.has(String(loc.call("t", "STORY_BEAT_NIGHT_RECORD"))),
		"which records the Night (%s)" % str(story_page))
	assert_true(story_page.has("◆ " + String(loc.call("t", "STORY_CHOICE_NIGHT_STAND_STOOD"))),
		"and the decision made there")
	assert_eq(int(input.call("current_context")), int(input.Context.GAMEPLAY),
		"reading takes no input context")
	var read_from := player.global_position
	Input.action_press(MOVE_RIGHT)
	await _wait_until(func() -> bool: return player.global_position.x > read_from.x + 4.0, 60)
	Input.action_release(MOVE_RIGHT)
	assert_true(player.global_position.x > read_from.x + 4.0 and hud.is_chronicle_open(),
		"the player walks with the book open")
	# The same real key turns every page and, after the last, closes the book. Each section
	# says what its OWNER holds (D-073 §4), read here as the player would read it.
	var read := {}
	var turns := 0
	while hud.is_chronicle_open() and turns < 24:
		var section := book.page_id()
		if not read.has(section):
			read[section] = []
		(read[section] as Array).append_array(book.page_lines())
		await _fire_action(CHRONICLE)
		turns += 1
	assert_false(hud.is_chronicle_open(), "and after the last page the key closes the book")
	assert_eq(turns, book.page_count(), "one press per page: no page was skipped or doubled")
	for section: StringName in [ChroniclePanel.PAGE_STORY, ChroniclePanel.PAGE_SELF,
			ChroniclePanel.PAGE_BODY, ChroniclePanel.PAGE_KNOWLEDGE, ChroniclePanel.PAGE_PEOPLE]:
		assert_true(read.has(section), "the book has a '%s' page" % section)
	assert_true((read[ChroniclePanel.PAGE_SELF] as Array).has(
		String(loc.call("t", "ORIGIN_THU_THU_NAME"))), "who the player was")
	assert_true((read[ChroniclePanel.PAGE_SELF] as Array).has(
		"◆ " + String(loc.call("t", "STORY_NOTICED_CARTER_THU_THU"))),
		"and what only a keeper of records noticed about the carter's load, kept (H21-11)")
	assert_true((read[ChroniclePanel.PAGE_KNOWLEDGE] as Array).has(
		String(loc.call("t", "KNOW_SURVEY_FRAGMENT_NAME"))), "what they know includes the sheet")
	var body_page: Array = read[ChroniclePanel.PAGE_BODY]
	assert_true(body_page.has(String(loc.call("t_args", "UI_CHRONICLE_HEALTH",
		{"current": int(player.call("get_current_health")),
			"max": int(player.call("get_max_health"))}))),
		"body and path: the health the player really has (%s)" % str(body_page))
	assert_true(body_page.has(String(loc.call("t_args", "UI_CHRONICLE_STATS", {
		"attack": int(player.call("get_attack_power")),
		"defense": int(player.call("get_defense")),
		"speed": int(round(float(player.get_node("StatsComponent").call("get_move_speed"))))}))),
		"the stats combat reads, from the player's own stat owner")
	var equipment := main.get_node("Systems/EquipmentRuntime") as EquipmentRuntime
	var worn_ids := equipment.get_state().worn_ids()
	assert_eq(body_page.has(String(loc.call("t", "UI_CHRONICLE_WORN_NONE"))), worn_ids.is_empty(),
		"what is worn is what the equipment owner says is worn (%s)" % str(worn_ids))
	assert_eq(body_page.has(String(loc.call("t", "ITEM_KIEM_THANH_THIET_NAME"))),
		worn_ids.has(&"item_kiem_thanh_thiet"),
		"a blade in the BAG is not listed as worn: the book is not a second satchel")
	var people_page: Array = read[ChroniclePanel.PAGE_PEOPLE]
	var lin_row := "%s — %s" % [loc.call("t", "CHARACTER_DISCIPLE_LIN_NAME"),
		loc.call("t", "CHARACTER_DISCIPLE_LIN_TITLE")]
	assert_true(people_page.has(lin_row), "Lâm Nguyệt is in it (%s)" % str(people_page))
	var trust_in_book := RegardRules.read(relationship.get_service(), relationship.get_config(),
		LIN, character.instance_id, &"trust")
	assert_true(people_page.has(String(loc.call("t_args", "UI_CHRONICLE_REGARD_LINE", {
		"dimension": "Tin cậy" if String(loc.call("get_language")) == "vi" else "Trust",
		"band": loc.call("t", RegardBands.key(&"trust", trust_in_book, 0, 100)),
		"value": "+%d" % trust_in_book}))),
		"her trust as the graph holds it (%d), named and in a word" % trust_in_book)
	assert_true(people_page.has("◆ " + String(loc.call("t", "STORY_CHOICE_LAM_READINGS_KEPT"))),
		"and the decision that earned it stands under her")
	# The people page follows the GRAPH, not the story: a regard moved by anything else (an
	# answer in a conversation, a quest's reward) shows without the story having moved.
	var moved_line := String(loc.call("t_args", "UI_CHRONICLE_REGARD_LINE", {
		"dimension": "Kính trọng" if String(loc.call("get_language")) == "vi" else "Respect",
		"band": loc.call("t", RegardBands.key(&"respect", 7, 0, 100)), "value": "+7"}))
	assert_false(book.all_lines().has(moved_line), "nobody respects the player at +7 yet")
	var beat_before := service.state().beat_id
	RegardRules.move(relationship.get_service(), relationship.get_config(), SHEN,
		character.instance_id, &"respect", 7, &"test_outside_the_story")
	await scene_tree.process_frame
	assert_eq(service.state().beat_id, beat_before, "the story did not move")
	assert_true(book.all_lines().has(moved_line),
		"and the book already says so: it reads the relationship graph (%s)" % moved_line)
	await _press_until(CHRONICLE, func() -> bool: return hud.is_chronicle_open())
	await _fire_action(OPEN_MENU)
	assert_false(hud.is_chronicle_open(), "Esc closes it like every reading surface")
	assert_eq(hud.session_prompt_kind(), &"", "without asking about leaving")
	_step("8g. the Chronicle opened, paged and closed with real keys; the player kept walking")

	# --- 8h. the way out: the carter, the road ahead, and what the player leaves holding -------
	assert_false((hub.get_node("Visual/Decor/CarterCart") as Node2D).visible,
		"the cart that waited on the east road never came back")
	carter = hub.get_node("Interactables/QiMu") as WorldNpc
	await _talk_to(player, hub, carter, Vector2(30, 0))
	assert_eq(_dialogue.current_node_id(), &"te_morning", "the carter opens with what he lost")
	await _say(&"te_morning_where", &"te_morning_road")
	assert_eq(service.state().chapter_id, &"chapter_ke_vo_danh", "the prologue is over")
	assert_false(story.is_scene_playing(), "the road ahead waits for him to finish")
	await _advance_to(&"")
	assert_true(story.is_scene_playing() and hud.story_scene_panel().covers_the_map(),
		"then it is told")
	await _press_until(INTERACT, func() -> bool: return not story.is_scene_playing())
	assert_eq(service.state().beat_id, &"beat_whose_hand",
		"open play, with a purpose the player can act on (D-073)")
	# The five things NARRATIVE_MASTER_PLAN §5 says the player must leave holding:
	assert_eq(hud.purpose_text(), String(loc.call("t", "STORY_BEAT_WHOSE_HAND_OBJECTIVE")),
		"1. an immediate goal, on the plaque")
	assert_ne(service.origin().goal_key, &"", "2. a personal goal from their Origin")
	assert_true(RegardRules.read(relationship.get_service(), relationship.get_config(), LIN,
		character.instance_id, &"trust") >= 15, "3. a relationship that was earned")
	assert_true(knowledge.get_service().knows(&"know_survey_fragment"), "4. an unanswered mystery")
	assert_true(service.flag_at_least(&"flag_heard_road_ahead", 1), "5. a reason to go on")
	assert_eq(str(character.sect_id), "", "and still belonging to no sect")
	_step("8h. the prologue ended into open play, holding all five things it must hand over")

	# --- 8i. THE BRIDGE (D-073): whom to show the sheet, the stake, the track, the door -------
	# Declining is a complete path: she is asked, the player says something else, nothing moves.
	lin = hub.get_node("Interactables/LinYue") as WorldNpc
	var lin_trust_before := RegardRules.read(relationship.get_service(), relationship.get_config(),
		LIN, character.instance_id, &"trust")
	await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
	assert_eq(_dialogue.current_node_id(), &"lin_trail",
		"with the sheet in hand and the prologue over, she opens on it")
	assert_true(_panel.choice_ids().has(&"lin_show"), "showing it is offered (%s)"
		% str(_panel.choice_ids()))
	await _say(&"lin_trail_back", &"lin_hub")
	await _say(&"lin_leave", &"")
	assert_false(service.state().has_chosen(&"choice_sheet_shown"),
		"declining records nothing")
	assert_eq(service.state().beat_id, &"beat_whose_hand", "and the purpose stands")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), LIN,
		character.instance_id, &"trust"), lin_trust_before, "nobody's regard moved")
	# Then: she is the first to see it.
	await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
	await _say(&"lin_show", &"lin_sheet_read")
	assert_eq(service.state().option_of(&"choice_sheet_shown"), &"lin",
		"ONE real answer recorded who saw the sheet first")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), LIN,
		character.instance_id, &"trust"), lin_trust_before + 10, "her trust rose, in the graph")
	assert_true(knowledge.get_service().knows(&"know_surveyors_line"),
		"and what she read is held by the Knowledge Core")
	assert_eq(service.state().beat_id, &"beat_stake_line", "the story moved on")
	await _advance_to(&"lin_trail")
	assert_false(_panel.choice_ids().has(&"lin_show"), "the same answer is not offered twice")
	await _say(&"lin_trail_back", &"lin_hub")
	await _say(&"lin_leave", &"")
	assert_eq(hud.purpose_text(), String(loc.call("t", "STORY_BEAT_STAKE_LINE_OBJECTIVE")),
		"and the plaque says where to look next")
	# The elder is asked second: he answers in character, and nothing is paid twice.
	var shen_affinity := RegardRules.read(relationship.get_service(),
		relationship.get_config(), SHEN, character.instance_id, &"affinity")
	shen = hub.get_node("Interactables/ShenBuqi") as WorldNpc
	await _talk_to(player, hub, shen, Vector2(30, 0))
	assert_eq(_dialogue.current_node_id(), &"shen_trail", "the elder opens on it too")
	await _say(&"shen_show_late", &"shen_sheet_late")
	assert_eq(service.state().option_of(&"choice_sheet_shown"), &"lin", "the record is unchanged")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), SHEN,
		character.instance_id, &"affinity"), shen_affinity, "a second showing costs nothing more")
	assert_false(knowledge.get_service().knows(&"know_shaft_claim"),
		"and he gives a latecomer only his denial")
	await _advance_to(&"shen_trail")
	await _say(&"shen_trail_back", &"shen_hub")
	await _say(&"shen_leave", &"")

	# The woods: where the stake stood.
	await _go_through_exit(player)
	field = router.call("get_current_scene")
	hud = _find_hud(field)
	_panel = hud.dialogue_panel()
	var socket := field.get_node("KnowledgeSources/StakeSocket") as KnowledgeSource
	assert_true(socket.visible, "the raked socket is where the stake was")
	assert_false((field.get_node("Visual/Decor/SurveyStake") as Node2D).visible,
		"and the stake is not")
	player.global_position = socket.global_position + Vector2(40, 0)  # setup: beside it
	await scene_tree.physics_frame
	Input.action_press(MOVE_LEFT)
	await _wait_until(func() -> bool: return field.call("active_knowledge_source") == socket, 120)
	Input.action_release(MOVE_LEFT)
	assert_eq(field.call("active_knowledge_source"), socket, "walking up to it offers it")
	await _press_until(INTERACT, func() -> bool:
		return knowledge.get_service().knows(&"know_stake_socket"))
	assert_eq(service.state().beat_id, &"beat_ruts", "a real examine: the track is next")
	assert_eq(hud.purpose_text(), String(loc.call("t", "STORY_BEAT_RUTS_OBJECTIVE")),
		"on the plaque")
	# The door. It is SOLID: walking up into it stops at its sill.
	var shaft := field.get_node("Visual/Decor/Prop_SurveyShaft") as Node2D
	var seal := field.get_node("KnowledgeSources/ShaftSeal") as KnowledgeSource
	player.global_position = seal.global_position + Vector2(0, 34)  # setup: below the door
	await scene_tree.physics_frame
	Input.action_press(MOVE_UP)
	for _i in 90:
		await scene_tree.physics_frame
	Input.action_release(MOVE_UP)
	await scene_tree.physics_frame
	assert_true(shaft.global_position.distance_to(seal.global_position) < 16.0,
		"the seal is read AT the door, not somewhere else")
	assert_true(player.global_position.y > seal.global_position.y - 12.0,
		"a held move key did not carry the player through the door (y %.1f, sill %.1f)"
		% [player.global_position.y, shaft.global_position.y])
	assert_eq(field.call("active_knowledge_source"), seal, "standing at the sill offers the seal")
	await _press_until(INTERACT, func() -> bool:
		return knowledge.get_service().knows(&"know_sealed_shaft"))
	assert_eq(service.state().beat_id, &"beat_standing", "the door is found: the story rests")
	assert_true(story.is_scene_playing(), "and says so, once")
	assert_false(hud.story_scene_panel().covers_the_map(), "over the place itself")
	await _press_until(INTERACT, func() -> bool: return not story.is_scene_playing())
	assert_eq(hud.purpose_text(), String(loc.call("t", "STORY_BEAT_STANDING_OBJECTIVE")),
		"the standing purpose now names the door and what it needs")
	var reads := knowledge.get_service().store().known_ids().size()
	await _fire_action(INTERACT)
	for _i in 4:
		await scene_tree.process_frame
	assert_eq(knowledge.get_service().store().known_ids().size(), reads,
		"examining it again teaches nothing new")
	assert_false(story.is_scene_playing(), "and tells nothing twice")
	_step("8i. the bridge with real keys: declined, shown, asked again, the stake, the door")

	# --- 8j. bringing it back: who answers, and what only this Origin notices ------------------
	await _go_through_exit(player)
	hub = router.call("get_current_scene")
	hud = _find_hud(hub)
	_panel = hud.dialogue_panel()
	lin = hub.get_node("Interactables/LinYue") as WorldNpc
	await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
	await _say(&"lin_shaft_kept", &"lin_shaft_kept_line")
	await _advance_to(&"lin_trail")
	assert_false(_panel.choice_ids().has(&"lin_shaft_kept"), "said once")
	await _say(&"lin_trail_back", &"lin_hub")
	await _say(&"lin_leave", &"")
	shen = hub.get_node("Interactables/ShenBuqi") as WorldNpc
	await _talk_to(player, hub, shen, Vector2(30, 0))
	assert_true(_panel.choice_ids().has(&"shen_trail_hand"),
		"a keeper of records sees what nobody else can: the second hand (%s)"
		% str(_panel.choice_ids()))
	await _say(&"shen_trail_hand", &"shen_hand_line")
	assert_true(service.flag_at_least(&"flag_trail_origin_said", 1), "noticed, on the record")
	await _advance_to(&"shen_trail")
	assert_false(_panel.choice_ids().has(&"shen_trail_hand"), "and noticed once")
	await _say(&"shen_shaft", &"shen_shaft_line")  # and he is told of the door
	await _advance_to(&"shen_trail")
	await _say(&"shen_trail_back", &"shen_hub")
	await _say(&"shen_leave", &"")
	# H21-15: with NOTHING left to say about it, a real interact opens each of them on their
	# ordinary hub — not on the sheet with one dead answer — however often they are asked.
	for _again in 2:
		await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
		assert_eq(_dialogue.current_node_id(), &"lin_hub",
			"she has said all she will about the sheet: she is simply herself again")
		assert_false(_panel.choice_ids().has(&"lin_trail_back"), "no dead 'something else' line")
		await _say(&"lin_leave", &"")
		await _talk_to(player, hub, shen, Vector2(30, 0))
		assert_eq(_dialogue.current_node_id(), &"shen_hub", "and so is the elder")
		await _say(&"shen_leave", &"")
	_step("8j. the door was brought back to those it concerns; the Origin's line was said once")

	# --- 9. leave through the real question; everything is torn down --------------------------
	await _press_until(OPEN_MENU, func() -> bool:
		return hud.session_prompt_kind() == GameplayHUD.PROMPT_LEAVE)
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_LEAVE,
		"with nothing open, Esc ASKS whether to leave")
	await _press_until(INTERACT, func() -> bool: return gs.get_phase() == gs.Phase.MENU)
	assert_eq(gs.get_phase(), gs.Phase.MENU, "the confirm key returned to the menu")
	assert_false(story.is_session_active() or bool(world.call("is_session_active")),
		"the story and world sessions ended")
	assert_null(story.get_service(), "the story keeps no record of the run that ended")
	var trace: Array = main.call("get_last_teardown_order")
	assert_eq(trace.slice(0, 3), [&"DialogueRuntime", &"StoryRuntime", &"QuestRuntime"],
		"conversations ended first, then the story, then quests (%s)" % str(trace))
	for connection: Dictionary in knowledge.knowledge_gained.get_connections():
		assert_ne((connection["callable"] as Callable).get_object(), story,
			"the story is no longer listening to the Knowledge Core")
	assert_eq(int(input.call("current_context")), int(input.Context.MENU),
		"no modal context survived")
	_step("9. left through the real prompt; the story ended second and stopped listening")

	# --- 10. a SECOND run, as someone else: nothing of the first survives ---------------------
	await scene_tree.process_frame
	await scene_tree.process_frame
	await _press_until(UI_ACCEPT, func() -> bool: return RunKit.identity_of(main) != null)
	identity = RunKit.identity_of(main) as IdentityScreen
	assert_not_null(identity, "New Game opens the identity screen again")
	if identity == null:
		_teardown(main)
		return
	assert_eq([identity.selected_appearance_id(), identity.selected_origin_id()],
		[&"appearance_wanderer_m", &"origin_ho_tieu"], "fresh, on its defaults")
	# THE REGRESSION: walking the cursor down THROUGH every Origin to reach Begin must not
	# change the choice. (The first build chose by moving; this run began as the last Origin.)
	for _i in 5:
		await _fire_action(UI_DOWN)
	assert_true((identity.find_child("Begin", true, false) as Button).has_focus(),
		"five downs reach Begin")
	assert_eq(identity.selected_origin_id(), &"origin_ho_tieu",
		"and passing over four other Origins on the way chose none of them")
	await _press_until(UI_ACCEPT, func() -> bool: return gs.get_phase() == gs.Phase.RUNNING)
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "a second run started")
	character = world.call("get_player_character")
	assert_true(story.get_service().origin_is(&"origin_ho_tieu"), "as the escort")
	assert_eq(character.gender, int(CharacterTemplateData.Gender.MALE), "in the man's look")
	assert_eq(inventory.count_of(&"item_kiem_thanh_thiet"), 1, "with ONE blade")
	assert_false(knowledge.get_service().knows(&"know_survey_notation"),
		"and none of the first run's knowledge")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), SHEN,
		character.instance_id, &"affinity"), -10,
		"the elder's first impression is THIS Origin's (-10), not the last one's on top")
	assert_true(character.story_flags.is_empty(), "no flag carried over")
	assert_eq(story.get_service().state().beat_id, &"beat_road", "and the story starts over")
	assert_eq(_count_players(main), 1, "one player")
	_step("10. a second run as another Origin: nothing of the first survived")

	# --- 11. the other answer to the Night: walk away from it ---------------------------------
	# SETUP (each proved with real keys in the first run): three people met, the village's
	# business heard, and — the OTHER answer this time — the elder told about Lâm Nguyệt's
	# readings. What is proved here is the leaving, and then (12) what telling costs.
	RunKit.skip_scenes(main)
	for who: StringName in [SHEN, LIN, KO]:
		story.meet(who)
	story.set_flag(&"flag_heard_village_business", 1)
	story.choose(&"choice_lam_readings", &"told")
	RunKit.skip_scenes(main)
	service = story.get_service()
	assert_eq(service.state().beat_id, &"beat_warning", "setup: the Night is due")
	player = world.call("get_player") as Node2D
	await _go_through_exit(player)
	assert_eq(service.state().beat_id, &"beat_night", "the vein breaks for this run too")
	hud = _find_hud(router.call("get_current_scene"))
	await _press_until(INTERACT, func() -> bool: return not story.is_scene_playing())
	await scene_tree.process_frame
	assert_eq(int(world.call("story_encounter_remaining")), 2, "the wave is here")
	var affinity_before := RegardRules.read(relationship.get_service(),
		relationship.get_config(), KO, character.instance_id, &"affinity")
	# --- 11a. FAULT INJECTION (Gate B1): the way out FAILS. Leaving is an answer only if the
	# player actually left. The router is made to refuse the village (its scene "missing"),
	# the real exit is pressed, and the Night must be exactly as it was: nothing answered, the
	# wave alive, the dark still down. Then the village is put back.
	var hub_scene := "res://src/gameplay/maps/hub_map.tscn"
	router.call("register_scene", "map_hub", "res://no_such_scene_gate_b1.tscn")
	await _go_through_exit(player)
	router.call("register_scene", "map_hub", hub_scene)
	assert_eq(str(world.call("get_current_map_id")), "map_field", "the refused exit led nowhere")
	assert_eq(_count_players(main), 1, "the player is still in the woods, once")
	assert_eq(service.state().option_of(&"choice_night_stand"), &"",
		"a way out that failed is NOT an answer to the Night")
	assert_eq(service.state().beat_id, &"beat_night", "the Night is still the Night")
	assert_true(bool(world.call("is_story_encounter_live")), "its encounter is still live")
	assert_eq(int(world.call("story_encounter_remaining")), 2, "with both creatures standing")
	assert_eq((router.call("get_current_scene").get_node(MapBase.AMBIENCE_PATH)
		as MapAmbience).ambience_id(), &"night", "and no morning came over a fight")
	assert_false(story.is_scene_playing(), "nor any card about one")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), KO,
		character.instance_id, &"affinity"), affinity_before, "nobody was left alone yet")
	_step("11a. a way out that failed answered nothing: the Night, its wave and its dark stand")
	await _go_through_exit(player)
	assert_eq(str(world.call("get_current_map_id")), "map_hub", "the way back was open")
	assert_eq(service.state().option_of(&"choice_night_stand"), &"withdrew",
		"leaving is an answer: recorded once, by the player's feet")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), KO,
		character.instance_id, &"affinity"), affinity_before - 5, "the watchman was left alone")
	assert_eq(service.flag_value(&"flag_night_over"), 2, "and the story knows which Night this was")
	assert_false(bool(world.call("is_story_encounter_live")),
		"no encounter follows the player home")
	assert_eq(service.state().beat_id, &"beat_aftermath", "morning comes either way")
	RunKit.skip_scenes(main)
	_step("11. withdrew from the Night through the real exit: a different, recorded outcome")

	# --- 12. the bridge for someone who TOLD and WITHDREW: a refusal that is not a dead end ----
	# SETUP (each proved with real keys in the first run): the elder heard, a sitting, the
	# sheet read, the carter's farewell.
	story.set_flag(&"flag_heard_elder_account", 1)
	story.note_cultivated()
	knowledge.grant(&"know_survey_fragment", &"source_survey_sheet")
	story.set_flag(&"flag_heard_road_ahead", 1)
	RunKit.skip_scenes(main)
	assert_eq(service.state().beat_id, &"beat_whose_hand", "setup: Act I, sheet in hand")
	hub = router.call("get_current_scene")
	hud = _find_hud(hub)
	_panel = hud.dialogue_panel()
	lin = hub.get_node("Interactables/LinYue") as WorldNpc
	var record_before := str(service.state().to_dict())
	var lin_trust := RegardRules.read(relationship.get_service(), relationship.get_config(),
		LIN, character.instance_id, &"trust")
	await _talk_to(player, hub, lin, Vector2(-30, 0), MOVE_RIGHT)
	assert_eq(_dialogue.current_node_id(), &"lin_trail", "she opens on the sheet")
	assert_false(_panel.choice_ids().has(&"lin_show"),
		"she does not read it for someone who told on her (%s)" % str(_panel.choice_ids()))
	await _say(&"lin_show_refused", &"lin_sheet_refuse")
	assert_eq(str(service.state().to_dict()), record_before, "her refusal records no decision")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), LIN,
		character.instance_id, &"trust"), lin_trust, "and moves nothing")
	await _advance_to(&"lin_trail")
	assert_false(_panel.choice_ids().has(&"lin_show_refused"), "she says it once")
	await _say(&"lin_trail_back", &"lin_hub")
	await _say(&"lin_leave", &"")
	assert_eq(service.state().beat_id, &"beat_whose_hand", "the purpose stands: ask someone else")
	# The watchman still answers — with the line of someone who was left alone at the treeline.
	await _go_through_exit(player)
	field = router.call("get_current_scene")
	hud = _find_hud(field)
	_panel = hud.dialogue_panel()
	var ko := field.get_node("Interactables/KoThan") as WorldNpc
	await _talk_to(player, field, ko, Vector2(30, 0))
	if _dialogue.current_node_id() == &"ko_night_left":  # the line the Night still owed
		await _say(&"ko_night_ack2", &"")
		await _talk_to(player, field, ko, Vector2(30, 0))
	assert_eq(_dialogue.current_node_id(), &"ko_trail", "the watchman opens on it")
	assert_false(_panel.choice_ids().has(&"ko_show_stood"), "not with the words for one who stood")
	var ko_trust := RegardRules.read(relationship.get_service(), relationship.get_config(), KO,
		character.instance_id, &"trust")
	await _say(&"ko_show_left", &"ko_sheet_left")
	assert_eq(service.state().option_of(&"choice_sheet_shown"), &"ko", "recorded: the watchman")
	assert_eq(RegardRules.read(relationship.get_service(), relationship.get_config(), KO,
		character.instance_id, &"trust"), ko_trust + 5, "his trust rose")
	assert_true(knowledge.get_service().knows(&"know_night_wheels"), "what he heard is known")
	assert_eq(service.state().beat_id, &"beat_stake_line", "and the run goes on")
	await _advance_to(&"ko_trail")
	await _say(&"ko_trail_back", &"ko_hub")
	await _say(&"ko_leave", &"")
	_step("12. told and withdrew: refused by her, answered by him — recorded once, no dead end")

	assert_true(_arrivals >= 9 and _arrivals_judged == _arrivals,
		"every arrival of the walk was judged (%d of %d)" % [_arrivals_judged, _arrivals])
	assert_eq(_arrival_faults, [] as Array[String],
		"at every arrival the map agreed with the story: %s" % str(_arrival_faults))
	_step("FG-4. %d arrivals: light, presence, pickups, spawn and creatures agree with the story"
		% _arrivals)

	var last_map: Node = router.call("get_current_scene")
	last_map.emit_signal("return_to_menu_requested")
	await scene_tree.process_frame
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.MENU, "back at the menu")

	# --- 13. the fallen answer nothing (Gate B1) ----------------------------------------------
	# A thunder bolt is still in the air when its caster falls. It may land; it may kill. It
	# may NOT make the story say the player "stood", bring the morning, or open a story card
	# over the defeat. SETUP through owners (each proved with real keys elsewhere): a third
	# run brought to the Night, the cultivator's first realm, the technique, the wave one
	# blow from down. REAL KEYS: the cast, and the acknowledgement of the defeat.
	await _press_until(UI_ACCEPT, func() -> bool: return RunKit.identity_of(main) != null)
	identity = RunKit.identity_of(main) as IdentityScreen
	for _i in 5:
		await _fire_action(UI_DOWN)
	await _press_until(UI_ACCEPT, func() -> bool: return gs.get_phase() == gs.Phase.RUNNING)
	RunKit.skip_scenes(main)
	for who: StringName in [SHEN, LIN, KO]:
		story.meet(who)
	story.set_flag(&"flag_heard_village_business", 1)
	story.choose(&"choice_lam_readings", &"kept")
	RunKit.skip_scenes(main)
	player = world.call("get_player") as Node2D
	character = world.call("get_player_character")
	service = story.get_service()
	await _go_through_exit(player)
	await _press_until(INTERACT, func() -> bool: return not story.is_scene_playing())
	await scene_tree.process_frame
	assert_eq(int(world.call("story_encounter_remaining")), 2, "setup: the wave is here")
	var skills := main.get_node("Systems/SkillRuntime") as SkillRuntime
	knowledge.grant(&"know_dan_khi_quyet", &"setup_gate_b1")
	cultivation.get_service().gather(character, 999)
	cultivation.get_service().breakthrough(character)
	cultivation.realm_advanced.emit(character.realm_id, character.realm_layer, true)
	knowledge.grant(&"know_loi_chi", &"setup_gate_b1")
	await _wait_until(func() -> bool: return skills.qi() >= 16.0, 1200)
	assert_true(skills.knows(&"tech_loi_chi") and skills.qi() >= 16.0,
		"setup: the thunder finger is known and there is breath for it")
	var wave: Array[Node2D] = []
	for enemy in combat.enemies():
		if String(enemy.name).begins_with(NIGHT_PREFIX):
			wave.append(enemy)
	wave[1].call("take_damage", 99999)
	wave[0].call("take_damage", int(wave[0].call("get_current_health")) - 1)
	await scene_tree.physics_frame
	assert_eq(int(world.call("story_encounter_remaining")), 1,
		"setup: one left, one blow from down")
	player.global_position = wave[0].global_position - Vector2(150, 0)
	(player.get_node("AttackComponent") as AttackComponent).set_facing(Vector2.RIGHT)
	var xp_before := character.xp
	await _fire_action(&"skill_2")
	await _wait_until(func() -> bool: return not skills.bolts().is_empty(), 240)
	assert_false(skills.bolts().is_empty(), "a real key cast it: the bolt is in the air")
	player.call("take_damage", 99999)   # the blow that fells the caster, bolt still flying
	await _wait_until(func() -> bool: return bool(wave[0].call("is_dead")), 240)
	for _i in 6:
		await scene_tree.process_frame
	hud = _find_hud(router.call("get_current_scene"))
	assert_true(bool(player.call("is_dead")) and bool(wave[0].call("is_dead")),
		"the caster fell, and the bolt it had already loosed still landed and killed")
	assert_true(character.xp > xp_before, "the kill is the kill it was (paid once by its owner)")
	assert_eq(service.state().option_of(&"choice_night_stand"), &"",
		"but the fallen did not 'stand': the Night is not answered for them")
	assert_eq(service.state().beat_id, &"beat_night", "no morning comes to a defeat")
	assert_false(story.is_scene_playing() or hud.is_story_scene_open(),
		"and no story card opens over it")
	assert_eq(hud.session_prompt_kind(), GameplayHUD.PROMPT_DEFEAT,
		"one surface holds the player: the defeat")
	await _press_until(INTERACT, func() -> bool: return gs.get_phase() == gs.Phase.MENU)
	assert_eq(gs.get_phase(), gs.Phase.MENU, "acknowledged with a real key: back at the menu")
	assert_false(story.is_session_active() or bool(world.call("is_story_encounter_live")),
		"with no story and no encounter left behind")
	_step("13. a bolt outlives its caster and kills: nothing answered, nothing over the defeat")
	_teardown(main)
	await scene_tree.process_frame


var _arrivals := 0
var _arrivals_judged := 0
var _arrival_faults: Array[String] = []


## WHAT A MAP SHOWS ON ARRIVAL IS WHAT THE STORY SAYS (D-073 follow-up, FG-4). Run deferred
## from `active_map_ready`: after every owner has wired the new map, before the frame that
## shows it. Five agreements, each a way a transition can lie to the player:
##   light     the map wears the ambience of the story's current beat (no night left behind,
##             no day over a Night);
##   presence  each thing the story puts in or takes out of the map is there exactly when its
##             flag says, and solid exactly when it is there;
##   pickups   nothing already taken, and nothing not yet in the world, is drawn;
##   spawn     the player stands on one of the map's own named spawn points;
##   creatures while a scene is still playing over the map, nothing of the story's encounter
##             is in it (a fight never starts under a caption).
func _judge_arrival(main: Node, arrival: int) -> void:
	var story := main.get_node_or_null("Systems/StoryRuntime") as StoryRuntime
	var world := main.get_node_or_null("Systems/WorldRuntime")
	var bag := main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	var combat := main.get_node_or_null("Systems/CombatRuntime") as CombatRuntime
	if story == null or world == null or not story.is_session_active():
		return  # a map arriving as the session is torn down has no story to agree with
	var map := world.call("get_active_map") as Node
	var player := world.call("get_player") as Node2D
	if map == null or player == null:
		return
	_arrivals_judged += 1
	var where := "arrival %d (%s, %s)" % [arrival, map.name,
		story.get_service().state().beat_id]
	var light := map.get_node_or_null("Visual/Ambience") as MapAmbience
	if light == null or light.ambience_id() != story.ambience_id():
		_arrival_faults.append("%s: light '%s' but the story says '%s'" % [where,
			light.ambience_id() if light != null else &"<none>", story.ambience_id()])
	for found in map.find_children("*", "", true, false):
		var presence := found as StoryPresence
		if presence == null:
			continue
		var host := presence.get_parent() as CanvasItem
		var there := story.get_service().flag_at_least(presence.flag_id, 1) \
			== presence.present_when_set
		if host.visible != there:
			_arrival_faults.append("%s: %s drawn=%s but the story says there=%s" % [where,
				host.name, host.visible, there])
		for body in host.find_children("*", "CollisionObject2D", true, false):
			for owner_id in (body as CollisionObject2D).get_shape_owners():
				if (body as CollisionObject2D).is_shape_owner_disabled(owner_id) == there:
					_arrival_faults.append("%s: %s solid=%s but there=%s" % [where,
						host.name, not there, there])
	var pickups := map.get_node_or_null("Pickups")
	for child in pickups.get_children() if pickups != null else []:
		var pickup := child as WorldItem
		if pickup == null or not pickup.visible:
			continue
		if bag != null and bag.is_collected(pickup.pickup_id):
			_arrival_faults.append("%s: %s drawn, already collected" % [where, pickup.name])
		elif pickup.appears_with_flag != &"" \
				and not story.get_service().flag_at_least(pickup.appears_with_flag, 1):
			_arrival_faults.append("%s: %s drawn, not in the world yet" % [where, pickup.name])
	var on_a_spawn := false
	var spawns := map.get_node_or_null("Spawns")
	for marker in spawns.get_children() if spawns != null else []:
		if (marker as Node2D).global_position.distance_to(player.global_position) < 2.0:
			on_a_spawn = true
	if not on_a_spawn:
		_arrival_faults.append("%s: the player is at %s, on no named spawn" % [where,
			player.global_position])
	if story.is_scene_playing() and combat != null:
		for enemy in combat.enemies():
			if enemy.look() != enemy.data().visual_profile:
				_arrival_faults.append("%s: '%s' is in the map under a playing scene"
					% [where, enemy.instance_id()])


func _step(step_name: String) -> void:
	var failed := get_failures().size()
	print("[e2e-story] [%s] %s" % ["PASS" if failed == _passed else "FAIL", step_name])
	_passed = failed


func _count_players(main: Node) -> int:
	var count := 0
	for node in main.find_children("*", "CharacterBody2D", true, false):
		if node is Player:
			count += 1
	return count


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


func _all_label_text(node: Node) -> Array:
	var out: Array = []
	if node is Label and (node as Label).is_visible_in_tree():
		out.append((node as Label).text)
	for child in node.get_children():
		out.append_array(_all_label_text(child))
	return out


func _on_withheld(pickup_id: StringName, _reason_key: StringName) -> void:
	_withheld.append(pickup_id)


## Stand the player beside `npc` (setup), then WALK into reach with a held move key and talk
## with a real interact.
func _talk_to(player: Node2D, map: Node, npc: WorldNpc, offset: Vector2,
		toward: StringName = MOVE_LEFT) -> void:
	assert_not_null(npc, "the person is in this map")
	if npc == null:
		return
	player.global_position = npc.global_position + offset
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	Input.action_press(toward)
	await _wait_until(func() -> bool: return map.call("active_interactable") == npc, 180)
	Input.action_release(toward)
	await scene_tree.physics_frame
	await _press_until(INTERACT, func() -> bool: return _dialogue.is_open())


## Acknowledge the current line until the conversation is at `node_id` ("" = closed).
func _advance_to(node_id: StringName) -> void:
	await _press_until(INTERACT, func() -> bool:
		return (not _dialogue.is_open()) if node_id == &"" \
			else _dialogue.current_node_id() == node_id)


## Move the cursor to `choice_id` with real move keys, then say it with ONE real interact.
func _say(choice_id: StringName, then: StringName) -> void:
	assert_true(_panel.choice_ids().has(choice_id), "'%s' is offered (%s)"
		% [choice_id, str(_panel.choice_ids())])
	for _i in 8:
		if _panel.selected_choice_id() == choice_id:
			break
		await _fire_action(MOVE_DOWN)
		for _j in 3:
			await scene_tree.process_frame
	assert_eq(_panel.selected_choice_id(), choice_id, "real move keys selected '%s'" % choice_id)
	await _press_until(INTERACT, func() -> bool:
		return (not _dialogue.is_open()) if then == &"" \
			else _dialogue.current_node_id() == then)
	assert_eq(_dialogue.current_node_id(), then, "saying '%s' led to '%s'" % [choice_id, then])


## Stand the player on the active map's exit (setup) and go through it with a real interact.
func _go_through_exit(player: Node2D) -> void:
	var router := scene_tree.root.get_node_or_null("SceneRouter")
	var active: Node = router.call("get_current_scene")
	var from_key := str(router.call("get_current_key"))
	var zone: Node2D = null
	for child in active.get_node("Exits").get_children():
		if child is MapExitZone:
			zone = child
			break
	assert_not_null(zone, "the active map has an exit")
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
	await scene_tree.process_frame


func _wait_until(predicate: Callable, frames: int) -> void:
	for _i in frames:
		if predicate.call():
			return
		await scene_tree.physics_frame


## Press `action` ONCE through the real input pipeline and wait for `done`. Only if nothing at
## all changed is the press repeated (bounded): a synthetic press can be lost between two
## reads (L-016), but a press that landed is never sent twice.
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
		assert_true(false, "action '%s' has no key to press" % action)
		return
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await scene_tree.process_frame
	Input.parse_input_event(_key_event_for(action, false))
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


func _teardown(main: Node) -> void:
	for a in [MOVE_RIGHT, INTERACT, OPEN_MENU, UI_ACCEPT, UI_CANCEL, UI_DOWN, UI_LEFT,
			UI_RIGHT, UI_UP]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()

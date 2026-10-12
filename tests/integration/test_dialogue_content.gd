extends TestCase
## Integration tests for the SHIPPED Phase-18 dialogue content against the real owners it
## names: the knowledge catalog, the relationship config, the shop catalog, the world
## simulation's cast and the localization table. Still no scene tree.

const DIALOGUES_PATH := "res://data/dialogue/dialogue_catalog.tres"
const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"
const SHOPS_PATH := "res://data/shops/shop_catalog.tres"
const QUESTS_PATH := "res://data/quests/quest_catalog.tres"
const STORY_PATH := "res://data/story/story_catalog.tres"
const ORIGINS_PATH := "res://data/story/origin_catalog.tres"
const WORLD_SIM_PATH := "res://data/worldsim/world_sim_catalog.tres"
const LocalizationScript := preload("res://src/infrastructure/localization.gd")

const KO := &"actor_scout_ko"
const SHEN := &"actor_elder_shen"
const PLAYER := &"char_test_player"
const LIN := &"actor_disciple_lin"
const TE := &"actor_carter_te"
const HEARD := &"flag_heard_village_business"
const STELE := &"know_lac_ha_stele_record"

var _knowledge: KnowledgeService = null
var _relationship: RelationshipService = null
var _config: RelationshipConfigData = null
var _service: DialogueService = null
var _quests: QuestService = null
var _loc: Node = null
var _story: StoryService = null
var _player: CharacterState = null


func before_each() -> void:
	_fresh_owners()
	_begin_story(&"origin_nghe_nhan")
	# A private instance: the shared autoload's language is never touched (L-010).
	_loc = LocalizationScript.new()


## Owners with nothing in them: no knowledge, no regard, no quest taken.
func _fresh_owners() -> void:
	_config = load(CONFIG_PATH) as RelationshipConfigData
	_relationship = RelationshipService.new(RelationshipStore.new(_config), _config)
	_knowledge = KnowledgeService.new(load(KNOWLEDGE_PATH) as KnowledgeCatalogData,
		KnowledgeStore.new())
	# The shipped conversations name the shipped quests (Phase 19): the quest owner is one of
	# the owners this content is validated against. Nothing here pays a reward.
	_quests = QuestService.new(load(QUESTS_PATH) as QuestCatalogData, QuestState.new(),
		_knowledge, RewardService.new(RewardLedger.new()),
		func(_item_id: StringName) -> int: return 0)


func after_each() -> void:
	if _loc != null:
		_loc.free()
	_loc = null
	_service = null
	_story = null
	_player = null
	_quests = null
	_relationship = null
	_knowledge = null


func _ids(dialogue_id: StringName, node_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for option in _service.eligible_choices(dialogue_id, node_id, PLAYER):
		ids.append(option.id)
	return ids


func _choose(dialogue_id: StringName, node_id: StringName,
		choice_id: StringName) -> DialogueOutcome:
	return _service.choose(dialogue_id, node_id, choice_id, PLAYER, _knowledge.grant,
		Callable(), _story_op)


## The story the shipped conversations ask (Phase 20), begun as `origin_id`, and the dialogue
## service over it. Bound methods, not lambdas: a lambda capturing this test would leak it.
func _begin_story(origin_id: StringName) -> void:
	_player = CharacterState.new()
	_player.instance_id = PLAYER
	var owners := StoryOwners.new()
	owners.knows = _knowledge.knows
	owners.can_teach = _knowledge.can_grant
	owners.teach_all = _knowledge_batch
	owners.can_move_regard = _can_move_regard
	owners.move_regard = _move_regard
	owners.give_all = _give_all
	owners.take_all = _give_all  # this rig's bag is a stand-in that accepts both ways
	_story = StoryService.new(load(STORY_PATH) as StoryCatalogData,
		load(ORIGINS_PATH) as OriginCatalogData, StoryState.new(), _player, owners)
	assert_true(_story.begin(origin_id).ok, "the story begins as %s" % origin_id)
	_service = DialogueService.new(load(DIALOGUES_PATH) as DialogueCatalogData, _knowledge,
		_relationship, _config, _quests, _story)


func _knowledge_batch(knowledge_ids: Array[StringName], source_id: StringName) -> bool:
	return _knowledge.grant_all(knowledge_ids, source_id) != null


func _can_move_regard(character_id: StringName, dimension: StringName, delta: int) -> bool:
	return RegardRules.can_move(_relationship, _config, character_id, PLAYER, dimension, delta)


func _move_regard(character_id: StringName, dimension: StringName, delta: int) -> Dictionary:
	return RegardRules.move(_relationship, _config, character_id, PLAYER, dimension,
		delta, &"test_story")


func _give_all(_items: Dictionary) -> bool:
	return true


func _story_op(effect: DialogueEffectData) -> StringName:
	var outcome: StoryOutcome = null
	if effect.kind == DialogueEffectData.Kind.SET_FLAG:
		outcome = _story.set_flag(effect.flag_id, effect.flag_value)
	else:
		outcome = _story.choose(effect.story_choice_id, effect.story_option_id)
	return &"" if outcome.ok else outcome.reason


func test_the_shipped_catalog_is_valid_against_every_owner_it_names() -> void:
	var catalog := load(DIALOGUES_PATH) as DialogueCatalogData
	assert_not_null(catalog, "the shipped dialogue catalog loads")
	assert_eq(catalog.validation_errors(), [] as Array[String], "structurally valid")
	assert_true(_service.is_ready(), "the service accepts it")
	var shops := load(SHOPS_PATH) as ShopCatalogData
	var errors := _service.content_errors(
		func(key: StringName) -> bool: return bool(_loc.call("is_translated", String(key))),
		func(id: StringName) -> bool: return shops.shop_of_keeper(id) != null)
	assert_eq(errors, [] as Array[String],
		"knowledge ids, dimensions, thresholds, shops and both languages all resolve")


func test_two_people_speak_and_both_exist_in_the_world() -> void:
	var catalog := _service.catalog()
	assert_true(catalog.entries.size() >= 2, "more than one conversation is authored")
	var cast: Dictionary = {}
	for actor in (load(WORLD_SIM_PATH) as WorldSimCatalog).actors:
		cast[actor.id] = true
	for dialogue in catalog.entries:
		assert_true(cast.has(dialogue.speaker_id),
			"%s is spoken by '%s', a character the session realizes"
				% [dialogue.id, dialogue.speaker_id])
	assert_not_null(catalog.dialogue_of_speaker(KO), "Kha Thản has one")
	assert_not_null(catalog.dialogue_of_speaker(SHEN), "Thẩm Bất Kỳ has one")


func test_every_mood_and_dimension_the_content_can_show_has_a_name() -> void:
	for mood: String in DialogueNodeData.Mood.keys():
		assert_true(bool(_loc.call("is_translated", "UI_DIALOGUE_MOOD_%s" % mood)),
			"mood %s is named in both languages" % mood)
	for dimension: Dictionary in _config.dimensions:
		assert_true(bool(_loc.call("is_translated",
			"UI_REL_DIM_%s" % String(dimension["id"]).to_upper())),
			"dimension %s is named in both languages" % dimension["id"])


func test_is_translated_rejects_a_missing_key() -> void:
	assert_false(bool(_loc.call("is_translated", "DLG_NO_SUCH_LINE")), "an unknown key")
	assert_true(bool(_loc.call("is_translated", "DLG_KO_GREET")), "a shipped line")


func test_the_scout_rewards_news_and_resents_haggling() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(KO)
	assert_eq(_service.advance(dialogue.id, dialogue.start_node_id).next_node_id, &"ko_hub",
		"his greeting leads to what he offers")
	assert_eq(_ids(dialogue.id, &"ko_price"), [&"ko_press", &"ko_price_back"]
		as Array[StringName], "with nothing to tell him, news is not on offer")
	_knowledge.grant(STELE, &"test")
	assert_true(_ids(dialogue.id, &"ko_price").has(&"ko_share_stele"),
		"having read the stele, the player has news")
	var shared := _choose(dialogue.id, &"ko_price", &"ko_share_stele")
	assert_eq([shared.new_value, shared.next_node_id], [40, &"ko_pleased"],
		"he is pleased: affinity 40")
	assert_false(_ids(dialogue.id, &"ko_price").has(&"ko_share_stele"),
		"the same news is not news twice")
	var pressed := _choose(dialogue.id, &"ko_price", &"ko_press")
	assert_eq([pressed.new_value, pressed.next_node_id], [10, &"ko_bristle"], "haggling costs 30")
	_choose(dialogue.id, &"ko_price", &"ko_press")
	_choose(dialogue.id, &"ko_price", &"ko_press")
	assert_eq(_service.regard(KO, PLAYER, &"affinity"), -50, "10 -> -20 -> -50")
	assert_false(_ids(dialogue.id, &"ko_price").has(&"ko_press"),
		"and then he will not be pressed further")
	assert_eq(_relationship.get_store().edge_count(), 1, "all of it on one edge")


func test_the_scout_teaches_the_woods_and_hands_over_to_his_shop() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(KO)
	var asked := _choose(dialogue.id, &"ko_hub", &"ko_ask_woods")
	assert_eq(asked.knowledge_result, KnowledgeService.GRANTED, "he tells what he knows")
	assert_true(_knowledge.knows(&"know_vu_lang_hunting_ground"), "and the Core holds it")
	assert_eq(asked.next_node_id, &"ko_woods", "the line that says it follows")
	var trade := _choose(dialogue.id, &"ko_hub", &"ko_trade")
	assert_eq(trade.action, DialogueService.ACTION_OPEN_SHOP, "trade is a handoff")
	assert_true(trade.ended, "that ends the talk")


func test_the_elder_opens_up_only_to_one_who_has_read() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(SHEN)
	assert_eq(_ids(dialogue.id, &"shen_hub"),
		[&"shen_issue_ask", &"shen_leave"] as Array[StringName],
		"to someone who has read nothing he offers only the door")
	_knowledge.grant(STELE, &"test")
	assert_eq(_ids(dialogue.id, &"shen_hub"),
		[&"shen_report", &"shen_task_ask", &"shen_issue_ask", &"shen_leave"] as Array[StringName],
		"the stele gives the player something to recount, and him someone to ask (Phase 19)")
	var reported := _choose(dialogue.id, &"shen_hub", &"shen_report")
	assert_eq([reported.dimension, reported.new_value], [&"respect", 15], "respect earned")
	assert_eq(_ids(dialogue.id, &"shen_hub"),
		[&"shen_ask", &"shen_task_ask", &"shen_issue_ask", &"shen_leave"] as Array[StringName],
		"which closes one line and opens the next")
	var taught := _choose(dialogue.id, &"shen_hub", &"shen_ask")
	assert_eq(taught.knowledge_result, KnowledgeService.GRANTED, "now he teaches")
	assert_true(_knowledge.knows(&"know_thanh_dai_precept"), "the precept is held by the Core")
	assert_eq(_service.regard(KO, PLAYER, &"affinity"), 0,
		"and none of it touched how someone else regards the player")


# --- The story seam (Phase 20, D-072) --------------------------------------------

func test_the_elder_hands_over_the_outposts_issue_once() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(SHEN)
	assert_false(_story.flag_at_least(&"flag_outpost_issue", 1), "nothing is issued at first")
	var asked := _choose(dialogue.id, &"shen_hub", &"shen_issue_ask")
	assert_true(asked.ok, "asking is accepted")
	assert_eq(asked.next_node_id, &"shen_issue", "and he says on what terms")
	assert_true(_story.flag_at_least(&"flag_outpost_issue", 1), "the story records the issue")
	assert_false(_ids(dialogue.id, &"shen_hub").has(&"shen_issue_ask"), "a line said once")
	assert_false(_choose(dialogue.id, &"shen_hub", &"shen_issue_ask").ok,
		"and a stale second answer is refused")


func test_hearing_a_problem_out_is_recorded_whether_or_not_it_is_taken() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(KO)
	assert_false(_story.flag_at_least(HEARD, 1), "nothing heard yet")
	assert_true(_choose(dialogue.id, &"ko_hub", &"ko_pills_ask").ok, "asking Kha Thản")
	assert_true(_story.flag_at_least(HEARD, 1), "is hearing the village's business")
	assert_eq(_quests.phase_of(&"quest_treeline_pills"), QuestData.Phase.AVAILABLE,
		"and takes nothing on: declining still counts as having heard")


func test_lin_confides_only_in_someone_who_has_taken_part() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(LIN)
	assert_eq(_service.opening_node_id(dialogue.id, PLAYER), &"lin_greet", "a stranger's greeting")
	assert_false(_ids(dialogue.id, &"lin_hub").has(&"lin_press"), "a stranger cannot press her")
	_story.set_flag(HEARD, 1)
	assert_true(_ids(dialogue.id, &"lin_hub").has(&"lin_press"), "one who has taken part can")


func test_keeping_lins_confidence_is_one_transaction_made_once() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(LIN)
	_story.set_flag(HEARD, 1)
	var kept := _choose(dialogue.id, &"lin_confide", &"lin_keep")
	assert_true(kept.ok, "the promise is accepted")
	assert_eq(_story.state().option_of(&"choice_lam_readings"), &"kept", "recorded by the story")
	assert_eq(_service.regard(LIN, PLAYER, &"trust"), 15, "her trust moved, through the graph")
	assert_eq(_story.flag_value(&"flag_lam_settled"), 1, "and the matter is settled as kept")
	var again := _choose(dialogue.id, &"lin_confide", &"lin_keep")
	assert_false(again.ok, "a second submission is refused")
	assert_eq(again.reason, StoryService.REFUSE_ALREADY_CHOSEN,
		"by the story owner, with its reason")
	assert_eq(_service.regard(LIN, PLAYER, &"trust"), 15, "and moves nothing twice")
	assert_false(_ids(dialogue.id, &"lin_hub").has(&"lin_press"), "she does not ask again")
	assert_eq(_service.opening_node_id(dialogue.id, PLAYER), &"lin_after_kept",
		"and greets the player as someone who kept faith")
	var elder := _service.catalog().dialogue_of_speaker(SHEN)
	assert_false(_ids(elder.id, &"shen_hub").has(&"shen_tell_lin"), "there is nothing to tell")


func test_refusing_lin_leaves_both_roads_open_and_telling_closes_them() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(LIN)
	var elder := _service.catalog().dialogue_of_speaker(SHEN)
	_story.set_flag(HEARD, 1)
	assert_false(_ids(elder.id, &"shen_hub").has(&"shen_tell_lin"),
		"the elder cannot be told what the player has not been asked to hide")
	assert_true(_choose(dialogue.id, &"lin_confide", &"lin_refuse").ok, "no promise given")
	assert_false(_story.state().has_chosen(&"choice_lam_readings"), "nothing is decided yet")
	assert_true(_ids(dialogue.id, &"lin_hub").has(&"lin_keep_late"), "she can still be promised")
	assert_false(_ids(elder.id, &"shen_hub").has(&"shen_tell_lin"),
		"but the elder hears reports only from those he has armed")
	assert_true(_choose(elder.id, &"shen_hub", &"shen_issue_ask").ok, "the issue is taken")
	assert_true(_ids(elder.id, &"shen_hub").has(&"shen_tell_lin"), "and now he can be told")
	var told := _choose(elder.id, &"shen_hub", &"shen_tell_lin")
	assert_true(told.ok, "telling him is accepted")
	assert_eq(_story.state().option_of(&"choice_lam_readings"), &"told", "recorded")
	assert_eq(_service.regard(SHEN, PLAYER, &"trust"), 10, "the elder trusts the player more")
	assert_eq(_service.regard(LIN, PLAYER, &"affinity"), -15, "and she likes them less")
	assert_false(_ids(dialogue.id, &"lin_hub").has(&"lin_keep_late"), "the promise is gone")
	assert_false(_ids(elder.id, &"shen_hub").has(&"shen_tell_lin"), "and it is told once")
	assert_eq(_service.opening_node_id(dialogue.id, PLAYER), &"lin_after_told",
		"she greets the player as the one who told")


func test_each_origin_notices_its_own_thing_about_the_carters_load_once() -> void:
	var expected := {&"origin_nghe_nhan": &"te_mark", &"origin_ho_tieu": &"te_knot",
		&"origin_lang_y": &"te_hands", &"origin_thu_thu": &"te_ledger",
		&"origin_de_tu_bi_loai": &"te_seats"}
	var all: Array = expected.values()
	for origin_id: StringName in expected:
		_begin_story(origin_id)
		var dialogue := _service.catalog().dialogue_of_speaker(TE)
		var offered := _ids(dialogue.id, &"te_hub")
		for choice_id: StringName in all:
			assert_eq(offered.has(choice_id), choice_id == expected[origin_id],
				"%s is offered %s only if it is theirs" % [origin_id, choice_id])
		assert_true(_choose(dialogue.id, &"te_hub", expected[origin_id]).ok, "noticed")
		assert_false(_ids(dialogue.id, &"te_hub").has(expected[origin_id]),
			"%s notices it once" % origin_id)


func test_the_rejected_disciple_and_lin_know_each_other() -> void:
	var dialogue := _service.catalog().dialogue_of_speaker(LIN)
	assert_false(_ids(dialogue.id, &"lin_hub").has(&"lin_rival"), "an artisan never sat the trial")
	_begin_story(&"origin_de_tu_bi_loai")
	dialogue = _service.catalog().dialogue_of_speaker(LIN)
	assert_true(_ids(dialogue.id, &"lin_hub").has(&"lin_rival"), "the one who failed it did")
	assert_eq(_service.regard(LIN, PLAYER, &"rivalry"), 15, "and she already remembers them")


# === The Act-I bridge (D-073 §1): who is shown the sheet, and what each Origin notices ======

const DLG_LIN := &"dlg_disciple_lin"
const DLG_KO := &"dlg_scout_ko"
const DLG_SHEN := &"dlg_elder_shen"
const FRAGMENT := &"know_survey_fragment"
const SHAFT := &"know_sealed_shaft"
## Each person's conversation and the line it opens on once Act I has begun.
const TRAILS := [[DLG_LIN, &"lin_trail"], [DLG_KO, &"ko_trail"], [DLG_SHEN, &"shen_trail"]]


## Bring the story to open Act-I play the way a run does: `readings` kept or told, the Night
## `stood` or `withdrew`, the sheet read, the carter heard.
func _to_act_one(origin_id: StringName, readings: StringName, night: StringName) -> void:
	_fresh_owners()  # a new run: nothing an earlier Origin knew or earned is carried over
	_begin_story(origin_id)
	_story.note(StoryTriggerData.Kind.SCENE_ENDED, &"scene")
	for who: StringName in [SHEN, LIN, KO]:
		_story.meet(who)
	_story.set_flag(HEARD, 1)
	assert_true(_story.choose(&"choice_lam_readings", readings).ok, "setup: %s" % readings)
	_story.note(StoryTriggerData.Kind.ARRIVED, &"map_field")
	assert_true(_story.choose(&"choice_night_stand", night).ok, "setup: %s" % night)
	_story.set_flag(&"flag_heard_elder_account", 1)
	_story.set_flag(&"flag_ko_night_said", 1)  # the line the Night owed has been heard
	_story.note(StoryTriggerData.Kind.CULTIVATED)


func _end_prologue() -> void:
	_knowledge.grant(FRAGMENT, &"source_survey_sheet")
	_story.refresh()
	_story.set_flag(&"flag_heard_road_ahead", 1)
	assert_eq(_story.state().beat_id, &"beat_whose_hand", "setup: Act I, the sheet in hand")


func test_nobody_opens_on_the_sheet_before_the_prologue_is_over() -> void:
	_to_act_one(&"origin_lang_y", &"kept", &"stood")
	_knowledge.grant(FRAGMENT, &"source_survey_sheet")
	_story.refresh()
	assert_eq(_story.state().beat_id, &"beat_leaving", "sheet held, the carter not yet heard")
	for pair: Array in TRAILS:
		assert_ne(_service.opening_node_id(pair[0], PLAYER), pair[1],
			"%s does not open on the sheet yet: the decision cannot be made early" % pair[0])
	_end_prologue()
	for pair: Array in TRAILS:
		assert_eq(_service.opening_node_id(pair[0], PLAYER), pair[1],
			"%s opens on it once Act I has begun" % pair[0])


func test_each_person_offers_the_sheet_in_the_words_the_run_has_earned() -> void:
	# kept + stood: she will read it; the watchman speaks to one who stood.
	_to_act_one(&"origin_lang_y", &"kept", &"stood")
	_end_prologue()
	assert_eq(_ids(DLG_LIN, &"lin_trail"), [&"lin_show", &"lin_trail_back"] as Array[StringName],
		"kept: she offers to read it")
	assert_eq(_ids(DLG_KO, &"ko_trail"), [&"ko_show_stood", &"ko_trail_back"] as Array[StringName],
		"stood: the watchman's line for one who stayed")
	assert_eq(_ids(DLG_SHEN, &"shen_trail"), [&"shen_show", &"shen_trail_back"]
		as Array[StringName], "the elder can always be shown it")
	# told + withdrew: she refuses; the watchman speaks to one who left.
	_to_act_one(&"origin_lang_y", &"told", &"withdrew")
	_end_prologue()
	assert_eq(_ids(DLG_LIN, &"lin_trail"), [&"lin_show_refused", &"lin_trail_back"]
		as Array[StringName], "told: she does not read it for the one who told on her")
	assert_eq(_ids(DLG_KO, &"ko_trail"), [&"ko_show_left", &"ko_trail_back"] as Array[StringName],
		"withdrew: the watchman's line for one who left")


func test_her_refusal_is_said_once_records_nothing_and_leaves_two_people_to_ask() -> void:
	_to_act_one(&"origin_lang_y", &"told", &"stood")
	_end_prologue()
	var record := str(_story.state().to_dict())
	var refused := _choose(DLG_LIN, &"lin_trail", &"lin_show_refused")
	assert_true(refused.ok, "the line is said")
	assert_eq(refused.next_node_id, &"lin_sheet_refuse", "and it is her refusal")
	assert_eq(str(_story.state().to_dict()), record, "which records no decision")
	assert_false(_story.state().has_chosen(&"choice_sheet_shown"), "the choice is still open")
	assert_eq(_ids(DLG_LIN, &"lin_trail"), [&"lin_trail_back"] as Array[StringName],
		"she does not say it twice")
	assert_true(_ids(DLG_KO, &"ko_trail").has(&"ko_show_stood")
		and _ids(DLG_SHEN, &"shen_trail").has(&"shen_show"), "and two people can still be shown it")


func test_the_first_showing_is_the_decision_and_the_others_answer_once_for_nothing() -> void:
	_to_act_one(&"origin_lang_y", &"kept", &"stood")
	_end_prologue()
	var shown := _choose(DLG_SHEN, &"shen_trail", &"shen_show")
	assert_true(shown.ok, "the elder is shown it first")
	assert_eq(_story.state().option_of(&"choice_sheet_shown"), &"shen", "recorded")
	assert_eq(RegardRules.read(_relationship, _config, SHEN, PLAYER, &"affinity"), -10,
		"he thinks the worse of someone holding that page")
	assert_true(_knowledge.knows(&"know_shaft_claim"), "and his claim about the shaft is known")
	assert_eq(_ids(DLG_SHEN, &"shen_trail"), [&"shen_trail_back"] as Array[StringName],
		"he has said his piece")
	var lin_trust := RegardRules.read(_relationship, _config, LIN, PLAYER, &"trust")
	assert_eq(_ids(DLG_LIN, &"lin_trail"), [&"lin_show_late", &"lin_trail_back"]
		as Array[StringName], "she can still be asked — as someone who came second")
	assert_true(_choose(DLG_LIN, &"lin_trail", &"lin_show_late").ok, "she answers")
	assert_eq(RegardRules.read(_relationship, _config, LIN, PLAYER, &"trust"), lin_trust,
		"with no trust for coming second")
	assert_false(_knowledge.knows(&"know_surveyors_line"), "and no second prize of knowledge")
	assert_eq(_story.state().option_of(&"choice_sheet_shown"), &"shen", "the record is unchanged")
	assert_eq(_ids(DLG_LIN, &"lin_trail"), [&"lin_trail_back"] as Array[StringName], "once")
	assert_true(_choose(DLG_KO, &"ko_trail", &"ko_show_late").ok, "the watchman answers too")
	assert_eq(_ids(DLG_KO, &"ko_trail"), [&"ko_trail_back"] as Array[StringName], "once")


## Every Origin has exactly ONE thing only it notices on the trail, with one person, after the
## door is found, said once. Two are opened by what the Origin KNOWS, three by who it was.
func test_each_origin_notices_one_thing_on_the_trail_once_and_only_after_the_door() -> void:
	var lines := {
		&"origin_thu_thu": [DLG_SHEN, &"shen_trail", &"shen_trail_hand"],
		&"origin_nghe_nhan": [DLG_KO, &"ko_trail", &"ko_trail_stones"],
		&"origin_ho_tieu": [DLG_KO, &"ko_trail", &"ko_trail_ruts"],
		&"origin_lang_y": [DLG_KO, &"ko_trail", &"ko_trail_nails"],
		&"origin_de_tu_bi_loai": [DLG_KO, &"ko_trail", &"ko_trail_cord"],
	}
	var every: Array[StringName] = []
	for origin_id: StringName in lines:
		every.append(lines[origin_id][2])
	for origin_id: StringName in lines:
		_to_act_one(origin_id, &"told", &"withdrew")
		_end_prologue()
		var mine: Array = lines[origin_id]
		var offered: Array[StringName] = []
		for pair: Array in TRAILS:
			offered.append_array(_ids(pair[0], pair[1]))
		for line in every:
			assert_false(offered.has(line), "%s: '%s' is not said before the door is found"
				% [origin_id, line])
		_knowledge.grant(SHAFT, &"source_shaft_seal")
		offered.clear()
		for pair: Array in TRAILS:
			offered.append_array(_ids(pair[0], pair[1]))
		for line in every:
			assert_eq(offered.has(line), line == mine[2],
				"%s: of the five, only its own line is offered ('%s')" % [origin_id, line])
		assert_true(_choose(mine[0], mine[1], mine[2]).ok, "%s notices it" % origin_id)
		assert_true(_story.flag_at_least(&"flag_trail_origin_said", 1), "on the record")
		assert_false(_ids(mine[0], mine[1]).has(mine[2]), "%s: and only once" % origin_id)


func test_the_door_is_answered_by_each_person_once_and_by_her_in_two_ways() -> void:
	for readings: StringName in [&"kept", &"told"]:
		_to_act_one(&"origin_lang_y", readings, &"stood")
		_end_prologue()
		_knowledge.grant(SHAFT, &"source_shaft_seal")
		var hers: StringName = &"lin_shaft_kept" if readings == &"kept" else &"lin_shaft_told"
		var not_hers: StringName = &"lin_shaft_told" if readings == &"kept" else &"lin_shaft_kept"
		assert_true(_ids(DLG_LIN, &"lin_trail").has(hers), "%s: her answer to the door" % readings)
		assert_false(_ids(DLG_LIN, &"lin_trail").has(not_hers), "%s: and not the other" % readings)
		for triple: Array in [[DLG_LIN, &"lin_trail", hers], [DLG_KO, &"ko_trail", &"ko_shaft"],
				[DLG_SHEN, &"shen_trail", &"shen_shaft"]]:
			assert_true(_choose(triple[0], triple[1], triple[2]).ok, "%s is said" % triple[2])
			assert_false(_ids(triple[0], triple[1]).has(triple[2]), "%s is said once" % triple[2])


## H21-15: a person who has NOTHING LEFT to say about the sheet does not greet the player on
## it. Each of the three opens on the trail line only while that line has an answer other
## than "speak of something else", and on their ordinary hub once it has none — whichever
## order the lines were said in, and for every Origin's extra line.
func test_someone_with_no_trail_line_left_opens_on_their_hub() -> void:
	var hubs := {DLG_LIN: &"lin_hub", DLG_KO: &"ko_hub", DLG_SHEN: &"shen_hub"}
	for origin_id: StringName in [&"origin_lang_y", &"origin_thu_thu", &"origin_nghe_nhan",
			&"origin_ho_tieu", &"origin_de_tu_bi_loai"]:
		for readings: StringName in [&"kept", &"told"]:
			# Both answers to the Night (Gate B1): the watchman's lines differ by it
			# (`ko_show_stood` / `ko_show_left`), and "nothing left to say" must hold either way.
			for night: StringName in [&"stood", &"withdrew"]:
				_to_act_one(origin_id, readings, night)
				_end_prologue()
				var run := "%s/%s/%s" % [origin_id, readings, night]
				for stage: String in ["sheet in hand", "door found"]:
					if stage == "door found":
						_knowledge.grant(SHAFT, &"source_shaft_seal")
					# Say everything each person has to say, checking the opening before each line.
					for pair: Array in TRAILS:
						for _line in 8:
							var real: Array[StringName] = []
							for id in _ids(pair[0], pair[1]):
								if not String(id).ends_with("_trail_back"):
									real.append(id)
							var opens_on := _service.opening_node_id(pair[0], PLAYER)
							assert_eq(opens_on == pair[1], not real.is_empty(),
								"%s, %s: %s opens on '%s' with %d line(s) left to say"
								% [run, stage, pair[0], opens_on, real.size()])
							if real.is_empty():
								assert_eq(opens_on, hubs[pair[0]],
									"%s, %s: with nothing left, %s opens on the hub itself"
									% [run, stage, pair[0]])
								break
							assert_true(_choose(pair[0], pair[1], real[0]).ok,
								"%s, %s: '%s' is said" % [run, stage, real[0]])
	# The hub she opens on offers its ordinary answers and no dead line.
	assert_true(_ids(DLG_LIN, &"lin_hub").has(&"lin_leave"), "a hub always has a way out")



# === The §6 hook beats (NARRATIVE_MASTER_PLAN.md §6, PROPOSAL — NOT CANON) =====================
# Each Origin's hook into Đêm Vỡ Mạch is a playable beat: one choice, said once, on the record.


func test_the_escort_walks_guard_on_the_last_load_once_before_the_night() -> void:
	_begin_story(&"origin_ho_tieu")
	var dialogue := _service.catalog().dialogue_of_speaker(TE)
	assert_true(_ids(dialogue.id, &"te_hub").has(&"te_guard"),
		"the escort is offered the guard")
	assert_true(_choose(dialogue.id, &"te_hub", &"te_guard").ok, "takes up the guard")
	assert_true(_story.flag_at_least(&"flag_te_guard_said", 1), "said once, on the record")
	assert_false(_ids(dialogue.id, &"te_hub").has(&"te_guard"), "and only once")
	_begin_story(&"origin_nghe_nhan")
	dialogue = _service.catalog().dialogue_of_speaker(TE)
	assert_false(_ids(dialogue.id, &"te_hub").has(&"te_guard"),
		"no other Origin is offered it")


func test_the_guard_is_not_offered_once_the_night_has_come() -> void:
	_begin_story(&"origin_ho_tieu")
	_story.set_flag(&"flag_night_over", 1)
	var dialogue := _service.catalog().dialogue_of_speaker(TE)
	assert_false(_ids(dialogue.id, &"te_hub").has(&"te_guard"),
		"the load is gone by morning")


func test_the_healer_tends_the_watchmans_wounds_after_the_night() -> void:
	_begin_story(&"origin_lang_y")
	_story.set_flag(&"flag_night_over", 1)  # stood: the watch fought beside the player
	var dialogue := _service.catalog().dialogue_of_speaker(KO)
	assert_true(_ids(dialogue.id, &"ko_night_stood").has(&"ko_wounds"),
		"the healer may tend him")
	assert_true(_choose(dialogue.id, &"ko_night_stood", &"ko_wounds").ok, "tends the wounds")
	assert_true(_story.flag_at_least(&"flag_ko_wounds_said", 1), "said once, on the record")
	assert_false(_ids(dialogue.id, &"ko_night_stood").has(&"ko_wounds"), "and only once")
	_begin_story(&"origin_lang_y")
	_story.set_flag(&"flag_night_over", 2)  # withdrew: he held the treeline alone
	dialogue = _service.catalog().dialogue_of_speaker(KO)
	assert_true(_ids(dialogue.id, &"ko_night_left").has(&"ko_wounds_left"),
		"him too, on the other branch of the Night")
	assert_true(_choose(dialogue.id, &"ko_night_left", &"ko_wounds_left").ok, "tends the wounds")
	assert_true(_story.flag_at_least(&"flag_ko_wounds_said", 1), "said once, on the record")
	_begin_story(&"origin_ho_tieu")
	_story.set_flag(&"flag_night_over", 1)
	dialogue = _service.catalog().dialogue_of_speaker(KO)
	assert_false(_ids(dialogue.id, &"ko_night_stood").has(&"ko_wounds"),
		"no other Origin may tend him")


func test_the_artisan_appraises_what_spilled_from_the_cart() -> void:
	_begin_story(&"origin_nghe_nhan")
	_story.set_flag(&"flag_night_over", 1)
	var dialogue := _service.catalog().dialogue_of_speaker(TE)
	assert_true(_ids(dialogue.id, &"te_morning").has(&"te_morning_appraise"),
		"the artisan may read the spill")
	assert_true(_choose(dialogue.id, &"te_morning", &"te_morning_appraise").ok, "reads it")
	assert_true(_story.flag_at_least(&"flag_te_appraise_said", 1), "said once, on the record")
	assert_false(_ids(dialogue.id, &"te_morning").has(&"te_morning_appraise"), "and only once")
	_begin_story(&"origin_lang_y")
	_story.set_flag(&"flag_night_over", 1)
	dialogue = _service.catalog().dialogue_of_speaker(TE)
	assert_false(_ids(dialogue.id, &"te_morning").has(&"te_morning_appraise"),
		"no other Origin may read it")


func test_the_keeper_reads_the_mark_in_the_veins_residue() -> void:
	_begin_story(&"origin_thu_thu")
	var dialogue := _service.catalog().dialogue_of_speaker(LIN)
	assert_false(_ids(dialogue.id, &"lin_hub").has(&"lin_residue"),
		"before the Night there is no residue to read")
	_story.set_flag(&"flag_night_over", 1)
	assert_true(_ids(dialogue.id, &"lin_hub").has(&"lin_residue"), "the keeper may ask")
	assert_true(_choose(dialogue.id, &"lin_hub", &"lin_residue").ok, "asks")
	assert_true(_story.flag_at_least(&"flag_lin_residue_said", 1), "said once, on the record")
	assert_false(_ids(dialogue.id, &"lin_hub").has(&"lin_residue"), "and only once")
	_begin_story(&"origin_de_tu_bi_loai")
	_story.set_flag(&"flag_night_over", 1)
	dialogue = _service.catalog().dialogue_of_speaker(LIN)
	assert_false(_ids(dialogue.id, &"lin_hub").has(&"lin_residue"), "no other Origin may ask")


func test_the_wandering_healer_begins_with_a_healers_craft() -> void:
	_begin_story(&"origin_lang_y")
	assert_true(_knowledge.knows(&"know_drawn_pulse"), "the healer reads a drawn pulse")
	_fresh_owners()  # a new run: nothing an earlier Origin knew is carried over
	_begin_story(&"origin_ho_tieu")
	assert_false(_knowledge.knows(&"know_drawn_pulse"), "and no other Origin does")

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
	_config = load(CONFIG_PATH) as RelationshipConfigData
	_relationship = RelationshipService.new(RelationshipStore.new(_config), _config)
	_knowledge = KnowledgeService.new(load(KNOWLEDGE_PATH) as KnowledgeCatalogData,
		KnowledgeStore.new())
	# The shipped conversations name the shipped quests (Phase 19): the quest owner is one of
	# the owners this content is validated against. Nothing here pays a reward.
	_quests = QuestService.new(load(QUESTS_PATH) as QuestCatalogData, QuestState.new(),
		_knowledge, RewardService.new(RewardLedger.new()),
		func(_item_id: StringName) -> int: return 0)
	_begin_story(&"origin_nghe_nhan")
	# A private instance: the shared autoload's language is never touched (L-010).
	_loc = LocalizationScript.new()


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
	owners.teach = _teach
	owners.move_regard = _move_regard
	owners.give_all = _give_all
	_story = StoryService.new(load(STORY_PATH) as StoryCatalogData,
		load(ORIGINS_PATH) as OriginCatalogData, StoryState.new(), _player, owners)
	assert_true(_story.begin(origin_id).ok, "the story begins as %s" % origin_id)
	_service = DialogueService.new(load(DIALOGUES_PATH) as DialogueCatalogData, _knowledge,
		_relationship, _config, _quests, _story)


func _teach(knowledge_id: StringName, source_id: StringName) -> bool:
	var result := _knowledge.grant(knowledge_id, source_id)
	return result == KnowledgeService.GRANTED or result == KnowledgeService.ALREADY_KNOWN


func _move_regard(character_id: StringName, dimension: StringName, delta: int) -> bool:
	return bool(RegardRules.move(_relationship, _config, character_id, PLAYER, dimension,
		delta, &"test_story")["ok"])


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

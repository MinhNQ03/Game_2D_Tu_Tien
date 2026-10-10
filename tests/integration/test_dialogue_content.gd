extends TestCase
## Integration tests for the SHIPPED Phase-18 dialogue content against the real owners it
## names: the knowledge catalog, the relationship config, the shop catalog, the world
## simulation's cast and the localization table. Still no scene tree.

const DIALOGUES_PATH := "res://data/dialogue/dialogue_catalog.tres"
const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"
const SHOPS_PATH := "res://data/shops/shop_catalog.tres"
const QUESTS_PATH := "res://data/quests/quest_catalog.tres"
const WORLD_SIM_PATH := "res://data/worldsim/world_sim_catalog.tres"
const LocalizationScript := preload("res://src/infrastructure/localization.gd")

const KO := &"actor_scout_ko"
const SHEN := &"actor_elder_shen"
const PLAYER := &"char_test_player"
const STELE := &"know_lac_ha_stele_record"

var _knowledge: KnowledgeService = null
var _relationship: RelationshipService = null
var _config: RelationshipConfigData = null
var _service: DialogueService = null
var _quests: QuestService = null
var _loc: Node = null


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
	_service = DialogueService.new(load(DIALOGUES_PATH) as DialogueCatalogData, _knowledge,
		_relationship, _config, _quests)
	# A private instance: the shared autoload's language is never touched (L-010).
	_loc = LocalizationScript.new()


func after_each() -> void:
	if _loc != null:
		_loc.free()
	_loc = null
	_service = null
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
	return _service.choose(dialogue_id, node_id, choice_id, PLAYER, _knowledge.grant)


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
	assert_eq(_ids(dialogue.id, &"shen_hub"), [&"shen_leave"] as Array[StringName],
		"to someone who has read nothing he offers only the door")
	_knowledge.grant(STELE, &"test")
	assert_eq(_ids(dialogue.id, &"shen_hub"), [&"shen_report", &"shen_task_ask", &"shen_leave"]
		as Array[StringName],
		"the stele gives the player something to recount, and him someone to ask (Phase 19)")
	var reported := _choose(dialogue.id, &"shen_hub", &"shen_report")
	assert_eq([reported.dimension, reported.new_value], [&"respect", 15], "respect earned")
	assert_eq(_ids(dialogue.id, &"shen_hub"), [&"shen_ask", &"shen_task_ask", &"shen_leave"]
		as Array[StringName], "which closes one line and opens the next")
	var taught := _choose(dialogue.id, &"shen_hub", &"shen_ask")
	assert_eq(taught.knowledge_result, KnowledgeService.GRANTED, "now he teaches")
	assert_true(_knowledge.knows(&"know_thanh_dai_precept"), "the precept is held by the Core")
	assert_eq(_service.regard(KO, PLAYER, &"affinity"), 0,
		"and none of it touched how someone else regards the player")

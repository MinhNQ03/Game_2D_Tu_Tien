extends TestCase
## Unit tests for the seam between Dialogue and Quest (Phase 19, D-070): the `QUEST_PHASE`
## condition and the three quest effects that joined D-066's closed sets. No scene tree. The
## `QuestService` is real; what carries out a quest effect is the `quest_op` Callable, so the
## tests can also answer "what if the owner refuses".

const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"
const PILL_PATH := "res://data/items/item_bo_huyet_dan.tres"

const DLG := &"dlg_test_giver"
const GIVER := &"char_test_giver"
const OTHER := &"char_test_other"
const PLAYER := &"char_test_player"
const QUEST := &"quest_test_errand"
const WORD := &"know_vu_lang_hunting_ground"

var _knowledge: KnowledgeService = null
var _relationship: RelationshipService = null
var _config: RelationshipConfigData = null
var _quests: QuestService = null
var _ops: Array = []
var _op_answer: StringName = &""


func before_each() -> void:
	_config = load(CONFIG_PATH) as RelationshipConfigData
	_relationship = RelationshipService.new(RelationshipStore.new(_config), _config)
	_knowledge = KnowledgeService.new(load(KNOWLEDGE_PATH) as KnowledgeCatalogData,
		KnowledgeStore.new())
	_quests = QuestService.new(_quest_catalog(), QuestState.new(), _knowledge,
		RewardService.new(RewardLedger.new()), func(_item_id: StringName) -> int: return 0)
	_ops = []
	_op_answer = &""


func after_each() -> void:
	_quests = null
	_relationship = null
	_knowledge = null
	_config = null


## One quest: know the scout's word; given by and answered to GIVER.
func _quest_catalog(receiver: StringName = GIVER) -> QuestCatalogData:
	var objective := QuestObjectiveData.new()
	objective.id = &"learn"
	objective.kind = QuestObjectiveData.Kind.KNOW
	objective.target_id = WORD
	objective.text_key = &"QUEST_TEST_OBJ"
	var item := RewardItemData.new()
	item.item = load(PILL_PATH) as ItemData
	var reward := RewardData.new()
	var items: Array[RewardItemData] = [item]
	reward.items = items
	var quest := QuestData.new()
	quest.id = QUEST
	quest.title_key = &"T"
	quest.summary_key = &"S"
	quest.lead_key = &"L"
	quest.goal_key = &"G"
	quest.return_key = &"R"
	quest.giver_id = GIVER
	quest.receiver_id = receiver
	var objectives: Array[QuestObjectiveData] = [objective]
	quest.objectives = objectives
	quest.reward = reward
	var catalog := QuestCatalogData.new()
	var entries: Array[QuestData] = [quest]
	catalog.entries = entries
	return catalog


func _phase(phase: QuestService.Phase, negate: bool = false) -> DialogueConditionData:
	var condition := DialogueConditionData.new()
	condition.kind = DialogueConditionData.Kind.QUEST_PHASE
	condition.quest_id = QUEST
	condition.quest_phase = phase
	condition.negate = negate
	return condition


func _effect(kind: DialogueEffectData.Kind) -> DialogueEffectData:
	var effect := DialogueEffectData.new()
	effect.kind = kind
	effect.quest_id = QUEST
	return effect


func _choice(id: StringName, next: StringName, conditions: Array = [],
		effect: DialogueEffectData = null) -> DialogueChoiceData:
	var option := DialogueChoiceData.new()
	option.id = id
	option.text_key = StringName("DLG_TEST_%s" % String(id).to_upper())
	var typed: Array[DialogueConditionData] = []
	for condition: DialogueConditionData in conditions:
		typed.append(condition)
	option.conditions = typed
	option.effect = effect
	option.next_node_id = next
	return option


## hub: take (AVAILABLE) · answer (READY) · give back (ACTIVE) · leave.
func _dialogue(speaker: StringName = GIVER) -> DialogueData:
	var hub := DialogueNodeData.new()
	hub.id = &"hub"
	hub.text_key = &"DLG_TEST_HUB"
	var options: Array[DialogueChoiceData] = [
		_choice(&"take", &"after", [_phase(QuestService.Phase.AVAILABLE)],
			_effect(DialogueEffectData.Kind.QUEST_ACCEPT)),
		_choice(&"answer", &"after", [_phase(QuestService.Phase.READY)],
			_effect(DialogueEffectData.Kind.QUEST_TURN_IN)),
		_choice(&"back", &"after", [_phase(QuestService.Phase.ACTIVE)],
			_effect(DialogueEffectData.Kind.QUEST_ABANDON)),
		_choice(&"leave", &""),
	]
	hub.choices = options
	var after := DialogueNodeData.new()
	after.id = &"after"
	after.text_key = &"DLG_TEST_AFTER"
	after.next_node_id = &"hub"
	var dialogue := DialogueData.new()
	dialogue.id = DLG
	dialogue.speaker_id = speaker
	dialogue.start_node_id = &"hub"
	var nodes: Array[DialogueNodeData] = [hub, after]
	dialogue.nodes = nodes
	return dialogue


func _service(dialogue: DialogueData = null, quests: QuestService = null,
		with_quests: bool = true) -> DialogueService:
	var catalog := DialogueCatalogData.new()
	var entries: Array[DialogueData] = [dialogue if dialogue != null else _dialogue()]
	catalog.entries = entries
	return DialogueService.new(catalog, _knowledge, _relationship, _config,
		(quests if quests != null else _quests) if with_quests else null)


## The quest owner, as `QuestRuntime` would be: records what was asked and does it for real
## unless `_op_answer` says to refuse.
func _quest_op(kind: int, quest_id: StringName, speaker_id: StringName) -> StringName:
	_ops.append([kind, quest_id, speaker_id])
	if _op_answer != &"":
		return _op_answer
	var outcome: QuestOutcome = null
	if kind == DialogueEffectData.Kind.QUEST_ACCEPT:
		outcome = _quests.accept(quest_id, speaker_id)
	elif kind == DialogueEffectData.Kind.QUEST_ABANDON:
		outcome = _quests.abandon(quest_id, speaker_id)
	return &"" if outcome != null and outcome.ok else &"UI_TEST_REFUSED"


func _offered(service: DialogueService) -> Array[StringName]:
	var ids: Array[StringName] = []
	for option in service.eligible_choices(DLG, &"hub", PLAYER):
		ids.append(option.id)
	return ids


func _choose(service: DialogueService, choice_id: StringName,
		op: Callable = Callable()) -> DialogueOutcome:
	return service.choose(DLG, &"hub", choice_id, PLAYER, _knowledge.grant,
		op if op.is_valid() else _quest_op)


func _has_error(errors: Array[String], fragment: String) -> bool:
	for problem in errors:
		if problem.contains(fragment):
			return true
	return false


# === Data ==========================================================================

func test_the_new_kinds_reject_payloads_they_do_not_use() -> void:
	assert_eq(_dialogue().validation_errors(), [] as Array[String], "the good graph is valid")
	assert_eq(_service().content_errors(), [] as Array[String], "and names nothing unknown")
	var unnamed := _phase(QuestService.Phase.READY)
	unnamed.quest_id = &""
	assert_true(_has_error(unnamed.validation_errors(), "names no quest_id"), "no quest")
	var out_of_range := _phase(QuestService.Phase.READY)
	out_of_range.quest_phase = 9 as QuestService.Phase
	assert_true(_has_error(out_of_range.validation_errors(), "unknown phase"), "a bad phase")
	var mixed := _phase(QuestService.Phase.READY)
	mixed.knowledge_id = WORD
	assert_true(_has_error(mixed.validation_errors(), "payload it does not use"),
		"a quest condition carrying knowledge")
	var knows := DialogueConditionData.new()
	knows.kind = DialogueConditionData.Kind.KNOWS
	knows.knowledge_id = WORD
	knows.quest_id = QUEST
	assert_true(_has_error(knows.validation_errors(), "carries a quest_id"),
		"a knowledge condition carrying a quest")
	var no_quest := _effect(DialogueEffectData.Kind.QUEST_ACCEPT)
	no_quest.quest_id = &""
	assert_true(_has_error(no_quest.validation_errors(), "names no quest_id"), "an effect on none")
	var stuffed := _effect(DialogueEffectData.Kind.QUEST_TURN_IN)
	stuffed.delta = 5
	assert_true(_has_error(stuffed.validation_errors(), "payload it does not use"),
		"a quest effect carrying a delta")
	var shop := DialogueEffectData.new()
	shop.kind = DialogueEffectData.Kind.OPEN_SHOP
	shop.quest_id = QUEST
	assert_true(_has_error(shop.validation_errors(), "quest_id its kind does not use"),
		"a shop handoff carrying a quest")


func test_content_that_names_a_quest_is_checked_against_the_quest_owner() -> void:
	var no_owner := _service(null, null, false)
	var errors := no_owner.content_errors()
	assert_true(_has_error(errors, "asks about quest"),
		"with no quest owner a condition is an error")
	assert_true(_has_error(errors, "acts on quest"), "and so is an effect")
	var ghost := _dialogue()
	ghost.node(&"hub").choice(&"take").effect.quest_id = &"quest_nothing"
	assert_true(_has_error(_service(ghost).content_errors(), "acts on quest 'quest_nothing'"),
		"a quest nobody defines")
	var stranger := _dialogue(OTHER)
	var by_stranger := _service(stranger).content_errors()
	assert_true(_has_error(by_stranger, "is given by 'char_test_giver', not by 'char_test_other'"),
		"a quest is taken from (and given back to) its giver")
	assert_true(_has_error(by_stranger, "is answered to 'char_test_giver'"),
		"and answered to its receiver")
	var elsewhere := QuestService.new(_quest_catalog(OTHER), QuestState.new(), _knowledge,
		RewardService.new(RewardLedger.new()), func(_item_id: StringName) -> int: return 0)
	assert_true(_has_error(_service(null, elsewhere).content_errors(),
		"is answered to 'char_test_other'"), "a turn-in said by someone who is not the receiver")
	var eager := _dialogue()
	eager.node(&"hub").choice(&"answer").conditions.clear()
	assert_true(_has_error(_service(eager).content_errors(), "must require QUEST_PHASE READY"),
		"a turn-in that would be offered before it can succeed")
	var negated := _dialogue()
	negated.node(&"hub").choice(&"answer").conditions[0].negate = true
	assert_true(_has_error(_service(negated).content_errors(), "must require QUEST_PHASE READY"),
		"'not ready' is not 'ready'")
	for kind_name: Array in [[&"take", "offers"], [&"answer", "takes the answer to"],
			[&"back", "takes back"]]:
		var partial := _dialogue()
		partial.node(&"hub").choice(kind_name[0]).effect = null
		assert_true(_has_error(_service(partial).content_errors(),
			"no conversation %s it" % kind_name[1]),
			"a quest that nobody %s is unreachable content" % kind_name[1])


# === Conditions ====================================================================

func test_a_quest_condition_follows_the_quest_owner() -> void:
	var service := _service()
	assert_eq(_offered(service), [&"take", &"leave"] as Array[StringName], "on offer: take it")
	_quests.accept(QUEST, GIVER)
	assert_eq(_offered(service), [&"back", &"leave"] as Array[StringName],
		"under way: it can be given back, not taken again and not answered yet")
	_knowledge.grant(WORD, &"test")
	assert_eq(_offered(service), [&"answer", &"leave"] as Array[StringName],
		"ready (the Knowledge Core says so): it can be answered")
	var negated := _phase(QuestService.Phase.AVAILABLE, true)
	assert_true(service.condition_met(negated, GIVER, PLAYER), "'not on offer' is now true")
	assert_false(_service(null, null, false).condition_met(_phase(QuestService.Phase.AVAILABLE),
		GIVER, PLAYER), "with nobody to ask, a quest condition is never met")
	assert_false(_service(null, null, false).condition_met(negated, GIVER, PLAYER),
		"negated or not")


# === Effects =======================================================================

func test_a_quest_effect_is_carried_out_by_the_owner_with_who_said_it() -> void:
	var service := _service()
	var taken := _choose(service, &"take")
	assert_true(taken.ok, "accepted")
	assert_eq(_ops, [[DialogueEffectData.Kind.QUEST_ACCEPT, QUEST, GIVER]],
		"the owner was asked once, and told which speaker asked")
	assert_eq([taken.quest_id, taken.effect_kind, taken.next_node_id],
		[QUEST, DialogueEffectData.Kind.QUEST_ACCEPT, &"after"], "and the talk moves on")
	assert_eq(_quests.phase_of(QUEST), QuestService.Phase.ACTIVE, "the quest IS taken")
	var stale := _choose(service, &"take")
	assert_eq(stale.reason, DialogueService.REFUSE_CHOICE_GONE,
		"the same answer again is no longer offered")
	assert_eq(_ops.size(), 1, "and the owner is not asked a second time")
	assert_true(_choose(service, &"back").ok, "given back")
	assert_eq(_quests.phase_of(QUEST), QuestService.Phase.AVAILABLE, "on offer again")


func test_the_owners_refusal_refuses_the_answer_with_the_owners_reason() -> void:
	var service := _service()
	_op_answer = &"UI_QUEST_REWARD_NO_ROOM"
	var refused := _choose(service, &"take")
	assert_false(refused.ok, "refused")
	assert_eq(refused.reason, &"UI_QUEST_REWARD_NO_ROOM",
		"with the owner's own reason, not a generic one")
	assert_eq(refused.next_node_id, &"hub", "and the conversation stays where it was")
	assert_eq(refused.quest_id, &"", "no quest is reported as acted on")
	assert_eq(_quests.phase_of(QUEST), QuestService.Phase.AVAILABLE, "nothing was taken")


func test_a_quest_effect_with_nobody_to_carry_it_out_is_refused() -> void:
	var service := _service()
	var nobody := service.choose(DLG, &"hub", &"take", PLAYER, _knowledge.grant)
	assert_false(nobody.ok, "no quest owner was handed over")
	assert_eq(nobody.reason, DialogueService.REFUSE_EFFECT_FAILED, "so the effect fails")
	assert_eq(_quests.phase_of(QUEST), QuestService.Phase.AVAILABLE, "and nothing changed")

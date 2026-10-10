extends TestCase
## Unit tests for the Phase-18 dialogue DATA and DOMAIN: the six `Dialogue*Data` resources and
## `DialogueService`. No scene tree, no node, no autoload — a conversation's rules are plain
## objects asking the real `KnowledgeService` and the real `RelationshipService` (D-066).

const ConditionScript := preload("res://src/data/dialogue/dialogue_condition_data.gd")
const EffectScript := preload("res://src/data/dialogue/dialogue_effect_data.gd")
const ChoiceScript := preload("res://src/data/dialogue/dialogue_choice_data.gd")
const NodeScript := preload("res://src/data/dialogue/dialogue_node_data.gd")
const DialogueScript := preload("res://src/data/dialogue/dialogue_data.gd")
const CatalogScript := preload("res://src/data/dialogue/dialogue_catalog_data.gd")
const ServiceScript := preload("res://src/domain/dialogue/dialogue_service.gd")

const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"

const DLG := &"dlg_test_keeper"
const SPEAKER := &"char_test_keeper"
const PLAYER := &"char_test_player"
const STELE := &"know_lac_ha_stele_record"
const PRECEPT := &"know_thanh_dai_precept"

var _knowledge: KnowledgeService = null
var _relationship: RelationshipService = null
var _config: RelationshipConfigData = null
var _changes: Array = []


func before_each() -> void:
	_config = load(CONFIG_PATH) as RelationshipConfigData
	_relationship = RelationshipService.new(RelationshipStore.new(_config), _config)
	_knowledge = KnowledgeService.new(load(KNOWLEDGE_PATH) as KnowledgeCatalogData,
		KnowledgeStore.new())
	_changes = []
	_relationship.relationship_changed.connect(_record_change)


func after_each() -> void:
	# The service holds this test's method; drop it so nothing pins the instance (L-019).
	if _relationship != null \
			and _relationship.relationship_changed.is_connected(_record_change):
		_relationship.relationship_changed.disconnect(_record_change)
	_relationship = null
	_knowledge = null
	_config = null


func _record_change(edge_id: StringName, dimension: StringName, old_value: int,
		new_value: int, cause: StringName) -> void:
	_changes.append([edge_id, dimension, old_value, new_value, cause])


# --- Builders: a known-GOOD graph; each negative case changes exactly one thing ----------

func _knows(knowledge_id: StringName, negate: bool = false) -> DialogueConditionData:
	var condition: DialogueConditionData = ConditionScript.new()
	condition.kind = DialogueConditionData.Kind.KNOWS
	condition.knowledge_id = knowledge_id
	condition.negate = negate
	return condition


func _regard(dimension: StringName, value: int, negate: bool = false) -> DialogueConditionData:
	var condition: DialogueConditionData = ConditionScript.new()
	condition.kind = DialogueConditionData.Kind.RELATIONSHIP_AT_LEAST
	condition.dimension = dimension
	condition.value = value
	condition.negate = negate
	return condition


func _delta(dimension: StringName, delta: int) -> DialogueEffectData:
	var effect: DialogueEffectData = EffectScript.new()
	effect.kind = DialogueEffectData.Kind.RELATIONSHIP_DELTA
	effect.dimension = dimension
	effect.delta = delta
	return effect


func _grant(knowledge_id: StringName) -> DialogueEffectData:
	var effect: DialogueEffectData = EffectScript.new()
	effect.kind = DialogueEffectData.Kind.GRANT_KNOWLEDGE
	effect.knowledge_id = knowledge_id
	return effect


func _open_shop() -> DialogueEffectData:
	var effect: DialogueEffectData = EffectScript.new()
	effect.kind = DialogueEffectData.Kind.OPEN_SHOP
	return effect


func _choice(id: StringName, next: StringName = &"", conditions: Array = [],
		effect: DialogueEffectData = null) -> DialogueChoiceData:
	var option: DialogueChoiceData = ChoiceScript.new()
	option.id = id
	option.text_key = &"DLG_TEST_CHOICE"
	var typed: Array[DialogueConditionData] = []
	for condition: DialogueConditionData in conditions:
		typed.append(condition)
	option.conditions = typed
	option.effect = effect
	option.next_node_id = next
	return option


func _node(id: StringName, choices: Array = [], next: StringName = &"") -> DialogueNodeData:
	var line: DialogueNodeData = NodeScript.new()
	line.id = id
	line.text_key = &"DLG_TEST_LINE"
	var typed: Array[DialogueChoiceData] = []
	for option: DialogueChoiceData in choices:
		typed.append(option)
	line.choices = typed
	line.next_node_id = next
	return line


## greet --continue--> hub { praise (+10 affinity while below 10) -> thanks, insult (-10 while
## at least -5) -> hub, told (needs the stele record) -> hub, learn (grants the precept) -> hub,
## trade (opens the shop, ends), leave (ends) };  thanks --continue--> hub.
func _dialogue(id: StringName = DLG, speaker: StringName = SPEAKER) -> DialogueData:
	var dialogue: DialogueData = DialogueScript.new()
	dialogue.id = id
	dialogue.speaker_id = speaker
	dialogue.start_node_id = &"greet"
	var nodes: Array[DialogueNodeData] = [
		_node(&"greet", [], &"hub"),
		_node(&"hub", [
			_choice(&"praise", &"thanks", [_regard(&"affinity", 10, true)],
				_delta(&"affinity", 10)),
			_choice(&"insult", &"hub", [_regard(&"affinity", -5)], _delta(&"affinity", -10)),
			_choice(&"told", &"hub", [_knows(STELE)]),
			_choice(&"learn", &"hub", [], _grant(PRECEPT)),
			_choice(&"trade", &"", [], _open_shop()),
			_choice(&"leave"),
		]),
		_node(&"thanks", [], &"hub"),
	]
	dialogue.nodes = nodes
	return dialogue


func _catalog(dialogues: Array = []) -> DialogueCatalogData:
	var catalog: DialogueCatalogData = CatalogScript.new()
	var typed: Array[DialogueData] = []
	if dialogues.is_empty():
		typed.append(_dialogue())
	for dialogue: DialogueData in dialogues:
		typed.append(dialogue)
	catalog.entries = typed
	return catalog


func _service(catalog: DialogueCatalogData = null) -> DialogueService:
	return ServiceScript.new(catalog if catalog != null else _catalog(), _knowledge,
		_relationship, _config)


func _offered(service: DialogueService, node_id: StringName = &"hub") -> Array[StringName]:
	var ids: Array[StringName] = []
	for option in service.eligible_choices(DLG, node_id, PLAYER):
		ids.append(option.id)
	return ids


func _choose(service: DialogueService, choice_id: StringName,
		node_id: StringName = &"hub") -> DialogueOutcome:
	return service.choose(DLG, node_id, choice_id, PLAYER, _knowledge.grant)


func _has_error(errors: Array[String], fragment: String) -> bool:
	for problem in errors:
		if problem.contains(fragment):
			return true
	return false


func _edge() -> RelationshipEdge:
	return _relationship.get_store().find_between(
		RelationshipEndpoint.for_character(SPEAKER),
		RelationshipEndpoint.for_character(PLAYER), true)


# --- 1/2. The content boundary -------------------------------------------------

func test_a_valid_graph_is_accepted_and_the_service_is_ready() -> void:
	var catalog := _catalog()
	assert_eq(catalog.validation_errors(), [] as Array[String], "the known-good graph")
	var service := _service(catalog)
	assert_true(service.is_ready(), "a valid catalog makes a ready service")
	assert_eq(service.content_errors(), [] as Array[String],
		"every id and dimension it names exists in its owner")
	assert_eq(catalog.dialogue_of_speaker(SPEAKER).id, DLG, "found by who speaks it")
	assert_null(catalog.dialogue_of_speaker(&"char_nobody"), "nobody authored, nothing found")


func test_structural_defects_are_each_named() -> void:
	var missing_start := _dialogue()
	missing_start.start_node_id = &"nowhere"
	assert_true(_has_error(missing_start.validation_errors(), "start_node_id 'nowhere'"),
		"a start node that is not in the dialogue")

	var no_start := _dialogue()
	no_start.start_node_id = &""
	assert_true(_has_error(no_start.validation_errors(), "start_node_id is empty"), "no start")

	var dangling := _dialogue()
	dangling.node(&"hub").choice(&"told").next_node_id = &"gone"
	assert_true(_has_error(dangling.validation_errors(), "leads to 'gone'"), "a dangling choice")

	var dangling_line := _dialogue()
	dangling_line.node(&"thanks").next_node_id = &"gone"
	assert_true(_has_error(dangling_line.validation_errors(), "continues to 'gone'"),
		"a dangling continue")

	var twin_node := _dialogue()
	twin_node.nodes.append(_node(&"hub", [], &"greet"))
	assert_true(_has_error(twin_node.validation_errors(), "duplicate node id 'hub'"),
		"two nodes with one id")

	var twin_choice := _dialogue()
	twin_choice.node(&"hub").choices.append(_choice(&"leave"))
	assert_true(_has_error(twin_choice.validation_errors(), "duplicate choice id 'leave'"),
		"two choices with one id")

	var no_speaker := _dialogue()
	no_speaker.speaker_id = &""
	assert_true(_has_error(no_speaker.validation_errors(), "speaker_id is empty"), "no speaker")

	var bad_id := _dialogue(&"talk_keeper")
	assert_true(_has_error(bad_id.validation_errors(), "dlg_ prefix"), "the id prefix")

	var no_text := _dialogue()
	no_text.node(&"greet").text_key = &""
	assert_true(_has_error(no_text.validation_errors(), "text_key is empty"), "a line with no key")

	var no_choice_text := _dialogue()
	no_choice_text.node(&"hub").choice(&"leave").text_key = &""
	assert_true(_has_error(no_choice_text.validation_errors(), "choice 'leave': text_key"),
		"an answer with no key")

	var orphan := _dialogue()
	orphan.nodes.append(_node(&"island"))
	assert_true(_has_error(orphan.validation_errors(), "'island' cannot be reached"),
		"a node nothing leads to")

	var ambiguous := _dialogue()
	ambiguous.node(&"hub").next_node_id = &"greet"
	assert_true(_has_error(ambiguous.validation_errors(), "ambiguous"),
		"choices and a continue target at once")

	var trapped := _dialogue()
	trapped.node(&"hub").choices = [trapped.node(&"hub").choice(&"told")] \
		as Array[DialogueChoiceData]
	assert_true(_has_error(trapped.validation_errors(), "every choice is conditional"),
		"a line that could offer nothing")

	var twin_dialogue := _catalog([_dialogue(), _dialogue()])
	assert_true(_has_error(twin_dialogue.validation_errors(), "duplicate dialogue id"),
		"two dialogues with one id")
	var two_voices := _catalog([_dialogue(), _dialogue(&"dlg_test_other")])
	assert_true(_has_error(two_voices.validation_errors(), "speaks two dialogues"),
		"one speaker, two conversations")
	assert_true(_has_error((CatalogScript.new() as DialogueCatalogData).validation_errors(),
		"empty"), "an empty catalog")


func test_unsupported_condition_and_effect_payloads_are_rejected() -> void:
	var unknown_condition := _knows(STELE)
	unknown_condition.kind = 99 as DialogueConditionData.Kind
	assert_true(_has_error(unknown_condition.validation_errors(), "unknown condition kind"),
		"a condition kind outside the closed set")
	assert_true(_has_error(_knows(&"").validation_errors(), "no knowledge_id"), "KNOWS nothing")
	assert_true(_has_error(_regard(&"", 5).validation_errors(), "no dimension"),
		"a regard condition on no dimension")
	var mixed := _knows(STELE)
	mixed.dimension = &"affinity"
	assert_true(_has_error(mixed.validation_errors(), "relationship payload"),
		"a KNOWS condition carrying a dimension")

	var unknown_effect := _open_shop()
	unknown_effect.kind = 99 as DialogueEffectData.Kind
	assert_true(_has_error(unknown_effect.validation_errors(), "unknown effect kind"),
		"an effect kind outside the closed set")
	assert_true(_has_error(_delta(&"affinity", 0).validation_errors(), "changes nothing"),
		"a zero delta")
	assert_true(_has_error(_delta(&"", 5).validation_errors(), "no dimension"), "no dimension")
	assert_true(_has_error(_delta(&"affinity", 500).validation_errors(), "ceiling"),
		"a delta past the ceiling")
	assert_true(_has_error(_grant(&"").validation_errors(), "no knowledge_id"), "grant nothing")
	var loaded_shop := _open_shop()
	loaded_shop.delta = 5
	assert_true(_has_error(loaded_shop.validation_errors(), "payload it does not use"),
		"OPEN_SHOP with a payload")

	var shop_then_more := _choice(&"trade", &"hub", [], _open_shop())
	assert_true(_has_error(shop_then_more.validation_errors(), "hands the conversation over"),
		"a shop handoff that claims to continue")
	var unbounded := _choice(&"praise", &"hub", [], _delta(&"affinity", 10))
	assert_true(_has_error(unbounded.validation_errors(), "no condition that stops it"),
		"regard that a repeated line could walk to its bound")
	var wrong_way := _choice(&"praise", &"hub", [_regard(&"affinity", 10)],
		_delta(&"affinity", 10))
	assert_true(_has_error(wrong_way.validation_errors(), "no condition that stops it"),
		"a raise gated on AT LEAST never stops itself")
	var other_dimension := _choice(&"praise", &"hub", [_regard(&"trust", 10, true)],
		_delta(&"affinity", 10))
	assert_true(_has_error(other_dimension.validation_errors(), "no condition that stops it"),
		"a bound on a different dimension bounds nothing")

	var bad_mood := _node(&"greet")
	bad_mood.mood = 99 as DialogueNodeData.Mood
	assert_true(_has_error(bad_mood.validation_errors(), "unknown mood"), "a mood outside the set")
	var bad_gesture := _node(&"greet")
	bad_gesture.gesture = &"backflip"
	assert_true(_has_error(bad_gesture.validation_errors(), "unknown gesture"), "a gesture")


func test_a_chain_of_lines_that_never_ends_is_rejected() -> void:
	var looping := _dialogue()
	looping.node(&"greet").next_node_id = &"thanks"
	looping.node(&"thanks").next_node_id = &"greet"
	assert_true(_has_error(looping.validation_errors(), "never reaches an answer"),
		"greet -> thanks -> greet with no choice anywhere on the way")
	# A cycle THROUGH a node with choices is a conversation, not a trap.
	assert_eq(_dialogue().validation_errors(), [] as Array[String], "hub <-> thanks is fine")


func test_what_other_owners_cannot_supply_is_reported_by_the_service() -> void:
	var unknown_knowledge := _dialogue()
	unknown_knowledge.node(&"hub").choice(&"told").conditions[0].knowledge_id = &"know_nothing"
	assert_true(_has_error(_service(_catalog([unknown_knowledge])).content_errors(),
		"requires knowledge 'know_nothing'"), "a condition on knowledge nobody defines")

	var unknown_grant := _dialogue()
	unknown_grant.node(&"hub").choice(&"learn").effect.knowledge_id = &"know_nothing"
	assert_true(_has_error(_service(_catalog([unknown_grant])).content_errors(),
		"grants knowledge 'know_nothing'"), "a grant of knowledge nobody defines")

	var unknown_dimension := _dialogue()
	var praise := unknown_dimension.node(&"hub").choice(&"praise")
	praise.conditions[0].dimension = &"charm"
	praise.effect.dimension = &"charm"
	var errors := _service(_catalog([unknown_dimension])).content_errors()
	assert_true(_has_error(errors, "asks about 'charm'"), "a condition on an unknown dimension")
	assert_true(_has_error(errors, "moves 'charm'"), "an effect on an unknown dimension")

	var out_of_range := _dialogue()
	out_of_range.node(&"hub").choice(&"praise").conditions[0].value = 500
	assert_true(_has_error(_service(_catalog([out_of_range])).content_errors(),
		"outside [-100, 100]"), "a threshold the dimension can never reach")

	var service := _service()
	assert_true(_has_error(service.content_errors(func(_key: StringName) -> bool: return false),
		"has no translation"), "a missing translation is a content error")
	assert_true(_has_error(service.content_errors(Callable(),
		func(_id: StringName) -> bool: return false), "who keeps none"),
		"a shop handoff for someone who keeps no shop")

	var invalid := _dialogue()
	invalid.start_node_id = &"nowhere"
	assert_false(_service(_catalog([invalid])).is_ready(),
		"a structurally invalid catalog is refused outright")


# --- 3/4. Eligibility ------------------------------------------------------------

func test_the_offered_choices_follow_the_owners_state() -> void:
	var service := _service()
	assert_eq(_offered(service), [&"praise", &"insult", &"learn", &"trade", &"leave"]
		as Array[StringName], "a stranger who has read nothing is not offered 'told'")
	_knowledge.grant(STELE, &"test")
	assert_true(_offered(service).has(&"told"), "reading the stele opens the line about it")
	# Regard is read from the graph: move it there, and the offers follow.
	var edge := _relationship.create_edge(&"rel_test", RelationshipEndpoint.for_character(SPEAKER),
		RelationshipEndpoint.for_character(PLAYER))
	_relationship.set_dimension(edge.id, &"affinity", 10)
	assert_false(_offered(service).has(&"praise"), "at 10 the 'below 10' line is gone")
	_relationship.set_dimension(edge.id, &"affinity", -6)
	assert_false(_offered(service).has(&"insult"), "below -5 the 'at least -5' line is gone")
	assert_true(_offered(service).has(&"praise"), "and the 'below 10' line is back")


func test_a_negated_knowledge_condition_reads_the_other_way() -> void:
	var dialogue := _dialogue()
	dialogue.node(&"hub").choice(&"told").conditions[0].negate = true
	var service := _service(_catalog([dialogue]))
	assert_true(_offered(service).has(&"told"), "offered while the player does NOT know it")
	_knowledge.grant(STELE, &"test")
	assert_false(_offered(service).has(&"told"), "and withdrawn once they do")


func test_a_choice_that_is_not_offered_is_refused_and_changes_nothing() -> void:
	var service := _service()
	var before := _relationship.get_store().edge_count()
	var hidden := _choose(service, &"told")
	assert_false(hidden.ok, "an ineligible choice is refused")
	assert_eq(hidden.reason, DialogueService.REFUSE_CHOICE_GONE, "with the 'gone' reason")
	assert_eq(hidden.next_node_id, &"hub", "and the conversation stays where it was")
	assert_eq(_choose(service, &"nonsense").reason, DialogueService.REFUSE_CHOICE_GONE,
		"an id the node does not have")
	assert_eq(_choose(service, &"praise", &"greet").reason, DialogueService.REFUSE_CHOICE_GONE,
		"a real choice submitted against a different node (a stale view)")
	assert_eq(service.choose(&"dlg_nothing", &"hub", &"leave", PLAYER, _knowledge.grant).reason,
		DialogueService.REFUSE_NOT_READY, "an unknown dialogue")
	assert_eq(service.choose(DLG, &"hub", &"leave", &"", _knowledge.grant).reason,
		DialogueService.REFUSE_NOT_READY, "nobody listening")
	assert_eq(_relationship.get_store().edge_count(), before, "no edge was made")
	assert_eq(_knowledge.store().known_ids().size(), 0, "nothing was learned")
	assert_eq(_changes.size(), 0, "nothing was announced")


func test_a_choice_that_stopped_being_eligible_is_refused_on_submit() -> void:
	var service := _service()
	assert_true(_offered(service).has(&"praise"), "offered when the list was built")
	assert_true(_choose(service, &"praise").ok, "taken once")
	var stale := _choose(service, &"praise")
	assert_false(stale.ok, "the same answer from the stale list is refused")
	assert_eq(service.regard(SPEAKER, PLAYER, &"affinity"), 10, "and regard moved exactly once")
	assert_eq(_changes.size(), 1, "one change announced, not two")


# --- 5. The graph ----------------------------------------------------------------

func test_lines_and_choices_follow_the_authored_graph() -> void:
	var service := _service()
	var first := service.advance(DLG, &"greet")
	assert_true(first.ok and not first.ended, "a line without choices continues")
	assert_eq(first.next_node_id, &"hub", "to its authored next node")
	assert_eq(first.effect_kind, DialogueOutcome.NO_EFFECT, "continuing changes nothing")
	assert_false(service.advance(DLG, &"hub").ok, "a line WITH choices cannot be skipped")
	var told_first := _choose(service, &"praise")
	assert_eq(told_first.next_node_id, &"thanks", "a choice leads to its authored node")
	assert_false(told_first.ended, "which is not the end")
	var leave := _choose(service, &"leave")
	assert_true(leave.ok and leave.ended, "a choice with no next node ends the conversation")
	assert_eq(leave.next_node_id, &"", "nowhere to go")
	var last_line := _dialogue()
	last_line.node(&"thanks").next_node_id = &""
	assert_true(_service(_catalog([last_line])).advance(DLG, &"thanks").ended,
		"a line with no next node ends it too")
	assert_false(service.advance(DLG, &"nowhere").ok, "an unknown node moves nothing")


# --- 6. Regard goes through RelationshipService ------------------------------------

func test_a_regard_choice_makes_one_edge_and_moves_it_through_the_service() -> void:
	var service := _service()
	assert_null(_edge(), "strangers: no edge yet")
	assert_eq(service.regard(SPEAKER, PLAYER, &"affinity"), 0, "a stranger reads the default")
	var outcome := _choose(service, &"praise")
	assert_true(outcome.ok, "the choice is taken")
	assert_eq(outcome.effect_kind, DialogueEffectData.Kind.RELATIONSHIP_DELTA, "its kind")
	assert_eq([outcome.dimension, outcome.old_value, outcome.new_value],
		[&"affinity", 0, 10], "the outcome reports the move")
	var edge := _edge()
	assert_not_null(edge, "the speaker now has an edge to the player")
	assert_eq(_relationship.get_store().edge_count(), 1, "exactly one")
	assert_false(edge.symmetric, "it is the SPEAKER's regard: directed")
	assert_eq(edge.from_ref.id, SPEAKER, "from the speaker")
	assert_eq(edge.to_ref.id, PLAYER, "to the player")
	assert_eq(edge.relationship_type, DialogueService.EDGE_TYPE, "they have now spoken")
	assert_eq(_changes, [[edge.id, &"affinity", 0, 10, DLG]],
		"announced once by the service, caused by the dialogue")
	assert_eq(edge.history_size(), 1, "and written to the edge's history once")
	# Lower it: the SAME edge, never a second one.
	var lowered := _choose(service, &"insult")
	assert_eq([lowered.old_value, lowered.new_value], [10, 0], "the insult takes it back")
	assert_eq(_relationship.get_store().edge_count(), 1, "still one edge")
	assert_eq(edge.history_size(), 2, "two entries on it")


func test_an_existing_edge_is_reused_whichever_way_it_was_made() -> void:
	# The pair already share a SYMMETRIC edge (made by something else): regard reads and moves
	# that one; a second, directed edge beside it would be two answers to one question.
	var shared := _relationship.create_edge(&"rel_shared",
		RelationshipEndpoint.for_character(PLAYER), RelationshipEndpoint.for_character(SPEAKER),
		&"ALLY", true)
	var service := _service()
	assert_true(_choose(service, &"praise").ok, "taken")
	assert_eq(_relationship.get_store().edge_count(), 1, "no second edge")
	assert_eq(shared.get_dimension(&"affinity", 0), 10, "the shared edge moved")
	assert_eq(shared.relationship_type, &"ALLY", "and kept its own type")


func test_regard_clamps_at_the_configured_bound_without_noise() -> void:
	var dialogue := _dialogue()
	var praise := dialogue.node(&"hub").choice(&"praise")
	praise.conditions[0].value = 100  # offered right up to the ceiling
	praise.effect.delta = 40
	var service := _service(_catalog([dialogue]))
	for i in 3:
		_choose(service, &"praise")
	assert_eq(service.regard(SPEAKER, PLAYER, &"affinity"), 100, "40 + 40 + 40 clamps at 100")
	assert_eq(_changes.size(), 3, "three real changes: 40, 80, 100")
	assert_eq(_changes[2][3], 100, "the last one stops at the bound")
	assert_false(_choose(service, &"praise").ok, "and at the bound the line is gone")
	assert_eq(_changes.size(), 3, "so nothing more is announced")


func test_a_move_that_would_move_nothing_makes_no_edge() -> void:
	# `fear` is 0..100 and defaults to 0: lowering a stranger's fear cannot change anything.
	var dialogue := _dialogue()
	dialogue.node(&"hub").choices.append(_choice(&"soothe", &"hub", [_regard(&"fear", 0)],
		_delta(&"fear", -10)))
	var service := _service(_catalog([dialogue]))
	var outcome := _choose(service, &"soothe")
	assert_true(outcome.ok, "the line is still said")
	assert_eq([outcome.old_value, outcome.new_value], [0, 0], "nothing moved")
	assert_null(_edge(), "and no empty edge was left in the graph")
	assert_eq(_changes.size(), 0, "nothing announced")


func test_an_unknown_dimension_is_refused_with_no_partial_change() -> void:
	# Bypass the content boundary on purpose (a catalog validated against another config).
	var dialogue := _dialogue()
	var praise := dialogue.node(&"hub").choice(&"praise")
	praise.conditions.clear()
	praise.effect.dimension = &"charm"
	var catalog := _catalog([dialogue])
	var service: DialogueService = ServiceScript.new()
	service._catalog = catalog
	service._knowledge = _knowledge
	service._relationship = _relationship
	service._config = _config
	var outcome := _choose(service, &"praise")
	assert_false(outcome.ok, "refused")
	assert_eq(outcome.reason, DialogueService.REFUSE_EFFECT_FAILED, "by the effect's owner")
	assert_eq(outcome.next_node_id, &"hub", "the conversation did not move")
	assert_null(_edge(), "no edge was made for it")
	assert_eq(_changes.size(), 0, "nothing announced")


# --- 7. Knowledge goes through the Knowledge Core ------------------------------------

func test_a_knowledge_choice_grants_through_the_core_exactly_once() -> void:
	var service := _service()
	assert_false(_knowledge.knows(PRECEPT), "not known before")
	var first := _choose(service, &"learn")
	assert_true(first.ok, "taken")
	assert_eq(first.effect_kind, DialogueEffectData.Kind.GRANT_KNOWLEDGE, "its kind")
	assert_eq([first.knowledge_id, first.knowledge_result], [PRECEPT, KnowledgeService.GRANTED],
		"the Core's own answer is reported")
	assert_true(_knowledge.knows(PRECEPT), "the Core holds it")
	assert_eq(_knowledge.store().known_ids(), [PRECEPT] as Array[StringName], "once")
	var second := _choose(service, &"learn")
	assert_true(second.ok, "asking again is still a line that can be said")
	assert_eq(second.knowledge_result, KnowledgeService.ALREADY_KNOWN, "and teaches nothing new")
	assert_eq(_knowledge.store().known_ids().size(), 1, "still held once")
	# Dialogue keeps no copy: nothing on the service or the outcome is a knowledge store.
	for property in service.get_property_list():
		assert_false(String(property["name"]).contains("known"),
			"the dialogue service holds no knowledge of its own")


func test_a_grant_with_no_path_to_the_core_is_refused() -> void:
	var service := _service()
	var outcome := service.choose(DLG, &"hub", &"learn", PLAYER, Callable())
	assert_false(outcome.ok, "no grant path, no choice")
	assert_eq(outcome.reason, DialogueService.REFUSE_EFFECT_FAILED, "refused by the effect")
	assert_false(_knowledge.knows(PRECEPT), "and nothing was learned behind the Core's back")


# --- 8. The shop handoff is an intent --------------------------------------------------

func test_a_shop_choice_returns_an_action_and_mutates_nothing() -> void:
	var service := _service()
	var outcome := _choose(service, &"trade")
	assert_true(outcome.ok and outcome.ended, "the conversation ends")
	assert_eq(outcome.action, DialogueService.ACTION_OPEN_SHOP, "with an explicit action")
	assert_eq(outcome.effect_kind, DialogueEffectData.Kind.OPEN_SHOP, "of the shop kind")
	assert_eq(_relationship.get_store().edge_count(), 0, "no edge")
	assert_eq(_knowledge.store().known_ids().size(), 0, "no knowledge")
	assert_eq(_choose(service, &"leave").action, &"", "an ordinary choice asks for nothing")


# --- 9. Repetition ---------------------------------------------------------------------

func test_two_services_over_one_world_do_not_double_an_effect() -> void:
	# A session ended and re-entered builds a new service over the SAME owners' state.
	var first := _service()
	assert_true(_choose(first, &"praise").ok, "said in the first session")
	var second := _service()
	assert_false(_choose(second, &"praise").ok,
		"the re-entered session reads the graph, which already moved")
	assert_eq(second.regard(SPEAKER, PLAYER, &"affinity"), 10, "moved once")
	assert_eq(_relationship.get_store().edge_count(), 1, "one edge")
	assert_eq(_changes.size(), 1, "one announcement, although two services exist")

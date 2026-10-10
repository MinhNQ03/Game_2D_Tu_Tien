extends RefCounted
class_name DialogueService
## DialogueService — Aetheria domain (the rules of a conversation, Phase 18, D-066).
##
## Node-free and scene-free. Given the authored catalog and the two systems a dialogue may ask
## and change, it answers: which answers are OFFERED at a node, and what SUBMITTING one comes
## to. It keeps no cursor and no state of its own — where a conversation is belongs to the
## runtime, and what a choice changes belongs to its owner:
##
##   * regard moves through `RelationshipService` (the only relationship mutation path), on the
##     speaker → listener edge, which is created through the service only when absent;
##   * knowledge is granted through the `grant` Callable the caller supplies — the Knowledge
##     Core's own grant path (`KnowledgeRuntime.grant` in a session, so it is announced);
##   * opening a shop is returned as an ACTION for the gameplay layer: this class cannot and
##     does not open anything.
##
## A choice is authorised TWICE: `eligible_choices` decides what is shown, and `choose` asks
## the same conditions again before it changes anything, so a stale list cannot commit a
## choice the state no longer allows. One effect per choice: there is no half-applied choice.

const REFUSE_NOT_READY := &"UI_DIALOGUE_UNAVAILABLE"
## The choice is not (or no longer) one the current line offers.
const REFUSE_CHOICE_GONE := &"UI_DIALOGUE_CHOICE_GONE"
## The owner of the effect refused it; nothing changed.
const REFUSE_EFFECT_FAILED := &"UI_DIALOGUE_EFFECT_FAILED"

const ACTION_OPEN_SHOP := &"open_shop"

## The edge a conversation creates is `RegardRules`': the two have now dealt.
const EDGE_TYPE := RegardRules.EDGE_TYPE
const EDGE_ID_FORMAT := RegardRules.EDGE_ID_FORMAT

var _catalog: DialogueCatalogData = null
var _knowledge: KnowledgeService = null
var _relationship: RelationshipService = null
var _config: RelationshipConfigData = null


func _init(catalog: DialogueCatalogData = null, knowledge: KnowledgeService = null,
		relationship: RelationshipService = null, config: RelationshipConfigData = null) -> void:
	if catalog == null or knowledge == null or not knowledge.is_ready() \
			or relationship == null or config == null:
		return
	if not catalog.is_valid():
		push_error("[dialogue] refusing an invalid catalog: %s" % str(catalog.validation_errors()))
		return
	_catalog = catalog
	_knowledge = knowledge
	_relationship = relationship
	_config = config


func is_ready() -> bool:
	return _catalog != null


func catalog() -> DialogueCatalogData:
	return _catalog


## What the catalog asks of OTHER systems that they cannot give: a knowledge id the Core does
## not define, a dimension the graph does not have, a threshold outside its range. Structural
## errors are `DialogueCatalogData.validation_errors`; this is the cross-owner half.
## `has_text(key) -> bool`, `keeps_shop(character_id) -> bool` and
## `resolve_character(instance_id) -> CharacterState` are optional seams for the three owners
## the domain cannot see (localization, the shop catalog, the session's character registry —
## the same resolver `SectService` and `FactionService` take); an invalid Callable skips that
## check. A SPEAKER must resolve to a registered character: a conversation is found by who is
## addressed, so one spoken by nobody could never be opened and would never be noticed. Whether
## that character has a body in the CURRENT map is not asked here — that is `NpcRuntime`'s, at
## the moment of the talk.
func content_errors(has_text: Callable = Callable(), keeps_shop: Callable = Callable(),
		resolve_character: Callable = Callable()) -> Array[String]:
	var errors: Array[String] = []
	if not is_ready():
		errors.append("the dialogue service is not ready")
		return errors
	for dialogue in _catalog.entries:
		if resolve_character.is_valid() \
				and not (resolve_character.call(dialogue.speaker_id) is CharacterState):
			errors.append("%s: is spoken by '%s', who is not a registered character"
				% [dialogue.id, dialogue.speaker_id])
		if has_text.is_valid():
			for key in dialogue.text_keys():
				if not bool(has_text.call(key)):
					errors.append("%s: text '%s' has no translation in every language"
						% [dialogue.id, key])
		for line in dialogue.nodes:
			for option in line.choices:
				var where := "%s/%s" % [dialogue.id, option.id]
				for condition in option.conditions:
					errors.append_array(_condition_errors(where, condition))
				errors.append_array(_effect_errors(where, dialogue, option.effect, keeps_shop))
	return errors


func _condition_errors(where: String, condition: DialogueConditionData) -> Array[String]:
	var errors: Array[String] = []
	match condition.kind:
		DialogueConditionData.Kind.KNOWS:
			if not _knowledge.catalog().has(condition.knowledge_id):
				errors.append("%s: requires knowledge '%s', which the catalog does not define"
					% [where, condition.knowledge_id])
		DialogueConditionData.Kind.RELATIONSHIP_AT_LEAST:
			if not _config.has_dimension(condition.dimension):
				errors.append("%s: asks about '%s', which the relationship graph does not define"
					% [where, condition.dimension])
			elif condition.value < _config.get_min(condition.dimension) \
					or condition.value > _config.get_max(condition.dimension):
				errors.append("%s: threshold %d on '%s' is outside [%d, %d]" % [where,
					condition.value, condition.dimension, _config.get_min(condition.dimension),
					_config.get_max(condition.dimension)])
	return errors


func _effect_errors(where: String, dialogue: DialogueData, effect: DialogueEffectData,
		keeps_shop: Callable) -> Array[String]:
	var errors: Array[String] = []
	if effect == null:
		return errors
	match effect.kind:
		DialogueEffectData.Kind.RELATIONSHIP_DELTA:
			if not _config.has_dimension(effect.dimension):
				errors.append("%s: moves '%s', which the relationship graph does not define"
					% [where, effect.dimension])
		DialogueEffectData.Kind.GRANT_KNOWLEDGE:
			if not _knowledge.catalog().has(effect.knowledge_id):
				errors.append("%s: grants knowledge '%s', which the catalog does not define"
					% [where, effect.knowledge_id])
		DialogueEffectData.Kind.OPEN_SHOP:
			if keeps_shop.is_valid() and not bool(keeps_shop.call(dialogue.speaker_id)):
				errors.append("%s: opens the shop of '%s', who keeps none"
					% [where, dialogue.speaker_id])
	return errors


# --- Reading -------------------------------------------------------------------

## How `speaker_id` regards `listener_id` on `dimension`, read from the graph: the speaker's
## directed edge to them, or the pair's symmetric one. No edge is the dimension's default.
func regard(speaker_id: StringName, listener_id: StringName, dimension: StringName) -> int:
	if not is_ready():
		return 0
	return RegardRules.read(_relationship, _config, speaker_id, listener_id, dimension)


func condition_met(condition: DialogueConditionData, speaker_id: StringName,
		listener_id: StringName) -> bool:
	if not is_ready() or condition == null:
		return false
	var met := false
	match condition.kind:
		DialogueConditionData.Kind.KNOWS:
			met = _knowledge.knows(condition.knowledge_id)
		DialogueConditionData.Kind.RELATIONSHIP_AT_LEAST:
			met = regard(speaker_id, listener_id, condition.dimension) >= condition.value
		_:
			return false  # an unknown kind is never met, negated or not
	return met != condition.negate


## The answers `node_id` offers `listener_id` right now, in authored order.
func eligible_choices(dialogue_id: StringName, node_id: StringName,
		listener_id: StringName) -> Array[DialogueChoiceData]:
	var out: Array[DialogueChoiceData] = []
	var dialogue := _catalog.entry(dialogue_id) if is_ready() else null
	var line := dialogue.node(node_id) if dialogue != null else null
	if line == null:
		return out
	for option in line.choices:
		if _is_offered(option, dialogue.speaker_id, listener_id):
			out.append(option)
	return out


func _is_offered(option: DialogueChoiceData, speaker_id: StringName,
		listener_id: StringName) -> bool:
	for condition in option.conditions:
		if not condition_met(condition, speaker_id, listener_id):
			return false
	return true


# --- Submitting ----------------------------------------------------------------

## Acknowledge a line that offers no choices: on to its `next_node_id`, or the end. Changes
## nothing anywhere.
func advance(dialogue_id: StringName, node_id: StringName) -> DialogueOutcome:
	var dialogue := _catalog.entry(dialogue_id) if is_ready() else null
	var line := dialogue.node(node_id) if dialogue != null else null
	if line == null:
		return DialogueOutcome.refused(REFUSE_NOT_READY, dialogue_id, node_id)
	if not line.choices.is_empty():
		return DialogueOutcome.refused(REFUSE_CHOICE_GONE, dialogue_id, node_id)
	return _moved(dialogue_id, node_id, &"", line.next_node_id)


## Submit `choice_id` at `node_id`. Re-validated here: the choice must belong to that node and
## its conditions must pass NOW. Then its one effect is applied by its owner, and only then
## does the conversation move. A refusal — unknown, no longer offered, or refused by the
## effect's owner — changes nothing and leaves the conversation where it was.
## `grant(knowledge_id, source_id) -> StringName` is the Knowledge Core's grant path.
func choose(dialogue_id: StringName, node_id: StringName, choice_id: StringName,
		listener_id: StringName, grant: Callable) -> DialogueOutcome:
	var dialogue := _catalog.entry(dialogue_id) if is_ready() else null
	var line := dialogue.node(node_id) if dialogue != null else null
	if line == null or listener_id == &"":
		return DialogueOutcome.refused(REFUSE_NOT_READY, dialogue_id, node_id, choice_id)
	var option := line.choice(choice_id)
	if option == null or not _is_offered(option, dialogue.speaker_id, listener_id):
		return DialogueOutcome.refused(REFUSE_CHOICE_GONE, dialogue_id, node_id, choice_id)
	var outcome := _moved(dialogue_id, node_id, choice_id, option.next_node_id)
	if option.effect == null:
		return outcome
	outcome.effect_kind = option.effect.kind
	var applied := true
	match option.effect.kind:
		DialogueEffectData.Kind.RELATIONSHIP_DELTA:
			applied = _apply_regard(outcome, dialogue, option.effect, listener_id)
		DialogueEffectData.Kind.GRANT_KNOWLEDGE:
			applied = _apply_grant(outcome, dialogue, option.effect, grant)
		DialogueEffectData.Kind.OPEN_SHOP:
			outcome.action = ACTION_OPEN_SHOP
		_:
			applied = false
	if not applied:
		return DialogueOutcome.refused(REFUSE_EFFECT_FAILED, dialogue_id, node_id, choice_id)
	return outcome


func _moved(dialogue_id: StringName, node_id: StringName, choice_id: StringName,
		next_node_id: StringName) -> DialogueOutcome:
	var outcome := DialogueOutcome.new()
	outcome.ok = true
	outcome.dialogue_id = dialogue_id
	outcome.node_id = node_id
	outcome.choice_id = choice_id
	outcome.next_node_id = next_node_id
	outcome.ended = next_node_id == &""
	return outcome


## Move the speaker's regard through `RelationshipService` (`RegardRules` says which edge,
## and makes one only when the delta would actually change something). False — nothing
## changed, nothing created — when the edge cannot be made.
func _apply_regard(outcome: DialogueOutcome, dialogue: DialogueData,
		effect: DialogueEffectData, listener_id: StringName) -> bool:
	var moved := RegardRules.move(_relationship, _config, dialogue.speaker_id, listener_id,
		effect.dimension, effect.delta, dialogue.id)
	outcome.dimension = effect.dimension
	outcome.old_value = int(moved["old_value"])
	outcome.new_value = int(moved["new_value"])
	return bool(moved["ok"])


func _apply_grant(outcome: DialogueOutcome, dialogue: DialogueData,
		effect: DialogueEffectData, grant: Callable) -> bool:
	if not grant.is_valid():
		return false
	outcome.knowledge_id = effect.knowledge_id
	outcome.knowledge_result = grant.call(effect.knowledge_id, dialogue.id)
	return outcome.knowledge_result == KnowledgeService.GRANTED \
		or outcome.knowledge_result == KnowledgeService.ALREADY_KNOWN

extends RefCounted
class_name DialogueOutcome
## DialogueOutcome — Aetheria domain (what submitting a choice came to, Phase 18).
##
## Plain facts in stable ids: which choice, where the conversation goes next, and what — if
## anything — the choice's one effect did in the system that owns it. Never text, never a node.

var ok: bool = false
## A refusal's localization key (`DialogueService.REFUSE_*`); empty on success.
var reason: StringName = &""
var dialogue_id: StringName = &""
var node_id: StringName = &""
## Empty for a "continue" on a line without choices.
var choice_id: StringName = &""
## The node the conversation is at afterwards. Empty = it ended.
var next_node_id: StringName = &""
var ended: bool = false
## What the gameplay layer must now DO (`DialogueService.ACTION_*`); empty for nothing.
var action: StringName = &""

## The effect's kind (a `DialogueEffectData.Kind`), or NO_EFFECT.
var effect_kind: int = NO_EFFECT
## RELATIONSHIP_DELTA: the dimension and its value before / after (equal = already at a bound).
var dimension: StringName = &""
var old_value: int = 0
var new_value: int = 0
## GRANT_KNOWLEDGE: the id and the Knowledge Core's own answer (`KnowledgeService.GRANTED` …).
var knowledge_id: StringName = &""
var knowledge_result: StringName = &""

const NO_EFFECT := -1


static func refused(why: StringName, p_dialogue: StringName = &"", p_node: StringName = &"",
		p_choice: StringName = &"") -> DialogueOutcome:
	var outcome := DialogueOutcome.new()
	outcome.reason = why
	outcome.dialogue_id = p_dialogue
	outcome.node_id = p_node
	outcome.choice_id = p_choice
	outcome.next_node_id = p_node  # a refusal moves nothing
	return outcome

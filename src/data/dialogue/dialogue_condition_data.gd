extends Resource
class_name DialogueConditionData
## DialogueConditionData — Aetheria data (one thing a dialogue choice requires, Phase 18).
##
## A CLOSED set (D-066): a condition asks a system that already owns the answer — the Knowledge
## Core, the relationship graph, or (Phase 19, D-070) the quest owner — and nothing else. There
## is no flag kind: Dialogue owns no flag, and the story engine (Phase 20) adds its own kind
## when it exists.
##
## `negate` turns "knows" into "does not know", "regard at least" into "regard below" and
## "the quest is in this phase" into "it is in any other".

enum Kind {
	## The player holds `knowledge_id`.
	KNOWS,
	## The speaker's regard for the player on `dimension` is >= `value`.
	RELATIONSHIP_AT_LEAST,
	## Quest `quest_id` is in phase `quest_phase` (a `QuestService.Phase`), as `QuestService`
	## says right now.
	QUEST_PHASE,
}

@export var kind: Kind = Kind.KNOWS
## KNOWS only: an id in the knowledge catalog.
@export var knowledge_id: StringName = &""
## RELATIONSHIP_AT_LEAST only: a dimension of the relationship graph, and the value to reach.
@export var dimension: StringName = &""
@export var value: int = 0
## QUEST_PHASE only: a quest in the quest catalog, and the phase it must be in.
@export var quest_id: StringName = &""
@export var quest_phase: QuestService.Phase = QuestService.Phase.AVAILABLE
@export var negate: bool = false


func is_valid() -> bool:
	return validation_errors().is_empty()


## Structural errors only (which fields a kind uses). Whether the id or the dimension EXISTS is
## the owners' question, asked by `DialogueService.content_errors`.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	match kind:
		Kind.KNOWS:
			if knowledge_id == &"":
				errors.append("a KNOWS condition names no knowledge_id")
			if dimension != &"" or value != 0:
				errors.append("a KNOWS condition carries a relationship payload")
			if quest_id != &"":
				errors.append("a KNOWS condition carries a quest_id")
		Kind.RELATIONSHIP_AT_LEAST:
			if dimension == &"":
				errors.append("a RELATIONSHIP_AT_LEAST condition names no dimension")
			if knowledge_id != &"":
				errors.append("a RELATIONSHIP_AT_LEAST condition carries a knowledge_id")
			if quest_id != &"":
				errors.append("a RELATIONSHIP_AT_LEAST condition carries a quest_id")
		Kind.QUEST_PHASE:
			if quest_id == &"":
				errors.append("a QUEST_PHASE condition names no quest_id")
			if quest_phase < 0 or quest_phase >= QuestService.Phase.size():
				errors.append("a QUEST_PHASE condition names unknown phase %d" % quest_phase)
			if knowledge_id != &"" or dimension != &"" or value != 0:
				errors.append("a QUEST_PHASE condition carries a payload it does not use")
		_:
			errors.append("unknown condition kind %d" % kind)
	return errors

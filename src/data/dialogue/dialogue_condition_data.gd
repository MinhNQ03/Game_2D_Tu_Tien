extends Resource
class_name DialogueConditionData
## DialogueConditionData — Aetheria data (one thing a dialogue choice requires, Phase 18).
##
## A CLOSED set (D-066): a condition asks a system that already owns the answer — the Knowledge
## Core, the relationship graph, (Phase 19, D-070) the quest owner, or (Phase 20, D-072) the
## story owner — and nothing else. Dialogue owns no flag: `FLAG` and `ORIGIN` ask
## `StoryService`, which is the flags' only writer.
##
## `negate` turns "knows" into "does not know", "regard at least" into "regard below" and
## "the quest is in this phase" into "it is in any other".

enum Kind {
	## The player holds `knowledge_id`.
	KNOWS,
	## The speaker's regard for the player on `dimension` is >= `value`.
	RELATIONSHIP_AT_LEAST,
	## Quest `quest_id` is in phase `quest_phase` (a `QuestData.Phase`), as `QuestService`
	## says right now.
	QUEST_PHASE,
	## Story flag `flag_id` is at least `value` (1 for a BOOL), as `StoryService` says.
	FLAG,
	## The player's Origin is `origin_id`.
	ORIGIN,
}

@export var kind: Kind = Kind.KNOWS
## KNOWS only: an id in the knowledge catalog.
@export var knowledge_id: StringName = &""
## RELATIONSHIP_AT_LEAST only: a dimension of the relationship graph, and the value to reach.
@export var dimension: StringName = &""
@export var value: int = 0
## QUEST_PHASE only: a quest in the quest catalog, and the phase it must be in.
@export var quest_id: StringName = &""
@export var quest_phase: QuestData.Phase = QuestData.Phase.AVAILABLE
## FLAG only: a flag the story catalog declares (`value` is the least it must hold, >= 1).
@export var flag_id: StringName = &""
## ORIGIN only: an Origin in the origin catalog.
@export var origin_id: StringName = &""
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
			if quest_phase < 0 or quest_phase >= QuestData.Phase.size():
				errors.append("a QUEST_PHASE condition names unknown phase %d" % quest_phase)
			if knowledge_id != &"" or dimension != &"" or value != 0:
				errors.append("a QUEST_PHASE condition carries a payload it does not use")
		Kind.FLAG:
			if flag_id == &"":
				errors.append("a FLAG condition names no flag_id")
			if value < 1:
				errors.append("a FLAG condition must ask for at least 1 (use negate for 'not')")
			if knowledge_id != &"" or dimension != &"" or quest_id != &"":
				errors.append("a FLAG condition carries a payload it does not use")
		Kind.ORIGIN:
			if origin_id == &"":
				errors.append("an ORIGIN condition names no origin_id")
			if knowledge_id != &"" or dimension != &"" or value != 0 or quest_id != &"":
				errors.append("an ORIGIN condition carries a payload it does not use")
		_:
			errors.append("unknown condition kind %d" % kind)
	if flag_id != &"" and kind != Kind.FLAG:
		errors.append("carries a flag_id its kind does not use")
	if origin_id != &"" and kind != Kind.ORIGIN:
		errors.append("carries an origin_id its kind does not use")
	return errors

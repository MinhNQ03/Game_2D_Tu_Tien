extends Resource
class_name DialogueEffectData
## DialogueEffectData — Aetheria data (the one consequence of a dialogue choice, Phase 18).
##
## A CLOSED set (D-066). Each kind is applied by the system that owns what it changes — the
## data only says WHICH and with what payload; it carries no code, no callback and no node path.

enum Kind {
	## Move the speaker's regard for the player: `dimension` by `delta`, through
	## `RelationshipService`.
	RELATIONSHIP_DELTA,
	## Teach the player `knowledge_id`, through the Knowledge Core.
	GRANT_KNOWLEDGE,
	## Hand the conversation over to the speaker's shop (its owner opens it). No payload.
	OPEN_SHOP,
	## The player takes quest `quest_id` from the speaker, through the quest owner (D-070).
	QUEST_ACCEPT,
	## The player answers quest `quest_id` to the speaker: its reward is paid by its owners.
	QUEST_TURN_IN,
	## The player gives quest `quest_id` back to the speaker; its progress is discarded.
	QUEST_ABANDON,
	## Set story flag `flag_id` to `flag_value`, through the story owner (D-072): the line
	## has now been said, the thing has now been heard.
	SET_FLAG,
	## Answer story choice `story_choice_id` with `story_option_id`. The story owner records
	## it once and carries out its authored consequences in the same call (D-072 §7).
	STORY_CHOICE,
}

## The kinds the quest owner carries out.
const QUEST_KINDS: Array[Kind] = [Kind.QUEST_ACCEPT, Kind.QUEST_TURN_IN, Kind.QUEST_ABANDON]

## The kinds the story owner carries out.
const STORY_KINDS: Array[Kind] = [Kind.SET_FLAG, Kind.STORY_CHOICE]

## The largest single move a line may make. A dimension spans at most 200 points; one sentence
## does not carry someone from one end to the other.
const MAX_DELTA := 50

@export var kind: Kind = Kind.RELATIONSHIP_DELTA
@export var dimension: StringName = &""
@export var delta: int = 0
@export var knowledge_id: StringName = &""
## QUEST_ACCEPT / QUEST_TURN_IN / QUEST_ABANDON: a quest in the quest catalog.
@export var quest_id: StringName = &""
## SET_FLAG: a flag the story catalog declares, and the value to write (>= 1).
@export var flag_id: StringName = &""
@export var flag_value: int = 1
## STORY_CHOICE: a choice in the story catalog and one of its options.
@export var story_choice_id: StringName = &""
@export var story_option_id: StringName = &""


func is_story_kind() -> bool:
	return STORY_KINDS.has(kind)


func is_quest_kind() -> bool:
	return QUEST_KINDS.has(kind)


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	match kind:
		Kind.RELATIONSHIP_DELTA:
			if dimension == &"":
				errors.append("a RELATIONSHIP_DELTA effect names no dimension")
			if delta == 0:
				errors.append("a RELATIONSHIP_DELTA effect of 0 changes nothing")
			elif absi(delta) > MAX_DELTA:
				errors.append("a RELATIONSHIP_DELTA of %d exceeds the ceiling %d"
					% [delta, MAX_DELTA])
			if knowledge_id != &"":
				errors.append("a RELATIONSHIP_DELTA effect carries a knowledge_id")
		Kind.GRANT_KNOWLEDGE:
			if knowledge_id == &"":
				errors.append("a GRANT_KNOWLEDGE effect names no knowledge_id")
			if dimension != &"" or delta != 0:
				errors.append("a GRANT_KNOWLEDGE effect carries a relationship payload")
		Kind.OPEN_SHOP:
			if dimension != &"" or delta != 0 or knowledge_id != &"":
				errors.append("an OPEN_SHOP effect carries a payload it does not use")
		Kind.QUEST_ACCEPT, Kind.QUEST_TURN_IN, Kind.QUEST_ABANDON:
			if quest_id == &"":
				errors.append("a quest effect names no quest_id")
			if dimension != &"" or delta != 0 or knowledge_id != &"":
				errors.append("a quest effect carries a payload it does not use")
		Kind.SET_FLAG:
			if flag_id == &"":
				errors.append("a SET_FLAG effect names no flag_id")
			if flag_value < 1:
				errors.append("a SET_FLAG effect must write at least 1")
			if dimension != &"" or delta != 0 or knowledge_id != &"":
				errors.append("a SET_FLAG effect carries a payload it does not use")
		Kind.STORY_CHOICE:
			if story_choice_id == &"" or story_option_id == &"":
				errors.append("a STORY_CHOICE effect must name a choice and an option")
			if dimension != &"" or delta != 0 or knowledge_id != &"":
				errors.append("a STORY_CHOICE effect carries a payload it does not use")
		_:
			errors.append("unknown effect kind %d" % kind)
	if flag_id != &"" and kind != Kind.SET_FLAG:
		errors.append("carries a flag_id its kind does not use")
	if (story_choice_id != &"" or story_option_id != &"") and kind != Kind.STORY_CHOICE:
		errors.append("carries a story choice its kind does not use")
	if quest_id != &"" and not is_quest_kind():
		errors.append("carries a quest_id its kind does not use")
	return errors

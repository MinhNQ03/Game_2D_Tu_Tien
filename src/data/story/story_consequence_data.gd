extends Resource
class_name StoryConsequenceData
## StoryConsequenceData — Aetheria data (one thing a story decision changes, Phase 20, D-072).
##
## A CLOSED set, and each kind is carried out by the owner of what it changes: a flag by the
## story itself, a regard by the relationship graph, a piece of knowledge by the Knowledge
## Core. The data says WHICH and by how much; it carries no code and no node path.

enum Kind {
	## Set flag `flag_id` to `value` (a BOOL takes 0 or 1).
	SET_FLAG,
	## Move `character_id`'s regard for the player on `dimension` by `delta`.
	REGARD,
	## Teach the player `knowledge_id`.
	GRANT_KNOWLEDGE,
}

## The largest single move one decision may make (the dialogue seam's ceiling, D-066).
const MAX_DELTA := 50

@export var kind: Kind = Kind.SET_FLAG
@export var flag_id: StringName = &""
@export var value: int = 1
@export var character_id: StringName = &""
@export var dimension: StringName = &""
@export var delta: int = 0
@export var knowledge_id: StringName = &""


## What this consequence writes to, as a comparable key: two consequences of one decision
## with the same key would fight over one value.
func target_key() -> String:
	match kind:
		Kind.SET_FLAG:
			return "flag:%s" % flag_id
		Kind.REGARD:
			return "regard:%s:%s" % [character_id, dimension]
		Kind.GRANT_KNOWLEDGE:
			return "knowledge:%s" % knowledge_id
	return ""


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	match kind:
		Kind.SET_FLAG:
			if flag_id == &"":
				errors.append("a SET_FLAG consequence names no flag")
			if value < 0:
				errors.append("a SET_FLAG consequence sets %d; a flag is never negative" % value)
			if character_id != &"" or dimension != &"" or delta != 0 or knowledge_id != &"":
				errors.append("a SET_FLAG consequence carries a payload it does not use")
		Kind.REGARD:
			if character_id == &"" or dimension == &"":
				errors.append("a REGARD consequence names no character or no dimension")
			if delta == 0:
				errors.append("a REGARD consequence of 0 changes nothing")
			elif absi(delta) > MAX_DELTA:
				errors.append("a REGARD consequence of %d exceeds the ceiling %d"
					% [delta, MAX_DELTA])
			if flag_id != &"" or knowledge_id != &"":
				errors.append("a REGARD consequence carries a payload it does not use")
		Kind.GRANT_KNOWLEDGE:
			if knowledge_id == &"":
				errors.append("a GRANT_KNOWLEDGE consequence names no knowledge")
			if flag_id != &"" or character_id != &"" or dimension != &"" or delta != 0:
				errors.append("a GRANT_KNOWLEDGE consequence carries a payload it does not use")
		_:
			errors.append("unknown consequence kind %d" % kind)
	return errors

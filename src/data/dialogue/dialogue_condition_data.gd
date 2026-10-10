extends Resource
class_name DialogueConditionData
## DialogueConditionData — Aetheria data (one thing a dialogue choice requires, Phase 18).
##
## A CLOSED set (D-066): a condition asks a system that already owns the answer — the Knowledge
## Core or the relationship graph — and nothing else. There is no flag kind: Dialogue owns no
## flag, and the story engine (Phase 20) adds its own kind when it exists.
##
## `negate` turns "knows" into "does not know" and "regard at least" into "regard below".

enum Kind {
	## The player holds `knowledge_id`.
	KNOWS,
	## The speaker's regard for the player on `dimension` is >= `value`.
	RELATIONSHIP_AT_LEAST,
}

@export var kind: Kind = Kind.KNOWS
## KNOWS only: an id in the knowledge catalog.
@export var knowledge_id: StringName = &""
## RELATIONSHIP_AT_LEAST only: a dimension of the relationship graph, and the value to reach.
@export var dimension: StringName = &""
@export var value: int = 0
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
		Kind.RELATIONSHIP_AT_LEAST:
			if dimension == &"":
				errors.append("a RELATIONSHIP_AT_LEAST condition names no dimension")
			if knowledge_id != &"":
				errors.append("a RELATIONSHIP_AT_LEAST condition carries a knowledge_id")
		_:
			errors.append("unknown condition kind %d" % kind)
	return errors

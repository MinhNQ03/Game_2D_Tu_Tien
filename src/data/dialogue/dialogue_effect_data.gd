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
}

## The largest single move a line may make. A dimension spans at most 200 points; one sentence
## does not carry someone from one end to the other.
const MAX_DELTA := 50

@export var kind: Kind = Kind.RELATIONSHIP_DELTA
@export var dimension: StringName = &""
@export var delta: int = 0
@export var knowledge_id: StringName = &""


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
		_:
			errors.append("unknown effect kind %d" % kind)
	return errors

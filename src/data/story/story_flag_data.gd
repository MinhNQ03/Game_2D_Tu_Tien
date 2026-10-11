extends Resource
class_name StoryFlagData
## StoryFlagData — Aetheria data (the DECLARATION of one story flag, Phase 20, D-072).
##
## A flag exists only if the story catalog declares it here, with a type. `StoryService`
## refuses an undeclared id and a value of the wrong type, so the flags dictionary on the
## player's `CharacterState` can never hold a typo, an object or a second meaning for one name.
##
## A flag records something only the STORY cares about (a thing heard, a line already said).
## It is not knowledge (`KnowledgeService`), not a quest's phase (`QuestService`) and not the
## current beat (`StoryState`).

enum Kind {
	## false until set true.
	BOOL,
	## A count from 0 to `max_value`.
	INT,
}

@export var id: StringName = &""
@export var kind: Kind = Kind.BOOL
## INT only: the largest value it may hold.
@export var max_value: int = 1
## Why this flag exists — for the author reading the catalog, never shown to the player.
@export var purpose: String = ""


## The largest value a read of this flag can return (a BOOL reads as 0 or 1).
func ceiling() -> int:
	return max_value if kind == Kind.INT else 1


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("flag", id)
	if bad != "":
		errors.append(bad)
	if kind != Kind.BOOL and kind != Kind.INT:
		errors.append("flag '%s' has unknown kind %d" % [id, kind])
	if kind == Kind.INT and max_value < 1:
		errors.append("INT flag '%s' has max_value %d; it could hold nothing" % [id, max_value])
	if purpose.strip_edges() == "":
		errors.append("flag '%s' states no purpose" % id)
	return errors

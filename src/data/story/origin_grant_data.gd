extends Resource
class_name OriginGrantData
## OriginGrantData — Aetheria data (one thing an Origin starts the run with, Phase 20, D-072).
##
## A CLOSED set, each carried out by the owner of what it changes: an item by the bag, a piece
## of knowledge by the Knowledge Core, a regard by the relationship graph. Small on purpose —
## an Origin changes context and a little kit, never power (`NARRATIVE_MASTER_PLAN.md` §6).

enum Kind {
	## `count` of `item_id` in the bag.
	ITEM,
	## The player already knows `knowledge_id`.
	KNOWLEDGE,
	## `character_id` already regards the player: `dimension` moved by `delta`.
	REGARD,
}

## An Origin's standing with someone is a first impression, not a history.
const MAX_REGARD := 20
## A little kit: no single grant hands over a stack.
const MAX_ITEMS := 3

@export var kind: Kind = Kind.ITEM
@export var item_id: StringName = &""
@export var count: int = 1
@export var knowledge_id: StringName = &""
@export var character_id: StringName = &""
@export var dimension: StringName = &""
@export var delta: int = 0
## Why this Origin has this — one line, for the author and the traceability table.
@export var reason: String = ""


func target_key() -> String:
	match kind:
		Kind.ITEM:
			return "item:%s" % item_id
		Kind.KNOWLEDGE:
			return "knowledge:%s" % knowledge_id
		Kind.REGARD:
			return "regard:%s:%s" % [character_id, dimension]
	return ""


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if reason.strip_edges() == "":
		errors.append("a grant states no reason")
	match kind:
		Kind.ITEM:
			if item_id == &"":
				errors.append("an ITEM grant names no item")
			if count < 1 or count > MAX_ITEMS:
				errors.append("an ITEM grant of %d is outside 1..%d" % [count, MAX_ITEMS])
			if knowledge_id != &"" or character_id != &"" or dimension != &"" or delta != 0:
				errors.append("an ITEM grant carries a payload it does not use")
		Kind.KNOWLEDGE:
			if knowledge_id == &"":
				errors.append("a KNOWLEDGE grant names no knowledge")
			if item_id != &"" or character_id != &"" or dimension != &"" or delta != 0:
				errors.append("a KNOWLEDGE grant carries a payload it does not use")
		Kind.REGARD:
			if character_id == &"" or dimension == &"":
				errors.append("a REGARD grant names no character or no dimension")
			if delta == 0 or absi(delta) > MAX_REGARD:
				errors.append("a REGARD grant of %d is outside 1..%d either way"
					% [delta, MAX_REGARD])
			if item_id != &"" or knowledge_id != &"":
				errors.append("a REGARD grant carries a payload it does not use")
		_:
			errors.append("unknown grant kind %d" % kind)
	return errors

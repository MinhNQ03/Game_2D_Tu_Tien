extends Resource
class_name QuestObjectiveData
## QuestObjectiveData — Aetheria data (one thing a quest asks for, Phase 19, D-070).
##
## A CLOSED set of kinds. Two are STATE — the owner is asked every time, so something already
## true when the quest is accepted counts at once and nothing is mirrored here — and one is an
## EVENT, counted by the quest only while it is active.

enum Kind {
	## The Knowledge Core holds `target_id`. State.
	KNOW,
	## The bag holds `count` of item `target_id`. State. `consumed`: handed over at turn-in.
	HOLD_ITEM,
	## `count` creatures of kind `target_id` (an `EnemyData.id`) were defeated. Events.
	DEFEAT,
}

const MAX_COUNT := 99

## Unique within its quest.
@export var id: StringName = &""
@export var kind: Kind = Kind.KNOW
@export var target_id: StringName = &""
@export var count: int = 1
## HOLD_ITEM only: the items leave the bag when the quest is turned in.
@export var consumed: bool = false
## What the journal says this objective is.
@export var text_key: StringName = &""


## True when the quest itself counts this objective (it is not a question to another owner).
func is_counted() -> bool:
	return kind == Kind.DEFEAT


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("objective id is empty")
	if text_key == &"":
		errors.append("text_key is empty")
	if target_id == &"":
		errors.append("names no target")
	match kind:
		Kind.KNOW:
			if count != 1:
				errors.append("a KNOW objective is held or not: count must be 1, not %d" % count)
			if consumed:
				errors.append("knowledge cannot be handed over: 'consumed' is for HOLD_ITEM")
		Kind.HOLD_ITEM:
			if count < 1 or count > MAX_COUNT:
				errors.append("count %d is outside 1..%d" % [count, MAX_COUNT])
		Kind.DEFEAT:
			if count < 1 or count > MAX_COUNT:
				errors.append("count %d is outside 1..%d" % [count, MAX_COUNT])
			if consumed:
				errors.append("a defeat cannot be handed over: 'consumed' is for HOLD_ITEM")
		_:
			errors.append("unknown objective kind %d" % kind)
	return errors

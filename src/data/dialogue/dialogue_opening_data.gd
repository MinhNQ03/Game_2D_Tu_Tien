extends Resource
class_name DialogueOpeningData
## DialogueOpeningData — Aetheria data (where a conversation starts when something is true).
##
## A person does not greet a stranger and someone they have dealt with in the same words, and
## nobody says "so you are the new one" twice (AUD-13). A dialogue lists its openings in
## order; the FIRST whose conditions all hold names the line the conversation opens on, and
## `DialogueData.start_node_id` is what is said when none does. An opening changes nothing —
## it only chooses a line — and it asks the same closed set of conditions a choice does.

@export var conditions: Array[DialogueConditionData] = []
@export var node_id: StringName = &""


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if node_id == &"":
		errors.append("an opening names no node_id")
	if conditions.is_empty():
		errors.append("an opening with no condition is the start node; author it there")
	for i in conditions.size():
		var condition := conditions[i]
		if condition == null:
			errors.append("opening condition %d is null" % i)
			continue
		for problem in condition.validation_errors():
			errors.append("opening condition %d: %s" % [i, problem])
	return errors

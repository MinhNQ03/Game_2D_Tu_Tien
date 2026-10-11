extends Resource
class_name StoryBranchData
## StoryBranchData — Aetheria data (one way on from a story beat, Phase 20, D-072).
##
## A beat lists its branches in order; the first whose conditions ALL hold is taken. The last
## must have no condition, so a completed beat always leads somewhere.

@export var conditions: Array[StoryConditionData] = []
@export var next_beat_id: StringName = &""


func is_unconditional() -> bool:
	return conditions.is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("branch target", next_beat_id)
	if bad != "":
		errors.append(bad)
	for i in conditions.size():
		var condition := conditions[i]
		if condition == null:
			errors.append("condition %d is null" % i)
			continue
		for problem in condition.validation_errors():
			errors.append("condition %d: %s" % [i, problem])
		for j in i:
			if conditions[j] != null and condition.contradicts(conditions[j]):
				errors.append("conditions %d and %d can never both hold" % [j, i])
	return errors

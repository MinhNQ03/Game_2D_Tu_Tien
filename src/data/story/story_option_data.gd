extends Resource
class_name StoryOptionData
## StoryOptionData — Aetheria data (one answer to a story choice, Phase 20, D-072).

@export var id: StringName = &""
## What the Chronicle writes down when this answer is given.
@export var record_key: StringName = &""
@export var consequences: Array[StoryConsequenceData] = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("option", id)
	if bad != "":
		errors.append(bad)
	if record_key == &"":
		errors.append("option '%s' has no record line for the Chronicle" % id)
	var targets := {}
	for i in consequences.size():
		var consequence := consequences[i]
		if consequence == null:
			errors.append("option '%s': consequence %d is null" % [id, i])
			continue
		for problem in consequence.validation_errors():
			errors.append("option '%s': consequence %d: %s" % [id, i, problem])
		var key := consequence.target_key()
		if targets.has(key):
			errors.append("option '%s': two consequences write '%s'" % [id, key])
		targets[key] = true
	return errors

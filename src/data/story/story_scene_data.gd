extends Resource
class_name StorySceneData
## StorySceneData — Aetheria data (a short authored scene, Phase 20, D-072 §6).
##
## An ordered list of steps on ONE contract: an Origin's vignette, the arrival, the warning and
## the rupture are all this resource with different data. No per-scene script.
##
## A scene is SHORT by rule, not by taste: the player is watching instead of playing, and every
## step is a key press. `MAX_STEPS` is the ceiling; a scene that needs more is two beats.

const MAX_STEPS := 6

@export var id: StringName = &""
## The scene happens SOMEWHERE ELSE (a memory, another place): the map behind it is covered,
## because showing the village behind "three months ago, on the post road" would be a lie.
@export var elsewhere: bool = false
@export var steps: Array[StorySceneStepData] = []
## An ELSEWHERE scene may be staged over an illustration of that place (a `res://` texture
## path): the past is shown, not only told. Empty = the bare ink ground. Presentation only.
@export var backdrop_ref: String = ""


func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for step in steps:
		if step != null:
			keys.append_array(step.text_keys())
	return keys


func speaker_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for step in steps:
		if step != null and step.speaker_id != &"" and not out.has(step.speaker_id):
			out.append(step.speaker_id)
	return out


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("scene", id)
	if bad != "":
		errors.append(bad)
	if steps.is_empty():
		errors.append("scene '%s' has no steps" % id)
	if steps.size() > MAX_STEPS:
		errors.append("scene '%s' has %d steps; the ceiling is %d" % [id, steps.size(), MAX_STEPS])
	if backdrop_ref != "" and not elsewhere:
		errors.append("scene '%s' has a backdrop but happens HERE; the live map is its ground"
			% id)
	for i in steps.size():
		var step := steps[i]
		if step == null:
			errors.append("scene '%s': step %d is null" % [id, i])
			continue
		for problem in step.validation_errors():
			errors.append("scene '%s': step %d: %s" % [id, i, problem])
		if step.kind == StorySceneStepData.Kind.CARD and i != 0:
			errors.append("scene '%s': step %d is a CARD; a card opens a scene" % [id, i])
	return errors

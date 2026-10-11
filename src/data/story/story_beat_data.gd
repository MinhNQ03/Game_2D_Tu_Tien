extends Resource
class_name StoryBeatData
## StoryBeatData — Aetheria data (one beat of a chapter, Phase 20, D-072).
##
## A beat is a stretch of play with ONE purpose the player can act on (`objective_key`, which
## the place plaque shows), ONE thing that completes it (`trigger`), and somewhere to go next.
## It carries no code: what it means on a map is derived by presentation from "this beat is
## the current one".

@export var id: StringName = &""
## What the player is trying to do, as one short line. Shown in the purpose line.
@export var objective_key: StringName = &""
## What happened, once it is done. The Chronicle records this line.
@export var record_key: StringName = &""
## The reveal-ladder layer this beat may touch (`NARRATIVE_MASTER_PLAN.md` §9). The prologue
## stays at 1; a beat authored higher than its chapter allows fails validation.
@export_range(1, 9) var reveal_layer: int = 1
## Where in canon this beat comes from — for the author and the traceability table.
@export var source: String = ""
## The scene shown when this beat is ENTERED (presentation only; it changes nothing).
@export var entry_scene_id: StringName = &""
## Enter by showing the run's ORIGIN vignette instead of a scene named here.
@export var plays_origin_vignette: bool = false
@export var trigger: StoryTriggerData = null
@export var branches: Array[StoryBranchData] = []
## The story rests here: nothing completes it yet (the standing purpose at the end of what is
## authored). A terminal beat has no trigger and no branches.
@export var terminal: bool = false


func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = [objective_key]
	if record_key != &"":
		keys.append(record_key)
	return keys


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("beat", id)
	if bad != "":
		errors.append(bad)
	if objective_key == &"":
		errors.append("states no objective: the purpose line would be blank")
	if source.strip_edges() == "":
		errors.append("names no source in canon")
	if plays_origin_vignette and entry_scene_id != &"":
		errors.append("plays the Origin's vignette AND names a scene of its own")
	if terminal:
		if trigger != null or not branches.is_empty():
			errors.append("is terminal but has a trigger or a way on")
		return errors
	if record_key == &"":
		errors.append("has no record line for the Chronicle")
	if trigger == null:
		errors.append("has no trigger: nothing could ever complete it")
	else:
		for problem in trigger.validation_errors():
			errors.append("trigger: %s" % problem)
	if branches.is_empty():
		errors.append("has no way on")
		return errors
	for i in branches.size():
		var branch := branches[i]
		if branch == null:
			errors.append("branch %d is null" % i)
			continue
		for problem in branch.validation_errors():
			errors.append("branch %d: %s" % [i, problem])
		if branch.is_unconditional() and i < branches.size() - 1:
			errors.append("branch %d has no condition, so branch %d can never be taken"
				% [i, i + 1])
	if branches[-1] != null and not branches[-1].is_unconditional():
		errors.append("its last branch is conditional: a completed beat could lead nowhere")
	return errors

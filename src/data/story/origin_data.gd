extends Resource
class_name OriginData
## OriginData — Aetheria data (one of the five Origins, Phase 20, D-072; CL-09).
##
## Run-scoped content referenced by id: not a class, not a character template, and never read
## by an `if`. It says who the player was before the road to Lạc Hà — the personal problem
## they carry — and the little that follows from it at the start.
##
## An Origin changes story context, a first impression or two, and a small kit. It never
## decides weapon, sect, morality, cultivation path or ending (`NARRATIVE_MASTER_PLAN.md` §6),
## and it is open to every appearance (§12).

@export var id: StringName = &""
@export var name_key: StringName = &""
## The personal problem, in one or two short sentences. Spoiler-safe: what the player knows.
@export var problem_key: StringName = &""
## What this past is good for at the start, and what it costs — one short line each.
@export var edge_key: StringName = &""
@export var cost_key: StringName = &""
## The personal goal the Chronicle keeps in view for the whole run.
@export var goal_key: StringName = &""
## The short scene that opens a run as this Origin: where they were, and what went wrong.
@export var vignette_scene_id: StringName = &""
@export var grants: Array[OriginGrantData] = []
## What this Origin ALONE notices, kept so it can be re-read (D-073): a story flag raised when
## a line only this Origin gets has been said, and the record line the Chronicle then shows.
## Index-aligned: `observation_flags[i]` set -> `observation_keys[i]` is on the record. The
## flag is the story's; this only says what it means for someone who was this person.
@export var observation_flags: Array[StringName] = []
@export var observation_keys: Array[StringName] = []


func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = [name_key, problem_key, edge_key, cost_key, goal_key]
	keys.append_array(observation_keys)
	return keys


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("origin", id)
	if bad != "":
		errors.append(bad)
	for key in text_keys():
		if key == &"":
			errors.append("origin '%s' leaves a text key empty" % id)
			break
	if vignette_scene_id == &"":
		errors.append("origin '%s' has no vignette" % id)
	if observation_flags.size() != observation_keys.size():
		errors.append("origin '%s': %d observation flags for %d record lines"
			% [id, observation_flags.size(), observation_keys.size()])
	for flag_id in observation_flags:
		if flag_id == &"":
			errors.append("origin '%s': an observation names no flag" % id)
	var targets := {}
	for i in grants.size():
		var grant := grants[i]
		if grant == null:
			errors.append("origin '%s': grant %d is null" % [id, i])
			continue
		for problem in grant.validation_errors():
			errors.append("origin '%s': grant %d: %s" % [id, i, problem])
		if targets.has(grant.target_key()):
			errors.append("origin '%s': two grants write '%s'" % [id, grant.target_key()])
		targets[grant.target_key()] = true
	return errors

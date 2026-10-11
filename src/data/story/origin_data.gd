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


func text_keys() -> Array[StringName]:
	return [name_key, problem_key, edge_key, cost_key, goal_key]


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

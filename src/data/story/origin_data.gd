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
## The identity screen's card and detail (experience upgrade): one line to compare all five at
## a glance, then who this person was, why the road leads to Lạc Hà, the first lead worth
## following there, and a spoiler-safe question about where the trouble goes. All are things
## the player-character already knows; none answers a reveal-ladder question early.
@export var tagline_key: StringName = &""
@export var past_key: StringName = &""
@export var why_here_key: StringName = &""
@export var lead_key: StringName = &""
@export var horizon_key: StringName = &""
## The illustration of this past (`res://` path): the card's picture and the vignette's
## backdrop. Presentation only; nothing in the rules reads it.
@export var art_ref: String = ""
## The short scene that opens a run as this Origin: where they were, and what went wrong.
@export var vignette_scene_id: StringName = &""
@export var grants: Array[OriginGrantData] = []
## What this Origin ALONE notices, kept so it can be re-read (D-073): a story flag raised when
## a line only this Origin gets has been said, and the record line the Chronicle then shows.
## Index-aligned: `observation_flags[i]` set -> `observation_keys[i]` is on the record. The
## flag is the story's; this only says what it means for someone who was this person.
@export var observation_flags: Array[StringName] = []
@export var observation_keys: Array[StringName] = []
## The PERSONAL STEPS of the first hour: what this person goes looking for in Lạc Hà, in order.
## Index-aligned: `personal_objective_keys[i]` is the purpose while `personal_done[i]` does not
## hold yet; the first unmet one is the personal objective. They stand in for the shared beat
## objective only while the current beat is one of `personal_beats` (the arrival), so the
## shared story is never blocked by them — and the Chronicle keeps the open one in view.
@export var personal_objective_keys: Array[StringName] = []
@export var personal_done: Array[StoryConditionData] = []
@export var personal_beats: Array[StringName] = []


## The keys an Origin cannot exist without: its name, its trouble, its goal, what it gives and
## what it costs (`NARRATIVE_MASTER_PLAN.md` §6).
func core_keys() -> Array[StringName]:
	return [name_key, problem_key, edge_key, cost_key, goal_key]


## The keys the identity screen's card and detail show beyond the core.
func card_keys() -> Array[StringName]:
	return [tagline_key, past_key, why_here_key, lead_key, horizon_key]


## Every key this Origin shows, in any surface (empty card keys are left out).
func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = core_keys()
	for key in card_keys():
		if key != &"":
			keys.append(key)
	keys.append_array(observation_keys)
	keys.append_array(personal_objective_keys)
	return keys


## What a SHIPPED Origin still lacks for the identity screen to tell its story: every card key,
## an illustration and at least one personal step. A fixture may omit them; content may not
## (asserted over the shipped catalog).
func card_errors() -> Array[String]:
	var errors: Array[String] = []
	for key in card_keys():
		if key == &"":
			errors.append("origin '%s' leaves a card line empty" % id)
			break
	if art_ref == "":
		errors.append("origin '%s' has no illustration" % id)
	if personal_objective_keys.is_empty():
		errors.append("origin '%s' has no personal step for the arrival" % id)
	return errors


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("origin", id)
	if bad != "":
		errors.append(bad)
	for key in core_keys():
		if key == &"":
			errors.append("origin '%s' leaves a text key empty" % id)
			break
	if vignette_scene_id == &"":
		errors.append("origin '%s' has no vignette" % id)
	if observation_flags.size() != observation_keys.size():
		errors.append("origin '%s': %d observation flags for %d record lines"
			% [id, observation_flags.size(), observation_keys.size()])
	if personal_objective_keys.size() != personal_done.size():
		errors.append("origin '%s': %d personal steps for %d conditions"
			% [id, personal_objective_keys.size(), personal_done.size()])
	for i in personal_done.size():
		var done := personal_done[i]
		if done == null:
			errors.append("origin '%s': personal step %d has no condition" % [id, i])
			continue
		for problem in done.validation_errors():
			errors.append("origin '%s': personal step %d: %s" % [id, i, problem])
	if not personal_objective_keys.is_empty() and personal_beats.is_empty():
		errors.append("origin '%s' has personal steps but no beat they stand in for" % id)
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

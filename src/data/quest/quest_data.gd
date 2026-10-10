extends Resource
class_name QuestData
## QuestData — Aetheria data (one authored quest, Phase 19, D-070).
##
## CONTENT: who asks, who is answered, what is asked for and what it pays. `giver_id` and
## `receiver_id` are CHARACTERS (`CharacterRegistry` instance ids, as `DialogueData.speaker_id`
## is): a quest belongs to people who already exist and defines none. A new quest is a new
## resource in the `QuestCatalogData` plus the lines its people say — never a branch in a
## service. It holds nothing that changes: progress is `QuestState`'s.

## How the objectives combine.
enum Completion {
	## Every objective must be met.
	ALL,
	## Any ONE objective is enough: they are different ways to the same end.
	ANY,
}

@export var id: StringName = &""
@export var title_key: StringName = &""
## WHY it matters, in the giver's terms (the journal shows it under the title).
@export var summary_key: StringName = &""
## The ONE line of purpose the place plaque shows, by phase — short enough for one row:
## on offer and not yet taken (where to go) · taken (what to do) · objectives met (who to
## return to).
@export var lead_key: StringName = &""
@export var goal_key: StringName = &""
@export var return_key: StringName = &""
## Who offers it, and who it is turned in to (often the same person).
@export var giver_id: StringName = &""
@export var receiver_id: StringName = &""
@export var completion: Completion = Completion.ALL
@export var objectives: Array[QuestObjectiveData] = []
@export var reward: RewardData = null


func objective(objective_id: StringName) -> QuestObjectiveData:
	for entry in objectives:
		if entry != null and entry.id == objective_id:
			return entry
	return null


## Every localization key the quest shows.
func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = [title_key, summary_key, lead_key, goal_key, return_key]
	for entry in objectives:
		if entry != null:
			keys.append(entry.text_key)
	return keys


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	elif not String(id).begins_with("quest_"):
		errors.append("id '%s' must use the quest_ prefix" % id)
	for pair: Array in [["title_key", title_key], ["summary_key", summary_key],
			["lead_key", lead_key], ["goal_key", goal_key], ["return_key", return_key]]:
		if pair[1] == &"":
			errors.append("%s is empty" % pair[0])
	if giver_id == &"":
		errors.append("giver_id is empty (a quest is asked by a character)")
	if receiver_id == &"":
		errors.append("receiver_id is empty (a quest is answered to a character)")
	if completion != Completion.ALL and completion != Completion.ANY:
		errors.append("unknown completion mode %d" % completion)
	if objectives.is_empty():
		errors.append("a quest with no objective asks for nothing")
	var ids: Dictionary = {}
	for i in objectives.size():
		var entry := objectives[i]
		if entry == null:
			errors.append("objective %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("objective '%s': %s" % [entry.id, problem])
		if ids.has(entry.id):
			errors.append("duplicate objective id '%s'" % entry.id)
		ids[entry.id] = true
	if reward == null:
		errors.append("reward is null (a quest that pays nothing has not taken part in the world)")
	else:
		for problem in reward.validation_errors():
			errors.append("reward: %s" % problem)
	return errors

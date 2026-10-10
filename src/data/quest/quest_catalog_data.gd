extends Resource
class_name QuestCatalogData
## QuestCatalogData — Aetheria data (every authored quest, Phase 19).
##
## Authored ORDER matters to presentation only: the journal lists quests in it, and the place
## plaque's purpose line names the first one that applies.

@export var entries: Array[QuestData] = []


func entry(quest_id: StringName) -> QuestData:
	for quest in entries:
		if quest != null and quest.id == quest_id:
			return quest
	return null


func has(quest_id: StringName) -> bool:
	return entry(quest_id) != null


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if entries.is_empty():
		errors.append("the quest catalog is empty")
	var ids: Dictionary = {}
	for i in entries.size():
		var quest := entries[i]
		if quest == null:
			errors.append("entry %d is null" % i)
			continue
		for problem in quest.validation_errors():
			errors.append("%s: %s" % [quest.id, problem])
		if ids.has(quest.id):
			errors.append("duplicate quest id '%s'" % quest.id)
		ids[quest.id] = true
	return errors

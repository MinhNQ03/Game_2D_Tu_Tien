extends Resource
class_name DialogueCatalogData
## DialogueCatalogData — Aetheria data (every authored conversation, Phase 18).
##
## One conversation per speaker: who you are talking to decides what is said, so "which
## dialogue" is never a second question (validated). Someone with no entry simply has nothing
## authored — `NpcRuntime`'s own behaviour stands for them.

@export var entries: Array[DialogueData] = []


func entry(dialogue_id: StringName) -> DialogueData:
	for dialogue in entries:
		if dialogue != null and dialogue.id == dialogue_id:
			return dialogue
	return null


func has(dialogue_id: StringName) -> bool:
	return entry(dialogue_id) != null


## The conversation `speaker_id` holds, or null.
func dialogue_of_speaker(speaker_id: StringName) -> DialogueData:
	for dialogue in entries:
		if dialogue != null and dialogue.speaker_id == speaker_id:
			return dialogue
	return null


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if entries.is_empty():
		errors.append("the dialogue catalog is empty")
	var ids: Dictionary = {}
	var speakers: Dictionary = {}
	for i in entries.size():
		var dialogue := entries[i]
		if dialogue == null:
			errors.append("entry %d is null" % i)
			continue
		for problem in dialogue.validation_errors():
			errors.append("%s: %s" % [dialogue.id, problem])
		if ids.has(dialogue.id):
			errors.append("duplicate dialogue id '%s'" % dialogue.id)
		ids[dialogue.id] = true
		if dialogue.speaker_id != &"":
			if speakers.has(dialogue.speaker_id):
				errors.append("'%s' speaks two dialogues" % dialogue.speaker_id)
			speakers[dialogue.speaker_id] = true
	return errors

extends Resource
class_name StoryChoiceData
## StoryChoiceData — Aetheria data (a decision the story remembers, Phase 20, D-072).
##
## A choice is answered ONCE. `StoryService.choose` is the whole transaction: it checks the
## answer, records it, and carries out the option's consequences through their owners. The
## record is what a later branch reads (`StoryConditionData.Kind.CHOICE`), so a prior decision
## shapes what follows through a stored fact, never through a flag set on the side.
##
## Not every choice is a line of dialogue. How the player came through the Night — stood, or
## withdrew — is a choice made with their feet, and it is recorded here the same way.

@export var id: StringName = &""
## The beat during which this may be answered. Empty: any beat.
@export var beat_id: StringName = &""
## The Chronicle's heading for this decision.
@export var title_key: StringName = &""
@export var options: Array[StoryOptionData] = []


func option(option_id: StringName) -> StoryOptionData:
	for entry in options:
		if entry != null and entry.id == option_id:
			return entry
	return null


func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = [title_key]
	for entry in options:
		if entry != null:
			keys.append(entry.record_key)
	return keys


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("choice", id)
	if bad != "":
		errors.append(bad)
	if title_key == &"":
		errors.append("has no title for the Chronicle")
	if options.size() < 2:
		errors.append("offers %d option(s); a choice needs at least two" % options.size())
	var seen := {}
	for i in options.size():
		var entry := options[i]
		if entry == null:
			errors.append("option %d is null" % i)
			continue
		errors.append_array(entry.validation_errors())
		if seen.has(entry.id):
			errors.append("duplicate option id '%s'" % entry.id)
		seen[entry.id] = true
	return errors

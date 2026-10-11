extends Resource
class_name StoryChapterData
## StoryChapterData — Aetheria data (one chapter: an ordered run of beats, Phase 20, D-072).
##
## The first beat is where the chapter is entered. Authored order is also the order the
## Chronicle lists what happened in.

@export var id: StringName = &""
@export var title_key: StringName = &""
## The act this chapter belongs to (`NARRATIVE_MASTER_PLAN.md` §8); 0 is the prologue.
@export_range(0, 10) var act: int = 0
## The highest reveal-ladder layer any beat here may touch.
@export_range(1, 9) var max_reveal_layer: int = 1
@export var beats: Array[StoryBeatData] = []


func beat(beat_id: StringName) -> StoryBeatData:
	for entry in beats:
		if entry != null and entry.id == beat_id:
			return entry
	return null


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("chapter", id)
	if bad != "":
		errors.append(bad)
	if title_key == &"":
		errors.append("has no title")
	if beats.is_empty():
		errors.append("has no beats")
	for i in beats.size():
		var entry := beats[i]
		if entry == null:
			errors.append("beat %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("%s: %s" % [entry.id, problem])
		if entry.reveal_layer > max_reveal_layer:
			errors.append("%s: touches reveal layer %d; this chapter stops at %d"
				% [entry.id, entry.reveal_layer, max_reveal_layer])
	return errors

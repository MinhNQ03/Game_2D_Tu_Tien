extends Resource
class_name StoryCatalogData
## StoryCatalogData — Aetheria data (every authored chapter, flag and choice, Phase 20, D-072).
##
## One resource holds the story's whole shape, plus the checks no single entry can make:
## unique ids, every "next" resolving, every beat reachable from the start, every beat able to
## reach a place where the story rests, and every condition asking about something declared.
## A new chapter is editing this and adding its `.tres`; `StoryService` does not change.

@export var chapters: Array[StoryChapterData] = []
@export var flags: Array[StoryFlagData] = []
@export var choices: Array[StoryChoiceData] = []
## The beat a new run begins on.
@export var start_beat_id: StringName = &""


func chapter(chapter_id: StringName) -> StoryChapterData:
	for entry in chapters:
		if entry != null and entry.id == chapter_id:
			return entry
	return null


func beat(beat_id: StringName) -> StoryBeatData:
	for entry in chapters:
		if entry == null:
			continue
		var found := entry.beat(beat_id)
		if found != null:
			return found
	return null


## The chapter that contains `beat_id`, or null.
func chapter_of(beat_id: StringName) -> StoryChapterData:
	for entry in chapters:
		if entry != null and entry.beat(beat_id) != null:
			return entry
	return null


func flag(flag_id: StringName) -> StoryFlagData:
	for entry in flags:
		if entry != null and entry.id == flag_id:
			return entry
	return null


func choice(choice_id: StringName) -> StoryChoiceData:
	for entry in choices:
		if entry != null and entry.id == choice_id:
			return entry
	return null


## Every beat, in authored order (chapter by chapter).
func all_beats() -> Array[StoryBeatData]:
	var out: Array[StoryBeatData] = []
	for entry in chapters:
		if entry == null:
			continue
		for found in entry.beats:
			if found != null:
				out.append(found)
	return out


## Every localization key the catalog shows the player.
func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for entry in chapters:
		if entry == null:
			continue
		keys.append(entry.title_key)
		for found in entry.beats:
			if found != null:
				keys.append_array(found.text_keys())
	for entry in choices:
		if entry != null:
			keys.append_array(entry.text_keys())
	return keys


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if chapters.is_empty():
		errors.append("the story catalog has no chapters")
	_collect_entry_errors(errors)
	if not errors.is_empty():
		# Graph checks on a catalog with null entries or duplicate ids would report noise.
		return errors
	if beat(start_beat_id) == null:
		errors.append("start_beat_id '%s' is not a beat" % start_beat_id)
		return errors
	_collect_reference_errors(errors)
	if errors.is_empty():
		_collect_graph_errors(errors)
	return errors


func _collect_entry_errors(errors: Array[String]) -> void:
	var chapter_ids := {}
	var beat_ids := {}
	for i in chapters.size():
		var entry := chapters[i]
		if entry == null:
			errors.append("chapter %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("%s: %s" % [entry.id, problem])
		if chapter_ids.has(entry.id):
			errors.append("duplicate chapter id '%s'" % entry.id)
		chapter_ids[entry.id] = true
		for found in entry.beats:
			if found == null:
				continue
			if beat_ids.has(found.id):
				errors.append("duplicate beat id '%s'" % found.id)
			beat_ids[found.id] = true
	var flag_ids := {}
	for i in flags.size():
		var entry := flags[i]
		if entry == null:
			errors.append("flag %d is null" % i)
			continue
		errors.append_array(entry.validation_errors())
		if flag_ids.has(entry.id):
			errors.append("duplicate flag id '%s'" % entry.id)
		flag_ids[entry.id] = true
	var choice_ids := {}
	for i in choices.size():
		var entry := choices[i]
		if entry == null:
			errors.append("choice %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("%s: %s" % [entry.id, problem])
		if choice_ids.has(entry.id):
			errors.append("duplicate choice id '%s'" % entry.id)
		choice_ids[entry.id] = true


## Everything the catalog refers to INSIDE itself must exist and be of the right type.
## (Knowledge, characters, dimensions and text belong to other owners: `StoryService`.)
func _collect_reference_errors(errors: Array[String]) -> void:
	for found in all_beats():
		if found.trigger != null:
			match found.trigger.kind:
				StoryTriggerData.Kind.FLAG:
					_check_flag(errors, "%s trigger" % found.id, found.trigger.subject_id,
						found.trigger.count)
				StoryTriggerData.Kind.CHOICE:
					if choice(found.trigger.subject_id) == null:
						errors.append("%s trigger: '%s' is not a choice"
							% [found.id, found.trigger.subject_id])
		for branch in found.branches:
			if beat(branch.next_beat_id) == null:
				errors.append("%s leads to '%s', which is not a beat"
					% [found.id, branch.next_beat_id])
			for condition in branch.conditions:
				_check_condition(errors, "%s branch" % found.id, condition)
	for entry in choices:
		if entry.beat_id != &"" and beat(entry.beat_id) == null:
			errors.append("%s: may be answered during '%s', which is not a beat"
				% [entry.id, entry.beat_id])
		for found in entry.options:
			for consequence in found.consequences:
				if consequence.kind == StoryConsequenceData.Kind.SET_FLAG:
					_check_flag(errors, "%s/%s" % [entry.id, found.id], consequence.flag_id,
						consequence.value)


func _check_flag(errors: Array[String], where: String, flag_id: StringName, value: int) -> void:
	var declared := flag(flag_id)
	if declared == null:
		errors.append("%s: flag '%s' is not declared" % [where, flag_id])
	elif value > declared.ceiling():
		errors.append("%s: asks flag '%s' for %d; it holds at most %d"
			% [where, flag_id, value, declared.ceiling()])


func _check_condition(errors: Array[String], where: String,
		condition: StoryConditionData) -> void:
	match condition.kind:
		StoryConditionData.Kind.FLAG:
			_check_flag(errors, where, condition.flag_id, condition.value)
		StoryConditionData.Kind.CHOICE:
			var asked := choice(condition.choice_id)
			if asked == null:
				errors.append("%s: '%s' is not a choice" % [where, condition.choice_id])
			elif asked.option(condition.option_id) == null:
				errors.append("%s: choice '%s' has no option '%s'"
					% [where, condition.choice_id, condition.option_id])


## Every beat must be reachable from the start, and from every beat the story must be able to
## reach a beat where it rests — otherwise a run could enter a loop with no way out, or the
## catalog carries content no run can ever see.
func _collect_graph_errors(errors: Array[String]) -> void:
	var forward := {}
	var backward := {}
	var rests: Array[StringName] = []
	for found in all_beats():
		forward[found.id] = []
		if not backward.has(found.id):
			backward[found.id] = []
		if found.terminal:
			rests.append(found.id)
		for branch in found.branches:
			(forward[found.id] as Array).append(branch.next_beat_id)
			if not backward.has(branch.next_beat_id):
				backward[branch.next_beat_id] = []
			(backward[branch.next_beat_id] as Array).append(found.id)
	if rests.is_empty():
		errors.append("no beat is terminal: the story has nowhere to rest")
		return
	# A beat is entered once. A loop would re-enter a completed beat, which the record
	# (`StoryState.completed_beats`: distinct ids) cannot represent.
	var looped := _first_on_a_loop(forward)
	if looped != &"":
		errors.append("beat '%s' can lead back to itself: a beat is entered once" % looped)
		return
	var from_start := _closure([start_beat_id], forward)
	var to_rest := _closure(rests, backward)
	for found in all_beats():
		if not from_start.has(found.id):
			errors.append("beat '%s' cannot be reached from the start" % found.id)
		elif not to_rest.has(found.id):
			errors.append("beat '%s' can never reach a beat where the story rests" % found.id)


static func _closure(seeds: Array[StringName], edges: Dictionary) -> Dictionary:
	var seen := {}
	var queue: Array[StringName] = seeds.duplicate()
	while not queue.is_empty():
		var at: StringName = queue.pop_back()
		if seen.has(at):
			continue
		seen[at] = true
		for next: StringName in edges.get(at, []):
			queue.append(next)
	return seen


## A beat that can reach itself by following branches, or empty when the graph has no loop.
static func _first_on_a_loop(forward: Dictionary) -> StringName:
	var ids: Array = forward.keys()
	ids.sort()
	for id: StringName in ids:
		var seeds: Array[StringName] = []
		for next: StringName in forward[id]:
			seeds.append(next)
		if _closure(seeds, forward).has(id):
			return id
	return &""

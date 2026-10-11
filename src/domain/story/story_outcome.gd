extends RefCounted
class_name StoryOutcome
## StoryOutcome — Aetheria domain (what asking the story owner for something came to).
##
## Plain facts in stable ids. Never text, never a node.

var ok: bool = false
## A refusal's reason (`StoryService.REFUSE_*`); empty on success.
var reason: StringName = &""
## The beats THIS call completed, in order. Empty when nothing moved.
var completed: Array[StringName] = []
## The current beat after the call.
var beat_id: StringName = &""
## True when the call carried the story into another chapter.
var chapter_changed: bool = false
## On a choice: what was answered.
var choice_id: StringName = &""
var option_id: StringName = &""


## Did this call change where the story stands?
func moved() -> bool:
	return not completed.is_empty()


static func refused(why: StringName) -> StoryOutcome:
	var outcome := StoryOutcome.new()
	outcome.reason = why
	return outcome

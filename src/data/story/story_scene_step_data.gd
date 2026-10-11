extends Resource
class_name StorySceneStepData
## StorySceneStepData — Aetheria data (one step of a story scene, Phase 20, D-072 §6).
##
## A CLOSED set. A step says what is SHOWN; it never changes anything. The beat that plays a
## scene has already been committed by `StoryService`, which is why skipping a scene cannot
## skip a consequence.

enum Kind {
	## Where and when: `text_key` is the place, `sub_key` the time. Opens a scene.
	CARD,
	## One or two sentences of narration.
	CAPTION,
	## Something `speaker_id` (a registered character) says.
	LINE,
}

@export var kind: Kind = Kind.CAPTION
@export var text_key: StringName = &""
## CARD only: the time of day or how long ago.
@export var sub_key: StringName = &""
## LINE only: the instance id of the character speaking.
@export var speaker_id: StringName = &""


func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = [text_key]
	if sub_key != &"":
		keys.append(sub_key)
	return keys


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if kind < 0 or kind >= Kind.size():
		errors.append("unknown step kind %d" % kind)
		return errors
	if text_key == &"":
		errors.append("a %s step shows no text" % Kind.keys()[kind])
	if kind == Kind.CARD and sub_key == &"":
		errors.append("a CARD names a place but no time")
	if kind != Kind.CARD and sub_key != &"":
		errors.append("a %s step carries a sub_key" % Kind.keys()[kind])
	if kind == Kind.LINE and speaker_id == &"":
		errors.append("a LINE names no speaker")
	if kind != Kind.LINE and speaker_id != &"":
		errors.append("a %s step carries a speaker" % Kind.keys()[kind])
	return errors

extends Resource
class_name DialogueNodeData
## DialogueNodeData — Aetheria data (one thing the speaker says, Phase 18).
##
## A line of the speaker's, HOW they say it (`mood`, `gesture` — read by presentation only),
## and what the player may answer. A node with `choices` waits for one; a node without them is
## a line the player acknowledges, continuing to `next_node_id` or — when that is empty —
## ending the conversation.

## How the line is delivered. Presentation words it and colours the name plate; nothing in the
## rules reads it.
enum Mood { CALM, WARM, STERN, WARY }

## The body gestures a line may ask for: names of `CharacterVisualComponent` actions. A look
## that authors no sheet for one keeps its idle.
const GESTURE_NONE := &""
const GESTURE_TALK := &"talk"
const GESTURES: Array[StringName] = [GESTURE_NONE, GESTURE_TALK]

@export var id: StringName = &""
@export var text_key: StringName = &""
@export var mood: Mood = Mood.CALM
@export var gesture: StringName = GESTURE_NONE
@export var choices: Array[DialogueChoiceData] = []
## Only for a node WITHOUT choices: where "continue" leads. Empty = the conversation ends.
@export var next_node_id: StringName = &""


func choice(choice_id: StringName) -> DialogueChoiceData:
	for entry in choices:
		if entry != null and entry.id == choice_id:
			return entry
	return null


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("node id is empty")
	if text_key == &"":
		errors.append("text_key is empty")
	if mood < 0 or mood >= Mood.size():
		errors.append("unknown mood %d" % mood)
	if not GESTURES.has(gesture):
		errors.append("unknown gesture '%s'" % gesture)
	if not choices.is_empty() and next_node_id != &"":
		errors.append("has choices AND next_node_id '%s': which one follows is ambiguous"
			% next_node_id)
	var unconditional := false
	for i in choices.size():
		var entry := choices[i]
		if entry == null:
			errors.append("choice %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("choice '%s': %s" % [entry.id, problem])
		if entry.conditions.is_empty():
			unconditional = true
	if not choices.is_empty() and not unconditional:
		errors.append("every choice is conditional: the player could be shown a line with "
			+ "nothing to answer")
	return errors

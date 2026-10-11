extends Resource
class_name StoryTriggerData
## StoryTriggerData — Aetheria data (what completes a story beat, Phase 20, D-072).
##
## A CLOSED set of two families.
##
## A STATE trigger is a question that has an answer at any moment (is this flag set, has this
## been chosen, is this known, have enough of these people been met). It is asked whenever the
## story's record changes — and when the beat is ENTERED, so something the player already did
## is acknowledged instead of being asked for again.
##
## An EVENT trigger is something that happens (a scene ended, the player arrived somewhere,
## a cultivation session yielded). It completes the beat only if it happens while that beat is
## the current one: arriving in the woods on day one is not "the Night".

enum Kind {
	# --- events ---
	## Story scene `subject_id` ended (or was skipped). Empty: whichever scene the beat started.
	SCENE_ENDED,
	## The player arrived in map `subject_id`.
	ARRIVED,
	## A cultivation session yielded, as the cultivation owner reports it.
	CULTIVATED,
	# --- states ---
	## Flag `subject_id` reads at least `count`.
	FLAG,
	## At least `count` of the characters in `subjects` have been met.
	MET,
	## Choice `subject_id` has been answered (with any option).
	CHOICE,
	## The player holds knowledge `subject_id`.
	KNOWS,
}

const EVENT_KINDS: Array[Kind] = [Kind.SCENE_ENDED, Kind.ARRIVED, Kind.CULTIVATED]

@export var kind: Kind = Kind.FLAG
@export var subject_id: StringName = &""
## MET only: the people who count.
@export var subjects: Array[StringName] = []
## FLAG: the value to reach. MET: how many of `subjects`.
@export var count: int = 1


func is_event() -> bool:
	return EVENT_KINDS.has(kind)


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if kind < 0 or kind >= Kind.size():
		errors.append("unknown trigger kind %d" % kind)
		return errors
	var label: String = Kind.keys()[kind]
	if kind == Kind.MET:
		if subjects.is_empty():
			errors.append("a MET trigger lists nobody")
		if count < 1 or count > subjects.size():
			errors.append("a MET trigger asks for %d of %d people" % [count, subjects.size()])
		var seen := {}
		for who in subjects:
			if who == &"" or seen.has(who):
				errors.append("a MET trigger lists '%s' twice or names nobody" % who)
			seen[who] = true
		if subject_id != &"":
			errors.append("a MET trigger carries a subject_id")
		return errors
	if not subjects.is_empty():
		errors.append("a %s trigger carries a list of people" % label)
	if subject_id == &"" and kind != Kind.SCENE_ENDED and kind != Kind.CULTIVATED:
		errors.append("a %s trigger names nothing" % label)
	if kind == Kind.CULTIVATED and subject_id != &"":
		errors.append("a CULTIVATED trigger carries a subject_id")
	if count < 1:
		errors.append("a %s trigger asks for %d" % [label, count])
	if count != 1 and kind != Kind.FLAG:
		errors.append("a %s trigger carries a count it does not use" % label)
	return errors

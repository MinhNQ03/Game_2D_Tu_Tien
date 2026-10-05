extends Resource
class_name WorldSimScheduleData
## WorldSimScheduleData — Aetheria data (one authored background routine).
##
## The `CharacterTemplateData.schedule_ref` target (`docs/DATA_SCHEMA.md`,
## `docs/CHARACTER_SYSTEM.md` §5): a cyclic list of PHASES, each an activity held for an
## authored number of ticks. This is what makes "where is NPC X now" a cheap lookup instead of
## a simulation of their day (`docs/WORLD_SIMULATION.md` §3).
##
## THE ACTIVITY VOCABULARY IS CLOSED, AND SMALL ON PURPOSE. Four abstract states — the ones
## `docs/WORLD_SIMULATION.md` §3 names as the example state machine, plus the return leg a
## mission implies. They describe what a character is BUSY WITH at a coarse grain; they are
## not a daily-life AI and must not grow into one. Adding a fifth activity is a code change
## (the enum) *and* a localization key, which is the friction that keeps this from becoming a
## simulation of eating and sleeping.
##
## WHY A CYCLE RATHER THAN A TIMELINE. A routine that ends would need a decision about what
## happens next, and that decision is behaviour — it belongs to the AI/quest phases, not to
## data. A cycle means an actor's activity is a PURE FUNCTION of the world tick, which is what
## makes LOD band changes provably lossless: a FAR actor and a NEAR actor compute the same
## answer from the same clock, so promoting one cannot change its state
## (`docs/WORLD_SIMULATION.md` §4).

## What a background character is occupied with. Closed vocabulary (see the class note).
enum Activity { TRAINING, MISSION, RETURNING, RESTING }

## Localization keys for the activities, index-aligned with `Activity`. Presentation resolves
## these; nothing here ever holds display text (`07-localization.md`).
const ACTIVITY_NAME_KEYS := [
	&"WORLDSIM_ACTIVITY_TRAINING",
	&"WORLDSIM_ACTIVITY_MISSION",
	&"WORLDSIM_ACTIVITY_RETURNING",
	&"WORLDSIM_ACTIVITY_RESTING",
]

## Stable id (`schedule_*`). IDS NEVER CHANGE ONCE SHIPPED (`DATA_SCHEMA.md` §0).
@export var id: StringName = &""

## The ordered phases of the routine. Each entry is `{ "activity": int, "ticks": int }`.
##
## A typed `Array[Dictionary]`, and a typed array will NOT accept an untyped one — the
## resulting VM error ABORTS the assigning function, which a test runner that counts only
## assertion failures then reports as PASS (L-026). Every fixture and every `.tres` must build
## a typed value.
@export var phases: Array[Dictionary] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


## Content loaded from disk is external input and is validated at the boundary
## (`04-coding-standards.md`). Returns the list of violations (empty == valid).
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be set")
	if phases.is_empty():
		errors.append("phases must have at least one entry (a routine with no phase has no "
			+ "activity to report)")
		return errors
	for i in phases.size():
		var phase: Dictionary = phases[i]
		if not phase.has("activity"):
			errors.append("phases[%d] has no 'activity'" % i)
			continue
		var activity_value: Variant = phase["activity"]
		if typeof(activity_value) != TYPE_INT:
			errors.append("phases[%d].activity must be an int ordinal (got %s)"
				% [i, type_string(typeof(activity_value))])
			continue
		var activity: int = activity_value
		if activity < 0 or activity >= Activity.size():
			errors.append("phases[%d].activity %d is not a known Activity ordinal"
				% [i, activity])
		if not phase.has("ticks"):
			errors.append("phases[%d] has no 'ticks'" % i)
			continue
		var ticks_value: Variant = phase["ticks"]
		if typeof(ticks_value) != TYPE_INT:
			errors.append("phases[%d].ticks must be an int (got %s)"
				% [i, type_string(typeof(ticks_value))])
			continue
		if int(ticks_value) <= 0:
			# A zero-tick phase would occupy no time, so the actor would be "in" it for no
			# tick at all — and a routine of only zero-tick phases would have a cycle length
			# of 0, which the position arithmetic cannot divide by.
			errors.append("phases[%d].ticks must be > 0 (got %d); a phase that occupies no "
				% [i, int(ticks_value)] + "time can never be observed")
	return errors


## Total ticks of one full cycle. 0 for an invalid/empty routine — callers must treat 0 as
## "unusable" rather than dividing by it.
func cycle_ticks() -> int:
	var total := 0
	for phase in phases:
		var ticks_value: Variant = (phase as Dictionary).get("ticks", 0)
		if typeof(ticks_value) == TYPE_INT and int(ticks_value) > 0:
			total += int(ticks_value)
	return total


## The activity in effect `elapsed` ticks into the routine — a PURE FUNCTION of the tick, which
## is the property that makes LOD band changes lossless (see the class note).
##
## Negative `elapsed` is treated as 0 rather than wrapping: a negative elapsed time means the
## caller's arithmetic is wrong, and wrapping would silently place the actor somewhere
## plausible instead of at the start.
func activity_at(elapsed: int) -> int:
	var cycle := cycle_ticks()
	if cycle <= 0:
		push_error("[worldsim] schedule '%s' has no usable cycle" % id)
		return Activity.RESTING
	var offset := (elapsed % cycle) if elapsed > 0 else 0
	for phase in phases:
		var ticks: int = int((phase as Dictionary).get("ticks", 0))
		if ticks <= 0:
			continue
		if offset < ticks:
			return int((phase as Dictionary).get("activity", Activity.RESTING))
		offset -= ticks
	# Unreachable while `cycle_ticks()` is the sum of the same phases, but a fall-through that
	# returned nothing would be a silent wrong answer rather than a reported one.
	push_error("[worldsim] schedule '%s': offset fell through the phase list" % id)
	return Activity.RESTING


## The localization key for `activity`, or the RESTING key (loud) for an unknown ordinal — so
## presentation always has something to render and the bad ordinal is reported once here
## rather than surfacing as an empty label.
static func activity_name_key(activity: int) -> StringName:
	if activity < 0 or activity >= ACTIVITY_NAME_KEYS.size():
		push_error("[worldsim] no name key for activity ordinal %d" % activity)
		return ACTIVITY_NAME_KEYS[Activity.RESTING]
	return ACTIVITY_NAME_KEYS[activity]

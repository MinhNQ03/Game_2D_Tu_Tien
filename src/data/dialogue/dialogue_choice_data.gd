extends Resource
class_name DialogueChoiceData
## DialogueChoiceData — Aetheria data (one thing the player may say, Phase 18).
##
## `conditions` must ALL pass for the choice to be offered — and they are asked again when it
## is submitted. `effect` is its ONE consequence (or none); `next_node_id` is where the
## conversation goes, empty meaning it ends.
##
## SELF-LIMITING REGARD (D-066). Dialogue keeps no "already said" flag, so a choice that moves
## regard must carry a condition on the same dimension that its own delta eventually makes
## false: raise only while BELOW a value, lower only while AT OR ABOVE one. Without it a line
## could be repeated to walk a dimension to its bound.

@export var id: StringName = &""
@export var text_key: StringName = &""
@export var conditions: Array[DialogueConditionData] = []
@export var effect: DialogueEffectData = null
## The node this choice leads to. Empty = the conversation ends.
@export var next_node_id: StringName = &""


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("choice id is empty")
	if text_key == &"":
		errors.append("text_key is empty")
	for i in conditions.size():
		var condition := conditions[i]
		if condition == null:
			errors.append("condition %d is null" % i)
			continue
		for problem in condition.validation_errors():
			errors.append("condition %d: %s" % [i, problem])
	if effect == null:
		return errors
	for problem in effect.validation_errors():
		errors.append("effect: %s" % problem)
	if effect.kind == DialogueEffectData.Kind.OPEN_SHOP and next_node_id != &"":
		errors.append("an OPEN_SHOP choice hands the conversation over; it cannot continue to '%s'"
			% next_node_id)
	if effect.kind == DialogueEffectData.Kind.RELATIONSHIP_DELTA and effect.delta != 0 \
			and not _bounds_its_own_delta():
		errors.append(("moves '%s' by %d with no condition that stops it: add a "
			+ "RELATIONSHIP_AT_LEAST on '%s' (%s)") % [effect.dimension, effect.delta,
			effect.dimension, "negated, to raise only while below a value" if effect.delta > 0
			else "to lower only while at or above a value"])
	return errors


## True when a condition on the effect's dimension is one the delta walks toward failing.
func _bounds_its_own_delta() -> bool:
	for condition in conditions:
		if condition == null or condition.dimension != effect.dimension \
				or condition.kind != DialogueConditionData.Kind.RELATIONSHIP_AT_LEAST:
			continue
		if condition.negate == (effect.delta > 0):
			return true
	return false

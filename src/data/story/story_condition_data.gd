extends Resource
class_name StoryConditionData
## StoryConditionData — Aetheria data (one thing a story branch requires, Phase 20, D-072).
##
## A CLOSED set. Each kind is a question put to the owner of the answer — the story's own
## record, or the Knowledge Core. There is no "script" kind and no arbitrary expression.

enum Kind {
	## Flag `flag_id` reads at least `value` (a BOOL reads 0 or 1).
	FLAG,
	## The run's Origin is `origin_id`.
	ORIGIN,
	## Choice `choice_id` was answered with `option_id`.
	CHOICE,
	## The player holds `knowledge_id`.
	KNOWS,
}

@export var kind: Kind = Kind.FLAG
@export var flag_id: StringName = &""
@export var value: int = 1
@export var origin_id: StringName = &""
@export var choice_id: StringName = &""
@export var option_id: StringName = &""
@export var knowledge_id: StringName = &""
@export var negate: bool = false


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var used := {
		Kind.FLAG: flag_id, Kind.ORIGIN: origin_id, Kind.CHOICE: choice_id,
		Kind.KNOWS: knowledge_id,
	}
	if not used.has(kind):
		errors.append("unknown condition kind %d" % kind)
		return errors
	for other: int in used:
		if other != kind and used[other] != &"":
			errors.append("a %s condition carries the payload of another kind"
				% Kind.keys()[kind])
	if used[kind] == &"":
		errors.append("a %s condition names nothing" % Kind.keys()[kind])
	match kind:
		Kind.FLAG:
			if value < 1:
				errors.append("a FLAG condition asks for at least %d, which is always true"
					% value)
			if option_id != &"":
				errors.append("a FLAG condition carries an option_id")
		Kind.CHOICE:
			if option_id == &"":
				errors.append("a CHOICE condition names no option")
		_:
			if option_id != &"":
				errors.append("a %s condition carries an option_id" % Kind.keys()[kind])
	return errors


## Two conditions that can never both hold (so a branch requiring both is dead).
func contradicts(other: StoryConditionData) -> bool:
	if other == null or kind != other.kind:
		return false
	match kind:
		Kind.ORIGIN:
			if not negate and not other.negate:
				return origin_id != other.origin_id
			return origin_id == other.origin_id and negate != other.negate
		Kind.CHOICE:
			if choice_id != other.choice_id:
				return false
			if not negate and not other.negate:
				return option_id != other.option_id
			return option_id == other.option_id and negate != other.negate
		Kind.FLAG:
			if flag_id != other.flag_id or negate == other.negate:
				return false
			# "at least a" and "below b" cannot both hold when a >= b.
			var at_least := other.value if negate else value
			var below := value if negate else other.value
			return at_least >= below
		Kind.KNOWS:
			return knowledge_id == other.knowledge_id and negate != other.negate
	return false

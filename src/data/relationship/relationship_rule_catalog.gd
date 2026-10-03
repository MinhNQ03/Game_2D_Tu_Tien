extends Resource
class_name RelationshipRuleCatalog
## RelationshipRuleCatalog — Aetheria data (the authored set of event → delta rules).
##
## The data-driven list of `RelationshipRuleData` (mirrors `MapCatalog`'s aggregate pattern,
## D-022). The `RelationshipService` loads this catalog once and looks up a rule by
## `event_kind` when an event is applied. Adding a new event→relationship reaction is a data
## edit here, not a code change (`docs/RELATIONSHIP_SYSTEM.md` §5, extensibility rule).
##
## DATA only — boundary-validated. Keeping the rules as content (not code `match`
## statements) is what keeps relationship balancing in data.

## Every authored rule. Identity is by `event_kind`; order is not significant.
@export var rules: Array[RelationshipRuleData] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


## Validate: no null entries; each rule valid; event_kinds unique (a double-mapped event
## would be ambiguous).
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for i in rules.size():
		var rule: RelationshipRuleData = rules[i]
		if rule == null:
			errors.append("rules[%d] is null" % i)
			continue
		if not rule.is_valid():
			errors.append("rules[%d] (%s): %s" % [
				i, String(rule.event_kind), str(rule.validation_errors())])
		var ek := String(rule.event_kind)
		if ek != "":
			if seen.has(ek):
				errors.append("duplicate rule event_kind '%s'" % ek)
			seen[ek] = true
	return errors


## Build an `event_kind (StringName) -> RelationshipRuleData` lookup. Call once (session
## start), not per event dispatch loop — though a single dictionary get is cheap, the point
## is one authoritative map (`05-performance-testing.md`).
func build_lookup() -> Dictionary:
	var lookup := {}
	for rule in rules:
		if rule != null and rule.event_kind != &"":
			lookup[rule.event_kind] = rule
	return lookup

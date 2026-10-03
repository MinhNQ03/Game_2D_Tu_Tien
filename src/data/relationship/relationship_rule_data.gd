extends Resource
class_name RelationshipRuleData
## RelationshipRuleData — Aetheria data (one event → dimension-delta rule).
##
## The minimal, DETERMINISTIC contract that maps a domain event kind to relationship
## dimension deltas (`docs/RELATIONSHIP_SYSTEM.md` §5). This is NOT a rule-engine DSL — it is
## just data: "when event `event_kind` happens, apply these `{ dimension: delta }` to the
## target edge". No randomness, no scripting, no conditions beyond a simple optional
## `relationship_type` gate. Combat/quest/dialogue (later phases) emit the real events; Phase
## 05 only needs enough to prove `event X => affinity +N, trust +M` reproducibly.
##
## DATA only — boundary-validated. The `RelationshipService.apply_event` reads the matching
## rule and applies each delta through the single mutation path (so clamp + history + signal
## all still happen). Two applications of the same event on the same starting state give the
## same result.

## The event this rule reacts to (e.g. `HELPED_STRANGER`, `KEPT_PROMISE`, `BROKE_PROMISE`,
## `WON_FAIR_DUEL`, `INTIMIDATED_WEAK`). A StringName from the event vocabulary.
@export var event_kind: StringName = &""

## Dimension deltas to apply, keyed by dimension id. Values are ints (may be negative). Keys
## must be dimensions the config knows (validated by the service against the config).
##   e.g. { "affinity": 8, "trust": 5 }
@export var dimension_deltas: Dictionary = {}

## OPTIONAL gate: if non-empty, this rule only applies when the target edge's
## `relationship_type` equals this value. Empty = applies regardless of type. (Deliberately
## the ONLY condition in Phase 05 — richer conditions are a later phase, not a DSL now.)
@export var required_relationship_type: StringName = &""


func is_valid() -> bool:
	return validation_errors().is_empty()


## Validate at the boundary:
##   - event_kind non-empty
##   - at least one delta
##   - every delta key non-empty, every delta value a number
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if event_kind == &"":
		errors.append("event_kind must be non-empty")
	if dimension_deltas.is_empty():
		errors.append("rule '%s' has no dimension_deltas" % String(event_kind))
	for key in dimension_deltas:
		if String(key) == "":
			errors.append("rule '%s' has an empty delta key" % String(event_kind))
		var v: Variant = dimension_deltas[key]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			errors.append("rule '%s' delta '%s' is not a number" % [
				String(event_kind), String(key)])
	return errors


## True if this rule applies to an edge of `edge_type` (honors the optional type gate).
func applies_to_type(edge_type: StringName) -> bool:
	return required_relationship_type == &"" or required_relationship_type == edge_type

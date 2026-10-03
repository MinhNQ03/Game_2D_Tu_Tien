extends TestCase
## Unit tests for RelationshipRuleData + RelationshipRuleCatalog (Phase 05 — event→delta
## contract). Pure Resources; no tree, no autoloads.

const RuleScript := preload("res://src/data/relationship/relationship_rule_data.gd")
const CatalogScript := preload("res://src/data/relationship/relationship_rule_catalog.gd")
const RULES_PATH := "res://data/relationship/relationship_rules.tres"


func _rule(event: StringName, deltas: Dictionary, type_gate: StringName = &"") -> Resource:
	var r: Resource = RuleScript.new()
	r.event_kind = event
	r.dimension_deltas = deltas
	r.required_relationship_type = type_gate
	return r


func test_authored_rules_valid_and_mapped() -> void:
	var cat: Resource = load(RULES_PATH)
	assert_not_null(cat, "relationship_rules.tres loads")
	assert_true(cat.is_valid(), "authored rules valid: %s" % str(cat.validation_errors()))
	var lookup: Dictionary = cat.build_lookup()
	assert_true(lookup.has(&"HELPED_STRANGER"), "HELPED_STRANGER rule present")
	assert_true(lookup.has(&"BROKE_PROMISE"), "BROKE_PROMISE rule present")
	var helped: Resource = lookup[&"HELPED_STRANGER"]
	assert_eq(int(helped.dimension_deltas["affinity"]), 8, "authored affinity delta")


func test_rule_requires_event_and_deltas() -> void:
	assert_false(_rule(&"", {"trust": 1}).is_valid(), "empty event_kind invalid")
	assert_false(_rule(&"X", {}).is_valid(), "no deltas invalid")
	assert_true(_rule(&"X", {"trust": 1}).is_valid(), "well-formed rule valid")


func test_duplicate_event_kind_rejected() -> void:
	var cat: Resource = CatalogScript.new()
	cat.rules = [_rule(&"X", {"trust": 1}), _rule(&"X", {"affinity": 1})]
	assert_false(cat.is_valid(), "duplicate event_kind invalid")


func test_type_gate() -> void:
	var gated := _rule(&"X", {"trust": 1}, &"MASTER_DISCIPLE")
	assert_true(gated.applies_to_type(&"MASTER_DISCIPLE"), "applies to matching type")
	assert_false(gated.applies_to_type(&"RIVAL"), "does not apply to a different type")
	var ungated := _rule(&"Y", {"trust": 1})
	assert_true(ungated.applies_to_type(&"ANYTHING"), "ungated rule applies to any type")

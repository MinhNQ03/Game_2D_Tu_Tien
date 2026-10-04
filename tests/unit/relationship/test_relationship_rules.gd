extends TestCase
## Unit tests for RelationshipRuleData + RelationshipRuleCatalog (Phase 05 — event→delta
## contract). Pure Resources; no tree, no autoloads.

const RuleScript := preload("res://src/data/relationship/relationship_rule_data.gd")
const CatalogScript := preload("res://src/data/relationship/relationship_rule_catalog.gd")
const RULES_PATH := "res://data/relationship/relationship_rules.tres"


## Returns the CONCRETE type, not `Resource`: `RelationshipRuleCatalog.rules` is
## `Array[RelationshipRuleData]`, so an array of statically-`Resource` values cannot be
## assigned to it. See `_catalog()` for why that mattered.
func _rule(event: StringName, deltas: Dictionary,
		type_gate: StringName = &"") -> RelationshipRuleData:
	var r: RelationshipRuleData = RuleScript.new()
	r.event_kind = event
	r.dimension_deltas = deltas
	r.required_relationship_type = type_gate
	return r


## Build a catalog fixture with a properly TYPED rules array.
##
## `rules` is `Array[RelationshipRuleData]`; assigning an untyped array (or one whose elements
## are statically `Resource`) raises `Invalid assignment of property 'rules' with value of
## type 'Array'`. That GDScript VM error aborts the running function, so the test method died
## before its assertion ran — and since the runner only counts recorded assertion failures, it
## reported PASS while testing nothing (fixed in the D-037 follow-up; the headless gate now
## fails on any `SCRIPT ERROR:`).
func _catalog(rules: Array[RelationshipRuleData]) -> RelationshipRuleCatalog:
	var cat: RelationshipRuleCatalog = CatalogScript.new()
	cat.rules = rules
	return cat


func test_authored_rules_valid_and_mapped() -> void:
	var cat := load(RULES_PATH) as RelationshipRuleCatalog
	assert_not_null(cat, "relationship_rules.tres loads")
	assert_true(cat.is_valid(), "authored rules valid: %s" % str(cat.validation_errors()))
	var lookup: Dictionary = cat.build_lookup()
	assert_true(lookup.has(&"HELPED_STRANGER"), "HELPED_STRANGER rule present")
	assert_true(lookup.has(&"BROKE_PROMISE"), "BROKE_PROMISE rule present")
	var helped: RelationshipRuleData = lookup[&"HELPED_STRANGER"]
	assert_eq(int(helped.dimension_deltas["affinity"]), 8, "authored affinity delta")


func test_rule_requires_event_and_deltas() -> void:
	assert_false(_rule(&"", {"trust": 1}).is_valid(), "empty event_kind invalid")
	assert_false(_rule(&"X", {}).is_valid(), "no deltas invalid")
	assert_true(_rule(&"X", {"trust": 1}).is_valid(), "well-formed rule valid")


func test_duplicate_event_kind_rejected() -> void:
	var rules: Array[RelationshipRuleData] = [
		_rule(&"X", {"trust": 1}), _rule(&"X", {"affinity": 1}),
	]
	var cat := _catalog(rules)
	# Prove the fixture actually carries both rules. An empty `rules` array is VALID (no
	# duplicates to find), so a silently-failed assignment would have made the assertion
	# below fail rather than pass — but only if it ever ran, which it did not.
	assert_eq(cat.rules.size(), 2, "the fixture actually carries both rules")
	assert_false(cat.is_valid(), "duplicate event_kind invalid")
	assert_true(" | ".join(cat.validation_errors()).contains("duplicate rule event_kind 'X'"),
		"the reason names the duplicated event kind: %s" % str(cat.validation_errors()))
	# A catalog with the SAME two rules under distinct event kinds is accepted, so the
	# rejection above is about the duplication and not about the fixture shape.
	var distinct: Array[RelationshipRuleData] = [
		_rule(&"X", {"trust": 1}), _rule(&"Y", {"affinity": 1}),
	]
	assert_true(_catalog(distinct).is_valid(), "distinct event kinds are accepted")


func test_type_gate() -> void:
	var gated := _rule(&"X", {"trust": 1}, &"MASTER_DISCIPLE")
	assert_true(gated.applies_to_type(&"MASTER_DISCIPLE"), "applies to matching type")
	assert_false(gated.applies_to_type(&"RIVAL"), "does not apply to a different type")
	var ungated := _rule(&"Y", {"trust": 1})
	assert_true(ungated.applies_to_type(&"ANYTHING"), "ungated rule applies to any type")

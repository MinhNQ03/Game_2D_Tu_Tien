extends TestCase
## Unit tests for the domain damage rule (src/domain/combat/damage_rules.gd).
## Pure static function — no nodes, no autoloads, fully deterministic (high-risk: damage).

const DamageRulesScript := preload("res://src/domain/combat/damage_rules.gd")


func test_zero_defense_is_full_attack() -> void:
	# defense 0 => defense_factor 1.0 => damage == attack.
	assert_eq(DamageRulesScript.compute_hit(20, 0), 20, "no defense => full attack")


func test_defense_reduces_damage() -> void:
	# attack 20, defense 100 => 20 * 100/200 = 10.
	assert_eq(DamageRulesScript.compute_hit(20, 100), 10, "defense halves at def==scale")


func test_minimum_damage_is_one() -> void:
	# Tiny attack vs huge defense still deals at least MIN_DAMAGE (never 0 on a landed hit).
	assert_eq(DamageRulesScript.compute_hit(1, 100000), 1, "landed hit floors at 1")


func test_zero_attack_still_floors_at_one() -> void:
	# A 0-attack hit is still a landed hit → floored to 1 (DATA_SCHEMA §2 max(1, …)).
	assert_eq(DamageRulesScript.compute_hit(0, 0), 1, "zero attack floors to 1")


func test_negative_inputs_treated_as_zero() -> void:
	# Defensive at the boundary: negatives clamp to 0, never produce a heal or garbage.
	assert_eq(DamageRulesScript.compute_hit(-50, 10), 1, "negative attack clamps to 0 -> 1")
	assert_eq(DamageRulesScript.compute_hit(20, -10), 20, "negative defense clamps to 0")


func test_deterministic_repeatable() -> void:
	# No RNG term: same inputs always give the same output.
	var a := DamageRulesScript.compute_hit(37, 23)
	var b := DamageRulesScript.compute_hit(37, 23)
	assert_eq(a, b, "damage rule is deterministic")


func test_higher_defense_never_increases_damage() -> void:
	var low := DamageRulesScript.compute_hit(50, 10)
	var high := DamageRulesScript.compute_hit(50, 200)
	assert_true(high <= low, "more defense never increases damage taken")

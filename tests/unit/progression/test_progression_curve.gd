extends TestCase
## Unit tests for `ProgressionCurveData` (Phase 11) — the authored level/XP curve.
##
## It covers the DERIVATION (level from cumulative XP, including every boundary the phase
## brief names) and the BOUNDARY VALIDATION that refuses malformed authoring.
##
## FIXTURE NOTE (L-026): `xp_to_next` is a typed `Array[int]` export. A typed export will not
## accept an untyped array, and that assignment raises a GDScript VM error which ABORTS the
## test method — which the runner reports as PASS, because it only counts recorded assertion
## failures. So every fixture builds a typed LOCAL and assigns that. `test_the_fixture_builds`
## below exists so a silently-empty fixture is a visible failure rather than a green no-op.

const CurveScript := preload("res://src/data/progression/progression_curve_data.gd")

const AUTHORED_CURVE := "res://data/progression/player_progression_curve.tres"


## A known-good 3-step curve: level 1→2 costs 20, 2→3 costs 45, 3→4 costs 80.
## Cumulative: level 2 at 20, level 3 at 65, level 4 at 145. Ceiling is level 4.
func _curve() -> ProgressionCurveData:
	var curve: ProgressionCurveData = CurveScript.new()
	curve.id = &"curve_test"
	curve.min_level = 1
	var costs: Array[int] = [20, 45, 80]
	curve.xp_to_next = costs
	return curve


# --- The fixture itself ------------------------------------------------------

func test_the_fixture_builds() -> void:
	var curve := _curve()
	assert_eq(curve.xp_to_next.size(), 3, "the typed cost array actually assigned")
	assert_true(curve.is_valid(), "and the known-good fixture is valid: %s"
		% str(curve.validation_errors()))


# --- Derivation --------------------------------------------------------------

func test_a_fresh_character_is_at_the_curves_minimum_level() -> void:
	var curve := _curve()
	assert_eq(curve.level_for_xp(0), 1, "0 XP is the minimum level")
	assert_eq(curve.xp_into_level(0), 0, "and no progress inside it")
	assert_eq(curve.cumulative_for_level(1), 0,
		"reaching the minimum level costs nothing by definition")


func test_one_xp_before_a_threshold_does_not_level() -> void:
	var curve := _curve()
	assert_eq(curve.level_for_xp(19), 1, "19 of 20 is still level 1")
	assert_eq(curve.xp_into_level(19), 19, "with 19 banked toward the next")


func test_an_exact_threshold_levels() -> void:
	var curve := _curve()
	# The boundary that is easiest to get wrong by one: spending the LAST point of a cost
	# must level, not leave the character one short forever.
	assert_eq(curve.level_for_xp(20), 2, "exactly 20 reaches level 2")
	assert_eq(curve.xp_into_level(20), 0, "and starts the new level at zero progress")
	assert_eq(curve.progress_fraction(20), 0.0, "so the meter reads empty, not full")


func test_one_xp_after_a_threshold_keeps_the_overflow() -> void:
	var curve := _curve()
	assert_eq(curve.level_for_xp(21), 2, "21 is level 2")
	assert_eq(curve.xp_into_level(21), 1,
		"and the 1 XP past the threshold is PRESERVED, not discarded")


func test_cumulative_totals_match_the_authored_steps() -> void:
	var curve := _curve()
	assert_eq(curve.cumulative_for_level(2), 20, "level 2 at 20")
	assert_eq(curve.cumulative_for_level(3), 65, "level 3 at 20+45")
	assert_eq(curve.cumulative_for_level(4), 145, "level 4 at 20+45+80")
	# And the derivation agrees with the cumulative table at every one of its own thresholds,
	# which is the invariant that keeps the meter's numerator and the level from disagreeing.
	for level in [2, 3, 4]:
		assert_eq(curve.level_for_xp(curve.cumulative_for_level(level)), level,
			"level_for_xp is the inverse of cumulative_for_level at level %d" % level)


func test_a_single_large_total_crosses_several_levels_at_once() -> void:
	var curve := _curve()
	assert_eq(curve.level_for_xp(145), 4, "145 reaches the ceiling level in one step")
	assert_eq(curve.level_for_xp(100), 3, "100 lands mid-level-3")
	assert_eq(curve.xp_into_level(100), 35, "with 100-65 banked inside it")


func test_progress_fraction_is_bounded_and_meaningful() -> void:
	var curve := _curve()
	assert_eq(curve.progress_fraction(0), 0.0, "nothing earned reads empty")
	assert_true(absf(curve.progress_fraction(10) - 0.5) < 0.001,
		"half of the first level's 20 reads as half")
	assert_eq(curve.progress_fraction(19), 0.95, "19/20")
	# At the ceiling the meter reads COMPLETE, not empty: there is no next level, and 0.0
	# there would render as "no progress" on a character who has earned the whole curve.
	assert_eq(curve.progress_fraction(145), 1.0, "the ceiling reads complete")
	assert_eq(curve.progress_fraction(99999), 1.0, "and stays complete beyond it")


func test_negative_total_clamps_instead_of_running_backwards() -> void:
	var curve := _curve()
	# The service rejects a negative grant at the boundary; this stays total rather than
	# trusting it to, because a negative level would be a state the game cannot render.
	assert_eq(curve.level_for_xp(-500), 1, "a negative total still reads as the minimum level")
	assert_eq(curve.xp_into_level(-500), 0, "with no progress inside it")


# --- The ceiling -------------------------------------------------------------

func test_the_ceiling_is_derived_from_the_authored_data() -> void:
	var curve := _curve()
	assert_eq(curve.max_level(), 4, "3 authored steps from level 1 reach level 4")
	assert_false(curve.is_ceiling(3), "level 3 still has a step above it")
	assert_true(curve.is_ceiling(4), "level 4 is the top")
	assert_true(curve.is_ceiling(99), "and anything above it is also the top")
	assert_eq(curve.cost_from(4), 0, "there is no cost to leave the top level")
	# EXTENDING the range must be pure content. Appending one step moves the ceiling with no
	# code change, which is the property that keeps the maximum a data fact rather than a
	# constant someone has to find.
	var longer: Array[int] = [20, 45, 80, 130]
	curve.xp_to_next = longer
	assert_eq(curve.max_level(), 5, "appending one authored step raises the ceiling to 5")


func test_a_level_below_the_curve_start_costs_nothing_rather_than_indexing_backwards() -> void:
	var curve := _curve()
	curve.min_level = 5
	assert_eq(curve.cost_from(4), 0,
		"a level under the curve's start returns 0 instead of reading off the array's front")
	assert_eq(curve.level_for_xp(0), 5, "and a fresh character starts at the authored minimum")


# --- Boundary validation -----------------------------------------------------

func test_an_empty_id_is_rejected() -> void:
	var curve := _curve()
	curve.id = &""
	assert_false(curve.is_valid(), "a curve with no id is invalid")
	assert_true(str(curve.validation_errors()).contains("id is empty"),
		"and the error names the id (got %s)" % str(curve.validation_errors()))


func test_an_empty_cost_array_is_rejected() -> void:
	var curve := _curve()
	var empty: Array[int] = []
	curve.xp_to_next = empty
	assert_false(curve.is_valid(), "a curve with no steps is invalid")
	assert_true(str(curve.validation_errors()).contains("empty"),
		"and the error says so (got %s)" % str(curve.validation_errors()))


func test_a_zero_or_negative_step_is_rejected() -> void:
	for bad_cost in [0, -5]:
		var curve := _curve()
		var costs: Array[int] = [20, bad_cost, 80]
		curve.xp_to_next = costs
		assert_false(curve.is_valid(), "a step of %d is invalid" % bad_cost)
		assert_true(str(curve.validation_errors()).contains("must be > 0"),
			"and the error names the reason for %d (got %s)"
				% [bad_cost, str(curve.validation_errors())])


func test_a_decreasing_curve_is_rejected_but_a_plateau_is_allowed() -> void:
	var dropping := _curve()
	var down: Array[int] = [20, 45, 30]
	dropping.xp_to_next = down
	assert_false(dropping.is_valid(), "a later level that is CHEAPER inverts the ramp")
	assert_true(str(dropping.validation_errors()).contains("must not decrease"),
		"and the error names the ordering (got %s)" % str(dropping.validation_errors()))

	# A plateau is a legitimate design choice (two levels costing the same), so it must NOT
	# be swept up by the ordering rule — the rule exists to stop an inversion, not to force
	# strictly increasing numbers.
	var flat := _curve()
	var plateau: Array[int] = [20, 45, 45, 80]
	flat.xp_to_next = plateau
	assert_true(flat.is_valid(), "a plateau is legal: %s" % str(flat.validation_errors()))


func test_a_minimum_level_below_one_is_rejected() -> void:
	var curve := _curve()
	curve.min_level = 0
	assert_false(curve.is_valid(), "level 0 is not a level this game has")
	assert_true(str(curve.validation_errors()).contains("min_level"),
		"and the error names it (got %s)" % str(curve.validation_errors()))


func test_validation_reports_every_problem_at_once() -> void:
	# A validator that stops at the first problem makes fixing authored content a sequence of
	# round trips. This one names them all.
	var curve: ProgressionCurveData = CurveScript.new()
	curve.id = &""
	curve.min_level = -3
	var costs: Array[int] = [10, 4]
	curve.xp_to_next = costs
	var errors := curve.validation_errors()
	assert_true(errors.size() >= 3,
		"an id, a min_level and an ordering problem are all reported (got %s)" % str(errors))


# --- The AUTHORED curve the game actually ships ------------------------------

func test_the_shipped_curve_loads_and_is_valid() -> void:
	assert_true(ResourceLoader.exists(AUTHORED_CURVE),
		"the authored curve exists at %s" % AUTHORED_CURVE)
	var curve := load(AUTHORED_CURVE) as ProgressionCurveData
	assert_not_null(curve, "it loads as a ProgressionCurveData")
	if curve == null:
		return
	assert_true(curve.is_valid(), "and it is valid: %s" % str(curve.validation_errors()))
	assert_eq(curve.min_level, 1, "the player curve starts at level 1")
	assert_true(curve.xp_to_next.size() >= 10,
		"and authors enough levels that a playtest cannot trivially reach the ceiling (got %d)"
			% curve.xp_to_next.size())


## The FIRST level must be reachable from ONE authored kill.
##
## This is a game-feel contract worth pinning, not an implementation detail: the first
## level-up is the moment the player learns that the progression loop exists, and if it takes
## several fights to arrive, the feature reads as absent during exactly the window when the
## player is deciding whether it is there. It also keeps the real-app E2E and the playtest
## harness able to observe a level change from a single reproducible encounter.
func test_one_authored_kill_reaches_the_first_level_up() -> void:
	var curve := load(AUTHORED_CURVE) as ProgressionCurveData
	var wolf := load("res://data/enemies/enemy_mist_wolf.tres") as EnemyData
	assert_not_null(curve, "the curve loads")
	assert_not_null(wolf, "the authored creature loads")
	if curve == null or wolf == null:
		return
	assert_true(wolf.xp_reward > 0, "the creature is worth something (got %d)" % wolf.xp_reward)
	assert_true(wolf.xp_reward >= curve.cost_from(curve.min_level),
		("one %s (%d XP) must reach level %d, which costs %d — the first level-up is where "
			+ "the player learns the loop exists")
			% [String(wolf.id), wolf.xp_reward, curve.min_level + 1,
				curve.cost_from(curve.min_level)])

extends TestCase
## Unit tests for `ProgressionService` (Phase 11) — THE one authoritative XP/level mutator.
##
## This file is where the phase's mutation contract is held to account: validate → compute →
## commit atomically → report. It covers every threshold boundary the brief names (exact, one
## before, one after, overflow, multi-level, large, repeated), the invariants (XP monotonic,
## level never derived below the curve's minimum), and the REJECTION paths with their reasons
## pinned — a negative test that only checks `accepted == false` passes for the wrong reason
## (L-024), so each one also asserts the reported reason AND that the state is untouched.
##
## No Node, no tree: the service is pure domain, which is the whole point of it being separate
## from `ProgressionRuntime`.

const CurveScript := preload("res://src/data/progression/progression_curve_data.gd")
const ServiceScript := preload("res://src/domain/progression/progression_service.gd")
const ResultScript := preload("res://src/domain/progression/progression_result.gd")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")


## The same 3-step curve the curve tests use: 20 / 45 / 80, ceiling at level 4 (145 XP).
func _curve() -> ProgressionCurveData:
	var curve: ProgressionCurveData = CurveScript.new()
	curve.id = &"curve_test"
	curve.min_level = 1
	var costs: Array[int] = [20, 45, 80]
	curve.xp_to_next = costs
	return curve


func _service() -> ProgressionService:
	return ServiceScript.new(_curve())


func _character() -> CharacterState:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var template: CharacterTemplateData = TemplateScript.new()
	template.id = &"char_test"
	template.name_key = &"NAME_TEST"
	template.base_stats = stats
	return StateScript.create_from_template(template, &"inst_test")


# --- Fixtures ----------------------------------------------------------------

func test_the_fixtures_build() -> void:
	var service := _service()
	assert_true(service.is_ready(), "the service accepted the known-good curve")
	var state := _character()
	assert_not_null(state, "a CharacterState is built from the template")
	if state == null:
		return
	assert_eq(state.xp, 0, "a fresh character has earned nothing")
	assert_eq(service.level_of(state), 1, "and derives as level 1")


# --- Readiness ---------------------------------------------------------------

func test_a_service_with_no_curve_is_not_ready_and_mutates_nothing() -> void:
	var service: ProgressionService = ServiceScript.new()
	assert_false(service.is_ready(), "no curve means not ready")
	var state := _character()
	state.set_total_xp(7)
	var result := service.grant_xp(state, 100)
	assert_false(result.accepted, "a grant with no curve is rejected")
	assert_eq(result.reason, ResultScript.REASON_NO_CURVE, "and names the missing curve")
	assert_eq(state.xp, 7, "the character is untouched")


func test_an_invalid_curve_is_refused_at_construction() -> void:
	var bad: ProgressionCurveData = CurveScript.new()
	bad.id = &""  # invalid: no id, no steps
	var service: ProgressionService = ServiceScript.new(bad)
	assert_false(service.is_ready(),
		"an invalid curve leaves the service not ready, so the owner fails closed")
	assert_null(service.curve(), "and no curve is bound")


# --- The threshold boundaries ------------------------------------------------

func test_a_zero_grant_is_a_legal_no_op() -> void:
	var service := _service()
	var state := _character()
	var result := service.grant_xp(state, 0)
	# 0 is AUTHORED CONTENT (a creature worth nothing), not an error — so it commits and
	# reports honestly rather than being rejected.
	assert_true(result.accepted, "a zero grant is accepted")
	assert_eq(result.xp_applied, 0, "and applies nothing")
	assert_false(result.leveled(), "and cannot level")
	assert_eq(state.xp, 0, "the character is unchanged")


func test_one_xp_short_of_the_threshold_does_not_level() -> void:
	var service := _service()
	var state := _character()
	var result := service.grant_xp(state, 19)
	assert_true(result.accepted, "the grant commits")
	assert_eq(state.xp, 19, "XP accumulated")
	assert_eq(result.level_after, 1, "but 19 of 20 is still level 1")
	assert_false(result.leveled(), "so no level transition is reported")
	assert_eq(service.xp_into_level(state), 19, "19 banked toward the next level")
	assert_eq(service.xp_for_next_level(state), 20, "against a cost of 20")


func test_the_exact_threshold_levels_and_resets_the_meter() -> void:
	var service := _service()
	var state := _character()
	var result := service.grant_xp(state, 20)
	assert_true(result.leveled(), "spending the LAST point of a cost levels")
	assert_eq(result.level_before, 1, "from level 1")
	assert_eq(result.level_after, 2, "to level 2")
	assert_eq(result.levels_gained(), 1, "exactly one level")
	assert_eq(service.xp_into_level(state), 0, "the new level starts empty")
	assert_eq(service.xp_for_next_level(state), 45, "with the next step's cost")


func test_one_xp_past_the_threshold_preserves_the_overflow() -> void:
	var service := _service()
	var state := _character()
	service.grant_xp(state, 21)
	assert_eq(service.level_of(state), 2, "level 2")
	assert_eq(service.xp_into_level(state), 1,
		"and the 1 XP of overflow is CARRIED, not discarded — losing it would make a big "
		+ "reward worth less than two small ones")


func test_one_grant_can_cross_several_thresholds_at_once() -> void:
	var service := _service()
	var state := _character()
	# 20 + 45 + 80 = 145 reaches level 4 from level 1 in a single grant.
	var result := service.grant_xp(state, 145)
	assert_eq(result.level_before, 1, "from level 1")
	assert_eq(result.level_after, 4, "straight to level 4")
	assert_eq(result.levels_gained(), 3, "three levels in one grant")
	assert_eq(state.xp, 145, "and all the XP is banked")


func test_a_very_large_grant_lands_at_the_ceiling_without_overrunning_the_curve() -> void:
	var service := _service()
	var state := _character()
	var result := service.grant_xp(state, 10_000_000)
	assert_true(result.accepted, "a huge grant still commits")
	assert_eq(result.level_after, 4,
		"and stops at the authored ceiling rather than reading past the cost array")
	assert_true(service.is_at_ceiling(state), "the character is at the ceiling")
	assert_eq(state.xp, 10_000_000, "the XP total itself is not clamped")


func test_repeated_grants_accumulate_and_level_monotonically() -> void:
	var service := _service()
	var state := _character()
	var last_level := service.level_of(state)
	var last_xp := state.xp
	# Seven grants of 10: 10,20,30,...,70 cumulative. Levels at 20 and 65.
	for i in 7:
		var result := service.grant_xp(state, 10)
		assert_true(result.accepted, "grant %d commits" % i)
		assert_true(state.xp > last_xp, "XP strictly increases on a positive grant")
		assert_true(service.level_of(state) >= last_level,
			"level never goes DOWN (monotonic by derivation)")
		last_xp = state.xp
		last_level = service.level_of(state)
	assert_eq(state.xp, 70, "seven grants of 10")
	assert_eq(service.level_of(state), 3, "which crosses 20 and 65")
	assert_eq(service.xp_into_level(state), 5, "with 70-65 inside level 3")


# --- Rejections, with the reason pinned --------------------------------------

func test_a_negative_grant_is_rejected_and_changes_nothing() -> void:
	var service := _service()
	var state := _character()
	service.grant_xp(state, 50)
	var before := state.xp
	var level_before := service.level_of(state)
	var result := service.grant_xp(state, -30)
	assert_false(result.accepted, "a negative grant is refused")
	assert_eq(result.reason, ResultScript.REASON_NEGATIVE_AMOUNT, "and names the reason")
	assert_eq(state.xp, before, "XP is untouched — progress is never taken away")
	assert_eq(service.level_of(state), level_before, "and so is the level")
	assert_eq(result.xp_applied, 0, "the result reports nothing applied")


func test_a_grant_at_the_ceiling_is_rejected_rather_than_silently_swallowed() -> void:
	var service := _service()
	var state := _character()
	service.grant_xp(state, 145)  # straight to the ceiling
	assert_true(service.is_at_ceiling(state), "at the ceiling")
	var before := state.xp
	var result := service.grant_xp(state, 500)
	assert_false(result.accepted, "further XP is refused at the top of the curve")
	assert_eq(result.reason, ResultScript.REASON_AT_CEILING,
		"and the reason distinguishes 'nothing left to earn' from a failure")
	assert_eq(state.xp, before,
		"the total does not grow toward a level that cannot arrive")
	# And the view-facing answers stay honest there rather than reading as 0 / 0 progress.
	assert_eq(service.progress_fraction(state), 1.0, "the meter reads COMPLETE at the ceiling")


func test_a_null_state_is_rejected() -> void:
	var service := _service()
	var result := service.grant_xp(null, 10)
	assert_false(result.accepted, "there is nothing to grant to")
	assert_eq(result.reason, ResultScript.REASON_NO_STATE, "and the reason says so")


# --- The result object -------------------------------------------------------

func test_the_result_reports_the_whole_transition() -> void:
	var service := _service()
	var state := _character()
	service.grant_xp(state, 10)
	var result := service.grant_xp(state, 60)
	assert_eq(result.xp_before, 10, "before")
	assert_eq(result.xp_after, 70, "after")
	assert_eq(result.xp_applied, 60, "applied")
	assert_eq(result.level_before, 1, "level before")
	assert_eq(result.level_after, 3, "level after")
	assert_true(result.leveled(), "it leveled")
	assert_eq(result.levels_gained(), 2, "by two")
	assert_true(result.describe().contains("1->3") or result.describe().contains("1->3"),
		"and describes itself usefully for a failure message (got '%s')" % result.describe())


# --- Determinism -------------------------------------------------------------

func test_the_same_inputs_always_produce_the_same_outputs() -> void:
	# No RNG anywhere in progression (D-040 reserves the seeded stream for the simulation and
	# combat), so the same grant sequence must land on the same numbers every time. A test
	# that runs it twice is what keeps a future "bonus XP roll" from being added here quietly.
	var totals: Array[int] = []
	var levels: Array[int] = []
	for _run in 2:
		var service := _service()
		var state := _character()
		for amount in [7, 13, 1, 44, 90]:
			service.grant_xp(state, amount)
		totals.append(state.xp)
		levels.append(service.level_of(state))
	assert_eq(totals[0], totals[1], "the same grants produce the same total (%s)" % str(totals))
	assert_eq(levels[0], levels[1], "and the same level (%s)" % str(levels))


# --- The level is DERIVED, not stored ---------------------------------------

## The central architectural claim of Phase 11, asserted rather than only documented: there is
## no stored level, so re-deriving from the same XP with a RETUNED curve re-levels the
## character — and no second number can be left disagreeing with the first.
func test_level_follows_the_curve_because_it_is_never_stored() -> void:
	var state := _character()
	state.set_total_xp(100)

	var original := _service()
	assert_eq(original.level_of(state), 3, "100 XP is level 3 on the shipped-shape curve")

	# A balance patch makes every level twice as expensive. The SAME stored XP must now read
	# as a lower level, with nothing migrated and no field rewritten.
	var retuned: ProgressionCurveData = CurveScript.new()
	retuned.id = &"curve_retuned"
	retuned.min_level = 1
	var dearer: Array[int] = [40, 90, 160]
	retuned.xp_to_next = dearer
	var patched: ProgressionService = ServiceScript.new(retuned)
	assert_eq(patched.level_of(state), 2,
		"the same 100 XP re-derives as level 2 against the dearer curve")
	assert_eq(state.xp, 100, "and the stored value — the only stored value — did not change")


func test_the_state_clamps_a_negative_total_at_its_own_boundary() -> void:
	# Defence in depth: the service refuses a negative GRANT, and the field refuses a negative
	# TOTAL. Either alone would be enough for the current call path; both together mean a
	# future writer cannot produce a negative total by going around the service.
	var state := _character()
	state.set_total_xp(-99)
	assert_eq(state.xp, 0, "a negative total clamps to zero")

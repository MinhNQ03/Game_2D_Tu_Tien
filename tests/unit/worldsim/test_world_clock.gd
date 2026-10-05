extends TestCase
## Unit tests for `WorldClock` (Phase 08).
##
## The clock has three contractual properties and they are what this file pins: it is
## MONOTONIC, it is advanced EXPLICITLY (no wall clock), and its calendar is DATA. The derived
## date is a pure function of one stored integer, so the tests mostly check that the
## arithmetic cannot be wrong at a boundary — hour 0 vs hour 1, day 30 vs day 31, the year
## rollover — which is where a calendar conversion actually breaks.

const ClockScript := preload("res://src/domain/worldsim/world_clock.gd")

## A small readable calendar: 2 ticks per hour, 4 hours per day, 3 days per season, 2 seasons
## per year. So one day is 8 ticks, one season 24, one year 48 — numbers small enough to check
## by hand, which is the point of a fixture.
const TPH := 2
const HPD := 4
const DPS := 3
const SPY := 2
const TICKS_PER_DAY := TPH * HPD          # 8
const TICKS_PER_SEASON := TICKS_PER_DAY * DPS   # 24
const TICKS_PER_YEAR := TICKS_PER_SEASON * SPY  # 48


func _clock() -> WorldClock:
	return ClockScript.new(TPH, HPD, DPS, SPY)


# === 1-2. Construction ======================================================

func test_01_a_well_formed_calendar_is_valid() -> void:
	var clock := _clock()
	assert_true(clock.is_valid(), "a positive calendar is valid")
	assert_eq(clock.tick(), 0, "a fresh clock starts at tick 0")
	assert_eq(clock.ticks_per_day(), TICKS_PER_DAY, "ticks per day is derived")
	assert_eq(clock.ticks_per_season(), TICKS_PER_SEASON, "and ticks per season")
	assert_eq(clock.ticks_per_year(), TICKS_PER_YEAR, "and ticks per year")


## Any non-positive unit leaves the clock INVALID rather than substituting a default. A
## substituted calendar would silently change what every authored tick cost in the catalog
## means, which is worse than refusing to start.
func test_02_a_non_positive_unit_invalidates_the_clock() -> void:
	for bad in [
		ClockScript.new(0, HPD, DPS, SPY), ClockScript.new(TPH, 0, DPS, SPY),
		ClockScript.new(TPH, HPD, 0, SPY), ClockScript.new(TPH, HPD, DPS, 0),
		ClockScript.new(-1, HPD, DPS, SPY),
	]:
		var clock: WorldClock = bad
		assert_false(clock.is_valid(), "a non-positive unit invalidates")
		assert_false(clock.advance(1), "and an invalid clock refuses to advance")
		assert_eq(clock.tick(), 0, "staying at tick 0")


# === 3-4. Advancement =======================================================

func test_03_advance_is_monotonic_and_additive() -> void:
	var clock := _clock()
	assert_true(clock.advance(5), "advancing 5 succeeds")
	assert_eq(clock.tick(), 5, "the tick moved")
	assert_true(clock.advance(7), "advancing again succeeds")
	assert_eq(clock.tick(), 12, "advances accumulate")
	# One advance of N equals N advances of 1 — the property the catch-up logic relies on.
	var stepped := _clock()
	for _i in 12:
		stepped.advance(1)
	assert_eq(stepped.tick(), clock.tick(), "12 single steps equal one 12-tick advance")


## A non-positive count is an ERROR, not a silent no-op. Every caller computes its tick count
## from authored data, so zero means that data is wrong — and a clock that reported success
## while standing still would hide a world that had stopped evolving.
func test_04_a_non_positive_advance_is_rejected() -> void:
	var clock := _clock()
	clock.advance(3)
	assert_false(clock.advance(0), "advancing by 0 is rejected")
	assert_false(clock.advance(-5), "advancing backwards is rejected")
	assert_eq(clock.tick(), 3, "and the clock did not move either way (it is monotonic)")


# === 5-7. The derived calendar ==============================================

## Boundary-by-boundary, because an off-by-one in a calendar conversion is invisible in the
## middle of a day and obvious only at the edges.
func test_05_the_date_is_derived_at_every_boundary() -> void:
	var clock := _clock()
	# Tick 0: the world's first moment.
	assert_eq(clock.hour_of_day(), 0, "tick 0 is hour 0")
	assert_eq(clock.day_of_season(), 1, "tick 0 is day 1, not day 0 (it reads as a date)")
	assert_eq(clock.season_of_year(), 1, "season 1")
	assert_eq(clock.year(), 1, "year 1, not year 0")
	assert_eq(clock.total_days(), 0, "zero whole days have elapsed")

	# One tick before the first day ends.
	clock.advance(TICKS_PER_DAY - 1)
	assert_eq(clock.day_of_season(), 1, "still day 1 one tick before midnight")
	assert_eq(clock.hour_of_day(), HPD - 1, "at the last hour of the day")

	# Exactly one day.
	clock.advance(1)
	assert_eq(clock.total_days(), 1, "one whole day elapsed")
	assert_eq(clock.day_of_season(), 2, "and it is now day 2")
	assert_eq(clock.hour_of_day(), 0, "back to hour 0")


func test_06_season_and_year_roll_over() -> void:
	var clock := _clock()
	clock.advance(TICKS_PER_SEASON)
	assert_eq(clock.season_of_year(), 2, "a full season advances the season")
	assert_eq(clock.day_of_season(), 1, "and resets the day")
	assert_eq(clock.year(), 1, "still year 1")

	clock.advance(TICKS_PER_SEASON)
	assert_eq(clock.year(), 2, "two seasons make a year in this fixture")
	assert_eq(clock.season_of_year(), 1, "and the season resets")
	assert_eq(clock.day_of_season(), 1, "as does the day")


## The hour must advance WITHIN a day, not only at day boundaries — a `ticks_per_hour` of 2
## means two ticks per hour, and flooring it wrong would freeze the hour.
func test_07_the_hour_advances_within_a_day() -> void:
	var clock := _clock()
	var seen := {}
	for _i in HPD * TPH:
		seen[clock.hour_of_day()] = true
		clock.advance(1)
	assert_eq(seen.size(), HPD, "every hour of the day is visited exactly once per day")


# === 8-9. Serialization =====================================================

## The CALENDAR is serialized alongside the tick on purpose: a save must still mean the same
## date after the owner retunes `ticks_per_hour`, and without the calendar in the snapshot the
## same stored tick would silently become a different in-world date.
func test_08_the_clock_round_trips_with_its_calendar() -> void:
	var clock := _clock()
	clock.advance(TICKS_PER_YEAR + TICKS_PER_SEASON + TICKS_PER_DAY + 3)
	var snapshot := clock.to_dict()

	# Restore into a clock built with a DIFFERENT calendar, to prove the snapshot carries it.
	var restored: WorldClock = ClockScript.new(1, 1, 1, 1)
	assert_true(restored.from_dict(snapshot), "the snapshot hydrates")
	assert_eq(restored.tick(), clock.tick(), "the tick survives")
	assert_eq(restored.ticks_per_day(), TICKS_PER_DAY,
		"the CALENDAR came from the snapshot, not from how the clock was constructed")
	assert_eq(restored.year(), clock.year(), "so the derived year agrees")
	assert_eq(restored.season_of_year(), clock.season_of_year(), "and the season")
	assert_eq(restored.day_of_season(), clock.day_of_season(), "and the day")
	assert_eq(restored.hour_of_day(), clock.hour_of_day(), "and the hour")
	assert_eq(str(restored.to_dict()), str(snapshot), "and the round trip is byte-stable")
	assert_true(restored.is_valid(), "a restored clock is usable")


## Malformed payloads are REJECTED, never coerced (L-024). Each case differs from a known-good
## payload in exactly one field and would otherwise be accepted; a rejection leaves the
## receiver byte-identical.
func test_09_malformed_clock_payloads_fail_closed() -> void:
	var good := {
		"tick": 10, "ticks_per_hour": TPH, "hours_per_day": HPD,
		"days_per_season": DPS, "seasons_per_year": SPY,
	}
	var baseline := _clock()
	assert_true(baseline.from_dict(good.duplicate()),
		"the baseline payload IS accepted, so every rejection below is about its one change")

	var cases := {
		"tick": "10",                 # int("10") would invent a valid time
		"ticks_per_hour": 2.0,        # a float is not a tick count even when integral
		"hours_per_day": 0,           # a zero unit would divide by zero in the conversion
		"days_per_season": -1,
		"seasons_per_year": true,
	}
	var fields: Array = cases.keys()
	fields.sort()
	for field in fields:
		var clock := _clock()
		clock.advance(4)
		var before := str(clock.to_dict())
		var payload: Dictionary = good.duplicate()
		payload[field] = cases[field]
		assert_false(clock.from_dict(payload),
			"a wrong-typed/out-of-range '%s' is REJECTED, never coerced" % String(field))
		assert_eq(str(clock.to_dict()), before,
			"and the clock is byte-identical afterwards ('%s')" % String(field))

	# A negative tick is refused because the clock is monotonic — it could only come from a
	# corrupt snapshot, and accepting it would let scheduled events re-fire.
	var negative := _clock()
	var payload_negative: Dictionary = good.duplicate()
	payload_negative["tick"] = -1
	assert_false(negative.from_dict(payload_negative), "a negative tick is rejected")
	assert_false(negative.from_dict("not a dict"), "a non-dict payload is rejected")

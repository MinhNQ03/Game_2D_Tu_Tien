extends RefCounted
class_name WorldClock
## WorldClock — Aetheria domain (the monotonic, explicitly-advanced world clock).
##
## The world's sense of time (`docs/WORLD_SIMULATION.md` §3/§5). It is a TICK COUNTER with a
## deterministic conversion to in-world time, and nothing else.
##
## THREE PROPERTIES THAT ARE NOT NEGOTIABLE
##   1. **Monotonic.** `advance()` only ever moves forward; there is no setter that can move
##      the clock backwards. A clock that could go back would make the scheduled-event queue
##      (`WorldSimulationState`) able to re-fire events that had already happened.
##   2. **Explicitly advanced.** There is no `_process`, no `Timer`, no `Time.get_ticks_msec()`
##      and no `OS` call anywhere in this file. A caller advances it by an integer number of
##      ticks at an explicit gameplay beat. This is what makes a K-tick run reproducible and
##      testable without waiting real seconds, and it is also what
##      `MULTIPLAYER_PLAN.md` §7 lists as a corner-painting risk if done the other way: a
##      wall-clock world cannot be advanced by a server and kept in sync.
##   3. **Calendar is DATA.** How many ticks make an hour, hours a day, days a season and
##      seasons a year are authored on `WorldSimCatalog`, not constants here
##      (`04-coding-standards.md`: no hard-coded gameplay numbers). `WORLD_BIBLE.md` freezes
##      no calendar, so these are tuning values the owner can change without touching code.
##
## Day/season/year are DERIVED, never stored. Storing them beside the tick would create a
## second source of truth that a save could contradict (the L-014 drift class); with one
## stored integer, "what date is it" has exactly one answer.

## The smallest calendar a conversion can be built on. Zero or negative would make the
## derived fields divide by zero, so an invalid calendar is rejected at construction.
const MIN_UNIT := 1

## Monotonic tick count since the world began. The ONE stored value.
var _tick: int = 0

# --- Calendar (authored tuning; see the class note) --------------------------
var _ticks_per_hour: int = MIN_UNIT
var _hours_per_day: int = MIN_UNIT
var _days_per_season: int = MIN_UNIT
var _seasons_per_year: int = MIN_UNIT
var _valid: bool = false


## Build a clock with an authored calendar. Any non-positive unit leaves the clock INVALID
## (reported loudly); `WorldSimulationService` refuses to start on an invalid clock rather
## than quietly substituting a default calendar, because a substituted calendar would make
## every authored tick cost in the catalog mean something different from what was authored.
func _init(
		ticks_per_hour: int = MIN_UNIT,
		hours_per_day: int = MIN_UNIT,
		days_per_season: int = MIN_UNIT,
		seasons_per_year: int = MIN_UNIT) -> void:
	if ticks_per_hour < MIN_UNIT or hours_per_day < MIN_UNIT \
			or days_per_season < MIN_UNIT or seasons_per_year < MIN_UNIT:
		push_error(("[clock] invalid calendar (ticks/hour %d, hours/day %d, days/season %d, "
			+ "seasons/year %d): every unit must be >= %d")
			% [ticks_per_hour, hours_per_day, days_per_season, seasons_per_year, MIN_UNIT])
		return
	_ticks_per_hour = ticks_per_hour
	_hours_per_day = hours_per_day
	_days_per_season = days_per_season
	_seasons_per_year = seasons_per_year
	_valid = true


func is_valid() -> bool:
	return _valid


# --- Advancement (the only mutation) -----------------------------------------

## Move the clock forward by `count` ticks. Returns false (loud) for a non-positive count or
## an invalid clock, having changed nothing.
##
## A non-positive count is an ERROR rather than a no-op: every caller computes its tick count
## from authored data, so a zero or negative count means that data (or the arithmetic that
## produced it) is wrong, and silently accepting it would hide a world that has stopped
## evolving behind a clock that reports success.
func advance(count: int) -> bool:
	if not _valid:
		push_error("[clock] advance refused: the clock has an invalid calendar")
		return false
	if count <= 0:
		push_error("[clock] advance requires a positive tick count (got %d)" % count)
		return false
	_tick += count
	return true


# --- Reads (all derived from the single stored tick) -------------------------

func tick() -> int:
	return _tick


## Ticks per in-world day / season / year, derived from the authored units.
func ticks_per_day() -> int:
	return _ticks_per_hour * _hours_per_day


func ticks_per_season() -> int:
	return ticks_per_day() * _days_per_season


func ticks_per_year() -> int:
	return ticks_per_season() * _seasons_per_year


func ticks_per_hour() -> int:
	return _ticks_per_hour


func hours_per_day() -> int:
	return _hours_per_day


func days_per_season() -> int:
	return _days_per_season


func seasons_per_year() -> int:
	return _seasons_per_year


## Hour of the current day, in [0, hours_per_day).
func hour_of_day() -> int:
	return (_tick / _ticks_per_hour) % _hours_per_day


## Day of the current season, 1-based (so it reads as a date, not an array index).
func day_of_season() -> int:
	return ((_tick / ticks_per_day()) % _days_per_season) + 1


## Season of the current year, 1-based.
func season_of_year() -> int:
	return ((_tick / ticks_per_season()) % _seasons_per_year) + 1


## Year, 1-based (the world starts in year 1, not year 0).
func year() -> int:
	return (_tick / ticks_per_year()) + 1


## Total elapsed in-world days (0 on the first day). For "how long has the world been running"
## readouts and for tests that want one number instead of a date tuple.
func total_days() -> int:
	return _tick / ticks_per_day()


# --- Serialization -----------------------------------------------------------

## Serialize the clock. The authored calendar is written ALONGSIDE the tick on purpose: a save
## must still mean the same date after the owner retunes `ticks_per_hour` in the catalog, and
## without the calendar in the snapshot the same stored tick would silently become a different
## in-world date (the §3b "resume exactly" requirement applied to time rather than to RNG).
func to_dict() -> Dictionary:
	return {
		"tick": _tick,
		"ticks_per_hour": _ticks_per_hour,
		"hours_per_day": _hours_per_day,
		"days_per_season": _days_per_season,
		"seasons_per_year": _seasons_per_year,
	}


## Hydrate, STRICTLY typed and fail-closed, leaving the receiver unchanged on rejection.
## A float tick is rejected even when integral: `int(12.0)` and `int("12")` both produce a
## plausible time out of data that was never a tick count (L-024).
func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[clock] from_dict: payload is not a Dictionary")
		return false
	var dict: Dictionary = data

	if dict.has("tick") and typeof(dict["tick"]) != TYPE_INT:
		push_error("[clock] from_dict: 'tick' must be an int (got %s)"
			% type_string(typeof(dict["tick"])))
		return false
	var in_tick: int = dict.get("tick", 0)
	if in_tick < 0:
		push_error("[clock] from_dict: tick must be >= 0 (got %d); the clock is monotonic"
			% in_tick)
		return false

	var units := {}
	for field in ["ticks_per_hour", "hours_per_day", "days_per_season", "seasons_per_year"]:
		var key := String(field)
		if dict.has(key) and typeof(dict[key]) != TYPE_INT:
			push_error("[clock] from_dict: '%s' must be an int (got %s)"
				% [key, type_string(typeof(dict[key]))])
			return false
		var value: int = dict.get(key, MIN_UNIT)
		if value < MIN_UNIT:
			push_error("[clock] from_dict: %s must be >= %d (got %d)"
				% [key, MIN_UNIT, value])
			return false
		units[key] = value

	_tick = in_tick
	_ticks_per_hour = int(units["ticks_per_hour"])
	_hours_per_day = int(units["hours_per_day"])
	_days_per_season = int(units["days_per_season"])
	_seasons_per_year = int(units["seasons_per_year"])
	_valid = true
	return true

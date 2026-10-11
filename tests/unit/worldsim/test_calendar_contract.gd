extends TestCase
## THE CALENDAR FLOOR IS ONE FACT WITH THREE READERS (Q19-05).
##
## `WorldSimCatalog` validates the authored calendar, `WorldClock` refuses to be built on or
## hydrated with a bad one, and `WorldSimulationState` falls back to the smallest legal one.
## The floor used to be stated by the domain clock and read UPWARD by the data catalog — the
## dependency arrow reversed. It is now stated once, on the catalog, and read downward.
##
## What this file pins is the CONTRACT, not the constant: for every unit and every value on
## both sides of the floor, the catalog's validation and the clock's two runtime boundaries
## give the same answer. If someone restates the floor on either side and the copies drift,
## a calendar the catalog accepts becomes a clock that will not start (or the reverse: content
## that validates and then divides by zero), and this is the test that says so.

const CatalogScript := preload("res://src/data/worldsim/world_sim_catalog.gd")
const ClockScript := preload("res://src/domain/worldsim/world_clock.gd")
const StateScript := preload("res://src/domain/worldsim/world_sim_state.gd")

const AUTHORED_CATALOG_PATH := "res://data/worldsim/world_sim_catalog.tres"
const UNITS: Array[String] = [
	"ticks_per_hour", "hours_per_day", "days_per_season", "seasons_per_year"]
## Both sides of the floor, and the floor itself.
const VALUES: Array[int] = [-30, -1, 0, 1, 2, 30]


func _catalog() -> WorldSimCatalog:
	return (load(AUTHORED_CATALOG_PATH) as WorldSimCatalog).duplicate() as WorldSimCatalog


## Does the catalog's validation object to `unit` specifically? (Other errors are not this
## test's business, and the authored catalog has none.)
func _catalog_accepts(catalog: WorldSimCatalog, unit: String) -> bool:
	for error in catalog.validation_errors():
		if error.begins_with(unit + " "):
			return false
	return true


func _clock_with(unit: String, value: int) -> WorldClock:
	var units := {}
	for name in UNITS:
		units[name] = value if name == unit else 2
	return ClockScript.new(units["ticks_per_hour"], units["hours_per_day"],
		units["days_per_season"], units["seasons_per_year"])


func test_the_floor_is_stated_once_and_read_downward() -> void:
	assert_eq(CatalogScript.MIN_CALENDAR_UNIT, 1,
		"the smallest authorable calendar unit is 1 (zero would divide by zero)")
	assert_eq(ClockScript.MIN_UNIT, CatalogScript.MIN_CALENDAR_UNIT,
		"the clock reads the catalog's floor")
	assert_eq(StateScript.MIN_CALENDAR_UNIT, CatalogScript.MIN_CALENDAR_UNIT,
		"and so does the state's hydration fallback")


func test_the_authored_calendar_is_accepted_by_both() -> void:
	var catalog := _catalog()
	assert_true(catalog.is_valid(), "the shipped catalog validates: %s"
		% str(catalog.validation_errors()))
	var clock: WorldClock = ClockScript.new(catalog.ticks_per_hour, catalog.hours_per_day,
		catalog.days_per_season, catalog.seasons_per_year)
	assert_true(clock.is_valid(), "and the clock starts on its calendar")


## The catalog's validation and the clock's CONSTRUCTOR agree on every unit and value.
func test_the_catalog_and_the_clock_refuse_the_same_calendars() -> void:
	var checked := 0
	for unit in UNITS:
		for value in VALUES:
			var catalog := _catalog()
			catalog.set(unit, value)
			var data_ok := _catalog_accepts(catalog, unit)
			var domain_ok := _clock_with(unit, value).is_valid()
			assert_eq(data_ok, domain_ok,
				"%s = %d: catalog says %s, clock says %s" % [unit, value, data_ok, domain_ok])
			assert_eq(data_ok, value >= 1,
				"%s = %d is %s" % [unit, value, "legal" if value >= 1 else "refused"])
			assert_eq(catalog.is_valid(), data_ok,
				"and it is the only thing wrong with the catalog (%s = %d)" % [unit, value])
			checked += 1
	assert_eq(checked, UNITS.size() * VALUES.size(), "every unit against every value")


## ...and so does the clock's HYDRATION boundary (a save written under a calendar the catalog
## would not accept must not load).
func test_the_catalog_and_clock_hydration_refuse_the_same_calendars() -> void:
	for unit in UNITS:
		for value in VALUES:
			var catalog := _catalog()
			catalog.set(unit, value)
			var snapshot: Dictionary = _clock_with(unit, 2).to_dict()
			assert_true(snapshot.has(unit), "the snapshot carries %s" % unit)
			snapshot[unit] = value
			var restored: WorldClock = ClockScript.new(2, 2, 2, 2)
			assert_eq(restored.from_dict(snapshot), _catalog_accepts(catalog, unit),
				"%s = %d: hydration and catalog validation agree" % [unit, value])

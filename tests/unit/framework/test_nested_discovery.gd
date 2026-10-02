extends TestCase
## Lives at tests/unit/framework/ (two levels deep) to PROVE the runner's recursive
## test discovery finds nested tests. If discovery were single-level, this file would
## never run and the behaviours below would go unverified.
##
## It also serves as the runner failure-detection regression proof (DECISIONS.md D-004 /
## task 8): it exercises both the pass and the recorded-fail paths of the harness using
## a throwaway probe, WITHOUT making the main suite fail.


## Marker so a human/CI can confirm nested discovery actually executed this file.
func test_nested_discovery_marker() -> void:
	assert_true(true, "nested test discovered and executed")


## A passing probe records NO failures.
func test_probe_pass_records_nothing() -> void:
	var probe := TestCase.new()
	probe.reset_failures()
	probe.assert_eq(2 + 2, 4, "basic arithmetic")
	probe.assert_true(true)
	assert_true(probe.get_failures().is_empty(),
		"a passing probe must record zero failures")


## A failing probe records a failure for EACH failed assertion — this is the mechanism
## the runner relies on to turn a bad test into a non-zero exit. Verified here without
## failing this (the real) test.
func test_probe_fail_records_failures() -> void:
	var probe := TestCase.new()
	probe.reset_failures()
	probe.assert_true(false, "deliberately false")
	probe.assert_eq(1, 2, "deliberately unequal")
	probe.assert_not_null(null, "deliberately null")
	assert_eq(probe.get_failures().size(), 3,
		"each failed assertion must be recorded (3 expected)")

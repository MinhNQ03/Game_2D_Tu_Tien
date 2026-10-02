extends SceneTree
## Headless test runner for Aetheria (custom runner — decision D-004).
##
## Run with:
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Recursively discovers every `test_*.gd` under the test directories (including nested
## folders like tests/unit/combat/test_damage.gd), instantiates each (must extend
## TestCase), injects the live SceneTree, and runs every `test_*` method. A single
## process frame is awaited after each method so any Node added to the tree has had its
## `_ready` lifecycle run.
##
## Exit code:
##   0  -> all discovered tests passed AND the required smoke test ran
##   1  -> any assertion/test failed, a file failed to load, a file didn't implement
##         TestCase, zero tests ran, or the required smoke test was missing
##
## Limitation: GDScript has no try/catch, so a hard runtime error inside a test aborts
## the process with a non-zero code (still a CI failure). Recorded assertion failures are
## the normal catchable path. See docs/TEST_PLAN.md and DECISIONS.md D-004.

## Root directory scanned recursively for tests.
const TESTS_ROOT := "res://tests"

## Folders under tests/ that are framework/support code or run in their own process, not
## in-runner test cases. `e2e/` holds the dedicated real-application flow driven by its own
## entrypoint (`tests/e2e/run_app_flow.gd`) in a separate Godot process (D-019); it must
## NOT run inside this shared runner, where booting Main would contaminate the shared
## /root autoloads.
const EXCLUDED_DIRS := ["framework", "e2e"]

## The suite must always contain this smoke test; its absence fails the suite so the
## suite can't silently shrink to nothing and report green.
const REQUIRED_TEST := "res://tests/smoke/test_boot.gd"


func _initialize() -> void:
	# Run after the SceneTree is ready so `root` and `process_frame` are usable.
	_run.call_deferred()


## Cross-test isolation guard (D-019).
##
## The project autoloads (GameState, SceneRouter, ...) are LIVE singletons under /root even
## in this runner process. A well-behaved test must NOT mutate them — unit/integration
## tests use fresh `Script.new()` instances, and the real application boot lives in a
## separate process (`tests/e2e/run_app_flow.gd`). This guard records the shared GameState
## phase before each test and FAILS loudly if a test leaves it changed, so cross-test
## singleton contamination (the bug fixed in D-019) can never silently pass again. It does
## not reset anything — resetting would hide the contamination; detecting it is the point.
func _shared_gamestate_phase() -> Variant:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		return null  # no shared singleton to guard (not expected with project autoloads)
	return gs.call("get_phase")


func _run() -> void:
	var total := 0
	var passed := 0
	var failed := 0
	var failures: Array[String] = []

	var found_files := _discover_tests(TESTS_ROOT)

	if not found_files.has(REQUIRED_TEST):
		push_error("[tests] Required smoke test missing: %s" % REQUIRED_TEST)
		print("[tests] RESULT: FAIL — required smoke test not found.")
		quit(1)
		return

	# Baseline phase of the shared GameState autoload before any test runs.
	var baseline_phase: Variant = _shared_gamestate_phase()

	for file_path in found_files:
		var script: Script = load(file_path)
		if script == null:
			failed += 1
			failures.append("%s — could not load script" % file_path)
			continue

		var test_case: Object = script.new()
		if not _is_test_case(test_case):
			failed += 1
			failures.append("%s — does not implement the TestCase API" % file_path)
			continue

		test_case.call("set_scene_tree", self)

		for method_name in _test_methods(test_case):
			total += 1
			test_case.call("reset_failures")
			test_case.call("before_each")
			# `await` tolerates both plain and coroutine (`await`-using) test methods.
			await test_case.call(method_name)
			test_case.call("after_each")
			# Let any node added during the test finish its `_ready` lifecycle.
			await process_frame
			var method_failures: Array = test_case.call("get_failures").duplicate()

			# Isolation guard (D-019): a test must not mutate the shared GameState autoload.
			# Treat a leftover change as a failure of this test method (single reporting path
			# below), so contamination fails the suite loudly instead of passing silently.
			var after_phase: Variant = _shared_gamestate_phase()
			if baseline_phase != null and after_phase != baseline_phase:
				method_failures.append(
					"ISOLATION VIOLATION: shared /root/GameState phase changed %s -> %s "
					% [str(baseline_phase), str(after_phase)]
					+ "(a test mutated a project autoload; use a fresh instance or the "
					+ "dedicated E2E process in tests/e2e/)")

			if method_failures.is_empty():
				passed += 1
				print("[PASS] %s::%s" % [file_path, method_name])
			else:
				failed += 1
				for f in method_failures:
					var line := "[FAIL] %s::%s — %s" % [file_path, method_name, f]
					print(line)
					failures.append(line)

	print("\n[tests] ran %d test(s): %d passed, %d failed." % [total, passed, failed])

	if total == 0:
		push_error("[tests] No test methods were executed.")
		print("[tests] RESULT: FAIL")
		quit(1)
		return

	if failed > 0:
		print("[tests] RESULT: FAIL")
		quit(1)
		return

	print("[tests] RESULT: PASS")
	quit(0)


## True if the object exposes the TestCase runner API (duck typing — avoids a hard
## dependency on the class_name being registered in the global cache).
func _is_test_case(obj: Object) -> bool:
	return obj != null \
		and obj.has_method("reset_failures") \
		and obj.has_method("get_failures") \
		and obj.has_method("before_each") \
		and obj.has_method("after_each") \
		and obj.has_method("set_scene_tree")


## Returns the `test_*` method names declared on a test instance, sorted for
## deterministic ordering.
func _test_methods(test_case: Object) -> Array[String]:
	var names: Array[String] = []
	for m in test_case.get_method_list():
		var n: String = m.get("name", "")
		if n.begins_with("test_") and not names.has(n):
			names.append(n)
	names.sort()
	return names


## Recursively collects `test_*.gd` files under `root`, skipping EXCLUDED_DIRS and
## hidden folders. Returns a sorted (deterministic) list. Safe if `root` is missing.
## Uses an explicit stack (no recursion) so it cannot loop infinitely.
func _discover_tests(start_dir: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [start_dir]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry == "." or entry == "..":
				entry = dir.get_next()
				continue
			var full := "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				if not EXCLUDED_DIRS.has(entry) and not entry.begins_with("."):
					pending.append(full)
			elif entry.begins_with("test_") and entry.ends_with(".gd"):
				out.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out

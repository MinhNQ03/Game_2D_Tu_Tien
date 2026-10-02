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

## Folders under tests/ that are framework/support code, not test cases.
const EXCLUDED_DIRS := ["framework"]

## The suite must always contain this smoke test; its absence fails the suite so the
## suite can't silently shrink to nothing and report green.
const REQUIRED_TEST := "res://tests/smoke/test_boot.gd"


func _initialize() -> void:
	# Run after the SceneTree is ready so `root` and `process_frame` are usable.
	_run.call_deferred()


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
			var method_failures: Array = test_case.call("get_failures")
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

extends SceneTree
## Dedicated real-application E2E entrypoint (D-019).
##
## Run with (its OWN Godot process — this is the whole point of isolation):
##   godot --headless --path . -s res://tests/e2e/run_app_flow.gd
##
## This process boots the real application against the ACTUAL project autoloads (the five
## declared in project.godot [autoload], which Godot loads under /root for any run). It is
## the only thing running here, so driving the shared GameState to RUNNING contaminates
## nothing — unlike the in-process `tests/run_tests.gd`, where that would corrupt sibling
## tests (the bug this ADR fixes).
##
## It is a THIN ADAPTER only: it reuses `tests/framework/test_case.gd` (the shared
## assert_* API + failure recording) and the E2E assertions in
## `tests/e2e/app_flow_case.gd`. No assertion logic is duplicated here.
##
## Exit code: 0 if every E2E assertion passed; 1 on any failure or a load/implementation
## problem. CI runs this as its own gate; a non-zero exit fails the job.

const AppFlowCase := preload("res://tests/e2e/app_flow_case.gd")


func _initialize() -> void:
	# Defer so `root` and `process_frame` are usable (same pattern as run_tests.gd).
	_run.call_deferred()


func _run() -> void:
	var case: Object = AppFlowCase.new()
	# Duck-typed sanity: the case must expose the TestCase runner API we rely on.
	if not (case.has_method("set_scene_tree") and case.has_method("get_failures") \
			and case.has_method("reset_failures")):
		push_error("[e2e] app_flow_case.gd does not implement the TestCase API")
		print("[e2e] RESULT: FAIL — case does not implement TestCase")
		quit(1)
		return

	case.call("set_scene_tree", self)
	case.call("reset_failures")
	case.call("before_each")
	await case.call("test_real_application_flow")
	case.call("after_each")
	await process_frame  # let any deferred frees finish

	var failures: Array = case.call("get_failures")
	if failures.is_empty():
		print("[e2e] PASS — real application flow (boot -> menu -> new game -> hub map)")
		print("[e2e] RESULT: PASS")
		quit(0)
		return

	for f in failures:
		print("[e2e] [FAIL] %s" % f)
	print("[e2e] RESULT: FAIL — %d assertion(s) failed." % failures.size())
	quit(1)

extends SceneTree
## Dedicated Phase-20 Story E2E entrypoint (D-019 isolation pattern).
##
## Run with (its OWN Godot process — the point of isolation):
##   godot --headless --path . -s res://tests/e2e/run_story_flow.gd
##
## Boots the real application against the ACTUAL project autoloads and plays the opening
## with real key events: New Game, the identity screen (moved through, backed out of,
## reopened, confirmed with a doubled press), the run that starts as the chosen Origin and
## look with NO sect, the vignette and the arrival, a walk, leaving through the real prompt,
## and a second run as someone else.
##
## THIN ADAPTER only: reuses `tests/framework/test_case.gd` (assert_* + failure recording)
## and the assertions in `tests/e2e/story_flow_case.gd`. No assertion logic duplicated here.
##
## Exit code: 0 if every assertion passed; 1 on any failure or load/implementation problem.

const StoryFlowCase := preload("res://tests/e2e/story_flow_case.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var case: Object = StoryFlowCase.new()
	if not (case.has_method("set_scene_tree") and case.has_method("get_failures") \
			and case.has_method("reset_failures")):
		push_error("[e2e-story] story_flow_case.gd does not implement the TestCase API")
		print("[e2e-story] RESULT: FAIL — case does not implement TestCase")
		quit(1)
		return

	case.call("set_scene_tree", self)
	case.call("reset_failures")
	case.call("before_each")
	await case.call("test_real_story_flow")
	case.call("after_each")
	await process_frame

	var failures: Array = case.call("get_failures")
	if failures.is_empty():
		print("[e2e-story] PASS - real story flow "
			+ "(identity -> cancel -> confirm once -> sectless run -> scenes -> leave -> rerun)")
		print("[e2e-story] RESULT: PASS")
		quit(0)
		return

	for f in failures:
		print("[e2e-story] [FAIL] %s" % f)
	print("[e2e-story] RESULT: FAIL — %d assertion(s) failed." % failures.size())
	quit(1)

extends SceneTree
## Dedicated Phase-03 world/map-flow E2E entrypoint (D-019 isolation pattern).
##
## Run with (its OWN Godot process — the point of isolation):
##   godot --headless --path . -s res://tests/e2e/run_world_flow.gd
##
## Boots the real application against the ACTUAL project autoloads and exercises the real
## World/Map flow (New Game → hub map → persistent player → real interact → field map →
## repeated round trips with no orphan leak → real open_menu → clean return). It is the only
## thing running here, so driving the shared GameState/InputService contaminates nothing —
## unlike the in-process `tests/run_tests.gd`.
##
## THIN ADAPTER only: reuses `tests/framework/test_case.gd` (assert_* + failure recording)
## and the assertions in `tests/e2e/world_flow_case.gd`. No assertion logic duplicated here.
##
## Exit code: 0 if every assertion passed; 1 on any failure or load/implementation problem.

const WorldFlowCase := preload("res://tests/e2e/world_flow_case.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var case: Object = WorldFlowCase.new()
	if not (case.has_method("set_scene_tree") and case.has_method("get_failures") \
			and case.has_method("reset_failures")):
		push_error("[e2e-world] world_flow_case.gd does not implement the TestCase API")
		print("[e2e-world] RESULT: FAIL — case does not implement TestCase")
		quit(1)
		return

	case.call("set_scene_tree", self)
	case.call("reset_failures")
	case.call("before_each")
	await case.call("test_real_world_map_flow")
	case.call("after_each")
	await process_frame

	var failures: Array = case.call("get_failures")
	if failures.is_empty():
		print("[e2e-world] PASS - real world/map flow "
			+ "(new game -> hub -> interact -> field -> back -> menu)")
		print("[e2e-world] RESULT: PASS")
		quit(0)
		return

	for f in failures:
		print("[e2e-world] [FAIL] %s" % f)
	print("[e2e-world] RESULT: FAIL — %d assertion(s) failed." % failures.size())
	quit(1)

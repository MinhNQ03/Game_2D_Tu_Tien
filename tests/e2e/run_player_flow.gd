extends SceneTree
## Dedicated Phase-02 player-flow E2E entrypoint (D-019).
##
## Run with (its OWN Godot process — the point of isolation):
##   godot --headless --path . -s res://tests/e2e/run_player_flow.gd
##
## Runs against the ACTUAL project autoloads and exercises the real Phase-02 combat sandbox
## (instantiated directly: move → attack → bidirectional damage → death → cleanup). It is the
## only thing running here, so driving the shared InputService contaminates nothing — unlike
## the in-process `tests/run_tests.gd`. (Phase 03: New Game now enters the World/Map, so the
## sandbox is reached directly rather than through the menu — see run_world_flow.gd.)
##
## THIN ADAPTER only: reuses `tests/framework/test_case.gd` (assert_* + failure recording)
## and the assertions in `tests/e2e/player_flow_case.gd`. No assertion logic duplicated here.
##
## Exit code: 0 if every assertion passed; 1 on any failure or load/implementation problem.

const PlayerFlowCase := preload("res://tests/e2e/player_flow_case.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var case: Object = PlayerFlowCase.new()
	if not (case.has_method("set_scene_tree") and case.has_method("get_failures") \
			and case.has_method("reset_failures")):
		push_error("[e2e-player] player_flow_case.gd does not implement the TestCase API")
		print("[e2e-player] RESULT: FAIL — case does not implement TestCase")
		quit(1)
		return

	case.call("set_scene_tree", self)
	case.call("reset_failures")
	case.call("before_each")
	await case.call("test_real_player_sandbox_flow")
	case.call("after_each")
	await process_frame

	var failures: Array = case.call("get_failures")
	if failures.is_empty():
		print("[e2e-player] PASS — real player sandbox flow (new game -> move -> attack -> death)")
		print("[e2e-player] RESULT: PASS")
		quit(0)
		return

	for f in failures:
		print("[e2e-player] [FAIL] %s" % f)
	print("[e2e-player] RESULT: FAIL — %d assertion(s) failed." % failures.size())
	quit(1)

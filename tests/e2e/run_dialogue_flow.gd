extends SceneTree
## Dedicated Phase-18 Dialogue E2E entrypoint (D-019 isolation pattern).
##
## Run with (its OWN Godot process — the point of isolation):
##   godot --headless --path . -s res://tests/e2e/run_dialogue_flow.gd
##
## Boots the real application against the ACTUAL project autoloads and drives two
## conversations with semantic inputs: the elder in the hub (a knowledge-gated answer, respect,
## a taught precept) and the scout in the field (affinity, then "Trade" handing over to his
## shop at the adjusted price), with the modal context, Esc, a map change and return to menu.
##
## THIN ADAPTER only: reuses `tests/framework/test_case.gd` (assert_* + failure recording)
## and the assertions in `tests/e2e/dialogue_flow_case.gd`. No assertion logic duplicated here.
##
## Exit code: 0 if every assertion passed; 1 on any failure or load/implementation problem.

const DialogueFlowCase := preload("res://tests/e2e/dialogue_flow_case.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var case: Object = DialogueFlowCase.new()
	if not (case.has_method("set_scene_tree") and case.has_method("get_failures") \
			and case.has_method("reset_failures")):
		push_error("[e2e-dialogue] dialogue_flow_case.gd does not implement the TestCase API")
		print("[e2e-dialogue] RESULT: FAIL — case does not implement TestCase")
		quit(1)
		return

	case.call("set_scene_tree", self)
	case.call("reset_failures")
	case.call("before_each")
	await case.call("test_real_dialogue_flow")
	case.call("after_each")
	await process_frame

	var failures: Array = case.call("get_failures")
	if failures.is_empty():
		print("[e2e-dialogue] PASS - real dialogue flow "
			+ "(two NPCs -> branch -> regard -> knowledge -> trade handoff -> menu)")
		print("[e2e-dialogue] RESULT: PASS")
		quit(0)
		return

	for f in failures:
		print("[e2e-dialogue] [FAIL] %s" % f)
	print("[e2e-dialogue] RESULT: FAIL — %d assertion(s) failed." % failures.size())
	quit(1)

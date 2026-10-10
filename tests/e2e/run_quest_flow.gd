extends SceneTree
## Dedicated Phase-19 Quest E2E entrypoint (D-019 isolation pattern).
##
## Run with (its OWN Godot process — the point of isolation):
##   godot --headless --path . -s res://tests/e2e/run_quest_flow.gd
##
## Boots the real application against the ACTUAL project autoloads and plays both shipped
## quests with semantic inputs: the purpose line at spawn, the elder's offer declined and then
## taken, the journal (opened, walked with, closed by its key and by Esc), a quest given back
## and taken again, the scout's errand, the knowledge route, a real kill counted, a reward
## refused by a full bag and then paid once, the elder's pills carried to the scout, and a
## return to the menu.
##
## THIN ADAPTER only: reuses `tests/framework/test_case.gd` (assert_* + failure recording)
## and the assertions in `tests/e2e/quest_flow_case.gd`. No assertion logic duplicated here.
##
## Exit code: 0 if every assertion passed; 1 on any failure or load/implementation problem.

const QuestFlowCase := preload("res://tests/e2e/quest_flow_case.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var case: Object = QuestFlowCase.new()
	if not (case.has_method("set_scene_tree") and case.has_method("get_failures") \
			and case.has_method("reset_failures")):
		push_error("[e2e-quest] quest_flow_case.gd does not implement the TestCase API")
		print("[e2e-quest] RESULT: FAIL — case does not implement TestCase")
		quit(1)
		return

	case.call("set_scene_tree", self)
	case.call("reset_failures")
	case.call("before_each")
	await case.call("test_real_quest_flow")
	case.call("after_each")
	await process_frame

	var failures: Array = case.call("get_failures")
	if failures.is_empty():
		print("[e2e-quest] PASS - real quest flow "
			+ "(lead -> decline -> accept -> journal -> abandon -> two quests -> reward -> menu)")
		print("[e2e-quest] RESULT: PASS")
		quit(0)
		return

	for f in failures:
		print("[e2e-quest] [FAIL] %s" % f)
	print("[e2e-quest] RESULT: FAIL — %d assertion(s) failed." % failures.size())
	quit(1)

extends TestCase
## `tools/capture_ui.gd` paces itself: vsync off and a fixed frame cap, set before its run. A
## vsynced window in a locked X session presents at ~1 Hz, so a run that leaves vsync to the
## caller takes ~15 min and the UI-01 vi capture was killed at its 900 s check budget.

const TOOL := "res://tools/capture_ui.gd"


func test_capture_ui_caps_its_frame_rate() -> void:
	var script := load(TOOL) as GDScript
	assert_not_null(script, "capture_ui.gd loads")
	var fps := int(script.get_script_constant_map().get("PACED_FPS", 0))
	assert_true(fps > 0 and fps <= 60, "capture_ui.gd paces at a bounded rate (%d)" % fps)


func test_capture_ui_disables_vsync_before_its_run() -> void:
	var source := (load(TOOL) as GDScript).source_code
	var start := source.find("func _initialize()")
	assert_true(start >= 0, "capture_ui.gd has _initialize")
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, end - start if end > start else -1)
	assert_true(body.contains("window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)"),
		"capture_ui.gd turns vsync off in _initialize")
	assert_true(body.contains("Engine.max_fps = PACED_FPS"),
		"capture_ui.gd caps the frame rate in _initialize")
	assert_true(body.find("VSYNC_DISABLED") < body.find("_run.call_deferred()"),
		"vsync is off before the run starts")

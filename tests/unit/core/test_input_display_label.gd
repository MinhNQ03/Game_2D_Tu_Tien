extends TestCase
## Unit tests for InputService's display-label API (Phase 04). The UI asks the service for a
## human key label for a semantic action; it must resolve the project's real binding without
## the caller ever touching a physical keycode (L-003). Uses a FRESH InputService instance
## (the method only READS the global InputMap, which the engine loads from project.godot).

const InputServiceScript := preload("res://src/infrastructure/input_service.gd")


func test_interact_label_is_e() -> void:
	var svc: Node = InputServiceScript.new()
	assert_eq(svc.get_action_display_label(&"interact"), "E",
		"interact is bound to physical key E")
	svc.free()  # InputService is a Node: free it or it leaks at process exit (D-025).


func test_open_menu_label_is_esc() -> void:
	var svc: Node = InputServiceScript.new()
	assert_eq(svc.get_action_display_label(&"open_menu"), "Esc",
		"open_menu is bound to Escape, shortened to 'Esc'")
	svc.free()


func test_unknown_action_returns_placeholder() -> void:
	var svc: Node = InputServiceScript.new()
	assert_eq(svc.get_action_display_label(&"no_such_action"), "?",
		"an unknown action yields a safe placeholder, not a crash or raw code")
	svc.free()

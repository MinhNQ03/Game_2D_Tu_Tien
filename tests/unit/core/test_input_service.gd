extends TestCase
## Unit tests for InputService (src/infrastructure/input_service.gd).
##
## Verifies the semantic InputMap vocabulary exists and the context-gating ownership
## behaves. Gating logic is tested on a fresh instance; the action-existence check uses
## the real InputMap loaded from project.godot.

const InputScript := preload("res://src/infrastructure/input_service.gd")


func test_required_actions_exist_in_input_map() -> void:
	# The real project InputMap must contain every semantic action. We check InputMap
	# directly (not device keys) so the test asserts the vocabulary, not a physical key.
	var svc: Node = InputScript.new()
	for action in svc.SEMANTIC_ACTIONS:
		assert_true(InputMap.has_action(action),
			"InputMap must define semantic action: %s" % action)
	svc.free()


func test_missing_actions_reports_empty() -> void:
	var svc: Node = InputScript.new()
	var missing: Array = svc.missing_actions()
	assert_true(missing.is_empty(),
		"no semantic actions missing from InputMap; missing=%s" % str(missing))
	svc.free()


func test_gating_blocks_gameplay_when_not_active() -> void:
	var svc: Node = InputScript.new()
	# Baseline context is MENU; gameplay must not be active.
	assert_false(svc.is_gameplay_active(), "menu baseline is not gameplay")
	assert_eq(svc.get_move_vector(), Vector2.ZERO, "no movement intent outside gameplay")
	svc.free()


func test_context_stack_priority() -> void:
	var svc: Node = InputScript.new()
	svc.set_gameplay_context()
	assert_true(svc.is_gameplay_active(), "gameplay active after set_gameplay_context()")
	# A UI modal on top must suppress gameplay (modal > gameplay).
	svc.push_modal_context()
	assert_false(svc.is_gameplay_active(), "modal on top suppresses gameplay")
	svc.pop_context()
	assert_true(svc.is_gameplay_active(), "popping modal restores gameplay")
	svc.free()


func test_baseline_context_cannot_be_popped_away() -> void:
	var svc: Node = InputScript.new()
	svc.set_menu_context()
	svc.pop_context()  # should be a no-op (keeps baseline)
	assert_eq(svc.current_context(), svc.Context.MENU, "baseline context preserved")
	svc.free()


## The semantic context setters must map to the right underlying context and reset the
## stack (no stale modal survives) — guards the magic-int removal (§15).
func test_semantic_context_setters() -> void:
	var svc: Node = InputScript.new()
	svc.set_gameplay_context()
	assert_eq(svc.current_context(), svc.Context.GAMEPLAY, "set_gameplay_context -> GAMEPLAY")
	# Stack a modal, then switching to menu must reset (modal does not survive).
	svc.push_modal_context()
	assert_eq(svc.current_context(), svc.Context.UI_MODAL, "modal pushed on top")
	svc.set_menu_context()
	assert_eq(svc.current_context(), svc.Context.MENU, "set_menu_context -> MENU")
	svc.pop_context()  # baseline-only now; must stay MENU (stack was reset)
	assert_eq(svc.current_context(), svc.Context.MENU,
		"set_menu_context reset the stack; no stale modal remained")
	svc.free()

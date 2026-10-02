extends TestCase
## Unit tests for EventBus (src/infrastructure/event_bus.gd).
## Fresh instance per check; a tiny listener callback records deliveries.
##
## EventBus is a notification backbone only: it declares signals and offers thin emit
## helpers. These tests assert delivery semantics AND that the bus carries no business
## state (it must never become a service locator / global data dumping ground).

const EventBusScript := preload("res://src/infrastructure/event_bus.gd")


func test_boot_signal_delivery() -> void:
	var bus: Node = EventBusScript.new()
	add_to_tree(bus)
	var hits := {"n": 0}
	bus.game_booted.connect(func() -> void: hits["n"] += 1)
	assert_eq(hits["n"], 0, "no delivery before emit")
	bus.emit_game_booted()
	assert_eq(hits["n"], 1, "single delivery after one emit")
	free_node(bus)


func test_transition_started_payload() -> void:
	var bus: Node = EventBusScript.new()
	add_to_tree(bus)
	var seen := {"from": "", "to": ""}
	bus.scene_transition_started.connect(func(f: String, t: String) -> void:
		seen["from"] = f
		seen["to"] = t)
	bus.emit_scene_transition_started("menu", "prologue")
	assert_eq(seen["from"], "menu")
	assert_eq(seen["to"], "prologue")
	free_node(bus)


func test_transition_completed_and_failed_payloads() -> void:
	var bus: Node = EventBusScript.new()
	add_to_tree(bus)
	var done := {"to": ""}
	var failed := {"to": "", "reason": ""}
	bus.scene_transition_completed.connect(func(t: String) -> void: done["to"] = t)
	bus.scene_transition_failed.connect(func(t: String, r: String) -> void:
		failed["to"] = t
		failed["reason"] = r)
	bus.emit_scene_transition_completed("prologue")
	bus.emit_scene_transition_failed("village", "scene_key not registered")
	assert_eq(done["to"], "prologue", "completed payload delivered")
	assert_eq(failed["to"], "village", "failed target delivered")
	assert_eq(failed["reason"], "scene_key not registered", "failure reason delivered")
	free_node(bus)


func test_language_changed_payload() -> void:
	var bus: Node = EventBusScript.new()
	add_to_tree(bus)
	var seen := {"code": ""}
	bus.language_changed.connect(func(code: String) -> void: seen["code"] = code)
	bus.emit_language_changed("vi")
	assert_eq(seen["code"], "vi", "language code delivered")
	free_node(bus)


## The bus must NOT accumulate business/session state. Its only script-level variable is
## the opt-in `debug_log` flag; everything else is signals + emit helpers. This guards
## against the EventBus silently becoming a global state dumping ground / service locator
## (`.kiro/steering/03-architecture.md`).
func test_eventbus_holds_no_business_state() -> void:
	var bus: Node = EventBusScript.new()
	add_to_tree(bus)
	var script_vars: Array[String] = []
	for prop in bus.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			script_vars.append(String(prop.get("name", "")))
	assert_eq(script_vars.size(), 1,
		"EventBus must declare exactly one script variable; got %s" % str(script_vars))
	assert_true(script_vars.has("debug_log"),
		"the only EventBus field is the debug_log flag; got %s" % str(script_vars))
	free_node(bus)

extends TestCase
## Unit tests for EventBus (src/infrastructure/event_bus.gd).
## Fresh instance per check; a tiny listener callback records deliveries.

const EventBusScript := preload("res://src/infrastructure/event_bus.gd")


func test_listener_receives_event() -> void:
	var bus: Node = EventBusScript.new()
	add_to_tree(bus)
	var received := {"count": 0, "run_id": ""}
	var cb := func(run_id: String) -> void:
		received["count"] += 1
		received["run_id"] = run_id
	bus.session_started.connect(cb)
	bus.emit_session_started("run_123")
	assert_eq(received["count"], 1, "listener invoked exactly once")
	assert_eq(received["run_id"], "run_123", "payload delivered correctly")
	free_node(bus)


func test_no_delivery_without_emit() -> void:
	var bus: Node = EventBusScript.new()
	add_to_tree(bus)
	var hits := {"n": 0}
	bus.game_booted.connect(func() -> void: hits["n"] += 1)
	assert_eq(hits["n"], 0, "no delivery before emit")
	bus.emit_game_booted()
	assert_eq(hits["n"], 1, "single delivery after one emit")
	free_node(bus)


func test_transition_signals_payload() -> void:
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

extends TestCase
## Integration test: map load + repeated transitions via the REAL SceneRouter.
##
## Exercises SceneRouter + the authored map catalog together, driving the same scene_key
## registration + request_transition sequence WorldRuntime uses — but with a FRESH router
## instance and a fresh host (never the live /root/SceneRouter autoload, L-010). Proves:
##   - both authored maps load through the router,
##   - moving back and forth repeatedly does not grow orphan nodes (no leak, L-013 /
##     docs/PERFORMANCE.md map-transition no-leak contract),
##   - clearing the current scene frees it (no dangling content under the host).

const RouterScript := preload("res://src/infrastructure/scene_router.gd")
const MapDataScript := preload("res://src/data/maps/map_data.gd")

const HUB := "res://data/maps/map_hub.tres"
const FIELD := "res://data/maps/map_field.tres"


## Register scenes from the AUTHORITATIVE MapData (scene_key -> scene_path), exactly as
## WorldRuntime does from the catalog — no hard-coded scene paths here (D-022).
func _register(router: Node) -> void:
	var hub: MapData = load(HUB) as MapData
	var field: MapData = load(FIELD) as MapData
	router.register_scene(hub.scene_key, hub.scene_path)
	router.register_scene(field.scene_key, field.scene_path)


func test_both_maps_load_through_router() -> void:
	var router: Node = RouterScript.new()
	var host := Node2D.new()
	add_to_tree(router)
	add_to_tree(host)
	router.set_scene_host(host)
	_register(router)

	assert_true(router.request_transition("map_hub", &"world_main", &"map_hub"),
		"hub loads through the router")
	assert_eq(router.get_current_key(), "map_hub", "router tracks the hub")
	assert_eq(host.get_child_count(), 1, "exactly one content scene under host (hub)")

	assert_true(router.request_transition("map_field", &"world_main", &"map_field"),
		"field loads through the router")
	assert_eq(router.get_current_key(), "map_field", "router tracks the field")
	assert_eq(host.get_child_count(), 1, "old map freed, one content scene under host (field)")

	router.clear_current_scene()
	free_node(host)
	free_node(router)


func test_repeated_transitions_do_not_leak() -> void:
	var router: Node = RouterScript.new()
	var host := Node2D.new()
	add_to_tree(router)
	add_to_tree(host)
	router.set_scene_host(host)
	_register(router)

	# Warm up: one full round trip, then let queued frees settle so the baseline is stable.
	router.request_transition("map_hub", &"world_main", &"map_hub")
	router.request_transition("map_field", &"world_main", &"map_field")
	await scene_tree.process_frame
	await scene_tree.process_frame
	var baseline: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	# Many more round trips: each frees the previous content scene (queue_free).
	for _i in range(8):
		router.request_transition("map_hub", &"world_main", &"map_hub")
		router.request_transition("map_field", &"world_main", &"map_field")
	# Let every queued free actually run.
	await scene_tree.process_frame
	await scene_tree.process_frame
	var after: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	assert_eq(host.get_child_count(), 1, "still exactly one content scene after many trips")
	assert_true(after <= baseline,
		"no orphan growth across repeated transitions (%d -> %d)" % [int(baseline), int(after)])

	router.clear_current_scene()
	await scene_tree.process_frame
	free_node(host)
	free_node(router)


func test_clear_frees_the_active_scene() -> void:
	var router: Node = RouterScript.new()
	var host := Node2D.new()
	add_to_tree(router)
	add_to_tree(host)
	router.set_scene_host(host)
	_register(router)

	router.request_transition("map_hub", &"world_main", &"map_hub")
	assert_eq(host.get_child_count(), 1, "a scene is loaded")

	router.clear_current_scene()
	await scene_tree.process_frame
	assert_eq(router.get_current_key(), "", "router key cleared")
	assert_eq(host.get_child_count(), 0, "host has no content scene after clear")

	free_node(host)
	free_node(router)


func test_unknown_map_key_is_rejected() -> void:
	var router: Node = RouterScript.new()
	var host := Node2D.new()
	add_to_tree(router)
	add_to_tree(host)
	router.set_scene_host(host)
	_register(router)

	# Negative path: an unregistered key must be rejected loudly, not half-transition.
	assert_false(router.request_transition("map_nope", &"world_main", &"map_nope"),
		"unregistered scene_key rejected")
	assert_eq(router.get_current_key(), "", "no scene became current on a rejected request")
	assert_eq(host.get_child_count(), 0, "nothing loaded under host on rejection")

	free_node(host)
	free_node(router)


func test_rejected_transition_leaves_previous_scene_intact() -> void:
	# This is the INVARIANT WorldRuntime's transactional rollback depends on (D-022): a
	# rejected transition must NOT free or change the currently-loaded scene, so WorldRuntime
	# can safely re-attach the persistent player to the still-alive old map.
	var router: Node = RouterScript.new()
	var host := Node2D.new()
	add_to_tree(router)
	add_to_tree(host)
	router.set_scene_host(host)
	_register(router)

	assert_true(router.request_transition("map_hub", &"world_main", &"map_hub"), "hub loaded")
	var current_before: Node = router.get_current_scene()
	assert_not_null(current_before, "a scene is current")

	# Request a transition that the router will reject (unregistered key).
	assert_false(router.request_transition("map_ghost", &"world_main", &"map_ghost"),
		"rejected transition returns false")

	# The previous scene is untouched: same instance, still current, still the only child,
	# and the router is not stuck in a transitioning state.
	assert_eq(router.get_current_key(), "map_hub", "current key unchanged after rejection")
	assert_eq(router.get_current_scene(), current_before, "same scene instance after rejection")
	assert_true(is_instance_valid(current_before), "previous scene not freed on rejection")
	assert_eq(host.get_child_count(), 1, "still exactly one content scene after rejection")
	assert_false(router.is_transitioning(), "router not left transitioning after rejection")

	# And a subsequent valid transition still works (not wedged).
	assert_true(router.request_transition("map_field", &"world_main", &"map_field"),
		"a valid transition still works after a rejected one")

	router.clear_current_scene()
	await scene_tree.process_frame
	free_node(host)
	free_node(router)

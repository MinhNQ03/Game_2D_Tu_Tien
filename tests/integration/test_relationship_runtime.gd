extends TestCase
## Integration test for RelationshipRuntime (Phase 05). Uses a FRESH RelationshipRuntime
## instance added to the tree (never the real one under a booted Main — that path is the E2E
## process, D-019). Verifies the subsystem loads the authored config + rules, builds a working
## store+service, and tears down cleanly. No shared autoload is mutated (isolation guard stays
## green). All Nodes are freed (L-019).

const RuntimeScript := preload("res://src/gameplay/world/relationship_runtime.gd")
const EndpointScript := preload("res://src/domain/relationship/relationship_endpoint.gd")


func _runtime() -> Node:
	var rt: Node = RuntimeScript.new()
	add_to_tree(rt)
	return rt


func test_runtime_starts_and_builds_service() -> void:
	var rt := _runtime()
	assert_false(rt.call("is_session_active"), "idle before start_session")
	assert_true(rt.call("start_session"), "session starts (config + rules load + validate)")
	assert_true(rt.call("is_session_active"), "active after start")
	var service: RefCounted = rt.call("get_service")
	assert_not_null(service, "runtime exposes a RelationshipService")
	var store: RefCounted = rt.call("get_store")
	assert_not_null(store, "runtime exposes a RelationshipStore")
	assert_eq(store.edge_count(), 0, "a fresh session starts with an empty graph")
	free_node(rt)


func test_runtime_service_is_usable_end_to_end() -> void:
	var rt := _runtime()
	rt.call("start_session")
	var service: RefCounted = rt.call("get_service")
	# Create an edge and drive a real authored event through the runtime's service.
	var player: RefCounted = EndpointScript.for_character(&"player")
	var elder: RefCounted = EndpointScript.for_character(&"npc_elder")
	assert_not_null(service.create_edge(&"e_pe", player, elder, &"STRANGER", true),
		"runtime service creates an edge")
	assert_true(service.apply_event(&"e_pe", &"HELPED_STRANGER"),
		"runtime service applies an authored event deterministically")
	var edge: RefCounted = service.get_store().get_edge(&"e_pe")
	assert_eq(edge.get_dimension(&"affinity"), 8, "HELPED_STRANGER raised affinity via runtime")
	free_node(rt)


func test_end_session_drops_graph() -> void:
	var rt := _runtime()
	rt.call("start_session")
	rt.call("end_session")
	assert_false(rt.call("is_session_active"), "inactive after end_session")
	assert_null(rt.call("get_service"), "service dropped on end_session")
	assert_null(rt.call("get_store"), "store dropped on end_session")
	free_node(rt)

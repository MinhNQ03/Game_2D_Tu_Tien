extends TestCase
## Unit tests for `WorldInteractable` — the one contract `MapBase` selects on (Phase 16) — and
## for the deterministic choice among overlapping interactables.

const InteractableScript := preload("res://src/gameplay/maps/world_interactable.gd")
const KnowledgeSourceScript := preload("res://src/gameplay/knowledge/knowledge_source.gd")


class Named extends WorldInteractable:
	var kind: StringName = &"test"
	var id: StringName = &""

	func interaction_kind() -> StringName:
		return kind

	func interaction_id() -> StringName:
		return id


func _at(id: StringName, position: Vector2, reach: float = 30.0) -> Named:
	var node := Named.new()
	node.id = id
	node.reach_px = reach
	add_to_tree(node)
	node.global_position = position
	return node


func test_reach_is_a_distance_and_the_nearest_in_reach_wins() -> void:
	var near := _at(&"near", Vector2(10, 0))
	var far := _at(&"far", Vector2(25, 0))
	var out := _at(&"out", Vector2(200, 0))
	var all := [far, out, near]
	assert_eq(WorldInteractable.nearest_in_reach(all, Vector2.ZERO), near, "the nearest wins")
	assert_eq(WorldInteractable.nearest_in_reach(all, Vector2(24, 0)), far,
		"and it changes as the player moves")
	assert_null(WorldInteractable.nearest_in_reach(all, Vector2(100, 0)),
		"outside every reach there is none")
	assert_eq(WorldInteractable.nearest_in_reach(all, Vector2(175, 0)), out,
		"reach is measured to the interactable itself")
	for node in all:
		free_node(node)


func test_an_exact_tie_resolves_by_identity_not_by_scene_order() -> void:
	var b := _at(&"bravo", Vector2(10, 0))
	var a := _at(&"alpha", Vector2(-10, 0))
	assert_eq(WorldInteractable.nearest_in_reach([b, a], Vector2.ZERO), a,
		"equidistant: the lower identity wins")
	assert_eq(WorldInteractable.nearest_in_reach([a, b], Vector2.ZERO), a,
		"whatever order they are listed in")
	a.kind = &"zeta"
	assert_eq(WorldInteractable.nearest_in_reach([a, b], Vector2.ZERO), b,
		"the kind sorts before the id")
	free_node(a)
	free_node(b)


func test_an_unavailable_interactable_is_never_offered() -> void:
	var hidden := _at(&"hidden", Vector2(5, 0))
	var shown := _at(&"shown", Vector2(20, 0))
	hidden.visible = false
	assert_eq(WorldInteractable.nearest_in_reach([hidden, shown], Vector2.ZERO), shown,
		"a hidden one is skipped even when nearer")
	shown.visible = false
	assert_null(WorldInteractable.nearest_in_reach([hidden, shown], Vector2.ZERO),
		"and with none available there is none")
	assert_null(WorldInteractable.nearest_in_reach([null, 4, "x"], Vector2.ZERO),
		"junk candidates are ignored, not crashed on")
	free_node(hidden)
	free_node(shown)


func test_a_knowledge_source_is_an_interactable_with_its_own_kind() -> void:
	var stele: KnowledgeSource = KnowledgeSourceScript.new()
	stele.source_id = &"source_test"
	add_to_tree(stele)
	assert_true(stele is WorldInteractable, "a stele is selected through the same contract")
	assert_eq(stele.interaction_kind(), KnowledgeSource.KIND, "with its own routing kind")
	assert_eq(stele.interaction_id(), &"source_test", "and its authored id")
	assert_eq(stele.prompt_key, &"UI_HUD_READ_ACTION", "and its own verb")
	free_node(stele)

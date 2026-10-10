extends TestCase
## Performance claims for Phase 18, each measured by a test that can fail (L-032).
##
##   1. A conversation that is not open costs NOTHING per frame: no dialogue node processes.
##   2. Deciding what a line offers is a handful of indexed reads — cheap enough to do on every
##      line shown, which is the only time it is done.

const DialogueRuntimeScript := preload("res://src/gameplay/world/dialogue_runtime.gd")
const DialoguePanelScript := preload("res://src/presentation/dialogue/dialogue_panel.gd")
const WorldNpcScript := preload("res://src/gameplay/npcs/world_npc.gd")

const DIALOGUES_PATH := "res://data/dialogue/dialogue_catalog.tres"
const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"

const EVALUATIONS := 20000
## Generous on purpose: the claim is "microseconds, not a frame", and CI machines vary. The
## measured figure is printed and logged in docs/PERFORMANCE.md.
const BUDGET_USEC_PER_EVALUATION := 100.0


func test_nothing_in_a_closed_conversation_runs_per_frame() -> void:
	var runtime: DialogueRuntime = DialogueRuntimeScript.new()
	add_to_tree(runtime)
	assert_false(runtime.is_processing(), "DialogueRuntime has no _process")
	assert_false(runtime.is_physics_processing(), "and no _physics_process")
	var panel: DialoguePanel = DialoguePanelScript.new()
	add_to_tree(panel)
	assert_false(panel.is_processing(), "a closed DialoguePanel reads no key")
	assert_false(panel.is_physics_processing(), "and has no physics tick")
	var npc: WorldNpc = WorldNpcScript.new()
	add_to_tree(npc)
	assert_false(npc.is_processing(), "a person nobody is talking to does not process")
	free_node(npc)
	free_node(panel)
	free_node(runtime)


func test_deciding_what_a_line_offers_costs_microseconds() -> void:
	var config := load(CONFIG_PATH) as RelationshipConfigData
	var relationship := RelationshipService.new(RelationshipStore.new(config), config)
	var knowledge := KnowledgeService.new(load(KNOWLEDGE_PATH) as KnowledgeCatalogData,
		KnowledgeStore.new())
	# With the quest owner, as in a session: a quest condition is then a real question
	# (the phase is DERIVED from the owners each time it is asked — Phase 19).
	var quests := QuestService.new(load("res://data/quests/quest_catalog.tres") as QuestCatalogData,
		QuestState.new(), knowledge, RewardService.new(RewardLedger.new()),
		func(_item_id: StringName) -> int: return 2)
	assert_true(quests.accept(&"quest_treeline_pills", &"actor_scout_ko").ok, "a quest under way")
	var service := DialogueService.new(load(DIALOGUES_PATH) as DialogueCatalogData, knowledge,
		relationship, config, quests)
	assert_true(service.is_ready(), "the shipped catalog")
	# The realistic worst case: an edge exists (so regard is a graph read, not a default) and
	# the gated knowledge is held (so every condition is evaluated to the end).
	knowledge.grant(&"know_lac_ha_stele_record", &"test")
	var edge := relationship.create_edge(&"rel_budget",
		RelationshipEndpoint.for_character(&"actor_scout_ko"),
		RelationshipEndpoint.for_character(&"player"))
	relationship.set_dimension(edge.id, &"affinity", 10)
	var offered := 0
	var started := Time.get_ticks_usec()
	for i in EVALUATIONS:
		# The two nodes with the most conditions, alternated.
		offered += service.eligible_choices(&"dlg_scout_ko",
			&"ko_price" if i % 2 == 0 else &"ko_hub", &"player").size()
	var per_call := float(Time.get_ticks_usec() - started) / float(EVALUATIONS)
	print("[dialogue-budget] eligible_choices: %.2f usec per call over %d calls"
		% [per_call, EVALUATIONS])
	assert_eq(offered, EVALUATIONS / 2 * 3 + EVALUATIONS / 2 * 5,
		"every call really evaluated its node (3 answers at the price talk, 5 at the hub: "
		+ "the four he always has and the errand that is ready to hand in)")
	assert_true(per_call <= BUDGET_USEC_PER_EVALUATION,
		"%.2f usec per evaluation is within %.0f" % [per_call, BUDGET_USEC_PER_EVALUATION])

extends TestCase
## Performance claims for Phase 19, each measured by a test that can fail (L-032).
##
##   1. Quests cost NOTHING per frame: no quest or reward node processes, and the journal
##      panel does not either.
##   2. "Where does this quest stand" is DERIVED from its owners each time it is asked — a
##      handful of indexed reads, cheap enough to ask on every world event that could change it
##      (knowledge gained, the bag changing, a defeat), which is the only time it is asked.

const QuestRuntimeScript := preload("res://src/gameplay/world/quest_runtime.gd")
const RewardRuntimeScript := preload("res://src/gameplay/world/reward_runtime.gd")
const JournalScript := preload("res://src/presentation/quest/quest_journal_panel.gd")

const QUESTS_PATH := "res://data/quests/quest_catalog.tres"
const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const PILL_PATH := "res://data/items/item_bo_huyet_dan.tres"

const EVALUATIONS := 20000
## Generous on purpose: the claim is "microseconds, not a frame", and CI machines vary. The
## measured figure is printed and logged in docs/PERFORMANCE.md.
const BUDGET_USEC_PER_EVALUATION := 100.0


func test_nothing_about_quests_runs_per_frame() -> void:
	var quests: QuestRuntime = QuestRuntimeScript.new()
	add_to_tree(quests)
	var rewards: RewardRuntime = RewardRuntimeScript.new()
	add_to_tree(rewards)
	var journal: QuestJournalPanel = JournalScript.new()
	add_to_tree(journal)
	for node: Node in [quests, rewards, journal]:
		assert_false(node.is_processing(), "%s has no _process" % node.get_script().resource_path)
		assert_false(node.is_physics_processing(), "and no _physics_process")
	for script: Script in [QuestRuntimeScript, RewardRuntimeScript, JournalScript]:
		var source := script.source_code
		assert_false(source.contains("func _process(") or source.contains("func _physics_process(")
			or source.contains("Timer.new()"),
			"%s declares no per-frame callback and no timer" % script.resource_path)
	free_node(journal)
	free_node(rewards)
	free_node(quests)


func test_asking_where_a_quest_stands_costs_microseconds() -> void:
	var knowledge := KnowledgeService.new(load(KNOWLEDGE_PATH) as KnowledgeCatalogData,
		KnowledgeStore.new())
	var bag := InventoryState.new()
	bag.add(load(PILL_PATH) as ItemData, 1)
	var service := QuestService.new(load(QUESTS_PATH) as QuestCatalogData, QuestState.new(),
		knowledge, RewardService.new(RewardLedger.new()),
		func(item_id: StringName) -> int: return bag.count_of(item_id))
	assert_true(service.is_ready(), "the shipped catalog")
	# The realistic worst case: both quests under way, neither ready, so every objective is
	# asked of its owner to the end (the bag is searched, the Core is asked, the count read).
	assert_true(service.accept(&"quest_unquiet_vein", &"actor_elder_shen").ok, "one under way")
	assert_true(service.accept(&"quest_treeline_pills", &"actor_scout_ko").ok, "and the other")
	var ready := 0
	var started := Time.get_ticks_usec()
	for i in EVALUATIONS:
		if service.phase_of(&"quest_unquiet_vein" if i % 2 == 0 else &"quest_treeline_pills") \
				== QuestData.Phase.READY:
			ready += 1
	var per_call := float(Time.get_ticks_usec() - started) / float(EVALUATIONS)
	print("[quest-budget] phase_of: %.2f usec per call over %d calls" % [per_call, EVALUATIONS])
	assert_eq(ready, 0, "every call really evaluated a quest that is not ready")
	assert_true(per_call <= BUDGET_USEC_PER_EVALUATION,
		"%.2f usec per evaluation is within %.0f" % [per_call, BUDGET_USEC_PER_EVALUATION])

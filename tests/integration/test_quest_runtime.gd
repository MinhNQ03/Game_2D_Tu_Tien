extends TestCase
## Integration tests for Phase 19: `QuestRuntime` with the REAL `DialogueRuntime`, `NpcRuntime`,
## `KnowledgeRuntime`, `InventoryRuntime`, `RelationshipRuntime`, `RewardRuntime`, the real
## `WorldNpc` bodies and the SHIPPED quest, dialogue and shop catalogs. A quest is taken,
## answered and given back the way a player does it: by saying so to the person, in reach.
## The world, combat and progression are stand-ins (the things a runtime asks them for). No
## live `/root` singleton is driven (D-019) and every node is freed by its test (L-019).

const KnowledgeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")
const CultivationScript := preload("res://src/gameplay/world/cultivation_runtime.gd")
const InventoryScript := preload("res://src/gameplay/world/inventory_runtime.gd")
const RelationshipScript := preload("res://src/gameplay/world/relationship_runtime.gd")
const NpcRuntimeScript := preload("res://src/gameplay/world/npc_runtime.gd")
const DialogueRuntimeScript := preload("res://src/gameplay/world/dialogue_runtime.gd")
const QuestRuntimeScript := preload("res://src/gameplay/world/quest_runtime.gd")
const RewardRuntimeScript := preload("res://src/gameplay/world/reward_runtime.gd")
const WorldNpcScript := preload("res://src/gameplay/npcs/world_npc.gd")
const RegistryScript := preload("res://src/domain/character/character_registry.gd")

const KO_TEMPLATE := "res://data/characters/npc_scout_ko.tres"
const SHEN_TEMPLATE := "res://data/characters/npc_elder_shen.tres"
const QUESTS := "res://data/quests/quest_catalog.tres"
const KO := &"actor_scout_ko"
const SHEN := &"actor_elder_shen"
const PLAYER := &"player"
const VEIN := &"quest_unquiet_vein"
const PILLS := &"quest_treeline_pills"
const WOLF := &"enemy_mist_wolf"
const STELE := &"know_lac_ha_stele_record"
const WORD := &"know_vu_lang_hunting_ground"
const PILL := &"item_bo_huyet_dan"
const STONE := &"item_linh_thach"
const SWORD := &"item_kiem_thanh_thiet"


class StubWorld extends Node:
	signal active_map_leaving()
	signal active_map_ready()
	var map: Node2D = null
	var player: Node2D = null
	var character: CharacterState = null
	var registry: CharacterRegistry = null
	var kinds: Array[StringName] = [&"enemy_mist_wolf"]

	func get_active_map() -> Node:
		return map

	func get_player() -> Node:
		return player

	func get_player_character() -> CharacterState:
		return character

	func get_character_registry() -> CharacterRegistry:
		return registry

	func get_enemy_kinds() -> Array[StringName]:
		return kinds


class StubCombat extends Node:
	signal enemy_defeated(reward_id: StringName, xp_reward: int)
	var kinds: Dictionary = {}

	func defeated_kind(reward_id: StringName) -> StringName:
		return kinds.get(reward_id, &"")

	## A creature of `kind` falls, announced as `reward_id` — as `CombatRuntime` does.
	func fell(kind: StringName, reward_id: StringName) -> void:
		kinds[reward_id] = kind
		enemy_defeated.emit(reward_id, 5)


class StubProgression extends Node:
	var xp: int = 0

	func grant_reward(amount: int, _source_id: StringName) -> bool:
		xp += amount
		return true


class Rig extends RefCounted:
	var world: StubWorld
	var knowledge: KnowledgeRuntime
	var cultivation: CultivationRuntime
	var inventory: InventoryRuntime
	var relationship: RelationshipRuntime
	var npcs: NpcRuntime
	var combat: StubCombat
	var progression: StubProgression
	var rewards: RewardRuntime
	var quests: QuestRuntime
	var dialogue: DialogueRuntime
	var ko: WorldNpc
	var shen: WorldNpc
	var log: Array[String] = []
	var refused: Array[StringName] = []
	var views: int = 0

	func on_accepted(quest_id: StringName) -> void:
		log.append("accepted %s" % quest_id)

	func on_abandoned(quest_id: StringName) -> void:
		log.append("abandoned %s" % quest_id)

	func on_advanced(quest_id: StringName, objective_id: StringName, value: int,
			required: int) -> void:
		log.append("advanced %s/%s %d/%d" % [quest_id, objective_id, value, required])

	func on_ready(quest_id: StringName) -> void:
		log.append("ready %s" % quest_id)

	func on_completed(quest_id: StringName) -> void:
		log.append("completed %s" % quest_id)

	func on_refused(reason: StringName) -> void:
		refused.append(reason)

	func on_view() -> void:
		views += 1


func _npc(host: Node, id: StringName, template_path: String, at: Vector2) -> WorldNpc:
	var npc: WorldNpc = WorldNpcScript.new()
	npc.name = String(id)
	npc.character_id = id
	npc.character_template = load(template_path) as CharacterTemplateData
	host.add_child(npc)
	npc.global_position = at
	return npc


## Kha Thản and Thẩm Bất Kỳ stand 400 px apart; the player starts beside the elder.
func _rig(quest_catalog: QuestCatalogData = null, start: bool = true) -> Rig:
	var rig := Rig.new()
	rig.world = StubWorld.new()
	add_to_tree(rig.world)
	rig.world.map = Node2D.new()
	rig.world.add_child(rig.world.map)
	var pickups := Node2D.new()
	pickups.name = "Pickups"
	rig.world.map.add_child(pickups)
	var host := Node2D.new()
	host.name = "Interactables"
	rig.world.map.add_child(host)
	rig.ko = _npc(host, KO, KO_TEMPLATE, Vector2(200, 200))
	rig.shen = _npc(host, SHEN, SHEN_TEMPLATE, Vector2(600, 200))
	rig.world.player = Node2D.new()
	rig.world.map.add_child(rig.world.player)
	rig.world.character = CharacterState.new()
	rig.world.character.instance_id = PLAYER
	rig.world.character.realm_id = &"realm_pham"
	rig.world.registry = RegistryScript.new()
	rig.world.registry.add(rig.world.character)
	rig.knowledge = KnowledgeScript.new()
	add_to_tree(rig.knowledge)
	rig.knowledge.start_session()
	rig.cultivation = CultivationScript.new()
	add_to_tree(rig.cultivation)
	rig.cultivation.start_session(rig.world.character, rig.knowledge, rig.world)
	rig.inventory = InventoryScript.new()
	add_to_tree(rig.inventory)
	rig.inventory.start_session(rig.world.character, rig.world, rig.knowledge, rig.cultivation)
	rig.relationship = RelationshipScript.new()
	add_to_tree(rig.relationship)
	rig.relationship.start_session()
	rig.npcs = NpcRuntimeScript.new()
	add_to_tree(rig.npcs)
	rig.npcs.start_session(rig.world, rig.inventory, rig.relationship)
	rig.combat = StubCombat.new()
	add_to_tree(rig.combat)
	rig.progression = StubProgression.new()
	add_to_tree(rig.progression)
	rig.rewards = RewardRuntimeScript.new()
	add_to_tree(rig.rewards)
	rig.rewards.start_session()
	rig.quests = QuestRuntimeScript.new()
	add_to_tree(rig.quests)
	rig.dialogue = DialogueRuntimeScript.new()
	add_to_tree(rig.dialogue)
	if start:
		assert_true(_start_quests(rig, quest_catalog), "the quest session starts")
		assert_true(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
			rig.relationship, null, rig.quests), "the dialogue session starts")
	rig.quests.quest_accepted.connect(rig.on_accepted)
	rig.quests.quest_abandoned.connect(rig.on_abandoned)
	rig.quests.quest_advanced.connect(rig.on_advanced)
	rig.quests.quest_ready.connect(rig.on_ready)
	rig.quests.quest_completed.connect(rig.on_completed)
	rig.quests.view_changed.connect(rig.on_view)
	rig.dialogue.choice_refused.connect(rig.on_refused)
	_stand_by(rig, rig.shen)
	return rig


func _start_quests(rig: Rig, catalog: QuestCatalogData = null) -> bool:
	return rig.quests.start_session(rig.world, rig.knowledge, rig.inventory, rig.combat,
		rig.progression, rig.relationship, rig.rewards, catalog)


func _free(rig: Rig) -> void:
	rig.quests.quest_accepted.disconnect(rig.on_accepted)
	rig.quests.quest_abandoned.disconnect(rig.on_abandoned)
	rig.quests.quest_advanced.disconnect(rig.on_advanced)
	rig.quests.quest_ready.disconnect(rig.on_ready)
	rig.quests.quest_completed.disconnect(rig.on_completed)
	rig.quests.view_changed.disconnect(rig.on_view)
	rig.dialogue.choice_refused.disconnect(rig.on_refused)
	rig.dialogue.end_session()
	rig.quests.end_session()
	rig.npcs.end_session()
	rig.rewards.end_session()
	rig.relationship.end_session()
	rig.inventory.end_session()
	rig.cultivation.end_session()
	rig.knowledge.end_session()
	for node: Node in [rig.dialogue, rig.quests, rig.rewards, rig.progression, rig.combat,
			rig.npcs, rig.relationship, rig.inventory, rig.cultivation, rig.knowledge, rig.world]:
		free_node(node)


func _stand_by(rig: Rig, npc: WorldNpc) -> void:
	rig.world.player.global_position = npc.global_position + Vector2(0, 20)


func _choice_ids(rig: Rig) -> Array[StringName]:
	var ids: Array[StringName] = []
	for option in rig.dialogue.build_view().choices:
		ids.append(option["id"])
	return ids


## Walk to `npc`, talk, pass the greeting: the conversation is at their "what do you need".
func _open_hub(rig: Rig, npc: WorldNpc) -> void:
	_stand_by(rig, npc)
	rig.dialogue.leave()
	assert_eq(rig.dialogue.talk(npc.character_id), &"", "the talk starts")
	rig.dialogue.advance()


## Say `choice_id` at the current line.
func _say(rig: Rig, choice_id: StringName) -> DialogueOutcome:
	return rig.dialogue.choose(rig.dialogue.current_node_id(), choice_id)


func _phase(rig: Rig, quest_id: StringName) -> QuestService.Phase:
	return rig.quests.get_service().phase_of(quest_id)


func _regard(rig: Rig, who: StringName, dimension: StringName) -> int:
	return RegardRules.read(rig.relationship.get_service(), rig.relationship.get_config(), who,
		PLAYER, dimension)


## Read the stele, then take the elder's task through his own lines.
func _take_vein(rig: Rig) -> void:
	rig.knowledge.grant(STELE, &"source_lac_ha_stele")
	_open_hub(rig, rig.shen)
	assert_true(_say(rig, &"shen_task_ask").ok, "asked what weighs on him")
	rig.dialogue.advance()
	assert_true(_say(rig, &"shen_task_accept").ok, "agreed")


func _take_pills(rig: Rig) -> void:
	_open_hub(rig, rig.ko)
	assert_true(_say(rig, &"ko_pills_ask").ok, "asked what he is short of")
	assert_true(_say(rig, &"ko_pills_accept").ok, "agreed")


func _entry(view: QuestJournalView, quest_id: StringName) -> Dictionary:
	for entry in view.entries:
		if entry["quest_id"] == quest_id:
			return entry
	return {}


func _connections(emitter: Signal, target: Object) -> int:
	var count := 0
	for connection in emitter.get_connections():
		if (connection["callable"] as Callable).get_object() == target:
			count += 1
	return count


# === Session ======================================================================

func test_the_session_starts_on_the_shipped_content_and_owns_no_process() -> void:
	var rig := _rig()
	assert_true(rig.quests.is_session_active(), "live")
	assert_false(rig.quests.is_processing(), "it never runs per frame")
	assert_false(rig.quests.is_physics_processing(), "nor per physics tick")
	assert_false(rig.rewards.is_processing(), "nor does the reward ledger's node")
	assert_false(_start_quests(rig), "a second start is refused")
	var catalog := rig.quests.get_service().catalog()
	assert_eq(catalog.entries.size(), 2, "two authored quests")
	assert_eq(catalog.validation_errors(), [] as Array[String], "structurally valid")
	assert_eq([_phase(rig, VEIN), _phase(rig, PILLS)],
		[QuestService.Phase.AVAILABLE, QuestService.Phase.AVAILABLE], "both on offer, none taken")
	assert_eq(rig.quests.to_dict(), {"schema": 1, "quests": {}}, "and nothing recorded")
	assert_eq(rig.rewards.to_dict(), {"schema": 1, "claimed": []}, "nothing paid")
	_free(rig)


func test_content_an_owner_cannot_supply_stops_the_session_and_leaves_nothing_behind() -> void:
	var rig := _rig(null, false)
	var shipped := load(QUESTS) as QuestCatalogData
	var cases: Dictionary = {}
	var unknown_item: QuestCatalogData = shipped.duplicate(true)
	unknown_item.entry(PILLS).objectives[0].target_id = &"item_nothing"
	cases["an item nobody defines"] = unknown_item
	var unknown_knowledge: QuestCatalogData = shipped.duplicate(true)
	unknown_knowledge.entry(VEIN).objectives[1].target_id = &"know_nothing"
	cases["knowledge nobody defines"] = unknown_knowledge
	var unknown_enemy: QuestCatalogData = shipped.duplicate(true)
	unknown_enemy.entry(VEIN).objectives[0].target_id = &"enemy_nothing"
	cases["a creature no map spawns"] = unknown_enemy
	var unknown_giver: QuestCatalogData = shipped.duplicate(true)
	unknown_giver.entry(VEIN).giver_id = &"actor_nobody"
	cases["a giver nobody registered"] = unknown_giver
	var unknown_dimension: QuestCatalogData = shipped.duplicate(true)
	unknown_dimension.entry(PILLS).reward.regard_dimension = &"charm"
	cases["a dimension the graph lacks"] = unknown_dimension
	var untranslated: QuestCatalogData = shipped.duplicate(true)
	untranslated.entry(VEIN).title_key = &"QUEST_NO_SUCH_TITLE"
	cases["a title with no translation"] = untranslated
	var invalid: QuestCatalogData = shipped.duplicate(true)
	invalid.entry(VEIN).objectives.clear()
	cases["a structurally invalid catalog"] = invalid
	for label: String in cases:
		assert_false(_start_quests(rig, cases[label]), "%s fails closed" % label)
		assert_false(rig.quests.is_session_active(), "%s: no session" % label)
		assert_null(rig.quests.get_service(), "%s: no service kept" % label)
		assert_eq(_connections(rig.knowledge.knowledge_gained, rig.quests)
			+ _connections(rig.inventory.inventory_changed, rig.quests)
			+ _connections(rig.combat.enemy_defeated, rig.quests), 0,
			"%s: nothing connected" % label)
	assert_eq(shipped.validation_errors(), [] as Array[String],
		"the shipped catalog itself was never touched")
	# Dependencies: each missing or inactive one refuses the start.
	var idle := RewardRuntimeScript.new() as RewardRuntime
	assert_false(rig.quests.start_session(rig.world, rig.knowledge, rig.inventory, rig.combat,
		rig.progression, rig.relationship, idle), "an inactive reward ledger")
	idle.free()
	assert_false(rig.quests.start_session(rig.world, rig.knowledge, rig.inventory, Node.new(),
		rig.progression, rig.relationship, rig.rewards), "a combat that announces nothing")
	assert_false(rig.quests.start_session(null, rig.knowledge, rig.inventory, rig.combat,
		rig.progression, rig.relationship, rig.rewards), "no world")
	var registry := rig.world.registry
	rig.world.registry = null
	assert_false(_start_quests(rig), "a world with no registry: refused, not skipped")
	rig.world.registry = registry
	assert_false(rig.quests.is_session_active(), "still no session")
	assert_true(_start_quests(rig), "and every refusal left it able to start properly")
	assert_eq(_connections(rig.knowledge.knowledge_gained, rig.quests)
		+ _connections(rig.inventory.inventory_changed, rig.quests)
		+ _connections(rig.combat.enemy_defeated, rig.quests), 3, "with exactly its three")
	_free(rig)


func test_ending_the_session_stops_listening_and_a_restart_listens_once() -> void:
	var rig := _rig()
	_take_vein(rig)
	rig.dialogue.end_session()
	rig.quests.end_session()
	assert_false(rig.quests.is_session_active(), "ended")
	assert_eq(_connections(rig.knowledge.knowledge_gained, rig.quests)
		+ _connections(rig.inventory.inventory_changed, rig.quests)
		+ _connections(rig.combat.enemy_defeated, rig.quests), 0, "every connection dropped")
	rig.log.clear()
	rig.combat.fell(WOLF, &"enemy_mist_wolf_1#1")
	rig.knowledge.grant(WORD, &"test")
	assert_eq(rig.log, [] as Array[String], "the world moving reaches nothing")
	assert_eq(rig.quests.accept(VEIN, SHEN).reason, QuestService.REFUSE_NOT_READY,
		"and nothing can be asked of it")
	assert_false(rig.quests.build_view().available, "its view is empty")
	rig.quests.end_session()  # idempotent
	assert_true(_start_quests(rig), "it starts again over the same world")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.AVAILABLE,
		"a new session knows nothing of the old one's quests")
	assert_eq(_connections(rig.combat.enemy_defeated, rig.quests), 1, "connected once, not twice")
	assert_true(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, null, rig.quests), "and conversations with it")
	_free(rig)


# === Taking, declining, giving back ================================================

func test_the_elder_offers_only_to_one_who_has_read_and_declining_changes_nothing() -> void:
	var rig := _rig()
	_open_hub(rig, rig.shen)
	assert_eq(_choice_ids(rig), [&"shen_leave"] as Array[StringName],
		"to someone who has not read the stele he offers nothing")
	assert_false(_say(rig, &"shen_task_ask").ok, "and asking anyway is refused")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.AVAILABLE, "nothing was taken")
	rig.knowledge.grant(STELE, &"source_lac_ha_stele")
	_open_hub(rig, rig.shen)
	assert_true(_choice_ids(rig).has(&"shen_task_ask"), "a reader may ask what weighs on him")
	_say(rig, &"shen_task_ask")
	assert_eq(rig.dialogue.current_node_id(), &"shen_task_why", "he says why")
	rig.dialogue.advance()
	assert_eq(_choice_ids(rig), [&"shen_task_accept", &"shen_task_decline"] as Array[StringName],
		"and the ask is an explicit choice: take it, or not now")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.AVAILABLE, "hearing the ask takes nothing")
	var declined := _say(rig, &"shen_task_decline")
	assert_true(declined.ok, "declining is a complete path")
	assert_eq(rig.dialogue.current_node_id(), &"shen_hub", "back to what he offers")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.AVAILABLE, "still on offer")
	assert_eq(rig.quests.to_dict()["quests"], {}, "with no record of a refusal anywhere")
	assert_eq(rig.log, [] as Array[String], "and nothing announced")
	assert_true(_choice_ids(rig).has(&"shen_task_ask"), "he can be asked again")
	_free(rig)


func test_accepting_is_announced_once_and_changes_what_he_says() -> void:
	var rig := _rig()
	_take_vein(rig)
	assert_eq(_phase(rig, VEIN), QuestService.Phase.ACTIVE, "taken")
	assert_eq(rig.log, ["accepted quest_unquiet_vein"] as Array[String], "announced once")
	assert_eq(rig.dialogue.current_node_id(), &"shen_task_taken", "he sends the player off")
	_open_hub(rig, rig.shen)
	var ids := _choice_ids(rig)
	assert_false(ids.has(&"shen_task_ask"), "it is not offered twice")
	assert_true(ids.has(&"shen_task_about"), "he can be spoken to about it")
	assert_false(ids.has(&"shen_task_report_word") or ids.has(&"shen_task_report_fight"),
		"and there is nothing to report yet")
	assert_eq(rig.quests.accept(VEIN, SHEN).reason, QuestService.REFUSE_ALREADY_TAKEN,
		"asked directly, a second accept is refused")
	assert_eq(rig.quests.accept(PILLS, SHEN).reason, QuestService.REFUSE_WRONG_PERSON,
		"and the scout's errand is not the elder's to give")
	_free(rig)


func test_abandoning_needs_a_second_explicit_choice_and_offers_the_quest_again() -> void:
	var rig := _rig()
	_take_vein(rig)
	_open_hub(rig, rig.shen)
	_say(rig, &"shen_task_about")
	assert_eq(_choice_ids(rig), [&"shen_task_keep", &"shen_task_giveup"] as Array[StringName],
		"he asks how it goes")
	_say(rig, &"shen_task_giveup")
	assert_eq(rig.dialogue.current_node_id(), &"shen_task_confirm",
		"asking to be released only raises the question")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.ACTIVE, "nothing is given up yet")
	assert_eq(_choice_ids(rig)[0], &"shen_task_stay",
		"the answer under the cursor is the one that keeps the quest")
	_say(rig, &"shen_task_stay")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.ACTIVE, "staying keeps it")
	_say(rig, &"shen_task_about")
	_say(rig, &"shen_task_giveup")
	rig.log.clear()
	assert_true(_say(rig, &"shen_task_abandon").ok, "confirmed")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.AVAILABLE, "given back")
	assert_eq(rig.log, ["abandoned quest_unquiet_vein"] as Array[String], "announced once")
	assert_eq(rig.rewards.to_dict()["claimed"], [], "nothing was paid for it")
	_open_hub(rig, rig.shen)
	assert_true(_choice_ids(rig).has(&"shen_task_ask"), "and he offers it again")
	_free(rig)


# === Quest 1: two ways to the same answer ==========================================

func test_the_scouts_word_answers_the_elder_without_a_fight() -> void:
	var rig := _rig()
	_take_vein(rig)
	rig.log.clear()
	_open_hub(rig, rig.ko)
	assert_true(_say(rig, &"ko_ask_woods").ok, "asked the scout about the woods")
	assert_true(rig.knowledge.get_service().knows(WORD), "the Knowledge Core holds his word")
	assert_eq(rig.log, ["ready quest_unquiet_vein"] as Array[String],
		"and the quest says it is ready — once, with no separate 'progress' line before it")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.READY, "ready")
	_open_hub(rig, rig.shen)
	var ids := _choice_ids(rig)
	assert_true(ids.has(&"shen_task_report_word"), "he can be told what the scout says")
	assert_false(ids.has(&"shen_task_report_fight"), "not a fight that never happened")
	rig.log.clear()
	var told := _say(rig, &"shen_task_report_word")
	assert_true(told.ok, "told")
	assert_eq(rig.dialogue.current_node_id(), &"shen_task_done_word",
		"and he answers what the scout's word means")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.COMPLETED, "completed")
	assert_eq(rig.log, ["completed quest_unquiet_vein"] as Array[String], "announced once")
	assert_eq(rig.inventory.count_of(PILL), 2, "two pills from the hall's store are in the bag")
	assert_eq(rig.progression.xp, 10, "10 XP reached progression")
	assert_eq(_regard(rig, SHEN, &"respect"), 10, "his respect is in the relationship graph")
	assert_true(rig.rewards.get_ledger().has(&"quest:quest_unquiet_vein"), "recorded as paid")
	_free(rig)


func test_a_fight_answers_the_elder_without_the_scout() -> void:
	var rig := _rig()
	rig.combat.fell(WOLF, &"enemy_mist_wolf_1#1")
	_take_vein(rig)
	assert_eq(_phase(rig, VEIN), QuestService.Phase.ACTIVE,
		"a wolf killed BEFORE the task was taken answers nothing")
	rig.log.clear()
	rig.combat.fell(&"enemy_other_thing", &"enemy_other_thing_1#2")
	assert_eq(rig.log, [] as Array[String], "nor does some other creature")
	rig.combat.fell(WOLF, &"enemy_mist_wolf_2#3")
	rig.combat.enemy_defeated.emit(&"enemy_mist_wolf_2#3", 5)  # the same defeat, delivered twice
	assert_eq(rig.log, ["ready quest_unquiet_vein"] as Array[String], "one wolf, counted once")
	assert_false(rig.knowledge.get_service().knows(WORD), "with the scout never asked")
	_open_hub(rig, rig.shen)
	var ids := _choice_ids(rig)
	assert_true(ids.has(&"shen_task_report_fight"), "he can be told what was met at the vein")
	assert_false(ids.has(&"shen_task_report_word"), "not a word nobody gave")
	assert_true(_say(rig, &"shen_task_report_fight").ok, "told")
	assert_eq(rig.dialogue.current_node_id(), &"shen_task_done_fight",
		"and he draws the OTHER conclusion: nobody crosses unarmed")
	assert_eq([rig.inventory.count_of(PILL), rig.progression.xp, _regard(rig, SHEN, &"respect")],
		[2, 10, 10], "the same reward, once")
	_free(rig)


func test_what_was_already_known_counts_the_moment_the_task_is_taken() -> void:
	var rig := _rig()
	rig.knowledge.grant(WORD, &"test")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.AVAILABLE,
		"knowing the answer does not take the task for the player")
	_take_vein(rig)
	assert_eq(rig.log, ["accepted quest_unquiet_vein", "ready quest_unquiet_vein"]
		as Array[String], "taken, and ready at once: nobody is sent to learn what they know")
	_open_hub(rig, rig.shen)
	assert_true(_say(rig, &"shen_task_report_word").ok, "it can be reported straight away")
	_free(rig)


# === Quest 2: something carried ====================================================

func test_the_scouts_pills_are_counted_from_the_bag_and_change_hands_once() -> void:
	var rig := _rig()
	_take_pills(rig)
	rig.log.clear()
	rig.inventory.give(PILL, 1)
	assert_eq(rig.log, ["advanced quest_treeline_pills/carry 1/2"] as Array[String],
		"one pill is progress, said as such")
	rig.inventory.give(PILL, 2)
	assert_eq(rig.log.back(), "ready quest_treeline_pills", "with two, it is ready")
	assert_eq(rig.log.size(), 2, "and that was said once, though three are held")
	# The same pills heal the player: using them is a real choice.
	rig.inventory.take(PILL, 2)
	assert_eq(_phase(rig, PILLS), QuestService.Phase.ACTIVE, "swallowed on the road: not ready")
	_open_hub(rig, rig.ko)
	assert_false(_choice_ids(rig).has(&"ko_pills_give"), "so handing over is not offered")
	assert_false(_say(rig, &"ko_pills_give").ok, "and saying it anyway is refused")
	assert_eq(rig.refused, [DialogueService.REFUSE_CHOICE_GONE] as Array[StringName], "loudly")
	assert_eq(rig.inventory.count_of(PILL), 1, "the one pill left was not taken")
	rig.inventory.give(PILL, 1)
	assert_eq(rig.log.back(), "ready quest_treeline_pills", "ready AGAIN is said again")
	rig.inventory.give(STONE, 1)
	var base := rig.npcs.standing_for(rig.npcs.get_service().catalog().shop_of_keeper(KO)).value
	_open_hub(rig, rig.ko)
	rig.log.clear()
	var given := _say(rig, &"ko_pills_give")
	assert_true(given.ok, "handed over")
	assert_eq(rig.dialogue.current_node_id(), &"ko_pills_done", "he counts them")
	assert_eq([rig.inventory.count_of(PILL), rig.inventory.count_of(STONE)], [0, 4],
		"two pills left the bag and three stones joined the one already there")
	assert_eq(_regard(rig, KO, &"affinity"), base + 15, "his affinity moved in the graph")
	assert_eq(rig.npcs.standing_for(rig.npcs.get_service().catalog().shop_of_keeper(KO)).value,
		base + 15, "which is the very number his shop prices on")
	assert_eq(rig.log, ["completed quest_treeline_pills"] as Array[String], "announced once")
	assert_eq(rig.progression.xp, 0, "this errand pays no XP, and none was invented")
	_open_hub(rig, rig.ko)
	var ids := _choice_ids(rig)
	assert_false(ids.has(&"ko_pills_ask") or ids.has(&"ko_pills_about")
		or ids.has(&"ko_pills_give"), "and it is over: he does not bring it up again")
	_free(rig)


# === Reward safety =================================================================

func test_a_full_bag_refuses_the_reward_keeps_the_talk_where_it_was_and_loses_nothing() -> void:
	var rig := _rig()
	_take_vein(rig)
	rig.knowledge.grant(WORD, &"test")
	var bag := rig.inventory.get_bag()
	rig.inventory.give(SWORD, bag.capacity)
	assert_eq(bag.stack_count(), bag.capacity, "the bag is full")
	_open_hub(rig, rig.shen)
	rig.log.clear()
	var refused := _say(rig, &"shen_task_report_word")
	assert_false(refused.ok, "the report is refused")
	assert_eq(rig.refused, [QuestService.REFUSE_NO_ROOM] as Array[StringName],
		"with the reason that matters to the player: no room in the satchel")
	assert_eq(rig.dialogue.current_node_id(), &"shen_hub",
		"the conversation did not move on as if it had worked")
	assert_true(_choice_ids(rig).has(&"shen_task_report_word"), "the report is still offered")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.READY, "the quest is still ready")
	assert_eq([rig.inventory.count_of(PILL), rig.progression.xp, _regard(rig, SHEN, &"respect")],
		[0, 0, 0], "no XP and no regard were paid ahead of the pills")
	assert_eq(rig.rewards.to_dict()["claimed"], [], "nothing is recorded as paid")
	assert_eq(rig.log, [] as Array[String], "and nothing was announced as done")
	# Make room; say it again.
	rig.inventory.take(SWORD, 1)
	assert_true(_say(rig, &"shen_task_report_word").ok, "with room made, it goes through")
	assert_eq([rig.inventory.count_of(PILL), rig.progression.xp, _regard(rig, SHEN, &"respect")],
		[2, 10, 10], "in full, once")
	assert_eq(rig.log, ["completed quest_unquiet_vein"] as Array[String], "and is announced")
	_free(rig)


func test_a_finished_quest_cannot_be_answered_or_paid_a_second_time() -> void:
	var rig := _rig()
	_take_vein(rig)
	rig.knowledge.grant(WORD, &"test")
	_open_hub(rig, rig.shen)
	_say(rig, &"shen_task_report_word")
	var paid := [rig.inventory.count_of(PILL), rig.progression.xp, _regard(rig, SHEN, &"respect")]
	rig.log.clear()
	_open_hub(rig, rig.shen)
	assert_false(_choice_ids(rig).has(&"shen_task_report_word"), "the report is gone")
	assert_false(_say(rig, &"shen_task_report_word").ok, "saying it again is refused")
	assert_eq(rig.quests.turn_in(VEIN, SHEN).reason, QuestService.REFUSE_ALREADY_DONE,
		"asked directly, by any path: refused as done")
	assert_eq(rig.quests.accept(VEIN, SHEN).reason, QuestService.REFUSE_ALREADY_DONE,
		"and it is never offered again")
	assert_eq([rig.inventory.count_of(PILL), rig.progression.xp, _regard(rig, SHEN, &"respect")],
		paid, "nothing was paid twice")
	assert_eq(rig.log, [] as Array[String], "nor announced twice")
	_free(rig)


func test_a_listener_that_answers_again_from_inside_the_payment_is_refused() -> void:
	var rig := _rig()
	_take_vein(rig)
	rig.knowledge.grant(WORD, &"test")
	var inner: Array[StringName] = []
	# Someone hears the bag change mid-payment and submits the same turn-in again.
	var on_bag := func() -> void:
		if inner.is_empty():
			inner.append(rig.quests.turn_in(VEIN, SHEN).reason)
	rig.inventory.inventory_changed.connect(on_bag)
	_open_hub(rig, rig.shen)
	var told := _say(rig, &"shen_task_report_word")
	rig.inventory.inventory_changed.disconnect(on_bag)
	assert_true(told.ok, "the outer answer completes")
	assert_eq(inner, [QuestService.REFUSE_UNPAYABLE] as Array[StringName],
		"the answer from inside its own payment is refused")
	assert_eq([rig.inventory.count_of(PILL), rig.progression.xp, _regard(rig, SHEN, &"respect")],
		[2, 10, 10], "and everything was paid exactly once")
	_free(rig)


func test_answers_are_only_taken_by_the_right_person_in_reach() -> void:
	var rig := _rig()
	_take_vein(rig)
	rig.knowledge.grant(WORD, &"test")
	assert_eq(rig.quests.turn_in(VEIN, KO).reason, QuestService.REFUSE_WRONG_PERSON,
		"the scout cannot take the elder's answer")
	_open_hub(rig, rig.shen)
	rig.world.player.global_position = Vector2(2000, 2000)
	var far := _say(rig, &"shen_task_report_word")
	assert_false(far.ok, "an answer shouted from across the map is refused")
	assert_eq(rig.refused, [NpcRuntime.REFUSE_TOO_FAR] as Array[StringName], "for range")
	assert_eq(_phase(rig, VEIN), QuestService.Phase.READY, "and nothing was paid")
	assert_eq(rig.inventory.count_of(PILL), 0, "no pills crossed the map")
	_free(rig)


# === The world moving ==============================================================

func test_progress_survives_a_map_change_and_readiness_is_said_once() -> void:
	var rig := _rig()
	_take_pills(rig)
	rig.inventory.give(PILL, 1)
	rig.world.active_map_leaving.emit()
	rig.world.active_map_ready.emit()
	assert_eq(_phase(rig, PILLS), QuestService.Phase.ACTIVE, "still under way after a map change")
	rig.log.clear()
	rig.inventory.give(PILL, 1)
	rig.inventory.give(STONE, 5)  # the bag changing again changes nothing about the quest
	rig.knowledge.grant(STELE, &"test")
	assert_eq(rig.log, ["ready quest_treeline_pills"] as Array[String],
		"ready is said once, however often the world moves afterwards")
	_free(rig)


func test_the_view_changes_only_when_something_it_shows_does() -> void:
	var rig := _rig()
	assert_eq(rig.views, 0, "an idle session announces nothing")
	rig.inventory.give(STONE, 3)
	rig.knowledge.grant(STELE, &"test")
	assert_eq(rig.views, 0, "the bag and the Core moving, with no quest taken, change no view")
	_take_pills(rig)
	assert_eq(rig.views, 1, "taking a quest: one change")
	rig.inventory.give(STONE, 1)
	assert_eq(rig.views, 1, "an item no quest asks for: none")
	rig.inventory.give(PILL, 1)
	assert_eq(rig.views, 2, "progress: one more")
	rig.inventory.give(PILL, 5)
	assert_eq(rig.views, 3, "ready: one more")
	rig.inventory.give(PILL, 1)
	assert_eq(rig.views, 3, "more than was asked for shows nothing new")
	_free(rig)


func test_the_journal_view_says_what_to_do_next_for_whom_and_for_what() -> void:
	var rig := _rig()
	var idle := rig.quests.build_view()
	assert_true(idle.available, "a session has a view")
	assert_eq(idle.entries.size(), 2, "both quests are listed while on offer")
	assert_eq([idle.purpose_key, idle.purpose_phase],
		[&"QUEST_UNQUIET_VEIN_LEAD", QuestService.Phase.AVAILABLE],
		"with nothing taken, the purpose line is the first lead: where to go")
	_take_pills(rig)
	var taken := rig.quests.build_view()
	assert_eq([taken.purpose_key, taken.purpose_phase],
		[&"QUEST_TREELINE_PILLS_GOAL", QuestService.Phase.ACTIVE],
		"a quest under way outranks a lead: what to do")
	var pills := _entry(taken, PILLS)
	assert_eq([pills["title_key"], pills["summary_key"], pills["phase"], pills["owed"]],
		[&"QUEST_TREELINE_PILLS_TITLE", &"QUEST_TREELINE_PILLS_SUMMARY",
			QuestService.Phase.ACTIVE, false], "its title, its why, its state")
	assert_eq(pills["giver_name_key"], rig.world.registry.get_character(KO).name_key,
		"who asked, by the name in his CharacterState")
	assert_eq(pills["objectives"], [{"text_key": &"QUEST_TREELINE_PILLS_OBJ_CARRY", "value": 0,
		"required": 2, "met": false}], "the objective and its count, read from the bag")
	assert_eq(pills["reward_items"], [{"name_key": &"ITEM_LINH_THACH_NAME", "count": 3}],
		"and what it pays, before the commitment")
	assert_eq([pills["reward_regard_dimension"], pills["reward_regard_delta"]], [&"affinity", 15],
		"including whose regard")
	rig.inventory.give(PILL, 2)
	var ready := rig.quests.build_view()
	assert_eq([ready.purpose_key, ready.purpose_phase],
		[&"QUEST_TREELINE_PILLS_RETURN", QuestService.Phase.READY],
		"ready outranks everything: who to return to")
	assert_eq(_entry(ready, PILLS)["objectives"][0]["value"], 2, "2 of 2")
	var vein := _entry(ready, VEIN)
	assert_true(vein["any"], "the elder's task is marked as one-of")
	assert_eq(vein["objectives"].size(), 2, "with both ways listed")
	_open_hub(rig, rig.ko)
	_say(rig, &"ko_pills_give")
	var done := rig.quests.build_view()
	assert_eq(_entry(done, PILLS)["phase"], QuestService.Phase.COMPLETED, "done is shown as done")
	assert_eq(done.purpose_key, &"QUEST_UNQUIET_VEIN_LEAD",
		"and the purpose line moves on to what is still on offer")
	_free(rig)


# === Persistence boundary ==========================================================

func test_a_quest_under_way_round_trips_through_the_runtime_and_stays_paid_once() -> void:
	var rig := _rig()
	_take_vein(rig)
	rig.knowledge.grant(WORD, &"test")
	_open_hub(rig, rig.shen)
	_say(rig, &"shen_task_report_word")
	_take_pills(rig)
	rig.inventory.give(PILL, 2)
	var quests := rig.quests.to_dict()
	var ledger := rig.rewards.to_dict()
	assert_eq(quests["quests"]["quest_unquiet_vein"]["status"], "completed", "one done")
	assert_eq(quests["quests"]["quest_treeline_pills"]["status"], "active", "one under way")
	assert_true(ledger["claimed"].has("quest:quest_unquiet_vein"), "and its payment recorded")
	assert_false(rig.quests.has_method("save") or rig.quests.has_method("load"),
		"the boundary is plain data: no file is written by the quest session (Phase 23)")
	# A fresh session over the same world, hydrated as a load would.
	rig.dialogue.end_session()
	rig.quests.end_session()
	rig.rewards.end_session()
	rig.rewards.start_session()
	assert_true(_start_quests(rig), "restarted")
	assert_false(rig.quests.from_dict({"schema": 1, "quests": {"quest_nothing": {}}}),
		"a bad payload is rejected")
	assert_eq(rig.quests.to_dict()["quests"], {}, "and changed nothing")
	rig.log.clear()
	assert_true(rig.rewards.from_dict(ledger), "the ledger is restored")
	assert_true(rig.quests.from_dict(quests), "the quests are restored")
	assert_eq(rig.quests.to_dict(), quests, "identically")
	assert_eq(rig.log, ["ready quest_treeline_pills"] as Array[String],
		"what is ready says so once after the restore")
	assert_eq(rig.quests.turn_in(VEIN, SHEN).reason, QuestService.REFUSE_ALREADY_DONE,
		"the completed quest cannot be answered again")
	assert_true(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, null, rig.quests), "conversations resume")
	_open_hub(rig, rig.ko)
	assert_true(_say(rig, &"ko_pills_give").ok, "and the one under way is finished normally")
	assert_eq(rig.inventory.count_of(STONE), 3, "paid once")
	_free(rig)

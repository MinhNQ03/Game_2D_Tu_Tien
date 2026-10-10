extends TestCase
## Integration tests for Phase 18: `DialogueRuntime` with a REAL `NpcRuntime`, `KnowledgeRuntime`,
## `RelationshipRuntime`, `InventoryRuntime`, the real `WorldNpc` bodies and the SHIPPED dialogue
## and shop catalogs. The world is a stand-in (`StubWorld`): the things a runtime asks a world
## for. No live `/root` singleton is driven (D-019) and every node is freed by its test (L-019).

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
const LIN_TEMPLATE := "res://data/characters/npc_disciple_lin.tres"
const DIALOGUES := "res://data/dialogue/dialogue_catalog.tres"
const KO := &"actor_scout_ko"
const SHEN := &"actor_elder_shen"
const LIN := &"actor_disciple_lin"
const SHOP := &"shop_ko_than_packs"
const SWORD := &"item_kiem_thanh_thiet"
const PILL := &"item_bo_huyet_dan"
const COIN := &"item_linh_thach"
const STELE := &"know_lac_ha_stele_record"
const WOODS := &"know_vu_lang_hunting_ground"
const PLAYER := &"player"


class StubWorld extends Node:
	signal active_map_leaving()
	signal active_map_ready()
	var map: Node2D = null
	var player: Node2D = null
	var character: CharacterState = null
	var registry: CharacterRegistry = null

	func get_active_map() -> Node:
		return map

	func get_player() -> Node:
		return player

	func get_player_character() -> CharacterState:
		return character

	func get_character_registry() -> CharacterRegistry:
		return registry

	func get_enemy_kinds() -> Array[StringName]:
		return [&"enemy_mist_wolf"]


## What the quest session asks of combat: the defeat announcement and what fell.
class StubCombat extends Node:
	signal enemy_defeated(reward_id: StringName, xp_reward: int)
	var kinds: Dictionary = {}

	func defeated_kind(reward_id: StringName) -> StringName:
		return kinds.get(reward_id, &"")


## What the quest session asks of progression: the XP part of a reward.
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
	var lin: WorldNpc
	var made: Array = []
	var refused: Array[StringName] = []
	var closed: Array = []
	var learned: Array[StringName] = []
	var views: int = 0

	func on_made(outcome: DialogueOutcome) -> void:
		made.append(outcome)

	func on_refused(reason: StringName) -> void:
		refused.append(reason)

	func on_closed(dialogue_id: StringName, reason: StringName) -> void:
		closed.append([dialogue_id, reason])

	func on_learned(knowledge_id: StringName, _source: StringName) -> void:
		learned.append(knowledge_id)

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


## Kha Thản stands 20 px from the player (in reach); Thẩm Bất Kỳ and Lâm Nguyệt stand far off.
func _rig(catalog: DialogueCatalogData = null, start: bool = true) -> Rig:
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
	rig.lin = _npc(host, LIN, LIN_TEMPLATE, Vector2(900, 200))
	rig.world.player = Node2D.new()
	rig.world.map.add_child(rig.world.player)
	rig.world.player.global_position = Vector2(200, 220)
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
	assert_true(rig.quests.start_session(rig.world, rig.knowledge, rig.inventory, rig.combat,
		rig.progression, rig.relationship, rig.rewards), "the quest session starts")
	rig.dialogue = DialogueRuntimeScript.new()
	add_to_tree(rig.dialogue)
	if start:
		assert_true(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
			rig.relationship, catalog, rig.quests), "the dialogue session starts")
	rig.dialogue.choice_made.connect(rig.on_made)
	rig.dialogue.choice_refused.connect(rig.on_refused)
	rig.dialogue.dialogue_closed.connect(rig.on_closed)
	rig.dialogue.view_changed.connect(rig.on_view)
	rig.knowledge.knowledge_gained.connect(rig.on_learned)
	return rig


func _free(rig: Rig) -> void:
	rig.dialogue.choice_made.disconnect(rig.on_made)
	rig.dialogue.choice_refused.disconnect(rig.on_refused)
	rig.dialogue.dialogue_closed.disconnect(rig.on_closed)
	rig.dialogue.view_changed.disconnect(rig.on_view)
	rig.knowledge.knowledge_gained.disconnect(rig.on_learned)
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


## A one-line conversation for `speaker` — with a "trade" answer when `trades`.
func _small_talk(id: StringName, speaker: StringName, trades: bool) -> DialogueData:
	var line := DialogueNodeData.new()
	line.id = &"hello"
	line.text_key = &"DLG_KO_GREET"
	if trades:
		var effect := DialogueEffectData.new()
		effect.kind = DialogueEffectData.Kind.OPEN_SHOP
		var option := DialogueChoiceData.new()
		option.id = &"trade"
		option.text_key = &"DLG_KO_CHOICE_TRADE"
		option.effect = effect
		var options: Array[DialogueChoiceData] = [option]
		line.choices = options
	var dialogue := DialogueData.new()
	dialogue.id = id
	dialogue.speaker_id = speaker
	dialogue.start_node_id = &"hello"
	var nodes: Array[DialogueNodeData] = [line]
	dialogue.nodes = nodes
	return dialogue


func _stand_by(rig: Rig, npc: WorldNpc) -> void:
	rig.world.player.global_position = npc.global_position + Vector2(0, 20)


func _choice_ids(rig: Rig) -> Array[StringName]:
	var ids: Array[StringName] = []
	for option in rig.dialogue.build_view().choices:
		ids.append(option["id"])
	return ids


func _affinity(rig: Rig) -> int:
	return rig.dialogue.get_service().regard(KO, PLAYER, &"affinity")


## Talk to Kha Thản and walk to his "what do you need" line.
func _open_ko_hub(rig: Rig) -> void:
	assert_eq(rig.dialogue.talk(KO), &"", "the talk starts")
	rig.dialogue.advance()
	assert_eq(rig.dialogue.current_node_id(), &"ko_hub", "past the greeting")


func _sword_price(rig: Rig) -> int:
	for row in rig.npcs.build_shop_view().buy_rows:
		if row["item_id"] == SWORD:
			return int(row["price"])
	return -1


# === Session ======================================================================

func test_the_session_starts_on_the_shipped_content_and_owns_no_process() -> void:
	var rig := _rig()
	assert_true(rig.dialogue.is_session_active(), "live")
	assert_false(rig.dialogue.is_open(), "with no conversation open")
	assert_false(rig.dialogue.is_processing(), "it never runs per frame")
	assert_false(rig.dialogue.is_physics_processing(), "nor per physics tick")
	assert_false(rig.dialogue.build_view().open, "and its view is closed")
	assert_false(rig.dialogue.has_method("to_dict"),
		"it has no save boundary: Dialogue owns no persistent state (D-066)")
	assert_false(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, null, rig.quests), "a second start is refused")
	_free(rig)


func test_content_that_names_what_an_owner_lacks_stops_the_session() -> void:
	var catalog: DialogueCatalogData = (load(DIALOGUES) as DialogueCatalogData).duplicate(true)
	catalog.dialogue_of_speaker(KO).node(&"ko_hub").choice(&"ko_ask_woods") \
		.effect.knowledge_id = &"know_nothing_at_all"
	var rig := _rig(null, false)
	assert_false(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, catalog, rig.quests), "a grant of knowledge nobody defines fails closed")
	assert_false(rig.dialogue.is_session_active(), "no half-session")
	var no_shop: DialogueCatalogData = (load(DIALOGUES) as DialogueCatalogData).duplicate(true)
	no_shop.entries.append(_small_talk(&"dlg_test_lin", LIN, true))
	assert_eq(no_shop.validation_errors(), [] as Array[String], "structurally fine")
	assert_false(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, no_shop, rig.quests),
		"a 'trade' choice for someone who keeps no shop fails closed")
	var no_quests: DialogueCatalogData = load(DIALOGUES) as DialogueCatalogData
	assert_false(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, no_quests), "content that names quests cannot start without them")
	assert_false(rig.dialogue.is_session_active(), "no half-session")
	var inactive := RelationshipScript.new() as RelationshipRuntime
	assert_false(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge, inactive),
		"an inactive dependency refuses the start")
	inactive.free()
	_free(rig)


func _listeners(rig: Rig) -> int:
	var count := 0
	for connection in rig.world.active_map_leaving.get_connections():
		if (connection["callable"] as Callable).get_object() == rig.dialogue:
			count += 1
	return count


func test_a_speaker_nobody_registered_stops_the_session_and_leaves_nothing_behind() -> void:
	var rig := _rig(null, false)
	assert_true(rig.world.registry.has(KO) and rig.world.registry.has(SHEN),
		"both shipped speakers are registered characters")
	var orphan: DialogueCatalogData = (load(DIALOGUES) as DialogueCatalogData).duplicate(true)
	orphan.entries.append(_small_talk(&"dlg_test_nobody", &"actor_nobody_at_all", false))
	assert_eq(orphan.validation_errors(), [] as Array[String],
		"the catalog is structurally fine: only the registry can tell")
	assert_false(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, orphan, rig.quests), "a conversation spoken by nobody fails closed")
	assert_false(rig.dialogue.is_session_active(), "no session")
	assert_null(rig.dialogue.get_service(), "no service kept")
	assert_false(rig.dialogue.is_open(), "no conversation")
	assert_eq(_listeners(rig), 0, "and no connection to the world")
	assert_eq(rig.dialogue.talk(KO), DialogueService.REFUSE_NOT_READY,
		"so nobody can be talked to through it")
	# Registration is the question, not a body in THIS map: a registered speaker whose body
	# is elsewhere is valid content (reach is NpcRuntime's, when they are addressed).
	var elsewhere := CharacterState.new()
	elsewhere.instance_id = &"actor_nobody_at_all"
	rig.world.registry.add(elsewhere)
	assert_true(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, orphan, rig.quests), "once registered, the same content starts")
	assert_eq(_listeners(rig), 1, "with its one connection")
	assert_eq(rig.dialogue.talk(&"actor_nobody_at_all"), NpcRuntime.REFUSE_NOBODY,
		"and someone with no body here is refused by NpcRuntime, at the talk")
	_free(rig)


func test_a_world_with_no_character_registry_refuses_the_session() -> void:
	var rig := _rig(null, false)
	var registry := rig.world.registry
	rig.world.registry = null
	assert_false(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, null, rig.quests),
		"nobody to resolve the speakers in: refused, not skipped")
	assert_false(rig.dialogue.is_session_active(), "no half-session")
	assert_eq(_listeners(rig), 0, "no connection")
	rig.world.registry = registry
	assert_true(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, null, rig.quests), "and the refusal left it able to start properly")
	_free(rig)


# === Starting a talk ================================================================

func test_talking_opens_the_authored_conversation_at_its_first_line() -> void:
	var rig := _rig()
	assert_eq(rig.dialogue.talk(KO), &"", "accepted")
	assert_true(rig.dialogue.is_open(), "a conversation is open")
	assert_eq(rig.dialogue.open_dialogue_id(), &"dlg_scout_ko", "his")
	assert_eq(rig.dialogue.current_node_id(), &"ko_greet", "at its first line")
	assert_false(rig.npcs.is_shop_open(), "talking to a shopkeeper no longer opens his shop")
	assert_true(rig.ko.is_greeting(), "the line's gesture plays on his body")
	assert_eq(rig.ko.visual().get_direction(), CharacterVisualProfileData.Direction.DOWN,
		"and he has turned to the player")
	var view := rig.dialogue.build_view()
	assert_true(view.open, "the view is open")
	assert_eq(view.speaker_name_key, rig.world.registry.get_character(KO).name_key,
		"it names the speaker from his CharacterState")
	assert_eq(view.text_key, &"DLG_KO_GREET", "shows the line")
	assert_eq(view.mood, DialogueNodeData.Mood.WARY, "and how it is said")
	assert_true(view.gestures, "the portrait reacts with the gesture")
	assert_true(ResourceLoader.exists(view.portrait_path), "his portrait is a real texture")
	assert_eq(view.choices.size(), 0, "a greeting offers nothing to answer")
	assert_true(view.continues, "it continues")
	var serial := view.line_serial
	assert_eq(rig.dialogue.talk(KO), &"", "talking again while open is absorbed")
	assert_eq(rig.dialogue.build_view().line_serial, serial, "and shows no new line")
	_free(rig)


func test_range_is_npc_runtimes_decision() -> void:
	var rig := _rig()
	assert_eq(rig.dialogue.talk(SHEN), NpcRuntime.REFUSE_TOO_FAR, "400 px away is too far")
	assert_false(rig.dialogue.is_open(), "nothing opened")
	assert_eq(rig.dialogue.talk(&"actor_nobody"), NpcRuntime.REFUSE_NOBODY,
		"someone with no body here")
	rig.ko.unbind()
	assert_eq(rig.dialogue.talk(KO), NpcRuntime.REFUSE_TOO_FAR, "an unbound body cannot be met")
	assert_false(rig.dialogue.is_open(), "still nothing")
	_free(rig)


func test_someone_with_nothing_authored_keeps_npc_runtimes_behaviour() -> void:
	var rig := _rig()
	_stand_by(rig, rig.lin)
	var greeted: Array[StringName] = []
	var on_greeted := func(id: StringName) -> void: greeted.append(id)
	rig.npcs.npc_greeted.connect(on_greeted)
	assert_eq(rig.dialogue.talk(LIN), &"", "accepted")
	rig.npcs.npc_greeted.disconnect(on_greeted)
	assert_false(rig.dialogue.is_open(), "no conversation: none is authored for her")
	assert_eq(greeted, [LIN] as Array[StringName], "she acknowledges the player, as before")
	assert_false(rig.npcs.is_shop_open(), "and no shop opened for someone who keeps none")
	_free(rig)


# === Lines and answers ==============================================================

func test_continue_and_choices_walk_the_graph() -> void:
	var rig := _rig()
	rig.dialogue.talk(KO)
	var first := rig.dialogue.advance()
	assert_true(first.ok, "the greeting is acknowledged")
	assert_eq(_choice_ids(rig), [&"ko_trade", &"ko_ask_woods", &"ko_talk_price",
		&"ko_pills_ask", &"ko_leave"] as Array[StringName],
		"the hub offers its answers, and the errand he has for whoever asks (Phase 19)")
	assert_false(rig.dialogue.advance().ok, "a line with answers cannot be skipped")
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	assert_eq(rig.dialogue.current_node_id(), &"ko_price", "an answer leads to its node")
	assert_eq(_choice_ids(rig), [&"ko_press", &"ko_price_back"] as Array[StringName],
		"with nothing to tell him, sharing news is not offered")
	rig.dialogue.choose(&"ko_price", &"ko_price_back")
	rig.dialogue.choose(&"ko_hub", &"ko_leave")
	assert_false(rig.dialogue.is_open(), "the leave answer ends the conversation")
	assert_eq(rig.closed, [[&"dlg_scout_ko", DialogueRuntime.REASON_ENDED]], "as ENDED")
	assert_false(rig.dialogue.build_view().open, "and the view closes")
	_free(rig)


func test_an_answer_to_a_line_that_is_not_current_is_refused() -> void:
	var rig := _rig()
	_open_ko_hub(rig)
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	var edges := rig.relationship.get_store().edge_count()
	var stale := rig.dialogue.choose(&"ko_hub", &"ko_ask_woods")
	assert_false(stale.ok, "an answer to the previous line is refused")
	assert_eq(rig.refused, [DialogueService.REFUSE_CHOICE_GONE] as Array[StringName], "loudly")
	assert_eq(rig.dialogue.current_node_id(), &"ko_price", "the conversation did not move")
	assert_false(rig.knowledge.get_service().knows(WOODS), "and nothing was learned")
	assert_false(rig.dialogue.choose(&"ko_price", &"ko_share_stele").ok,
		"an answer the line does not offer now is refused too")
	assert_eq(rig.relationship.get_store().edge_count(), edges, "no edge was made")
	_free(rig)


func test_with_nothing_open_every_intent_is_refused() -> void:
	var rig := _rig()
	assert_false(rig.dialogue.advance().ok, "continue")
	assert_false(rig.dialogue.choose(&"ko_hub", &"ko_leave").ok, "choose")
	rig.dialogue.leave()
	assert_eq(rig.closed, [], "leaving nothing closes nothing")
	_free(rig)


# === Effects land in their owners ==================================================

func test_a_regard_answer_moves_the_real_graph_once_and_the_shop_reads_it() -> void:
	var rig := _rig()
	rig.npcs.open_shop_of(KO)
	var base := _sword_price(rig)
	rig.npcs.close_shop()
	assert_eq(base, 14, "a stranger pays the base price")
	rig.knowledge.grant(STELE, &"test")
	_open_ko_hub(rig)
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	assert_true(_choice_ids(rig).has(&"ko_share_stele"), "having read the stele, news is offered")
	var shared := rig.dialogue.choose(&"ko_price", &"ko_share_stele")
	assert_true(shared.ok, "said")
	assert_eq(_affinity(rig), 40, "his affinity for the player is 40 in the relationship graph")
	assert_eq(rig.relationship.get_store().edge_count(), 1, "on one edge")
	assert_eq(rig.dialogue.current_node_id(), &"ko_pleased", "and he answers it")
	assert_eq(rig.made.size(), 3, "continue, the price talk, the news: three accepted intents")
	rig.dialogue.advance()
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	assert_false(_choice_ids(rig).has(&"ko_share_stele"), "the same news is not offered twice")
	assert_false(rig.dialogue.choose(&"ko_price", &"ko_share_stele").ok, "nor accepted")
	assert_eq(_affinity(rig), 40, "so regard moved exactly once")
	# The shop prices on the SAME dimension, read from the SAME graph — nothing was staged.
	rig.dialogue.choose(&"ko_price", &"ko_price_back")
	rig.dialogue.choose(&"ko_hub", &"ko_trade")
	assert_true(rig.npcs.is_shop_open(), "trade hands over to his shop")
	assert_eq(rig.npcs.build_shop_view().modifier_percent, -8, "40 of 100 affinity: 8% off")
	assert_eq(_sword_price(rig), 13, "the sword is cheaper for someone he likes")
	_free(rig)


func test_pressing_him_raises_his_prices() -> void:
	var rig := _rig()
	_open_ko_hub(rig)
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	rig.dialogue.choose(&"ko_price", &"ko_press")
	assert_eq(_affinity(rig), -30, "haggling costs 30 affinity")
	assert_eq(rig.dialogue.current_node_id(), &"ko_bristle", "and he says so")
	rig.dialogue.advance()
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	assert_false(_choice_ids(rig).has(&"ko_press"), "he will not be pressed twice")
	rig.dialogue.choose(&"ko_price", &"ko_price_back")
	rig.dialogue.choose(&"ko_hub", &"ko_trade")
	assert_eq(rig.npcs.build_shop_view().modifier_percent, 9, "30 of 100 below neutral: 9% dearer")
	assert_eq(_sword_price(rig), 16, "14 x 1.09, rounded up")
	_free(rig)


func test_a_knowledge_answer_grants_through_the_core_and_is_announced_once() -> void:
	var rig := _rig()
	_open_ko_hub(rig)
	var asked := rig.dialogue.choose(&"ko_hub", &"ko_ask_woods")
	assert_eq(asked.knowledge_result, KnowledgeService.GRANTED, "granted by the Core")
	assert_true(rig.knowledge.get_service().knows(WOODS), "the Knowledge Core holds it")
	assert_eq(rig.learned, [WOODS] as Array[StringName],
		"announced through KnowledgeRuntime.knowledge_gained, like any other learning")
	assert_eq(rig.dialogue.current_node_id(), &"ko_woods", "and the line that says it follows")
	rig.dialogue.advance()
	var again := rig.dialogue.choose(&"ko_hub", &"ko_ask_woods")
	assert_eq(again.knowledge_result, KnowledgeService.ALREADY_KNOWN,
		"asking again teaches nothing")
	assert_eq(rig.learned.size(), 1, "and announces nothing")
	assert_eq(rig.knowledge.to_dict(), rig.knowledge.to_dict(), "one copy, the Core's")
	_free(rig)


func test_knowledge_gained_elsewhere_changes_what_the_elder_offers() -> void:
	var rig := _rig()
	_stand_by(rig, rig.shen)
	rig.dialogue.talk(SHEN)
	assert_eq(rig.dialogue.build_view().mood, DialogueNodeData.Mood.STERN, "he greets sternly")
	assert_false(rig.shen.is_greeting(), "and without a gesture: a different authored reaction")
	rig.dialogue.advance()
	assert_eq(_choice_ids(rig), [&"shen_leave"] as Array[StringName], "nothing read, only the door")
	rig.dialogue.leave()
	rig.knowledge.grant(STELE, &"source_lac_ha_stele")
	rig.dialogue.talk(SHEN)
	rig.dialogue.advance()
	assert_eq(_choice_ids(rig), [&"shen_report", &"shen_task_ask", &"shen_leave"]
		as Array[StringName],
		"the stele, read at the stele, opens a line with him — and what he would ask of a reader")
	rig.dialogue.choose(&"shen_hub", &"shen_report")
	assert_eq(rig.dialogue.get_service().regard(SHEN, PLAYER, &"respect"), 15, "respect earned")
	assert_true(rig.shen.is_greeting(), "now he gestures: the same seam, his own sheet")
	assert_eq(rig.dialogue.build_view().mood, DialogueNodeData.Mood.WARM, "and warms")
	rig.dialogue.advance()
	assert_eq(_choice_ids(rig), [&"shen_ask", &"shen_task_ask", &"shen_leave"]
		as Array[StringName], "respect closes one line and opens the next")
	rig.dialogue.choose(&"shen_hub", &"shen_ask")
	assert_true(rig.knowledge.get_service().knows(&"know_thanh_dai_precept"), "he teaches")
	assert_eq(_affinity(rig), 0, "none of it touched how Kha Thản regards the player")
	_free(rig)


# === The shop handoff =================================================================

func test_trade_closes_the_conversation_before_the_shop_opens() -> void:
	var rig := _rig()
	var order: Array[String] = []
	var on_closed := func(_id: StringName, reason: StringName) -> void:
		order.append("closed:%s shop_open=%s" % [reason, rig.npcs.is_shop_open()])
	var on_shop := func(_id: StringName) -> void:
		order.append("shop dialogue_open=%s" % rig.dialogue.is_open())
	rig.dialogue.dialogue_closed.connect(on_closed)
	rig.npcs.shop_opened.connect(on_shop)
	rig.inventory.give(COIN, 20)
	var bag := rig.inventory.to_dict()
	var stock := rig.npcs.to_dict()
	_open_ko_hub(rig)
	var trade := rig.dialogue.choose(&"ko_hub", &"ko_trade")
	rig.dialogue.dialogue_closed.disconnect(on_closed)
	rig.npcs.shop_opened.disconnect(on_shop)
	assert_eq(trade.action, DialogueService.ACTION_OPEN_SHOP, "trade is a handoff")
	assert_eq(order, ["closed:handoff shop_open=false", "shop dialogue_open=false"]
		as Array[String], "the conversation closed FIRST; the shop never opened behind it")
	assert_eq(rig.npcs.open_shop_id(), SHOP, "his shop is open")
	assert_false(rig.dialogue.is_open(), "and no conversation is")
	assert_eq(rig.inventory.to_dict(), bag, "the handoff bought nothing")
	assert_eq(rig.npcs.to_dict(), stock, "and moved no stock")
	_free(rig)


func test_a_handoff_the_shop_refuses_is_answered_by_its_owner_and_opens_nothing() -> void:
	var rig := _rig()
	var answers: Array[StringName] = []
	var on_refused := func(reason: StringName) -> void: answers.append(reason)
	# The keeper stops being addressable between the answer and the handoff (his body is
	# unbound by whoever hears the answer first).
	var on_made := func(_outcome: DialogueOutcome) -> void: rig.ko.unbind()
	rig.npcs.interaction_refused.connect(on_refused)
	_open_ko_hub(rig)
	rig.dialogue.choice_made.connect(on_made)
	var bag := rig.inventory.to_dict()
	rig.dialogue.choose(&"ko_hub", &"ko_trade")
	rig.dialogue.choice_made.disconnect(on_made)
	rig.npcs.interaction_refused.disconnect(on_refused)
	assert_false(rig.npcs.is_shop_open(), "no shop opened behind a keeper who cannot be met")
	assert_false(rig.dialogue.is_open(), "and the conversation did close: nothing holds input")
	assert_eq(rig.closed, [[&"dlg_scout_ko", DialogueRuntime.REASON_HANDOFF]], "as a handoff")
	assert_eq(answers, [NpcRuntime.REFUSE_TOO_FAR] as Array[StringName],
		"NpcRuntime, the owner of the refusal, says why")
	assert_eq(rig.inventory.to_dict(), bag, "nothing was traded")
	_free(rig)


func test_a_listener_that_ends_the_conversation_mid_answer_leaves_it_ended() -> void:
	var rig := _rig()
	# Walks away on hearing an ANSWER (a "continue" has no choice id and is let through).
	var on_made := func(outcome: DialogueOutcome) -> void:
		if outcome.choice_id != &"":
			rig.dialogue.leave()
	_open_ko_hub(rig)
	rig.dialogue.choice_made.connect(on_made)
	# An answer that would lead to another line: whoever hears it walks away first.
	var moved := rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	assert_true(moved.ok, "the answer itself was accepted")
	assert_false(rig.dialogue.is_open(), "the conversation stays closed: no line is shown")
	assert_eq(rig.dialogue.current_node_id(), &"", "and its cursor is nowhere")
	assert_eq(rig.closed, [[&"dlg_scout_ko", DialogueRuntime.REASON_LEFT]], "closed once, as LEFT")
	# The same for an answer that hands over to the shop: nothing opens for someone who left.
	_open_ko_hub(rig)
	rig.dialogue.choose(&"ko_hub", &"ko_trade")
	assert_false(rig.npcs.is_shop_open(), "walking away mid-answer opens no shop")
	assert_false(rig.dialogue.is_open(), "and no conversation")
	# And for one that would have ended it anyway: closed once, not twice.
	_open_ko_hub(rig)
	rig.dialogue.choose(&"ko_hub", &"ko_leave")
	rig.dialogue.choice_made.disconnect(on_made)
	assert_eq(rig.closed.size(), 3, "three talks, three closings")
	# Someone who ends it the moment it OPENS: no first line is entered behind them.
	var views := rig.views
	var on_opened := func(_id: StringName, _speaker: StringName) -> void: rig.dialogue.leave()
	rig.dialogue.dialogue_opened.connect(on_opened)
	assert_eq(rig.dialogue.talk(KO), &"", "the talk was accepted")
	rig.dialogue.dialogue_opened.disconnect(on_opened)
	assert_false(rig.dialogue.is_open(), "and ended at once")
	assert_eq(rig.dialogue.current_node_id(), &"", "with no line entered")
	assert_eq(rig.views - views, 1, "one view change: the closing")
	_free(rig)


# === Closing ===========================================================================

func test_leaving_a_map_or_the_session_closes_the_conversation() -> void:
	var rig := _rig()
	rig.dialogue.talk(KO)
	rig.world.active_map_leaving.emit()
	assert_false(rig.dialogue.is_open(), "a map change closes it")
	assert_eq(rig.closed, [[&"dlg_scout_ko", DialogueRuntime.REASON_MAP]], "as MAP")
	rig.world.active_map_ready.emit()
	rig.dialogue.talk(KO)
	rig.dialogue.leave()
	assert_eq(rig.closed.back(), [&"dlg_scout_ko", DialogueRuntime.REASON_LEFT], "walking away")
	rig.dialogue.talk(KO)
	rig.dialogue.end_session()
	assert_eq(rig.closed.back(), [&"dlg_scout_ko", DialogueRuntime.REASON_SESSION],
		"ending the session closes it too")
	assert_false(rig.dialogue.is_session_active(), "and the session is over")
	var still_listening := 0
	for connection in rig.world.active_map_leaving.get_connections():
		if (connection["callable"] as Callable).get_object() == rig.dialogue:
			still_listening += 1
	assert_eq(still_listening, 0, "with its connection to the world dropped")
	rig.dialogue.end_session()  # idempotent
	_free(rig)


func test_a_speaker_who_went_out_of_reach_ends_the_conversation_on_the_next_answer() -> void:
	var rig := _rig()
	_open_ko_hub(rig)
	rig.world.player.global_position = Vector2(900, 900)
	var outcome := rig.dialogue.choose(&"ko_hub", &"ko_ask_woods")
	assert_false(outcome.ok, "an answer from across the map is refused")
	assert_eq(rig.refused, [NpcRuntime.REFUSE_TOO_FAR] as Array[StringName], "for range")
	assert_false(rig.dialogue.is_open(), "and the conversation is over")
	assert_false(rig.knowledge.get_service().knows(WOODS), "with nothing learned")
	_free(rig)


func test_a_restarted_session_does_not_repeat_what_was_said() -> void:
	var rig := _rig()
	rig.knowledge.grant(STELE, &"test")
	_open_ko_hub(rig)
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	rig.dialogue.choose(&"ko_price", &"ko_share_stele")
	rig.dialogue.end_session()
	assert_true(rig.dialogue.start_session(rig.world, rig.npcs, rig.knowledge,
		rig.relationship, null, rig.quests),
		"the dialogue session starts again over the same world")
	_open_ko_hub(rig)
	rig.dialogue.choose(&"ko_hub", &"ko_talk_price")
	assert_false(_choice_ids(rig).has(&"ko_share_stele"),
		"what was said is in the graph, not in the runtime: it is not offered again")
	assert_eq(_affinity(rig), 40, "moved once")
	assert_eq(rig.relationship.get_store().edge_count(), 1, "one edge")
	_free(rig)


# === Cost ================================================================================

func test_the_view_is_rebuilt_on_changes_only() -> void:
	var rig := _rig()
	assert_eq(rig.views, 0, "an idle session announces nothing")
	rig.dialogue.talk(KO)
	assert_eq(rig.views, 1, "opening: one change")
	rig.dialogue.advance()
	assert_eq(rig.views, 2, "a new line: one more")
	rig.dialogue.choose(&"ko_hub", &"nonsense")
	assert_eq(rig.views, 2, "a refusal shows no new line")
	rig.dialogue.leave()
	assert_eq(rig.views, 3, "closing: one more")
	_free(rig)

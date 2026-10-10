extends TestCase
## Unit tests for the Phase-19 quest DATA and DOMAIN (D-070): `Quest*Data`, `QuestState`,
## `QuestService`. No scene tree, no node, no autoload. The owners a quest asks are REAL — the
## `KnowledgeService`, an `InventoryState`, the relationship graph, the `RewardService` and its
## ledger — so "ready" and "paid" are asserted through them, not through call counts.

const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const CONFIG_PATH := "res://data/relationship/relationship_config.tres"
const PILL_PATH := "res://data/items/item_bo_huyet_dan.tres"
const STONE_PATH := "res://data/items/item_linh_thach.tres"
const SWORD_PATH := "res://data/items/item_kiem_thanh_thiet.tres"

const ELDER := &"char_test_elder"
const SCOUT := &"char_test_scout"
const PLAYER := &"char_test_player"
const WOLF := &"enemy_mist_wolf"
const SCOUTS_WORD := &"know_vu_lang_hunting_ground"
const VEIN := &"quest_test_vein"       # ANY: defeat one wolf, or know the scout's word
const PILLS := &"quest_test_pills"     # ALL: hold two pills, handed over
const HUNT := &"quest_test_hunt"       # ALL: defeat two wolves AND know the scout's word

var _knowledge: KnowledgeService = null
var _relationship: RelationshipService = null
var _config: RelationshipConfigData = null
var _bag: InventoryState = null
var _ledger: RewardLedger = null
var _rewards: RewardService = null
var _state: QuestState = null
var _items: Dictionary = {}
var _xp: int = 0
var _regard_accepts: bool = true


func before_each() -> void:
	_config = load(CONFIG_PATH) as RelationshipConfigData
	_relationship = RelationshipService.new(RelationshipStore.new(_config), _config)
	_knowledge = KnowledgeService.new(load(KNOWLEDGE_PATH) as KnowledgeCatalogData,
		KnowledgeStore.new())
	_bag = InventoryState.new()
	_ledger = RewardLedger.new()
	_rewards = RewardService.new(_ledger)
	_state = QuestState.new()
	_items = {}
	for path: String in [PILL_PATH, STONE_PATH, SWORD_PATH]:
		var item := load(path) as ItemData
		_items[item.id] = item
	_xp = 0
	_regard_accepts = true


func after_each() -> void:
	_knowledge = null
	_relationship = null
	_config = null
	_bag = null
	_ledger = null
	_rewards = null
	_state = null
	_items = {}


# --- Builders: a known-GOOD catalog; each negative case changes exactly one thing --------

func _objective(id: StringName, kind: QuestObjectiveData.Kind, target: StringName,
		count: int = 1, consumed: bool = false) -> QuestObjectiveData:
	var entry := QuestObjectiveData.new()
	entry.id = id
	entry.kind = kind
	entry.target_id = target
	entry.count = count
	entry.consumed = consumed
	entry.text_key = StringName("QUEST_TEST_%s" % String(id).to_upper())
	return entry


func _reward(item: ItemData, count: int, xp: int, who: StringName, dimension: StringName,
		delta: int) -> RewardData:
	var reward := RewardData.new()
	if item != null:
		var entry := RewardItemData.new()
		entry.item = item
		entry.count = count
		var items: Array[RewardItemData] = [entry]
		reward.items = items
	reward.xp = xp
	if delta != 0:
		reward.regard_character_id = who
		reward.regard_dimension = dimension
		reward.regard_delta = delta
	return reward


func _quest(id: StringName, giver: StringName, receiver: StringName,
		completion: QuestData.Completion, objectives: Array, reward: RewardData) -> QuestData:
	var quest := QuestData.new()
	quest.id = id
	quest.title_key = &"QUEST_TEST_TITLE"
	quest.summary_key = &"QUEST_TEST_SUMMARY"
	quest.lead_key = &"QUEST_TEST_LEAD"
	quest.goal_key = &"QUEST_TEST_GOAL"
	quest.return_key = &"QUEST_TEST_RETURN"
	quest.giver_id = giver
	quest.receiver_id = receiver
	quest.completion = completion
	var typed: Array[QuestObjectiveData] = []
	for entry: QuestObjectiveData in objectives:
		typed.append(entry)
	quest.objectives = typed
	quest.reward = reward
	return quest


func _vein() -> QuestData:
	return _quest(VEIN, ELDER, ELDER, QuestData.Completion.ANY, [
		_objective(&"fight", QuestObjectiveData.Kind.DEFEAT, WOLF),
		_objective(&"ask", QuestObjectiveData.Kind.KNOW, SCOUTS_WORD),
	], _reward(_items[&"item_bo_huyet_dan"], 2, 10, ELDER, &"respect", 10))


func _pills() -> QuestData:
	return _quest(PILLS, SCOUT, SCOUT, QuestData.Completion.ALL, [
		_objective(&"carry", QuestObjectiveData.Kind.HOLD_ITEM, &"item_bo_huyet_dan", 2, true),
	], _reward(_items[&"item_linh_thach"], 3, 0, SCOUT, &"affinity", 15))


func _hunt() -> QuestData:
	return _quest(HUNT, SCOUT, ELDER, QuestData.Completion.ALL, [
		_objective(&"cull", QuestObjectiveData.Kind.DEFEAT, WOLF, 2),
		_objective(&"learn", QuestObjectiveData.Kind.KNOW, SCOUTS_WORD),
	], _reward(null, 0, 20, &"", &"", 0))


func _catalog(quests: Array = []) -> QuestCatalogData:
	var catalog := QuestCatalogData.new()
	var typed: Array[QuestData] = []
	if quests.is_empty():
		quests = [_vein(), _pills(), _hunt()]
	for quest: QuestData in quests:
		typed.append(quest)
	catalog.entries = typed
	return catalog


func _held(item_id: StringName) -> int:
	return _bag.count_of(item_id)


func _service(catalog: QuestCatalogData = null) -> QuestService:
	return QuestService.new(catalog if catalog != null else _catalog(), _state, _knowledge,
		_rewards, _held)


func _payers() -> RewardPayers:
	var payers := RewardPayers.new()
	payers.trade = func(take: Dictionary, give: Dictionary) -> bool:
		var resolved: Dictionary = {}
		for item_id: StringName in give:
			resolved[_items[item_id]] = give[item_id]
		return _bag.exchange(take, resolved)
	payers.pay_xp = func(amount: int, _source: StringName) -> bool:
		_xp += amount
		return true
	payers.move_regard = func(who: StringName, dimension: StringName, delta: int,
			source: StringName) -> bool:
		if not _regard_accepts:
			return false
		return bool(RegardRules.move(_relationship, _config, who, PLAYER, dimension, delta,
			source)["ok"])
	return payers


func _regard(who: StringName, dimension: StringName) -> int:
	return RegardRules.read(_relationship, _config, who, PLAYER, dimension)


func _pill_count() -> int:
	return _bag.count_of(&"item_bo_huyet_dan")


func _has_error(errors: Array[String], fragment: String) -> bool:
	for problem in errors:
		if problem.contains(fragment):
			return true
	return false


# === 1. Data validation ============================================================

func test_the_known_good_catalog_is_valid_and_the_service_is_ready() -> void:
	assert_eq(_catalog().validation_errors(), [] as Array[String], "structurally valid")
	var service := _service()
	assert_true(service.is_ready(), "the service accepts it")
	assert_eq(service.content_errors(), [] as Array[String], "and it names nothing unknown")
	assert_eq(QuestService.reward_id_of(VEIN), &"quest:quest_test_vein", "a stable reward id")


func test_structural_defects_are_each_named() -> void:
	var unnamed := _vein()
	unnamed.id = &""
	assert_true(_has_error(unnamed.validation_errors(), "id is empty"), "no id")
	var prefix := _vein()
	prefix.id = &"vein"
	assert_true(_has_error(prefix.validation_errors(), "quest_ prefix"), "the id prefix")
	for field: String in ["title_key", "summary_key", "lead_key", "goal_key", "return_key"]:
		var silent := _vein()
		silent.set(field, &"")
		assert_true(_has_error(silent.validation_errors(), "%s is empty" % field), field)
	var nobody := _vein()
	nobody.giver_id = &""
	assert_true(_has_error(nobody.validation_errors(), "giver_id is empty"), "no giver")
	var nowhere := _vein()
	nowhere.receiver_id = &""
	assert_true(_has_error(nowhere.validation_errors(), "receiver_id is empty"), "no receiver")
	var idle := _vein()
	idle.objectives.clear()
	assert_true(_has_error(idle.validation_errors(), "asks for nothing"), "no objective")
	var unpaid := _vein()
	unpaid.reward = null
	assert_true(_has_error(unpaid.validation_errors(), "reward is null"), "no reward")
	var broke := _vein()
	broke.reward = RewardData.new()
	assert_true(_has_error(broke.validation_errors(), "reward: pays nothing"), "an empty reward")
	var twin := _vein()
	twin.objectives[1].id = &"fight"
	assert_true(_has_error(twin.validation_errors(), "duplicate objective id 'fight'"),
		"two objectives with one id")
	var hole := _vein()
	hole.objectives.append(null)
	assert_true(_has_error(hole.validation_errors(), "objective 2 is null"), "a null objective")
	var mode := _vein()
	mode.completion = 7 as QuestData.Completion
	assert_true(_has_error(mode.validation_errors(), "unknown completion mode"), "a bad mode")
	var doubled := _catalog([_vein(), _vein()])
	assert_true(_has_error(doubled.validation_errors(), "duplicate quest id"), "two of one quest")
	assert_true(_has_error(QuestCatalogData.new().validation_errors(), "catalog is empty"),
		"an empty catalog")
	var gap := _catalog()
	gap.entries.append(null)
	assert_true(_has_error(gap.validation_errors(), "entry 3 is null"), "a null entry")
	assert_false(_service(doubled).is_ready(), "a structurally invalid catalog is refused outright")


func test_objective_payloads_a_kind_does_not_use_are_rejected() -> void:
	var counted_knowledge := _objective(&"o", QuestObjectiveData.Kind.KNOW, SCOUTS_WORD, 3)
	assert_true(_has_error(counted_knowledge.validation_errors(), "count must be 1"),
		"knowledge is held or not")
	var handed_knowledge := _objective(&"o", QuestObjectiveData.Kind.KNOW, SCOUTS_WORD, 1, true)
	assert_true(_has_error(handed_knowledge.validation_errors(), "cannot be handed over"),
		"knowledge is not handed over")
	var handed_defeat := _objective(&"o", QuestObjectiveData.Kind.DEFEAT, WOLF, 1, true)
	assert_true(_has_error(handed_defeat.validation_errors(), "cannot be handed over"),
		"nor is a defeat")
	var none := _objective(&"o", QuestObjectiveData.Kind.DEFEAT, WOLF, 0)
	assert_true(_has_error(none.validation_errors(), "outside 1..99"), "defeat nothing")
	var hoard := _objective(&"o", QuestObjectiveData.Kind.HOLD_ITEM, &"item_x", 100)
	assert_true(_has_error(hoard.validation_errors(), "outside 1..99"), "a hundred of something")
	var aimless := _objective(&"o", QuestObjectiveData.Kind.DEFEAT, &"")
	assert_true(_has_error(aimless.validation_errors(), "names no target"), "no target")
	var wordless := _objective(&"o", QuestObjectiveData.Kind.DEFEAT, WOLF)
	wordless.text_key = &""
	assert_true(_has_error(wordless.validation_errors(), "text_key is empty"), "no text")
	var anonymous := _objective(&"", QuestObjectiveData.Kind.DEFEAT, WOLF)
	assert_true(_has_error(anonymous.validation_errors(), "objective id is empty"), "no id")
	var alien := _objective(&"o", 9 as QuestObjectiveData.Kind, WOLF)
	assert_true(_has_error(alien.validation_errors(), "unknown objective kind"), "an unknown kind")


func test_what_other_owners_cannot_supply_is_reported_by_the_service() -> void:
	var registry := CharacterRegistry.new()
	for who: StringName in [ELDER, SCOUT]:
		var state := CharacterState.new()
		state.instance_id = who
		registry.add(state)
	var has_item := func(item_id: StringName) -> bool: return _items.has(item_id)
	var has_enemy := func(enemy_id: StringName) -> bool: return enemy_id == WOLF
	var has_dimension := func(dimension: StringName) -> bool:
		return _config.has_dimension(dimension)
	var all_text := func(_key: StringName) -> bool: return true
	assert_eq(_service().content_errors(all_text, has_item, has_enemy, registry.resolver(),
		has_dimension), [] as Array[String], "the good catalog resolves in every owner")

	var unknown_knowledge := _vein()
	unknown_knowledge.objectives[1].target_id = &"know_nothing"
	assert_true(_has_error(_service(_catalog([unknown_knowledge])).content_errors(),
		"asks for knowledge 'know_nothing'"), "knowledge nobody defines")
	var unknown_item := _pills()
	unknown_item.objectives[0].target_id = &"item_nothing"
	assert_true(_has_error(_service(_catalog([unknown_item])).content_errors(Callable(),
		has_item), "asks for item 'item_nothing'"), "an item nobody defines")
	var unknown_enemy := _vein()
	unknown_enemy.objectives[0].target_id = &"enemy_nothing"
	assert_true(_has_error(_service(_catalog([unknown_enemy])).content_errors(Callable(),
		Callable(), has_enemy), "which no map spawns"), "a creature no map spawns")
	var stranger := _vein()
	stranger.receiver_id = &"char_nobody"
	assert_true(_has_error(_service(_catalog([stranger])).content_errors(Callable(), Callable(),
		Callable(), registry.resolver()), "names 'char_nobody'"), "an unregistered receiver")
	var owed_by_nobody := _vein()
	owed_by_nobody.reward.regard_character_id = &"char_nobody"
	assert_true(_has_error(_service(_catalog([owed_by_nobody])).content_errors(Callable(),
		Callable(), Callable(), registry.resolver()), "moves the regard of 'char_nobody'"),
		"regard of someone unregistered")
	var charm := _vein()
	charm.reward.regard_dimension = &"charm"
	assert_true(_has_error(_service(_catalog([charm])).content_errors(Callable(), Callable(),
		Callable(), Callable(), has_dimension), "moves 'charm'"), "an unknown dimension")
	assert_true(_has_error(_service().content_errors(
		func(_key: StringName) -> bool: return false), "has no translation"), "missing text")
	assert_true(_has_error(_service(_catalog([_vein(), _vein()])).content_errors(),
		"not ready"), "a service that refused its catalog reports that")


# === 2. Lifecycle ==================================================================

func test_a_quest_is_available_until_its_giver_is_asked() -> void:
	var service := _service()
	assert_eq(service.phase_of(VEIN), QuestService.Phase.AVAILABLE, "on offer")
	assert_eq(service.accept(VEIN, SCOUT).reason, QuestService.REFUSE_WRONG_PERSON,
		"only its giver offers it")
	assert_eq(service.accept(&"quest_nothing", ELDER).reason, QuestService.REFUSE_UNKNOWN,
		"an unknown quest")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.AVAILABLE, "refusals changed nothing")
	assert_eq(_state.to_dict()["quests"], {}, "and no record exists")
	var taken := service.accept(VEIN, ELDER)
	assert_true(taken.ok, "accepted")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.ACTIVE, "active")
	assert_eq(service.accept(VEIN, ELDER).reason, QuestService.REFUSE_ALREADY_TAKEN,
		"it cannot be taken twice")
	assert_eq(service.phase_of(PILLS), QuestService.Phase.AVAILABLE, "another quest is untouched")


func test_knowledge_already_held_counts_the_moment_the_quest_is_taken() -> void:
	var service := _service()
	_knowledge.grant(SCOUTS_WORD, &"test")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.AVAILABLE,
		"knowing the answer does not take the quest for the player")
	service.accept(VEIN, ELDER)
	assert_eq(service.phase_of(VEIN), QuestService.Phase.READY,
		"but once taken it is ready at once: nobody is sent to learn what they know")


func test_the_knowledge_route_and_the_fight_route_both_finish_an_any_quest() -> void:
	var by_word := _service()
	by_word.accept(VEIN, ELDER)
	assert_eq(by_word.phase_of(VEIN), QuestService.Phase.ACTIVE, "nothing done yet")
	_knowledge.grant(SCOUTS_WORD, &"test")
	assert_eq(by_word.phase_of(VEIN), QuestService.Phase.READY, "the scout's word is enough")
	assert_eq(_state.progress_of(VEIN, &"fight"), 0, "with no wolf harmed")

	before_each()
	var by_blade := _service()
	by_blade.accept(VEIN, ELDER)
	var advanced := by_blade.record_defeat(WOLF, &"enemy_mist_wolf_1#1")
	assert_eq(advanced, [[VEIN, &"fight", 1, 1]] as Array[Array], "the defeat is counted")
	assert_false(_knowledge.knows(SCOUTS_WORD), "without ever asking")
	assert_eq(by_blade.phase_of(VEIN), QuestService.Phase.READY, "and that is enough too")


func test_an_all_quest_needs_every_objective() -> void:
	var service := _service()
	service.accept(HUNT, SCOUT)
	service.record_defeat(WOLF, &"enemy_mist_wolf_1#1")
	service.record_defeat(WOLF, &"enemy_mist_wolf_2#2")
	assert_eq(service.phase_of(HUNT), QuestService.Phase.ACTIVE, "two wolves are not enough")
	_knowledge.grant(SCOUTS_WORD, &"test")
	assert_eq(service.phase_of(HUNT), QuestService.Phase.READY, "with the word too, it is")


func test_defeats_count_once_each_only_while_active_and_never_past_the_need() -> void:
	var service := _service()
	assert_eq(service.record_defeat(WOLF, &"enemy_mist_wolf_1#1"), [] as Array[Array],
		"a wolf killed before the quest was taken counts for nothing")
	service.accept(HUNT, SCOUT)
	assert_eq(service.record_defeat(WOLF, &"enemy_mist_wolf_1#1").size(), 1,
		"the same creature killed AFTER taking it would count (its id is new to the quest)")
	assert_eq(service.record_defeat(WOLF, &"enemy_mist_wolf_1#1"), [] as Array[Array],
		"the same defeat delivered twice counts once")
	assert_eq(service.record_defeat(&"enemy_other", &"enemy_other_1#9"), [] as Array[Array],
		"another kind of creature is not what was asked for")
	assert_eq(service.record_defeat(WOLF, &""), [] as Array[Array], "an unnamed defeat is ignored")
	assert_eq(service.record_defeat(&"", &"x#1"), [] as Array[Array], "so is an unnamed kind")
	assert_eq(service.record_defeat(WOLF, &"enemy_mist_wolf_2#2"), [[HUNT, &"cull", 2, 2]]
		as Array[Array], "a second creature completes the count")
	assert_eq(service.record_defeat(WOLF, &"enemy_mist_wolf_1#3"), [] as Array[Array],
		"a third is not counted: the objective never exceeds what it asks")
	assert_eq(_state.progress_of(HUNT, &"cull"), 2, "two, exactly")
	# One defeat advances every active quest that asks for that kind.
	service.accept(VEIN, ELDER)
	assert_eq(service.record_defeat(WOLF, &"enemy_mist_wolf_2#4"), [[VEIN, &"fight", 1, 1]]
		as Array[Array], "the other quest counts it; the finished objective does not")


func test_turning_in_too_early_or_to_the_wrong_person_changes_nothing() -> void:
	var service := _service()
	assert_eq(service.turn_in(VEIN, ELDER, _payers()).reason, QuestService.REFUSE_NOT_TAKEN,
		"a quest never taken cannot be answered")
	service.accept(VEIN, ELDER)
	assert_eq(service.turn_in(VEIN, ELDER, _payers()).reason, QuestService.REFUSE_OBJECTIVES,
		"an unfinished one is refused")
	_knowledge.grant(SCOUTS_WORD, &"test")
	assert_eq(service.turn_in(VEIN, SCOUT, _payers()).reason, QuestService.REFUSE_WRONG_PERSON,
		"only its receiver takes the answer")
	assert_eq(service.turn_in(&"quest_nothing", ELDER, _payers()).reason,
		QuestService.REFUSE_UNKNOWN, "an unknown quest")
	assert_eq([_pill_count(), _xp, _regard(ELDER, &"respect"), _ledger.count()], [0, 0, 0, 0],
		"no refusal paid anything")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.READY, "and it is still ready")


func test_a_turn_in_pays_every_owner_once_and_closes_the_quest() -> void:
	var service := _service()
	service.accept(VEIN, ELDER)
	_knowledge.grant(SCOUTS_WORD, &"test")
	var done := service.turn_in(VEIN, ELDER, _payers())
	assert_true(done.ok, "answered")
	assert_eq(done.paid_now, [&"bag", &"xp", &"regard"] as Array[StringName], "every part")
	assert_eq([_pill_count(), _xp, _regard(ELDER, &"respect")], [2, 10, 10],
		"two pills in the bag, 10 XP, the elder's respect in the graph")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.COMPLETED, "completed")
	assert_true(_ledger.has(&"quest:quest_test_vein"), "and recorded as paid")
	# Asked again, by any path: nothing.
	var again := service.turn_in(VEIN, ELDER, _payers())
	assert_eq(again.reason, QuestService.REFUSE_ALREADY_DONE, "a second answer is refused")
	assert_eq(service.accept(VEIN, ELDER).reason, QuestService.REFUSE_ALREADY_DONE,
		"it is not offered again")
	assert_eq(service.abandon(VEIN, ELDER).reason, QuestService.REFUSE_ALREADY_DONE,
		"and cannot be given back")
	assert_eq([_pill_count(), _xp, _regard(ELDER, &"respect")], [2, 10, 10], "paid once")


func test_a_full_bag_refuses_the_turn_in_and_keeps_the_reward_claimable() -> void:
	var service := _service()
	service.accept(VEIN, ELDER)
	_knowledge.grant(SCOUTS_WORD, &"test")
	_bag.add(_items[&"item_kiem_thanh_thiet"], _bag.capacity)
	var refused := service.turn_in(VEIN, ELDER, _payers())
	assert_false(refused.ok, "refused")
	assert_eq(refused.reason, QuestService.REFUSE_NO_ROOM, "because the bag has no room")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.READY, "the quest is still ready")
	assert_false(service.is_reward_owed(VEIN), "nothing is 'owed': nothing was paid at all")
	assert_eq([_pill_count(), _xp, _regard(ELDER, &"respect"), _ledger.count()], [0, 0, 0, 0],
		"no XP and no regard slipped out ahead of the pills")
	_bag.remove(&"item_kiem_thanh_thiet", 1)
	assert_true(service.turn_in(VEIN, ELDER, _payers()).ok, "with room made, it is paid")
	assert_eq([_pill_count(), _xp, _regard(ELDER, &"respect")], [2, 10, 10], "in full, once")


func test_items_asked_for_are_handed_over_in_the_same_exchange_as_the_reward() -> void:
	var service := _service()
	service.accept(PILLS, SCOUT)
	assert_eq(service.objective_value(PILLS, _pills().objectives[0]), 0, "none held")
	_bag.add(_items[&"item_bo_huyet_dan"], 1)
	assert_eq(service.phase_of(PILLS), QuestService.Phase.ACTIVE, "one pill is not two")
	_bag.add(_items[&"item_bo_huyet_dan"], 2)
	assert_eq(service.objective_value(PILLS, _pills().objectives[0]), 2,
		"the journal never shows more than was asked for")
	assert_eq(service.phase_of(PILLS), QuestService.Phase.READY, "ready with three in the bag")
	var done := service.turn_in(PILLS, SCOUT, _payers())
	assert_true(done.ok, "handed over")
	assert_eq(done.taken, {&"item_bo_huyet_dan": 2}, "exactly two change hands")
	assert_eq([_pill_count(), _bag.count_of(&"item_linh_thach")], [1, 3],
		"one pill kept, three stones paid")
	assert_eq(_regard(SCOUT, &"affinity"), 15, "and the scout's affinity is in the graph")


func test_readiness_is_asked_of_the_bag_every_time_never_remembered() -> void:
	var service := _service()
	service.accept(PILLS, SCOUT)
	_bag.add(_items[&"item_bo_huyet_dan"], 2)
	assert_eq(service.phase_of(PILLS), QuestService.Phase.READY, "ready")
	_bag.remove(&"item_bo_huyet_dan", 1)  # the player swallowed one on the road
	assert_eq(service.phase_of(PILLS), QuestService.Phase.ACTIVE,
		"a pill used on the way makes it not ready again, truthfully")
	assert_eq(service.turn_in(PILLS, SCOUT, _payers()).reason, QuestService.REFUSE_OBJECTIVES,
		"and the turn-in is refused")
	assert_eq(_pill_count(), 1, "the one pill left was not taken")


func test_a_reward_part_that_fails_after_the_bag_moved_is_owed_and_then_paid() -> void:
	var service := _service()
	service.accept(PILLS, SCOUT)
	_bag.add(_items[&"item_bo_huyet_dan"], 2)
	_regard_accepts = false
	var first := service.turn_in(PILLS, SCOUT, _payers())
	assert_false(first.ok, "not complete")
	assert_eq(first.reason, QuestService.REFUSE_REWARD_OWED, "the rest is owed")
	assert_eq([_pill_count(), _bag.count_of(&"item_linh_thach")], [0, 3],
		"the pills were taken and the stones paid")
	assert_true(service.is_reward_owed(PILLS), "the quest says it is owed")
	assert_eq(service.phase_of(PILLS), QuestService.Phase.READY,
		"and stays answerable although the pills are gone")
	assert_eq(service.abandon(PILLS, SCOUT).reason, QuestService.REFUSE_REWARD_OWED,
		"it cannot be abandoned: that would give up what is owed")
	# Asking again while the owner still refuses — and with two NEW pills in the bag, which
	# would satisfy the objective all over again: no second exchange.
	_bag.add(_items[&"item_bo_huyet_dan"], 2)
	var second := service.turn_in(PILLS, SCOUT, _payers())
	assert_eq(second.taken, {} as Dictionary, "no pills are asked for a second time")
	assert_eq(_pill_count(), 2, "the pills picked up since are still the player's")
	assert_eq(_bag.count_of(&"item_linh_thach"), 3, "and no stones paid twice")
	_regard_accepts = true
	var third := service.turn_in(PILLS, SCOUT, _payers())
	assert_true(third.ok, "the owed part is paid")
	assert_eq(third.paid_now, [&"regard"] as Array[StringName], "only that part")
	assert_eq(service.phase_of(PILLS), QuestService.Phase.COMPLETED, "and the quest closes")
	assert_eq([_bag.count_of(&"item_linh_thach"), _regard(SCOUT, &"affinity"), _pill_count()],
		[3, 15, 2], "once")


func test_abandoning_discards_progress_and_offers_the_quest_again() -> void:
	var service := _service()
	assert_eq(service.abandon(HUNT, SCOUT).reason, QuestService.REFUSE_NOT_TAKEN,
		"nothing to abandon")
	service.accept(HUNT, SCOUT)
	service.record_defeat(WOLF, &"enemy_mist_wolf_1#1")
	assert_eq(service.abandon(HUNT, ELDER).reason, QuestService.REFUSE_WRONG_PERSON,
		"it is given back to whoever gave it")
	assert_eq(_state.progress_of(HUNT, &"cull"), 1, "a refused abandon keeps the progress")
	assert_true(service.abandon(HUNT, SCOUT).ok, "abandoned")
	assert_eq(service.phase_of(HUNT), QuestService.Phase.AVAILABLE, "on offer again")
	assert_eq(_state.to_dict()["quests"], {}, "with no record left")
	assert_eq(_ledger.count(), 0, "and nothing was paid for it")
	service.accept(HUNT, SCOUT)
	assert_eq(_state.progress_of(HUNT, &"cull"), 0, "taken again, it starts from nothing")
	assert_eq(service.record_defeat(WOLF, &"enemy_mist_wolf_1#1").size(), 1,
		"and counts afresh")
	# A READY quest can still be given back; knowledge is not un-learned.
	_knowledge.grant(SCOUTS_WORD, &"test")
	service.accept(VEIN, ELDER)
	assert_true(service.abandon(VEIN, ELDER).ok, "a ready quest can be abandoned too")
	assert_true(_knowledge.knows(SCOUTS_WORD), "what was learned stays learned")


func test_a_service_that_is_not_ready_refuses_everything() -> void:
	var service := QuestService.new(null, _state, _knowledge, _rewards, _held)
	assert_false(service.is_ready(), "no catalog, no service")
	assert_eq(service.accept(VEIN, ELDER).reason, QuestService.REFUSE_NOT_READY, "accept")
	assert_eq(service.abandon(VEIN, ELDER).reason, QuestService.REFUSE_NOT_READY, "abandon")
	assert_eq(service.turn_in(VEIN, ELDER, _payers()).reason, QuestService.REFUSE_NOT_READY,
		"turn in")
	assert_eq(service.record_defeat(WOLF, &"x#1"), [] as Array[Array], "count")
	assert_eq(service.phase_of(VEIN), QuestService.Phase.AVAILABLE, "and reads as nothing taken")
	assert_false(QuestService.new(_catalog(), _state, _knowledge, _rewards).is_ready(),
		"no way to ask the bag: not ready")
	assert_false(QuestService.new(_catalog(), _state, _knowledge, RewardService.new(null),
		_held).is_ready(), "no ledger: not ready")


# === 3. Persistence boundary =======================================================

func test_a_quest_in_progress_round_trips_and_cannot_be_paid_twice_afterwards() -> void:
	var service := _service()
	service.accept(HUNT, SCOUT)
	service.record_defeat(WOLF, &"enemy_mist_wolf_1#1")
	service.accept(VEIN, ELDER)
	_knowledge.grant(SCOUTS_WORD, &"test")
	assert_true(service.turn_in(VEIN, ELDER, _payers()).ok, "one quest completed")
	var saved := _state.to_dict()
	assert_eq(saved, {"schema": 1, "quests": {
		"quest_test_hunt": {"status": "active", "progress": {"cull": 1},
			"counted": {"cull": ["enemy_mist_wolf_1#1"]}},
		"quest_test_vein": {"status": "completed", "progress": {}, "counted": {}},
	}}, "plain data: one quest mid-way, one done")
	var ledger_saved := _ledger.to_dict()
	# A fresh owner, as a load would build it.
	var state := QuestState.new()
	assert_true(state.from_dict(saved, _catalog()), "the quest state is accepted")
	assert_eq(state.to_dict(), saved, "and identical")
	var ledger := RewardLedger.new()
	assert_true(ledger.from_dict(ledger_saved), "the ledger is accepted")
	var restored := QuestService.new(_catalog(), state, _knowledge, RewardService.new(ledger),
		_held)
	assert_eq(restored.phase_of(HUNT), QuestService.Phase.ACTIVE, "the hunt is still under way")
	assert_eq(restored.record_defeat(WOLF, &"enemy_mist_wolf_1#1"), [] as Array[Array],
		"the wolf already counted is not counted again")
	assert_eq(restored.record_defeat(WOLF, &"enemy_mist_wolf_2#2"), [[HUNT, &"cull", 2, 2]]
		as Array[Array], "and the count resumes where it was")
	assert_eq(restored.phase_of(VEIN), QuestService.Phase.COMPLETED, "the done quest is done")
	assert_eq(restored.turn_in(VEIN, ELDER, _payers()).reason, QuestService.REFUSE_ALREADY_DONE,
		"it cannot be answered again")
	assert_eq([_pill_count(), _xp, _regard(ELDER, &"respect")], [2, 10, 10],
		"so nothing was paid twice across the round trip")
	# Even a state that FORGOT the completion cannot be paid again: the ledger remembers.
	var amnesiac := QuestState.new()
	var forgetful := QuestService.new(_catalog(), amnesiac, _knowledge, RewardService.new(ledger),
		_held)
	forgetful.accept(VEIN, ELDER)
	var replay := forgetful.turn_in(VEIN, ELDER, _payers())
	assert_true(replay.ok, "the quest closes")
	assert_eq(replay.reward_status, RewardOutcome.Status.ALREADY_PAID, "as already paid")
	assert_eq([_pill_count(), _xp, _regard(ELDER, &"respect")], [2, 10, 10], "with nothing paid")


func test_a_bad_quest_payload_is_rejected_whole() -> void:
	var service := _service()
	service.accept(HUNT, SCOUT)
	service.record_defeat(WOLF, &"enemy_mist_wolf_1#1")
	var good := _state.to_dict()
	var catalog := _catalog()
	var hunt := {"status": "active", "progress": {"cull": 1}, "counted": {"cull": ["a#1"]}}
	var cases: Array[Dictionary] = [
		{},
		{"schema": 2, "quests": {}},
		{"schema": 1, "quests": []},
		{"schema": 1, "quests": {"quest_nothing": hunt}},
		{"schema": 1, "quests": {"quest_test_hunt": "active"}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "asleep", "progress": {},
			"counted": {}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active", "progress": [],
			"counted": {}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active",
			"progress": {"nothing": 1}, "counted": {"nothing": ["a#1"]}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active",
			"progress": {"learn": 1}, "counted": {"learn": ["a#1"]}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active",
			"progress": {"cull": 3}, "counted": {"cull": ["a#1", "b#2", "c#3"]}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active",
			"progress": {"cull": 2}, "counted": {"cull": ["a#1"]}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active",
			"progress": {"cull": 2}, "counted": {"cull": ["a#1", "a#1"]}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active",
			"progress": {"cull": 1.0}, "counted": {"cull": ["a#1"]}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "active",
			"progress": {}, "counted": {"cull": ["a#1"]}}}},
		{"schema": 1, "quests": {"quest_test_hunt": {"status": "completed",
			"progress": {"cull": 1}, "counted": {"cull": ["a#1"]}}}},
	]
	for bad in cases:
		assert_false(_state.from_dict(bad, catalog), "rejected: %s" % str(bad))
		assert_eq(_state.to_dict(), good, "and the state is unchanged")
	assert_false(_state.from_dict(good, null), "no catalog to validate against: rejected")
	assert_true(_state.from_dict({"schema": 1, "quests": {"quest_test_hunt": hunt}}, catalog),
		"a well-formed payload is accepted")

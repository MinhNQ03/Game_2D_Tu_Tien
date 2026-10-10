extends Node
class_name QuestRuntime
## QuestRuntime — Aetheria gameplay (the session's quests, Phase 19, D-070).
##
## Per-session node under `Main/Systems` (no autoload). It owns the session's `QuestState`
## through the one `QuestService`, and the connections that let the world move it:
##
##   * a defeat (`CombatRuntime.enemy_defeated`) is counted by the service — combat is asked
##     WHAT fell, the per-spawn id makes each defeat count once;
##   * knowledge gained and the bag changing are not counted at all: those objectives are a
##     question to their owner, so this node only re-reads and announces what changed;
##   * a reward is paid by `RewardService` through the owners' own seams, handed over here —
##     the bag's all-or-nothing exchange, progression, the relationship graph.
##
## Accepting, abandoning and turning in are ASKED OF IT by the conversation
## (`DialogueRuntime`, the one surface a quest is offered and answered on). This node opens
## nothing and decides nothing the service did not.
##
## READINESS IS DERIVED. "Ready" is asked of the owners each time; what this node remembers
## (`_seen`) is only what it last ANNOUNCED, so it can say "ready" once per time it becomes
## true. That memory is runtime-only and is not saved.
##
## FAIL CLOSED. An invalid catalog, or content naming something its owner does not have,
## stops the session from starting. Every refusal returns a reason key and changes nothing.
##
## PERSISTENCE. `to_dict()` / `from_dict()` are `QuestState`'s plain-data boundary (SAVE_FORMAT
## `quests`). No file is written here.
##
## No `_process`: nothing here runs unless the world announces something or someone asks.

signal quest_accepted(quest_id: StringName)
signal quest_abandoned(quest_id: StringName)
## An objective moved and the quest is NOT yet ready (when it is, `quest_ready` says so).
signal quest_advanced(quest_id: StringName, objective_id: StringName, value: int, required: int)
## The objectives of an accepted quest are now met (announced once each time it becomes so).
signal quest_ready(quest_id: StringName)
## Turned in and paid in full.
signal quest_completed(quest_id: StringName)
## Anything the journal or the plaque shows changed.
signal view_changed()

const CATALOG_PATH := "res://data/quests/quest_catalog.tres"

var _world: Node = null
var _knowledge: KnowledgeRuntime = null
var _inventory: InventoryRuntime = null
var _combat: Node = null
var _progression: Node = null
var _relationship: RelationshipRuntime = null
var _service: QuestService = null
var _session_active: bool = false

## quest_id(String) -> { "ready": bool, "values": { objective_id(String) -> int } } as last
## announced. Runtime-only.
var _seen: Dictionary = {}
var _signature: String = ""


## Start the session. Builds into locals and commits only when every check passed: the catalog
## is structurally valid AND everything it names exists in its owner (registered characters,
## knowledge ids, items, creatures some map spawns, relationship dimensions, a translation of
## every line in every language). `catalog` is the content seam (null = the shipped one).
func start_session(world: Node, knowledge: KnowledgeRuntime, inventory: InventoryRuntime,
		combat: Node, progression: Node, relationship: RelationshipRuntime,
		rewards: RewardRuntime, catalog: QuestCatalogData = null) -> bool:
	if _session_active:
		push_error("[quest-rt] start_session while a session is active")
		return false
	if world == null or knowledge == null or not knowledge.is_session_active() \
			or inventory == null or not inventory.is_session_active() \
			or combat == null or not combat.has_signal("enemy_defeated") \
			or not combat.has_method("defeated_kind") \
			or progression == null or not progression.has_method("grant_reward") \
			or relationship == null or not relationship.is_session_active() \
			or rewards == null or not rewards.is_session_active():
		push_error("[quest-rt] session NOT started: a dependency is missing or inactive")
		return false
	if catalog == null:
		catalog = load(CATALOG_PATH) as QuestCatalogData
	if catalog == null:
		push_error("[quest-rt] session NOT started: %s did not load" % CATALOG_PATH)
		return false
	var service := QuestService.new(catalog, QuestState.new(), knowledge.get_service(),
		rewards.get_service(), inventory.count_of)
	if not service.is_ready():
		push_error("[quest-rt] session NOT started: the QuestService refused its catalog")
		return false
	# Who gives and receives is the registry's to answer, and which creatures exist is the
	# world's. Neither missing is a skipped check: both are refusals.
	var registry: CharacterRegistry = world.call("get_character_registry") \
		if world.has_method("get_character_registry") else null
	if registry == null or not world.has_method("get_enemy_kinds"):
		push_error("[quest-rt] session NOT started: the world cannot say who or what exists")
		return false
	var kinds: Array = world.call("get_enemy_kinds")
	var items := inventory.get_catalog()
	var graph := relationship.get_service()
	var errors := service.content_errors(_translation_check(),
		func(item_id: StringName) -> bool: return items.entry(item_id) != null,
		func(enemy_id: StringName) -> bool: return kinds.has(enemy_id),
		registry.resolver(),
		func(dimension: StringName) -> bool: return graph.has_dimension(dimension))
	if not errors.is_empty():
		push_error("[quest-rt] session NOT started: %s" % str(errors))
		return false
	_world = world
	_knowledge = knowledge
	_inventory = inventory
	_combat = combat
	_progression = progression
	_relationship = relationship
	_service = service
	_seen = {}
	_signature = ""
	_session_active = true
	_knowledge.knowledge_gained.connect(_on_knowledge_gained)
	_inventory.inventory_changed.connect(_refresh)
	_combat.connect("enemy_defeated", _on_enemy_defeated)
	# Take the first reading silently: a session that has just started has nothing to announce.
	_refresh(true)
	return true


## End the session: stop listening, then drop everything. Idempotent.
func end_session() -> void:
	if _knowledge != null and is_instance_valid(_knowledge) \
			and _knowledge.knowledge_gained.is_connected(_on_knowledge_gained):
		_knowledge.knowledge_gained.disconnect(_on_knowledge_gained)
	if _inventory != null and is_instance_valid(_inventory) \
			and _inventory.inventory_changed.is_connected(_refresh):
		_inventory.inventory_changed.disconnect(_refresh)
	if _combat != null and is_instance_valid(_combat) \
			and _combat.is_connected("enemy_defeated", _on_enemy_defeated):
		_combat.disconnect("enemy_defeated", _on_enemy_defeated)
	_world = null
	_knowledge = null
	_inventory = null
	_combat = null
	_progression = null
	_relationship = null
	_service = null
	_seen = {}
	_signature = ""
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_service() -> QuestService:
	return _service


# --- What the conversation asks ---------------------------------------------------

## `speaker_id` offers `quest_id` and the player takes it.
func accept(quest_id: StringName, speaker_id: StringName) -> QuestOutcome:
	if not _session_active:
		return QuestOutcome.refused(QuestService.REFUSE_NOT_READY, quest_id)
	var outcome := _service.accept(quest_id, speaker_id)
	if outcome.ok:
		quest_accepted.emit(quest_id)
		_refresh()
	return outcome


## The player gives `quest_id` back to `speaker_id`, its giver.
func abandon(quest_id: StringName, speaker_id: StringName) -> QuestOutcome:
	if not _session_active:
		return QuestOutcome.refused(QuestService.REFUSE_NOT_READY, quest_id)
	var outcome := _service.abandon(quest_id, speaker_id)
	if outcome.ok:
		_seen.erase(String(quest_id))
		quest_abandoned.emit(quest_id)
		_refresh()
	return outcome


## The player answers `quest_id` to `speaker_id`. The reward is paid through the owners; the
## quest is completed only when the ledger says it is paid in full.
func turn_in(quest_id: StringName, speaker_id: StringName) -> QuestOutcome:
	if not _session_active:
		return QuestOutcome.refused(QuestService.REFUSE_NOT_READY, quest_id)
	var outcome := _service.turn_in(quest_id, speaker_id, _payers())
	if outcome.ok:
		_seen.erase(String(quest_id))
		quest_completed.emit(quest_id)
	# Even a refusal may have changed what is shown (a reward now owed), and the bag moving
	# has already asked for a refresh; `_refresh` announces only what is new.
	_refresh()
	return outcome


func _payers() -> RewardPayers:
	var payers := RewardPayers.new()
	payers.trade = _inventory.exchange
	payers.pay_xp = Callable(_progression, "grant_reward")
	payers.move_regard = _move_regard
	return payers


## A character's regard for the PLAYER, moved through the relationship graph's service.
func _move_regard(character_id: StringName, dimension: StringName, delta: int,
		source_id: StringName) -> bool:
	var player: CharacterState = _world.call("get_player_character") \
		if _world != null and is_instance_valid(_world) else null
	if player == null:
		return false
	return bool(RegardRules.move(_relationship.get_service(), _relationship.get_config(),
		character_id, player.instance_id, dimension, delta, source_id)["ok"])


# --- The world moving ---------------------------------------------------------

func _on_enemy_defeated(reward_id: StringName, _xp_reward: int) -> void:
	if not _session_active:
		return
	var kind: StringName = _combat.call("defeated_kind", reward_id)
	if not _service.record_defeat(kind, reward_id).is_empty():
		_refresh()


func _on_knowledge_gained(_knowledge_id: StringName, _source_id: StringName) -> void:
	_refresh()


## Re-read every accepted quest from the owners and announce what is NEW since the last
## reading: an objective that moved forward, a quest that became ready. Emits `view_changed`
## only when something the journal shows is different. `silent` takes the reading and
## announces nothing (the first one of a session).
func _refresh(silent: bool = false) -> void:
	if not _session_active:
		return
	var parts: PackedStringArray = []
	for quest in _service.catalog().entries:
		var phase := _service.phase_of(quest.id)
		parts.append("%s=%d%s" % [quest.id, phase, "!" if _service.is_reward_owed(quest.id)
			else ""])
		if phase != QuestService.Phase.ACTIVE and phase != QuestService.Phase.READY:
			_seen.erase(String(quest.id))
			continue
		var before: Dictionary = _seen.get(String(quest.id), {"ready": false, "values": {}})
		var ready := phase == QuestService.Phase.READY
		var values: Dictionary = {}
		for entry in quest.objectives:
			var value := _service.objective_value(quest.id, entry)
			values[String(entry.id)] = value
			parts.append("%s:%d" % [entry.id, value])
			if not silent and not ready \
					and value > int(before["values"].get(String(entry.id), 0)):
				quest_advanced.emit(quest.id, entry.id, value, entry.count)
		if not silent and ready and not bool(before["ready"]):
			quest_ready.emit(quest.id)
		_seen[String(quest.id)] = {"ready": ready, "values": values}
	var signature := "|".join(parts)
	if signature != _signature:
		_signature = signature
		if not silent:
			view_changed.emit()


# --- View ---------------------------------------------------------------------

## The read-only snapshot the journal and the place plaque show.
func build_view() -> QuestJournalView:
	var view := QuestJournalView.make_empty()
	if not _session_active:
		return view
	view.available = true
	var registry: CharacterRegistry = _world.call("get_character_registry") \
		if _world != null and is_instance_valid(_world) else null
	var purpose_rank := -1
	for quest in _service.catalog().entries:
		var phase := _service.phase_of(quest.id)
		var hint := quest.lead_key
		if phase == QuestService.Phase.ACTIVE:
			hint = quest.goal_key
		elif phase == QuestService.Phase.READY:
			hint = quest.return_key
		elif phase == QuestService.Phase.COMPLETED:
			hint = &""
		# READY outranks ACTIVE outranks AVAILABLE; within a rank the first authored wins.
		var rank := -1 if phase == QuestService.Phase.COMPLETED else int(phase)
		if rank > purpose_rank:
			purpose_rank = rank
			view.purpose_key = hint
			view.purpose_phase = phase
		view.entries.append(_entry_of(quest, phase, hint, registry))
	return view


func _entry_of(quest: QuestData, phase: int, hint: StringName,
		registry: CharacterRegistry) -> Dictionary:
	var objectives: Array[Dictionary] = []
	for entry in quest.objectives:
		var value := _service.objective_value(quest.id, entry)
		objectives.append({"text_key": entry.text_key, "value": value,
			"required": entry.count, "met": value >= entry.count})
	var reward_items: Array[Dictionary] = []
	for row in quest.reward.items:
		reward_items.append({"name_key": row.item.name_key, "count": row.count})
	return {"quest_id": quest.id, "phase": phase, "owed": _service.is_reward_owed(quest.id),
		"title_key": quest.title_key, "summary_key": quest.summary_key, "hint_key": hint,
		"giver_name_key": _name_of(registry, quest.giver_id),
		"receiver_name_key": _name_of(registry, quest.receiver_id),
		"any": quest.completion == QuestData.Completion.ANY, "objectives": objectives,
		"reward_items": reward_items, "reward_xp": quest.reward.xp,
		"reward_regard_name_key": _name_of(registry, quest.reward.regard_character_id),
		"reward_regard_dimension": quest.reward.regard_dimension,
		"reward_regard_delta": quest.reward.regard_delta}


func _name_of(registry: CharacterRegistry, character_id: StringName) -> StringName:
	var character := registry.get_character(character_id) \
		if registry != null and character_id != &"" else null
	return character.name_key if character != null else &""


## `key -> bool`: translated in every language. Asked of the `Localization` autoload; a node
## outside the tree (a unit test with no autoloads) has nobody to ask and skips the check.
func _translation_check() -> Callable:
	var loc := get_node_or_null("/root/Localization") if is_inside_tree() else null
	if loc == null or not loc.has_method("is_translated"):
		return Callable()
	return func(key: StringName) -> bool: return bool(loc.call("is_translated", String(key)))


# --- Persistence boundary -------------------------------------------------------

func to_dict() -> Dictionary:
	return _service.state().to_dict() if _service != null else {}


## Restore quest state. Atomic: a rejected payload changes nothing. What was already
## announced is not part of it: a restored quest that is ready says so once.
func from_dict(data: Dictionary) -> bool:
	if not _session_active or not _service.state().from_dict(data, _service.catalog()):
		return false
	_seen = {}
	_signature = ""
	_refresh()
	return true

extends RefCounted
class_name QuestService
## QuestService — Aetheria domain (the rules of a quest, Phase 19, D-070).
##
## Node-free and scene-free. The ONLY writer of `QuestState`. Given the authored catalog and
## the owners a quest asks and pays through, it answers where a quest stands and carries out
## the four things that can be asked of it: accept, abandon, count a defeat, turn in.
##
## IT OWNS QUEST STATE AND NOTHING ELSE.
##   * "Is this known" is the Knowledge Core's; "is this held" is the bag's. Both are ASKED
##     every time, so READY is derived, never stored — a pill swallowed after the objective
##     was met makes the quest not ready again, truthfully.
##   * A reward is paid by `RewardService` through its owners' seams; "paid" is the reward
##     ledger's. This class marks a quest COMPLETED only after the ledger says so.
##
## A PHASE is what the player (and a dialogue condition) sees:
##   AVAILABLE  no record — it can be accepted
##   ACTIVE     accepted, objectives not met
##   READY      objectives met — or turned in with part of the reward still owed
##   COMPLETED  paid in full; it is never offered again
##
## Every refusal returns a reason key and changes nothing.

enum Phase { AVAILABLE, ACTIVE, READY, COMPLETED }

const REFUSE_NOT_READY := &"UI_QUEST_UNAVAILABLE"
const REFUSE_UNKNOWN := &"UI_QUEST_UNKNOWN"
## Accept: it is already taken, or already done.
const REFUSE_ALREADY_TAKEN := &"UI_QUEST_ALREADY_TAKEN"
const REFUSE_ALREADY_DONE := &"UI_QUEST_ALREADY_DONE"
## Abandon / turn in: it was never taken.
const REFUSE_NOT_TAKEN := &"UI_QUEST_NOT_TAKEN"
## Turn in: the objectives are not met (any more).
const REFUSE_OBJECTIVES := &"UI_QUEST_NOT_FINISHED"
## The person asked is not the one this quest is taken from / answered to.
const REFUSE_WRONG_PERSON := &"UI_QUEST_WRONG_PERSON"
## Abandon: the reward is already partly paid; the rest is owed, not given up.
const REFUSE_REWARD_OWED := &"UI_QUEST_REWARD_OWED"
## Turn in: the bag has no room for the reward. Nothing was paid, nothing was taken.
const REFUSE_NO_ROOM := &"UI_QUEST_REWARD_NO_ROOM"
## Turn in: the reward could not be paid at all.
const REFUSE_UNPAYABLE := &"UI_QUEST_REWARD_UNPAYABLE"

const REWARD_ID_FORMAT := "quest:%s"

var _catalog: QuestCatalogData = null
var _state: QuestState = null
var _knowledge: KnowledgeService = null
var _rewards: RewardService = null
## `(item_id: StringName) -> int`: how many the bag holds.
var _held: Callable = Callable()


func _init(catalog: QuestCatalogData = null, state: QuestState = null,
		knowledge: KnowledgeService = null, rewards: RewardService = null,
		held: Callable = Callable()) -> void:
	if catalog == null or state == null or knowledge == null or not knowledge.is_ready() \
			or rewards == null or not rewards.is_ready() or not held.is_valid():
		return
	if not catalog.is_valid():
		push_error("[quest] refusing an invalid catalog: %s" % str(catalog.validation_errors()))
		return
	_catalog = catalog
	_state = state
	_knowledge = knowledge
	_rewards = rewards
	_held = held


func is_ready() -> bool:
	return _catalog != null


func catalog() -> QuestCatalogData:
	return _catalog


func state() -> QuestState:
	return _state


## The reward ledger id of a quest: stable, so a quest pays once however often it is asked.
static func reward_id_of(quest_id: StringName) -> StringName:
	return StringName(REWARD_ID_FORMAT % quest_id)


## What the catalog asks of OTHER owners that they cannot give. Structural errors are
## `QuestCatalogData.validation_errors`; this is the cross-owner half. Each seam is optional
## (an invalid Callable skips that check): `has_text(key) -> bool`,
## `has_item(item_id) -> bool`, `has_enemy(enemy_id) -> bool`,
## `resolve_character(instance_id) -> CharacterState`, `has_dimension(dimension) -> bool`.
func content_errors(has_text: Callable = Callable(), has_item: Callable = Callable(),
		has_enemy: Callable = Callable(), resolve_character: Callable = Callable(),
		has_dimension: Callable = Callable()) -> Array[String]:
	var errors: Array[String] = []
	if not is_ready():
		errors.append("the quest service is not ready")
		return errors
	for quest in _catalog.entries:
		if has_text.is_valid():
			for key in quest.text_keys():
				if not bool(has_text.call(key)):
					errors.append("%s: text '%s' has no translation in every language"
						% [quest.id, key])
		if resolve_character.is_valid():
			for who: StringName in [quest.giver_id, quest.receiver_id]:
				if not (resolve_character.call(who) is CharacterState):
					errors.append("%s: names '%s', who is not a registered character"
						% [quest.id, who])
		for entry in quest.objectives:
			errors.append_array(_objective_errors("%s/%s" % [quest.id, entry.id], entry,
				has_item, has_enemy))
		errors.append_array(_reward_errors(quest, has_item, resolve_character, has_dimension))
	return errors


func _objective_errors(where: String, entry: QuestObjectiveData, has_item: Callable,
		has_enemy: Callable) -> Array[String]:
	var errors: Array[String] = []
	match entry.kind:
		QuestObjectiveData.Kind.KNOW:
			if not _knowledge.catalog().has(entry.target_id):
				errors.append("%s: asks for knowledge '%s', which the catalog does not define"
					% [where, entry.target_id])
		QuestObjectiveData.Kind.HOLD_ITEM:
			if has_item.is_valid() and not bool(has_item.call(entry.target_id)):
				errors.append("%s: asks for item '%s', which is not in the item catalog"
					% [where, entry.target_id])
		QuestObjectiveData.Kind.DEFEAT:
			if has_enemy.is_valid() and not bool(has_enemy.call(entry.target_id)):
				errors.append("%s: asks for the defeat of '%s', which no map spawns"
					% [where, entry.target_id])
	return errors


func _reward_errors(quest: QuestData, has_item: Callable, resolve_character: Callable,
		has_dimension: Callable) -> Array[String]:
	var errors: Array[String] = []
	var reward := quest.reward
	if has_item.is_valid():
		for item_id: StringName in reward.item_counts():
			if not bool(has_item.call(item_id)):
				errors.append("%s: rewards item '%s', which is not in the item catalog"
					% [quest.id, item_id])
	if reward.has_regard():
		if resolve_character.is_valid() \
				and not (resolve_character.call(reward.regard_character_id) is CharacterState):
			errors.append("%s: moves the regard of '%s', who is not a registered character"
				% [quest.id, reward.regard_character_id])
		if has_dimension.is_valid() and not bool(has_dimension.call(reward.regard_dimension)):
			errors.append("%s: moves '%s', which the relationship graph does not define"
				% [quest.id, reward.regard_dimension])
	return errors


# --- Reading -------------------------------------------------------------------

func phase_of(quest_id: StringName) -> Phase:
	var quest := _catalog.entry(quest_id) if is_ready() else null
	if quest == null or not _state.has(quest_id):
		return Phase.AVAILABLE
	match _state.status_of(quest_id):
		QuestState.Status.COMPLETED:
			return Phase.COMPLETED
		QuestState.Status.REWARD_OWED:
			return Phase.READY
	return Phase.READY if objectives_met(quest) else Phase.ACTIVE


## Turned in, with part of its reward still to be paid.
func is_reward_owed(quest_id: StringName) -> bool:
	return is_ready() and _state.is_status(quest_id, QuestState.Status.REWARD_OWED)


## How far `entry` is, 0..`entry.count`, asked of whoever owns the answer.
func objective_value(quest_id: StringName, entry: QuestObjectiveData) -> int:
	if not is_ready() or entry == null:
		return 0
	match entry.kind:
		QuestObjectiveData.Kind.KNOW:
			return 1 if _knowledge.knows(entry.target_id) else 0
		QuestObjectiveData.Kind.HOLD_ITEM:
			return clampi(int(_held.call(entry.target_id)), 0, entry.count)
		QuestObjectiveData.Kind.DEFEAT:
			return mini(_state.progress_of(quest_id, entry.id), entry.count)
	return 0


func objective_met(quest_id: StringName, entry: QuestObjectiveData) -> bool:
	return entry != null and objective_value(quest_id, entry) >= entry.count


func objectives_met(quest: QuestData) -> bool:
	if quest == null:
		return false
	var any := false
	for entry in quest.objectives:
		if objective_met(quest.id, entry):
			any = true
		elif quest.completion == QuestData.Completion.ALL:
			return false
	return any


# --- Changing ------------------------------------------------------------------

## `speaker_id` offers `quest_id` and the player takes it. State objectives already true
## count from this moment; counted ones start at zero.
func accept(quest_id: StringName, speaker_id: StringName) -> QuestOutcome:
	var quest := _catalog.entry(quest_id) if is_ready() else null
	if quest == null:
		return QuestOutcome.refused(REFUSE_UNKNOWN if is_ready() else REFUSE_NOT_READY, quest_id)
	if _state.has(quest_id):
		return QuestOutcome.refused(REFUSE_ALREADY_DONE
			if _state.is_status(quest_id, QuestState.Status.COMPLETED)
			else REFUSE_ALREADY_TAKEN, quest_id)
	if speaker_id != quest.giver_id:
		return QuestOutcome.refused(REFUSE_WRONG_PERSON, quest_id)
	_state.begin(quest_id)
	return QuestOutcome.accepted(quest_id)


## The player gives `quest_id` back to its giver. What was counted is discarded and the quest
## is AVAILABLE again. A quest whose reward is partly paid cannot be abandoned: it is owed.
func abandon(quest_id: StringName, speaker_id: StringName) -> QuestOutcome:
	var quest := _catalog.entry(quest_id) if is_ready() else null
	if quest == null:
		return QuestOutcome.refused(REFUSE_UNKNOWN if is_ready() else REFUSE_NOT_READY, quest_id)
	if not _state.has(quest_id):
		return QuestOutcome.refused(REFUSE_NOT_TAKEN, quest_id)
	if _state.is_status(quest_id, QuestState.Status.COMPLETED):
		return QuestOutcome.refused(REFUSE_ALREADY_DONE, quest_id)
	if _state.is_status(quest_id, QuestState.Status.REWARD_OWED):
		return QuestOutcome.refused(REFUSE_REWARD_OWED, quest_id)
	if speaker_id != quest.giver_id:
		return QuestOutcome.refused(REFUSE_WRONG_PERSON, quest_id)
	_state.erase(quest_id)
	return QuestOutcome.accepted(quest_id)


## A creature of kind `enemy_id` was defeated; `source_id` is that defeat's own identity (the
## per-spawn reward id). Every ACTIVE quest counting that kind advances by one — each source
## once, never past what the objective asks. Returns the quests that advanced, as
## `[quest_id, objective_id, value, required]` rows.
func record_defeat(enemy_id: StringName, source_id: StringName) -> Array[Array]:
	var advanced: Array[Array] = []
	if not is_ready() or enemy_id == &"" or source_id == &"":
		return advanced
	for quest_id in _state.quest_ids():
		if not _state.is_status(quest_id, QuestState.Status.ACTIVE):
			continue
		var quest := _catalog.entry(quest_id)
		for entry in quest.objectives:
			if entry.kind != QuestObjectiveData.Kind.DEFEAT or entry.target_id != enemy_id \
					or _state.progress_of(quest_id, entry.id) >= entry.count \
					or _state.has_counted(quest_id, entry.id, source_id):
				continue
			var value := _state.count_one(quest_id, entry.id, source_id)
			advanced.append([quest_id, entry.id, value, entry.count])
	return advanced


## The player answers `quest_id` to `speaker_id`. Legal when the objectives are met NOW (or
## the reward is owed); the reward is then paid through `payers` by `RewardService`. The quest
## is COMPLETED only when the ledger says the reward is paid in full.
##   * the bag refuses (no room): refused, nothing paid, nothing taken — still READY;
##   * a later part fails after the bag moved: the quest is owed its reward; ask again;
##   * asked again after completion: refused as done, nothing paid.
func turn_in(quest_id: StringName, speaker_id: StringName,
		payers: RewardPayers) -> QuestOutcome:
	var quest := _catalog.entry(quest_id) if is_ready() else null
	if quest == null:
		return QuestOutcome.refused(REFUSE_UNKNOWN if is_ready() else REFUSE_NOT_READY, quest_id)
	if not _state.has(quest_id):
		return QuestOutcome.refused(REFUSE_NOT_TAKEN, quest_id)
	if _state.is_status(quest_id, QuestState.Status.COMPLETED):
		return QuestOutcome.refused(REFUSE_ALREADY_DONE, quest_id)
	if speaker_id != quest.receiver_id:
		return QuestOutcome.refused(REFUSE_WRONG_PERSON, quest_id)
	var owed := _state.is_status(quest_id, QuestState.Status.REWARD_OWED)
	if not owed and not objectives_met(quest):
		return QuestOutcome.refused(REFUSE_OBJECTIVES, quest_id)
	# What is handed over: every met objective that says its items change hands. When the
	# reward is owed the bag part is already recorded as paid, so `RewardService` does not
	# run the exchange again — whatever the player has picked up since is not taken.
	var take: Dictionary = {}
	for entry in quest.objectives:
		if entry.kind == QuestObjectiveData.Kind.HOLD_ITEM and entry.consumed \
				and objective_met(quest_id, entry):
			take[entry.target_id] = int(take.get(entry.target_id, 0)) + entry.count
	var paid := _rewards.deliver(reward_id_of(quest_id), quest.reward, take, payers)
	var outcome := QuestOutcome.refused(&"", quest_id)
	outcome.reward_status = paid.status
	outcome.paid_now = paid.paid_now
	if paid.paid_now.has(RewardService.PART_BAG):
		outcome.taken = take
	match paid.status:
		RewardOutcome.Status.PAID, RewardOutcome.Status.ALREADY_PAID:
			_state.set_status(quest_id, QuestState.Status.COMPLETED)
			outcome.ok = true
		RewardOutcome.Status.OWED:
			_state.set_status(quest_id, QuestState.Status.REWARD_OWED)
			outcome.reason = REFUSE_REWARD_OWED
		_:
			outcome.reason = REFUSE_NO_ROOM \
				if paid.reason == RewardService.REFUSE_NO_ROOM else REFUSE_UNPAYABLE
	return outcome

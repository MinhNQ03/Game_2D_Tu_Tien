extends RefCounted
class_name QuestOutcome
## QuestOutcome — Aetheria domain (what asking the quest owner for something came to).
##
## Plain facts in stable ids. Never text, never a node.

var ok: bool = false
## A refusal's localization key (`QuestService.REFUSE_*`); empty on success.
var reason: StringName = &""
var quest_id: StringName = &""
## On a turn-in: what the reward ledger answered (a `RewardOutcome.Status`), else -1.
var reward_status: int = -1
## On a turn-in: the reward parts THIS call paid (`RewardService.PART_*`).
var paid_now: Array[StringName] = []
## On a turn-in that moved the bag: what left it, `{item_id -> count}`.
var taken: Dictionary = {}


static func accepted(p_quest: StringName) -> QuestOutcome:
	var outcome := QuestOutcome.new()
	outcome.ok = true
	outcome.quest_id = p_quest
	return outcome


static func refused(why: StringName, p_quest: StringName = &"") -> QuestOutcome:
	var outcome := QuestOutcome.new()
	outcome.reason = why
	outcome.quest_id = p_quest
	return outcome

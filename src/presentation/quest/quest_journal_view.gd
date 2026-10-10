extends RefCounted
class_name QuestJournalView
## QuestJournalView — Aetheria presentation DTO (what the journal and the place plaque show of
## the player's quests, Phase 19).
##
## A read-only snapshot built by `QuestRuntime.build_view()` and pushed through `WorldRuntime`
## → `MapBase` → `GameplayHUD`. Localization KEYS, numbers and phases — never a `QuestData`,
## a `QuestState` or a node. Presentation decides nothing from it: what is "ready" was decided
## by `QuestService`, by asking the owners.

## The session has a quest owner at all (false = show nothing).
var available: bool = false

## The ONE line of purpose for the place plaque, or empty when nothing is on offer or under
## way: the first quest ready to answer, else the first under way, else the first on offer.
var purpose_key: StringName = &""
## A `QuestService.Phase` of the quest the purpose line speaks of.
var purpose_phase: int = 0

## Every quest worth reading about, in authored order — on offer, under way, ready, done:
## { quest_id, phase: int, owed: bool, title_key, summary_key, hint_key,
##   giver_name_key, receiver_name_key, any: bool,
##   objectives: Array[{ text_key, value: int, required: int, met: bool }],
##   reward_items: Array[{ name_key, count: int }], reward_xp: int,
##   reward_regard_name_key, reward_regard_dimension }
var entries: Array[Dictionary] = []


static func make_empty() -> QuestJournalView:
	return QuestJournalView.new()

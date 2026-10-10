extends Node
class_name RewardRuntime
## RewardRuntime — Aetheria gameplay (the session's one reward ledger, Phase 19, D-070).
##
## Per-session node under `Main/Systems` (no autoload). It owns exactly two things: the
## `RewardLedger` — the ONE record of what has been paid, for a defeat's XP, a quest and (from
## Phase 21) a drop alike — and the `RewardService` that pays a multi-part reward against it.
## It pays nothing itself and listens to nothing: whoever has a reward to pay (`QuestRuntime`
## today) hands `RewardService.deliver` the owners' seams.
##
## A NODE, for the same reason every session owner is one: the ledger must not outlive the
## run it describes. It needs no other session, so it starts before `ProgressionRuntime`,
## which claims each defeat in this ledger instead of keeping a second one (audit AUD-12).
##
## PERSISTENCE. `to_dict()` / `from_dict()` are the ledger's plain-data boundary (SAVE_FORMAT
## `rewards`). No file is written here.
##
## No `_process`: nothing here runs unless someone pays.

var _ledger: RewardLedger = null
var _service: RewardService = null
var _session_active: bool = false


func start_session() -> bool:
	if _session_active:
		push_error("[reward-rt] start_session while a session is active")
		return false
	_ledger = RewardLedger.new()
	_service = RewardService.new(_ledger)
	_session_active = true
	return true


## End the session and drop the ledger with it. Idempotent.
func end_session() -> void:
	_service = null
	_ledger = null
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_ledger() -> RewardLedger:
	return _ledger


func get_service() -> RewardService:
	return _service


func to_dict() -> Dictionary:
	return _ledger.to_dict() if _ledger != null else {}


## Restore what has been paid. Atomic: a rejected payload changes nothing.
func from_dict(data: Dictionary) -> bool:
	return _session_active and _ledger.from_dict(data)

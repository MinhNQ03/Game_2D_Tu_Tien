extends RefCounted
class_name RewardOutcome
## RewardOutcome — Aetheria domain (what one attempt to pay a reward came to, Phase 19).

enum Status {
	## Every part is paid (by this call, or it and earlier ones).
	PAID,
	## The id was already fully paid before this call. Nothing was paid now.
	ALREADY_PAID,
	## Refused before anything changed: nothing was paid, nothing was taken, nothing recorded.
	REFUSED,
	## Some parts are paid and recorded, at least one is not. Calling again pays only the rest.
	OWED,
}

var status: Status = Status.REFUSED
## A localization key for REFUSED / OWED; empty otherwise.
var reason: StringName = &""
## The parts THIS call paid (`RewardService.PART_*`), in the order they were paid.
var paid_now: Array[StringName] = []


func is_settled() -> bool:
	return status == Status.PAID or status == Status.ALREADY_PAID


static func make(p_status: Status, p_reason: StringName = &"") -> RewardOutcome:
	var outcome := RewardOutcome.new()
	outcome.status = p_status
	outcome.reason = p_reason
	return outcome

extends RefCounted
class_name RewardService
## RewardService — Aetheria domain (paying a multi-part reward exactly once, Phase 19, D-070).
##
## Node-free. Given the ledger and the owners' seams, `deliver` pays ONE reward for ONE source
## id and can be called again safely, any number of times, by any path.
##
## THE CONTRACT — ordered, idempotent, resumable. Not a rollback, and it does not pretend to
## be one: no mechanism spans the bag, progression and the relationship graph.
##
##   1. The BAG part goes first (items in, and whatever the source takes out, as one
##      all-or-nothing exchange). It is the only part an owner legitimately refuses — a full
##      bag. Refused: REFUSED, nothing recorded, nothing changed anywhere.
##   2. Each part its owner ACCEPTS is recorded at once as `<id>/<part>`.
##   3. With every part recorded, `<id>` itself is recorded: PAID.
##   4. A later part that fails leaves OWED. Calling again pays only the unrecorded parts —
##      a part is never recorded before its owner accepted it and never paid twice.
##
## A reward being paid cannot be paid re-entrantly (a listener of the bag's change submitting
## the same turn-in): the id is in flight, and the inner call is refused.
##
## This is the seam Phase 21 reuses for drops: a source id and a `RewardData`. It knows
## nothing about quests.

const PART_BAG := &"bag"
const PART_XP := &"xp"
const PART_REGARD := &"regard"

## The bag refused the exchange (no room for what the reward gives).
const REFUSE_NO_ROOM := &"UI_REWARD_NO_ROOM"
## The reward names a part this session has no owner to pay through, or is malformed.
const REFUSE_UNPAYABLE := &"UI_REWARD_UNPAYABLE"
## The same reward is already being paid further up the call stack.
const REFUSE_BUSY := &"UI_REWARD_BUSY"
## A part after the bag was refused by its owner: the rest is owed.
const REASON_OWED := &"UI_REWARD_OWED"

var _ledger: RewardLedger = null
## id(String) -> true while `deliver` is paying it.
var _in_flight: Dictionary = {}


func _init(ledger: RewardLedger = null) -> void:
	_ledger = ledger


func is_ready() -> bool:
	return _ledger != null


func ledger() -> RewardLedger:
	return _ledger


static func part_id(reward_id: StringName, part: StringName) -> StringName:
	return StringName("%s/%s" % [reward_id, part])


## Has `reward_id` been fully paid?
func is_paid(reward_id: StringName) -> bool:
	return is_ready() and _ledger.has(reward_id)


## Has anything of `reward_id` been paid (so its bag part must not be asked for again)?
func is_part_paid(reward_id: StringName, part: StringName) -> bool:
	return is_ready() and _ledger.has(part_id(reward_id, part))


## Pay `reward` for `reward_id`, taking `take` (`{item_id -> count}`, may be empty) out of the
## bag in the same exchange that puts the reward's items in. See the class contract.
func deliver(reward_id: StringName, reward: RewardData, take: Dictionary,
		payers: RewardPayers) -> RewardOutcome:
	if not is_ready() or reward_id == &"" or reward == null or payers == null \
			or not reward.is_valid():
		return RewardOutcome.make(RewardOutcome.Status.REFUSED, REFUSE_UNPAYABLE)
	if _ledger.has(reward_id):
		return RewardOutcome.make(RewardOutcome.Status.ALREADY_PAID)
	var key := String(reward_id)
	if _in_flight.has(key):
		return RewardOutcome.make(RewardOutcome.Status.REFUSED, REFUSE_BUSY)
	# Every part this reward has must be payable BEFORE the first one is paid: a reward this
	# session cannot finish is refused whole rather than started.
	var has_bag := reward.has_items() or not take.is_empty()
	if (has_bag and not payers.trade.is_valid()) \
			or (reward.xp > 0 and not payers.pay_xp.is_valid()) \
			or (reward.has_regard() and not payers.move_regard.is_valid()):
		return RewardOutcome.make(RewardOutcome.Status.REFUSED, REFUSE_UNPAYABLE)
	_in_flight[key] = true
	var outcome := _pay_parts(reward_id, reward, take, payers, has_bag)
	_in_flight.erase(key)
	return outcome


func _pay_parts(reward_id: StringName, reward: RewardData, take: Dictionary,
		payers: RewardPayers, has_bag: bool) -> RewardOutcome:
	var outcome := RewardOutcome.make(RewardOutcome.Status.PAID)
	var bag_id := part_id(reward_id, PART_BAG)
	if has_bag and not _ledger.has(bag_id):
		if not bool(payers.trade.call(take, reward.item_counts())):
			return RewardOutcome.make(RewardOutcome.Status.REFUSED, REFUSE_NO_ROOM)
		_ledger.claim(bag_id)
		outcome.paid_now.append(PART_BAG)
	var xp_id := part_id(reward_id, PART_XP)
	if reward.xp > 0 and not _ledger.has(xp_id):
		if not bool(payers.pay_xp.call(reward.xp, reward_id)):
			return _owed(reward_id, outcome)
		_ledger.claim(xp_id)
		outcome.paid_now.append(PART_XP)
	var regard_id := part_id(reward_id, PART_REGARD)
	if reward.has_regard() and not _ledger.has(regard_id):
		if not bool(payers.move_regard.call(reward.regard_character_id,
				reward.regard_dimension, reward.regard_delta, reward_id)):
			return _owed(reward_id, outcome)
		_ledger.claim(regard_id)
		outcome.paid_now.append(PART_REGARD)
	_ledger.claim(reward_id)
	return outcome


## A part was refused by its owner. OWED when something of this reward HAS been paid (now or
## by an earlier call); when nothing has, nothing changed and the honest answer is REFUSED.
func _owed(reward_id: StringName, outcome: RewardOutcome) -> RewardOutcome:
	for part: StringName in [PART_BAG, PART_XP, PART_REGARD]:
		if _ledger.has(part_id(reward_id, part)):
			outcome.status = RewardOutcome.Status.OWED
			outcome.reason = REASON_OWED
			return outcome
	return RewardOutcome.make(RewardOutcome.Status.REFUSED, REFUSE_UNPAYABLE)

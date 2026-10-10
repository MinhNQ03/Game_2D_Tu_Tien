extends RefCounted
class_name RewardLedger
## RewardLedger — Aetheria domain (what has already been paid, Phase 19, D-070).
##
## THE one record of "this reward was paid", for every source that pays one: a defeat's XP
## (the per-spawn id `CombatRuntime` mints), a quest (`quest:<id>`), and from Phase 21 a drop
## or a container. One collection, so there is one answer — the audit found the alternative
## taking shape (AUD-12): an XP ledger inside `ProgressionRuntime` and a second one wherever
## quests would have kept theirs, with different keys.
##
## It records IDS and nothing else. It does not know what a reward is, pays nothing and
## decides nothing: `RewardService` (a multi-part reward) and `ProgressionRuntime` (a defeat)
## decide WHEN an id is recorded. An id is never removed: paid is paid.
##
## It grows by one entry per defeat and a handful per quest for the life of a session.

const SCHEMA := 1

## id(String) -> true.
var _claimed: Dictionary = {}


func has(reward_id: StringName) -> bool:
	return _claimed.has(String(reward_id))


## Record `reward_id` as paid. True when it was NOT recorded before — the caller may pay.
## False for an id already recorded (pay nothing) and for an EMPTY id, which is refused
## loudly and records nothing: every unnamed reward would otherwise share one key, and the
## first would block all the others (D-055).
func claim(reward_id: StringName) -> bool:
	var key := String(reward_id)
	if key == "":
		push_error("[reward-ledger] refusing to record an EMPTY reward id")
		return false
	if _claimed.has(key):
		return false
	_claimed[key] = true
	return true


func count() -> int:
	return _claimed.size()


func clear() -> void:
	_claimed.clear()


# --- Persistence boundary (`docs/SAVE_FORMAT.md` `rewards`) ----------------------

## Sorted, so two ledgers holding the same ids serialize identically.
func to_dict() -> Dictionary:
	var ids: Array = _claimed.keys()
	ids.sort()
	return {"schema": SCHEMA, "claimed": ids}


## Hydrate from `to_dict()` output. Atomic and strict: a wrong schema, a non-array, a
## non-string, an empty or a repeated id rejects the WHOLE payload and changes nothing.
func from_dict(data: Dictionary) -> bool:
	if typeof(data.get("schema")) != TYPE_INT or int(data["schema"]) != SCHEMA:
		push_error("[reward-ledger] from_dict: unsupported schema %s" % str(data.get("schema")))
		return false
	var rows: Variant = data.get("claimed")
	if typeof(rows) != TYPE_ARRAY:
		push_error("[reward-ledger] from_dict: 'claimed' must be an Array")
		return false
	var staged: Dictionary = {}
	for row: Variant in rows:
		if typeof(row) != TYPE_STRING or String(row) == "" or staged.has(String(row)):
			push_error("[reward-ledger] from_dict: an id is not a unique non-empty String")
			return false
		staged[String(row)] = true
	_claimed = staged
	return true

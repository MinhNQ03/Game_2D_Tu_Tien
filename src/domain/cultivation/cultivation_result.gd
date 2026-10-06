extends RefCounted
class_name CultivationResult
## CultivationResult — Aetheria domain (what one cultivation decision did, Phase 12).
##
## Returned by every `CultivationService` mutator, the same shape as `ProgressionResult`: the
## runtime announces from it and tests assert on it, so nobody has to diff a CharacterState to
## learn what happened. A rejected result names WHY in `reason`, because "the breakthrough did
## not happen" is useless to a player and to a test alike.

const REASON_NONE := &""
const REASON_NO_STATE := &"no_state"
const REASON_NOT_READY := &"not_ready"
const REASON_NEGATIVE := &"negative_amount"
## The step's tu vi is already full: more gathering is wasted until the cultivator breaks through.
const REASON_FULL := &"full"
## Not enough tu vi for the next step yet.
const REASON_INSUFFICIENT := &"insufficient_progress"
## The next realm requires knowledge the cultivator does not hold.
const REASON_MISSING_KNOWLEDGE := &"missing_knowledge"
## There is no attemptable step above (the next tier is structural, or this is the top).
const REASON_CEILING := &"ceiling"
const REASON_UNKNOWN_REALM := &"unknown_realm"

var accepted: bool = false
var reason: StringName = REASON_NONE

var realm_before: StringName = &""
var layer_before: int = 0
var realm_after: StringName = &""
var layer_after: int = 0

var progress_before: int = 0
var progress_after: int = 0

## For REASON_MISSING_KNOWLEDGE: the ids still missing.
var missing: Array[StringName] = []


## A realm or layer changed.
func advanced() -> bool:
	return accepted and (realm_after != realm_before or layer_after != layer_before)


## The MACRO realm changed (a breakthrough into a new realm, not just a layer).
func changed_realm() -> bool:
	return accepted and realm_after != realm_before


func gained() -> int:
	return maxi(0, progress_after - progress_before)


func describe() -> String:
	if not accepted:
		return "rejected(%s)" % String(reason)
	return "accepted(%s %d -> %s %d, progress %d -> %d)" % [realm_before, layer_before,
		realm_after, layer_after, progress_before, progress_after]


static func make(state: CharacterState) -> CultivationResult:
	var result := CultivationResult.new()
	if state != null:
		result.realm_before = state.realm_id
		result.layer_before = state.realm_layer
		result.progress_before = state.cultivation_progress
		result.realm_after = state.realm_id
		result.layer_after = state.realm_layer
		result.progress_after = state.cultivation_progress
	return result


func reject(why: StringName) -> CultivationResult:
	accepted = false
	reason = why
	return self


func commit(state: CharacterState) -> CultivationResult:
	accepted = true
	reason = REASON_NONE
	realm_after = state.realm_id
	layer_after = state.realm_layer
	progress_after = state.cultivation_progress
	return self

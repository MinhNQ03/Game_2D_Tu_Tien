extends RefCounted
class_name ProgressionResult
## ProgressionResult — Aetheria domain (what one XP grant actually did, Phase 11).
##
## The return value of `ProgressionService.grant_xp()`. It exists so the domain can report an
## outcome WITHOUT emitting anything: the service is pure and presentation-free, and the
## gameplay-layer owner (`ProgressionRuntime`) decides which semantic events this outcome
## deserves. A service that emitted its own signals would make the domain depend on a
## listener's existence (`03-architecture.md`: emitters never depend on listeners) and would
## be untestable without a tree.
##
## It is also what makes the "one coherent transition" event decision expressible: a single
## grant that crosses three thresholds reports ONE before/after pair plus `levels_gained = 3`,
## so a consumer can say "you reached level 4" without ever observing levels 2 and 3 — which
## were never states the character was in (the mutation is atomic).
##
## `reason` is a STABLE TOKEN, never a sentence: it is a domain fact a test can assert on and
## a future consumer can branch on. Player-facing text is the presentation layer's job and is
## resolved through `Localization` (`07-localization.md`).

## Rejection reasons. Named so a test pins WHY a grant failed rather than only that it did —
## a negative test that only checks `accepted == false` passes for the wrong reason (L-024).
const REASON_NONE := &""
const REASON_NO_STATE := &"no_state"
const REASON_NO_CURVE := &"no_curve"
const REASON_NEGATIVE_AMOUNT := &"negative_amount"
const REASON_AT_CEILING := &"at_ceiling"

## Did the grant commit? A rejected grant leaves the character byte-identical.
var accepted: bool = false

## Why it was rejected (one of the REASON_* tokens). Empty when accepted.
var reason: StringName = REASON_NONE

## Cumulative lifetime XP before and after. Equal when nothing committed.
var xp_before: int = 0
var xp_after: int = 0

## Derived level before and after. Equal unless a threshold was crossed.
var level_before: int = 0
var level_after: int = 0

## XP actually added (0 for a rejected or zero grant).
var xp_applied: int = 0


## Did the level change? Derived, never stored separately — `leveled` and the level pair
## cannot disagree if one is computed from the other.
func leveled() -> bool:
	return level_after > level_before


## How many levels this single grant crossed. 0, or 3 for a grant big enough to cross three
## thresholds at once.
func levels_gained() -> int:
	return maxi(0, level_after - level_before)


## A compact line for a test failure message or a debug readout. NOT player-facing text.
func describe() -> String:
	if not accepted:
		return "rejected(%s)" % String(reason)
	return "accepted(+%d xp: %d->%d, level %d->%d)" % [
		xp_applied, xp_before, xp_after, level_before, level_after]


## Build a rejection. Static factories rather than a constructor with eight arguments: a
## rejected result must be impossible to confuse with an accepted one, and naming the two
## paths separately is what makes that impossible at the call site.
static func rejected(why: StringName, state_xp: int, state_level: int) -> ProgressionResult:
	var result := ProgressionResult.new()
	result.accepted = false
	result.reason = why
	# A rejection still reports the UNCHANGED values, so a caller can log "nothing happened,
	# and here is what it still is" without having to re-read the state.
	result.xp_before = state_xp
	result.xp_after = state_xp
	result.level_before = state_level
	result.level_after = state_level
	result.xp_applied = 0
	return result


static func committed(
		xp_from: int, xp_to: int, level_from: int, level_to: int) -> ProgressionResult:
	var result := ProgressionResult.new()
	result.accepted = true
	result.reason = REASON_NONE
	result.xp_before = xp_from
	result.xp_after = xp_to
	result.level_before = level_from
	result.level_after = level_to
	result.xp_applied = xp_to - xp_from
	return result

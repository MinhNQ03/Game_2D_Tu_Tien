extends RefCounted
class_name AttackStateMachine
## AttackStateMachine — Aetheria domain (the real-time attack lifecycle, Phase 09, D-007).
##
## The ONE owner of attack TIMING: `READY → WINDUP → ACTIVE → RECOVERY → READY`. Pure and
## node-free, so it runs headless and every frame-timing question about combat is answerable
## by a unit test rather than by watching the game (`03-architecture.md`: rules live in the
## domain, pure and unit-testable).
##
## WHY A SEPARATE CLASS RATHER THAN FLAGS ON A COMPONENT. In an action model the four states
## are the whole combat feel, and almost every combat bug is a state bug: a hit that lands
## during windup, an attack that can be re-started mid-swing, a hit window that a long frame
## steps clean over. Flags scattered across a node give none of those a name; a state machine
## makes each one a case a test can drive. It is also the seam a future dodge/parry/stagger
## hooks onto — those are transitions, and transitions need something to transition.
##
## DETERMINISM IS THE CONTRACT. `advance(delta)` is the only thing that moves time, so a test
## feeds exact deltas and a frame-rate spike cannot change the outcome. In particular:
##
##   * **A single large delta cannot skip a state.** It is consumed state by state, carrying
##     the remainder forward, so `advance(10.0)` from WINDUP passes THROUGH ACTIVE (reporting
##     that the hit window opened) and lands in RECOVERY or READY. A naive implementation that
##     compared an elapsed total against thresholds would silently drop the hit window of
##     every attack that straddled a stutter — a hit the player made and never got.
##   * **The hit window is reported as an EDGE, not only as a level.** `consume_hit_window()`
##     returns true exactly once per attack, so one swing resolves one hit pass however the
##     frames fell. Polling `state() == ACTIVE` instead means a 60fps frame resolves the same
##     swing once and a 240fps frame resolves it four times, i.e. frame rate becomes damage.
##
## WHAT IS DELIBERATELY NOT HERE: hit detection (geometry is `CombatService`), damage
## (`DamageRules`), animation (presentation reads `state()`), input (`InputService` owns the
## intent, `AttackComponent` forwards it), and combo/cancel rules (no consumer yet).

## The four states. READY is the only one that accepts a new attack.
enum State {
	READY,
	WINDUP,
	ACTIVE,
	RECOVERY,
}

## Human-readable state names, index-aligned with `State`, for assertion messages and the
## debug overlay. Not user-facing text, so these are deliberately not localization keys.
const STATE_NAMES := ["READY", "WINDUP", "ACTIVE", "RECOVERY"]

var _attack: AttackData = null
var _state: int = State.READY
## Seconds remaining in the CURRENT state. Counted down rather than up so a state change is
## "remainder <= 0" and the leftover time is directly available to carry into the next state.
var _remaining: float = 0.0
## Set when ACTIVE is entered, cleared by `consume_hit_window()`. This is what makes one swing
## resolve exactly one hit pass regardless of frame rate.
var _hit_window_pending: bool = false
## Attacks completed since construction. A cheap, order-independent way for a test to assert
## "the swing finished" without reaching into private state.
var _completed: int = 0


## Bind the attack definition this machine runs. Rejects an invalid definition LOUDLY and
## stays unarmed, so a bad `.tres` means "cannot attack" rather than an attack with a
## zero-length hit window that silently never lands (fail closed — L-014: the owner degrades,
## the validator does not abort).
func _init(attack: AttackData = null) -> void:
	if attack == null:
		return
	if not attack.is_valid():
		push_error("[attack-fsm] refusing to arm an invalid AttackData; machine stays unarmed")
		return
	_attack = attack


## True once a usable attack definition is bound. An unarmed machine stays in READY forever
## and refuses every `try_begin()`.
func is_armed() -> bool:
	return _attack != null


func attack_data() -> AttackData:
	return _attack


func state() -> int:
	return _state


func state_name() -> String:
	return STATE_NAMES[_state]


## True only in READY — i.e. the attacker may start a new attack right now. The name is the
## question a caller actually asks; `state() == READY` is the same test spelled as an
## implementation detail.
func can_begin() -> bool:
	return is_armed() and _state == State.READY


## Start an attack. Returns false when one is already in flight (WINDUP/ACTIVE/RECOVERY) or no
## valid attack is bound.
##
## Rejecting mid-attack is the COMMITMENT rule and it is deliberate: in an action model an
## attack the player can restart at will has no recovery cost, which removes the only reason
## to time anything. A rejection is silent (no `push_error`) because a player mashing the
## attack key is normal play, not a programming error.
func try_begin() -> bool:
	if not can_begin():
		return false
	_enter(State.WINDUP, _attack.windup_seconds)
	return true


## Advance the lifecycle by `delta` seconds. Returns the state it ended in.
##
## Consumes `delta` STATE BY STATE, carrying the remainder, so no state can be skipped by a
## long frame: a 10-second delta from WINDUP still opens (and closes) the hit window on its
## way to READY. A non-positive delta is a no-op rather than an error — a paused frame is not
## a bug, and rejecting it loudly would fill the log during a transition.
func advance(delta: float) -> int:
	if delta <= 0.0 or _state == State.READY or not is_armed():
		return _state
	var left := delta
	# Bounded by construction: every state has a strictly positive duration (enforced by
	# `AttackData.is_valid`), so each pass through the loop either consumes `left` entirely or
	# completes a state, and a cycle has three states.
	while left > 0.0 and _state != State.READY:
		if left < _remaining:
			_remaining -= left
			return _state
		left -= _remaining
		_advance_state()
	return _state


## Move to the state that follows the current one, at the moment its time ran out.
func _advance_state() -> void:
	match _state:
		State.WINDUP:
			# Entering ACTIVE is what ARMS the hit window. It is recorded as a pending edge
			# rather than inferred from the state, so a frame long enough to pass straight
			# through ACTIVE still delivers the hit the player paid windup for.
			_hit_window_pending = true
			_enter(State.ACTIVE, _attack.active_seconds)
		State.ACTIVE:
			_enter(State.RECOVERY, _attack.recovery_seconds)
		State.RECOVERY:
			_completed += 1
			_enter(State.READY, 0.0)
		_:
			_enter(State.READY, 0.0)


func _enter(next_state: int, duration: float) -> void:
	_state = next_state
	_remaining = duration


## Seconds left in the current state (0.0 in READY). For a presentation layer driving an
## animation, and for assertion messages.
func time_remaining() -> float:
	return _remaining


## Take the pending hit window, if this attack has one. Returns true EXACTLY ONCE per attack,
## in the first `advance()` that reached ACTIVE.
##
## The caller resolves its hit pass when this returns true. That is the whole reason it is an
## edge: polling the ACTIVE state instead would resolve the same swing once per frame the
## window stays open, making damage a function of frame rate.
func consume_hit_window() -> bool:
	if not _hit_window_pending:
		return false
	_hit_window_pending = false
	return true


## Is a hit window waiting to be consumed? A read-only peek for tests and assertions; it does
## NOT consume, so it can never be used by accident where `consume_hit_window()` was meant.
func has_pending_hit_window() -> bool:
	return _hit_window_pending


## Attacks that ran all the way back to READY since construction.
func completed_count() -> int:
	return _completed


## Abandon any attack in flight and return to READY, dropping an unconsumed hit window.
##
## For an owner whose attacker stopped existing as an attacker — death, a scene transition, a
## session teardown. It drops the pending window ON PURPOSE: a hit window that outlives the
## swing would land after the attacker died, which is the kind of thing that looks like a
## random phantom hit and is nearly impossible to reproduce.
func cancel() -> void:
	_hit_window_pending = false
	_enter(State.READY, 0.0)

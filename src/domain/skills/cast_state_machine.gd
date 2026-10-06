extends RefCounted
class_name CastStateMachine
## CastStateMachine — Aetheria domain (the ONE timing authority of a cast, Phase 15).
##
## The cast lifecycle the presentation contract reserved (§5 `CAST`): READY → PREPARE → CHANNEL →
## RELEASE → RECOVER → READY, durations from `SkillData`. Like `AttackStateMachine` it owns time
## and nothing else: `advance()` reports whether the RELEASE began during the step, so the runtime
## resolves the effect exactly once, on entering RELEASE (a 0s CHANNEL is skipped). `interrupt()`
## returns to READY from PREPARE/CHANNEL — a cast broken before its release spends nothing.

enum State { READY, PREPARE, CHANNEL, RELEASE, RECOVER }

const STATE_NAMES := ["READY", "PREPARE", "CHANNEL", "RELEASE", "RECOVER"]

var _skill: SkillData = null
var _state: State = State.READY
var _left: float = 0.0


func state() -> State:
	return _state


func state_name() -> String:
	return STATE_NAMES[_state]


func skill() -> SkillData:
	return _skill


func time_remaining() -> float:
	return _left


## The authored length of the current phase (0 in READY).
func phase_length() -> float:
	if _skill == null:
		return 0.0
	match _state:
		State.PREPARE:
			return _skill.prepare_seconds
		State.CHANNEL:
			return _skill.channel_seconds
		State.RELEASE:
			return _skill.release_seconds
		State.RECOVER:
			return _skill.recover_seconds
		_:
			return 0.0


## How far through the current phase, in [0, 1].
func phase_progress() -> float:
	var length := phase_length()
	return 1.0 if length <= 0.0 else clampf(1.0 - _left / length, 0.0, 1.0)


func is_casting() -> bool:
	return _state != State.READY


## Before the release: the cast can still be broken without effect.
func is_committed() -> bool:
	return _state == State.RELEASE or _state == State.RECOVER


func try_begin(skill: SkillData) -> bool:
	if _state != State.READY or skill == null or not skill.is_valid():
		return false
	_skill = skill
	_enter(State.PREPARE)
	return true


## Advance by `delta`. Returns true when the RELEASE began during this step.
func advance(delta: float) -> bool:
	if _state == State.READY:
		return false
	var released := false
	_left -= delta
	while _state != State.READY and _left <= 0.0:
		var carry := -_left
		match _state:
			State.PREPARE:
				_enter(State.CHANNEL if _skill.channel_seconds > 0.0 else State.RELEASE)
			State.CHANNEL:
				_enter(State.RELEASE)
			State.RELEASE:
				_enter(State.RECOVER)
			State.RECOVER:
				_state = State.READY
				_left = 0.0
				return released
		if _state == State.RELEASE:
			released = true
		_left -= carry
	return released


## Break a cast that has not released yet. Returns true when something was broken.
func interrupt() -> bool:
	if _state == State.PREPARE or _state == State.CHANNEL:
		_state = State.READY
		_left = 0.0
		return true
	return false


func _enter(next: State) -> void:
	_state = next
	_left = phase_length()

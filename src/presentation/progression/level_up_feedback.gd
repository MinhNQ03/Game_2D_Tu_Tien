extends Node
class_name LevelUpFeedback
## LevelUpFeedback — Aetheria presentation (the one-shot level-up celebration, Phase 11).
##
## PRESENTATION ONLY. It drives `modulate` on one `CanvasItem` (the HUD's level badge) and
## owns nothing else: no XP, no level, no timer the gameplay layer can read, no decision. The
## phase brief is explicit that animation must never mutate gameplay and that animation state
## must never become authoritative — so the authority is `CharacterState.xp`, the number on
## screen comes from the pushed `ProgressionView`, and this node's entire contribution is a
## colour that decays back to where it started.
##
## IT IS A DECAYING LERP ON AN EXPLICIT CLOCK, NOT A `Tween`, and that is the established
## pattern in this project rather than a preference (`DamageFeedback` does the same): a tween
## cannot be stepped from a headless test, so an effect built on one can only be asserted by
## waiting on real frames — which makes the test slow, flaky, and unable to check the midpoint
## at all. `advance(delta)` is public so a test drives the whole curve deterministically.
##
## IT COSTS NOTHING WHEN IDLE. `_process` is switched off whenever no celebration is running,
## so a HUD that exists for the whole session pays only during the ~1.5 seconds after a
## level-up (`05-performance-testing.md`: no constantly-running tweens, no idle redraw).
##
## IT IS CANCELLABLE AND ALWAYS TERMINATES. A map transition or a return to the menu can
## happen mid-celebration; `cancel()` restores the resting colour immediately, and the HUD
## calls it on teardown. An effect that could outlive its target would be writing `modulate`
## on a freed node.

## The badge this effect tints. Assigned by the HUD; null is legal and inert.
var _target: CanvasItem = null

## An optional transient announcement shown only while the celebration runs.
##
## It is owned by this node rather than toggled by the HUD so that EVERY part of the
## celebration starts and stops in one place. A banner whose visibility the HUD set and this
## node cleared would have two owners, and the failure mode is a banner left on screen
## forever after a cancelled effect — which is exactly the "all animation must terminate
## cleanly" requirement failing in the least visible way.
var _banner: CanvasItem = null

## The target's resting colour, captured ONCE when the target is bound.
##
## Captured once rather than at the start of each celebration for the reason `DamageFeedback`
## records: re-reading it would snapshot the PREVIOUS celebration's tint whenever two
## level-ups land close together (a single big XP grant can cross several thresholds, and the
## player can then immediately kill something else), and the badge would never find its way
## back to gold.
var _base: Color = Color.WHITE

## Seconds remaining semantics: `_duration <= 0.0` IS the idle state. One value, so "is it
## celebrating" cannot disagree with "is it processing".
var _duration: float = 0.0
var _elapsed: float = 0.0

## The level most recently celebrated, for tests and a debug readout. Never authoritative —
## the HUD renders the level from the pushed view, not from this.
var _level: int = 0


func _ready() -> void:
	set_process(false)


## Bind the `CanvasItem` this effect tints, capturing its resting colour.
##
## Separate from the constructor so the HUD can build its badge, hand it over, and have the
## resting colour captured from a node that is already fully styled — capturing before the
## theme applied would snapshot the wrong base.
func bind_target(target: CanvasItem) -> void:
	_target = target
	if _target != null:
		_base = _target.modulate


## Bind the optional transient announcement. Hidden immediately, so binding it can never
## leave it on screen.
func bind_banner(banner: CanvasItem) -> void:
	_banner = banner
	if _banner != null:
		_banner.visible = false


## Start the celebration for `level`. Restarts cleanly if one is already running.
func celebrate(level: int) -> void:
	_level = level
	if _target == null:
		return
	_duration = UIPalette.LEVEL_UP_SECONDS
	_elapsed = 0.0
	_target.modulate = _peak_tint()
	if _banner != null and is_instance_valid(_banner):
		_banner.visible = true
	set_process(true)


## Stop immediately and restore the resting colour.
##
## Used on teardown and on a map change. It DOES write `modulate` (unlike `DamageFeedback`'s
## `_go_idle`, which deliberately does not) because a cancelled celebration must not leave the
## badge frozen mid-flash — there is no later frame coming to finish the decay.
func cancel() -> void:
	_duration = 0.0
	_elapsed = 0.0
	set_process(false)
	if _target != null and is_instance_valid(_target):
		_target.modulate = _base
	if _banner != null and is_instance_valid(_banner):
		_banner.visible = false


func _process(delta: float) -> void:
	advance(delta)


## Decay the celebration by `delta` seconds. PUBLIC so a test drives it deterministically
## instead of waiting on real frames (the same contract as `DamageFeedback.advance()` and
## `CharacterVisualComponent.advance()`).
func advance(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _duration <= 0.0:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if t >= 1.0:
		# ASSIGNED, not lerped, exactly as `DamageFeedback` does and for the same reason:
		# `lerp(base, 1.0)` only approximately reaches the endpoint in floating point, so
		# decaying to it would leave a few ten-millionths of tint behind after every level-up
		# and a long session would drift the badge's colour.
		_target.modulate = _base
		_duration = 0.0
		_elapsed = 0.0
		set_process(false)
		if _banner != null and is_instance_valid(_banner):
			_banner.visible = false
		return
	_target.modulate = _peak_tint().lerp(_base, t)


## Is the transient announcement on screen right now? (for tests — a banner that outlives its
## effect is the defect this exposes.)
func is_banner_visible() -> bool:
	return _banner != null and is_instance_valid(_banner) and _banner.visible


## The resting colour multiplied up to the flash peak. Derived from the BASE rather than
## written as a literal, so re-tinting the badge in the palette automatically re-tints its
## celebration instead of silently flashing the old hue.
func _peak_tint() -> Color:
	var gain := UIPalette.LEVEL_UP_FLASH_GAIN
	return Color(_base.r * gain, _base.g * gain, _base.b * gain, _base.a)


## Is a celebration running right now? (for tests — the effect IS the contract.)
func is_celebrating() -> bool:
	return _duration > 0.0


## The level last celebrated (for tests / debug). Not authoritative.
func celebrated_level() -> int:
	return _level


## The tint currently on the badge (for tests, which cannot see a colour on screen).
func current_tint() -> Color:
	if _target == null or not is_instance_valid(_target):
		return Color.WHITE
	return _target.modulate


## The resting colour a celebration decays back to (for tests).
func resting_tint() -> Color:
	return _base

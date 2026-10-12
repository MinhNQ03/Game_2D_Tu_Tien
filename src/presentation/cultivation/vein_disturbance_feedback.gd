extends Node2D
class_name VeinDisturbanceFeedback
## VeinDisturbanceFeedback — Aetheria presentation (the broken vein's disturbance beat).
##
## A child of a `CultivationSite` whose vein is BROKEN. The stele warns that the woods' vein
## "does not run quietly": its flow surges and falls on an uneven beat, as if something draws
## it off (`KNOW_BROKEN_VEIN_FLOW_DESC`). The wisps (`QiWellFeedback`) show the FLOW; this
## shows the BEAT — at each surge's crest a pale ring spreads from the fissure and qi streaks
## stand up higher than the wisps ever rise, then settle. It is the beat the mist wolves read
## (they gather where it surges and scatter where it falls:
## `KNOW_VU_LANG_HUNTING_GROUND_DESC`), made learnable by the eye before it must be learned
## the hard way.
##
## IT IS PHYSICAL, NOT PERCEIVED. The surge moves qi anyone can see — a mortal walking past
## sees the ground breathe, which is how Ko Than knows where the wolves gather. It is NOT
## gated by `perceived()`: the fine wisps need a realm; the beat does not.
##
## IT DECIDES NOTHING. The beat is the site's own `flow_factor` — the same deterministic
## function the runtime gathers by — so what the eye sees and what a cultivator receives
## agree. The pulse's own age is a transient clock that decides nothing (M-5.4). A STEADY
## vein has no beat: the node switches itself off there, and costs nothing while idle.
##
## FORESHADOW, NEVER ANSWER (M-7.2). The pulse shows THAT the vein surges, never WHY — the
## open question of CL-15 (why the Hoang Vực veins are failing now) stays open.

## The flow at which a surge's crest fires the pulse. `flow_factor` on a BROKEN vein spans
## roughly 0.2–1.8; 1.35 catches the crests without firing on every ripple.
const SURGE_FLOW := 1.35
## How long the pulse lives, in seconds: ambient scale, never macro (M-4.7) — this beat
## repeats every few seconds, so it must stay quiet enough to be seen a hundred times.
const PULSE_SECONDS := 0.9
## The streaks the crest stands up: how many, how high, how wide their stand.
const STREAKS := 5
const STREAK_RISE_PX := 42.0
## The colour of the qi: the vein's own pale jade — the same qi the wisps draw, never a new
## colour for the same thing.
const QI_COLOUR := Color(0.70, 0.96, 0.86)

var _site: CultivationSite = null
var _time: float = 0.0
var _prev_flow: float = 1.0
var _pulse_age: float = -1.0


func _ready() -> void:
	_site = get_parent() as CultivationSite
	z_index = 1
	# A steady vein has no beat: never process, never draw.
	if _site == null or _site.site == null \
			or _site.site.stability == CultivationSiteData.Stability.STEADY:
		set_process(false)


func _process(delta: float) -> void:
	advance(delta)


## Advance the presentation by `delta` (public for tests, like every presentation clock here).
func advance(delta: float) -> void:
	if _site == null or _site.site == null:
		return
	_time += delta
	var flow := _site.site.flow_factor(_time)
	# The crest: the flow rising through the surge line. Derived from the site's own beat —
	# no clock of its own (M-5.4).
	if _prev_flow < SURGE_FLOW and flow >= SURGE_FLOW:
		_pulse_age = 0.0
	_prev_flow = flow
	var was := _pulse_age >= 0.0
	if was:
		_pulse_age += delta
		if _pulse_age >= PULSE_SECONDS:
			_pulse_age = -1.0
	if was or _pulse_age >= 0.0:
		queue_redraw()


## True while a surge pulse is on screen (for tests and the capture scenario).
func is_pulsing() -> bool:
	return _pulse_age >= 0.0


## How far through the pulse we are, in [0, 1] (for tests).
func pulse_progress() -> float:
	if _pulse_age < 0.0:
		return 0.0
	return clampf(_pulse_age / PULSE_SECONDS, 0.0, 1.0)


## The flow the beat is read from right now (for tests).
func flow_now() -> float:
	if _site == null or _site.site == null:
		return 1.0
	return _site.site.flow_factor(_time)


func _draw() -> void:
	if _pulse_age < 0.0 or _site == null or _site.site == null:
		return
	var t := pulse_progress()
	var ease := 1.0 - (1.0 - t) * (1.0 - t)  # the ring leaves fast, then settles
	var radius := _site.site.radius_px
	# The ring the crest throws: from the fissure to the site's edge, thinning as it goes.
	var ring := QI_COLOUR
	ring.a = 0.8 * (1.0 - t) * (1.0 - t)
	draw_arc(Vector2.ZERO, lerpf(6.0, radius, ease), 0.0, TAU, 32, ring, 2.0)
	var inner := QI_COLOUR
	inner.a = 0.4 * (1.0 - t)
	draw_arc(Vector2.ZERO, lerpf(4.0, radius * 0.7, ease), 0.0, TAU, 32, inner, 1.0)
	# The streaks: qi standing up off the fissure, higher than the wisps ever rise.
	for i in STREAKS:
		var x := (float(i) - float(STREAKS - 1) * 0.5) * 9.0
		var top := -STREAK_RISE_PX * (1.0 - t * 0.6)
		var streak := QI_COLOUR
		streak.a = 0.7 * (1.0 - t)
		draw_line(Vector2(x, -2.0).round(), Vector2(x, top).round(), streak, 1.0)

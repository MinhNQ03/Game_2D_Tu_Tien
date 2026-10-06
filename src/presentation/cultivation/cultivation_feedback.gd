extends Node2D
class_name CultivationFeedback
## CultivationFeedback — Aetheria presentation (what cultivating LOOKS like, Phase 12).
##
## Pure presentation on the player (`player.tscn`), bound at session start by the
## `CultivationRuntime` it reads — the way `AttackFeedback` reads its `AttackComponent`. It
## decides nothing: removing it changes no realm, no tu vi, no outcome.
##
## THE CAUSAL CHAIN (`MOTION_DESIGN_CONTRACT.md` M-1.2; energy law of M-2.1, source → gather →
## focus → release → propagate → dissipate):
##
##   * the BODY lowers into the seat and breathes (the visual's MEDITATE action, driven from here:
##     the descent is column 0, one slow breath loops over the rest);
##   * qi rises FROM THE SITE — the vein, never the air (qi is not ambient) — and drifts into the
##     dantian (`core` anchor of the frame being drawn), as many motes as the vein is giving, and
##     only as visible as the body PERCEIVES it: a mortal with a method sees a faint few at the
##     body; a Hậu Thiên cultivator sees the flow arrive from the vein;
##   * a BREAKTHROUGH gathers (the motes accelerate and spiral in, a ring closes on the body),
##     RELEASES at the instant the runtime changes the realm (a ring bursts outward, a column of
##     light, and a wave of wind flattens the grass around — `WindField`), and SETTLES.
##
## MACRO vs MID (M-4.7). A breakthrough may own the screen for a moment; a level-up must not look
## like one. This node is also the level-up's missing CHARACTER RESPONSE (§20 debt, closed here):
## `celebrate_level_up()` raises a short gold ring from the feet to the crown — mid-scale, a
## fraction of a second, no wind, no light column.
##
## Zero cost idle: `_process` runs only while seated, breaking through or celebrating.

## One slow breath while seated, in seconds (the loop over the meditate sheet's breath columns).
const BREATH_SECONDS := 2.6
## The share of the meditate action's progress spent on the descent (its first column of four).
const DESCENT_SHARE := 0.24

## Mote slots (fixed: deterministic, allocation-free). A breakthrough uses all of them.
const MOTES := 14
const MOTES_GATHERING := 7

## Release: how far the ring bursts, how long it and the column of light live.
const RELEASE_RING_PX := 72.0
const RELEASE_SECONDS := 1.1
const WIND_IMPULSE_PX := 4.0
const WIND_IMPULSE_RADIUS := 240.0

const LEVEL_UP_SECONDS := 0.55

## The colour of perceived qi: a pale jade — the vein's, not a decoration's.
const QI_COLOUR := Color(0.70, 0.96, 0.86)
const RELEASE_COLOUR := Color(0.96, 1.0, 0.94)

var _runtime: CultivationRuntime = null
var _breath: float = 0.0
var _release_age: float = -1.0
var _level_up_age: float = -1.0
var _changed_realm: bool = false


func _ready() -> void:
	z_index = 1
	set_process(false)


## Bound (or unbound with null) by the `CultivationRuntime` at session start/end.
func bind_runtime(runtime: CultivationRuntime) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		if _runtime.meditation_started.is_connected(_on_meditation_started):
			_runtime.meditation_started.disconnect(_on_meditation_started)
		if _runtime.meditation_ended.is_connected(_on_meditation_ended):
			_runtime.meditation_ended.disconnect(_on_meditation_ended)
		if _runtime.realm_advanced.is_connected(_on_realm_advanced):
			_runtime.realm_advanced.disconnect(_on_realm_advanced)
	_runtime = runtime
	if runtime == null:
		_end_meditate_action()
		set_process(_release_age >= 0.0 or _level_up_age >= 0.0)
		queue_redraw()
		return
	runtime.meditation_started.connect(_on_meditation_started)
	runtime.meditation_ended.connect(_on_meditation_ended)
	runtime.realm_advanced.connect(_on_realm_advanced)


func is_bound() -> bool:
	return _runtime != null and is_instance_valid(_runtime)


func _on_meditation_started(_site_id: StringName) -> void:
	_breath = 0.0
	var visual := _visual()
	if visual != null:
		visual.play_action(CharacterVisualComponent.ACTION_MEDITATE)
	set_process(true)


func _on_meditation_ended(_reason: StringName) -> void:
	_end_meditate_action()
	queue_redraw()


func _on_realm_advanced(_realm_id: StringName, _layer: int, changed_realm: bool) -> void:
	_release_age = 0.0
	_changed_realm = changed_realm
	var field: WindField = null
	if is_inside_tree():
		field = get_tree().get_first_node_in_group(WindField.GROUP) as WindField
	if field != null:
		# A new REALM pushes harder than a new layer: the macro scale is earned, not constant.
		field.impulse(global_position + _core(), WIND_IMPULSE_PX * (1.5 if changed_realm else 1.0),
			WIND_IMPULSE_RADIUS)
	set_process(true)


## The level-up's character response (MID scale).
func celebrate_level_up() -> void:
	_level_up_age = 0.0
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## Advance the presentation by `delta` (public for tests, like every presentation clock here).
func advance(delta: float) -> void:
	var seated := _seated()
	if seated:
		_breath += delta
		_drive_meditate_action()
	if _release_age >= 0.0:
		_release_age += delta
		if _release_age >= RELEASE_SECONDS:
			_release_age = -1.0
	if _level_up_age >= 0.0:
		_level_up_age += delta
		if _level_up_age >= LEVEL_UP_SECONDS:
			_level_up_age = -1.0
	queue_redraw()
	if not seated and _release_age < 0.0 and _level_up_age < 0.0:
		set_process(false)


func is_releasing() -> bool:
	return _release_age >= 0.0


func is_celebrating_level_up() -> bool:
	return _level_up_age >= 0.0


## The meditate action's progress for the current moment: the descent, then the breath loop.
func meditate_progress() -> float:
	if not _seated():
		return 0.0
	if _runtime.phase() == CultivationRuntime.Phase.SETTLING:
		var t := clampf(_runtime.phase_time() / CultivationRuntime.SETTLE_SECONDS, 0.0, 1.0)
		return t * DESCENT_SHARE * 0.99
	var cycle := fposmod(_breath / BREATH_SECONDS, 1.0)
	return DESCENT_SHARE + (1.0 - DESCENT_SHARE) * cycle * 0.999


## How visible the qi is: the runtime's perception of the site being drawn on.
func qi_visibility() -> float:
	if not _seated():
		return 0.0
	return _runtime.perceived_at(_runtime.active_site())


## The motes being drawn right now, as positions in this node's space (for tests and `_draw`).
func mote_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not _seated() or qi_visibility() <= 0.0:
		return out
	var site := _runtime.active_site()
	if site == null:
		return out
	var source := to_local(site.global_position)
	var core := _core()
	var breaking := _runtime.phase() == CultivationRuntime.Phase.BREAKTHROUGH
	var count := MOTES if breaking else MOTES_GATHERING
	# Faster flow, faster motes: the vein's real rate drives the speed, so a surging broken
	# vein visibly pulses and a steady spring flows evenly.
	var speed := 0.35 + 0.08 * _runtime.gather_rate()
	if breaking:
		speed = 0.6 + 1.4 * clampf(_runtime.phase_time()
			/ CultivationRuntime.BREAKTHROUGH_RELEASE_AT, 0.0, 1.0)
	for i in count:
		var u := fposmod(_breath * speed + float(i) / float(count), 1.0)
		# Each mote leaves from its own point of the vein and bends on its own side.
		var angle := float(i) * 2.399963  # the golden angle: an even, non-repeating spread
		var start := source + Vector2.from_angle(angle) * 9.0
		var side := (core - start).orthogonal().normalized() * (10.0 if i % 2 == 0 else -10.0)
		if breaking:
			side *= 1.0 - u
		var mid := start.lerp(core, 0.5) + side
		var a := start.lerp(mid, u)
		var b := mid.lerp(core, u)
		out.append(a.lerp(b, u).round())
	return out


func _draw() -> void:
	var visibility := qi_visibility()
	if visibility > 0.0:
		var colour := QI_COLOUR
		var positions := mote_positions()
		for i in positions.size():
			colour.a = visibility * (0.45 + 0.5 * float(i % 3) / 2.0)
			# Two pixels once the body truly senses the flow; one faint pixel for a mortal.
			var size := Vector2(2, 2) if visibility > 0.6 else Vector2.ONE
			draw_rect(Rect2(positions[i], size), colour)
		var core := _core()
		if _runtime.phase() == CultivationRuntime.Phase.BREAKTHROUGH:
			# The gathering ring closes on the body as the release approaches.
			var t := clampf(_runtime.phase_time() / CultivationRuntime.BREAKTHROUGH_RELEASE_AT,
				0.0, 1.0)
			var ring := QI_COLOUR
			ring.a = visibility * (0.25 + 0.6 * t)
			draw_arc(core, lerpf(28.0, 5.0, t), 0.0, TAU, 24, ring, 1.0)
		# The dantian answers what it receives: a pulse with the breath.
		var glow := QI_COLOUR
		glow.a = visibility * (0.25 + 0.2 * sin(_breath * TAU / BREATH_SECONDS))
		draw_rect(Rect2(core - Vector2(1, 1), Vector2(3, 3)), glow)
	if _release_age >= 0.0:
		_draw_release()
	if _level_up_age >= 0.0:
		_draw_level_up()


func _draw_release() -> void:
	var t := clampf(_release_age / RELEASE_SECONDS, 0.0, 1.0)
	var core := _core()
	var reach := RELEASE_RING_PX * (1.25 if _changed_realm else 1.0)
	var ring := RELEASE_COLOUR
	ring.a = 0.9 * (1.0 - t) * (1.0 - t)
	draw_arc(core, lerpf(6.0, reach, 1.0 - (1.0 - t) * (1.0 - t)), 0.0, TAU, 40, ring, 3.0)
	# A second, slower ring: the wave the grass answers, so the release reads as propagating.
	var outer := QI_COLOUR
	outer.a = 0.5 * (1.0 - t)
	draw_arc(core, lerpf(4.0, reach * 1.4, t), 0.0, TAU, 40, outer, 1.0)
	# The body itself lit from within for the first instant: macro, earned, brief.
	if t < 0.3:
		var halo := RELEASE_COLOUR
		halo.a = 0.55 * (1.0 - t / 0.3)
		draw_circle(core + Vector2(0, -6), 14.0 * (0.7 + t), halo)
	# The column of light: brief, tallest at the release, thinning as it fades.
	var column := RELEASE_COLOUR
	column.a = 0.85 * (1.0 - t) * (1.0 - t)
	var height := 96.0 * (1.0 - t * 0.4)
	draw_rect(Rect2(Vector2(-2.0, core.y - height), Vector2(4.0, height)), column)
	column.a *= 0.4
	draw_rect(Rect2(Vector2(-4.0, core.y - height * 0.7), Vector2(8.0, height * 0.7)), column)
	# Sparks thrown out along the ring.
	for i in 12:
		var dir := Vector2.from_angle(float(i) * TAU / 12.0 + 0.2)
		var r := lerpf(4.0, reach * 0.8, t)
		var spark := RELEASE_COLOUR
		spark.a = 0.8 * (1.0 - t)
		draw_rect(Rect2((core + dir * r).round(), Vector2.ONE), spark)


func _draw_level_up() -> void:
	var t := clampf(_level_up_age / LEVEL_UP_SECONDS, 0.0, 1.0)
	var gold := UIPalette.GOLD_PRIMARY
	gold.a = 0.85 * (1.0 - t)
	# A thin ring rising from the feet to the crown: the body answering, at mid scale.
	var y := lerpf(-2.0, -44.0, t)
	draw_arc(Vector2(0.0, y), 9.0, 0.0, TAU, 20, gold, 1.0)
	for i in 4:
		var x := -6.0 + 4.0 * float(i)
		draw_rect(Rect2(Vector2(x, y - 3.0 * float(i % 2)).round(), Vector2.ONE), gold)


func _seated() -> bool:
	return is_bound() and _runtime.phase() != CultivationRuntime.Phase.IDLE


func _drive_meditate_action() -> void:
	var visual := _visual()
	if visual == null:
		return
	if visual.current_action() != CharacterVisualComponent.ACTION_MEDITATE:
		# An attack replaced it for a frame (the runtime ends the sitting next tick), or the
		# visual was rebuilt: re-assert the pose only while still seated.
		if visual.is_action_playing():
			return
		visual.play_action(CharacterVisualComponent.ACTION_MEDITATE)
	visual.drive_action(meditate_progress())


func _end_meditate_action() -> void:
	var visual := _visual()
	if visual != null and visual.current_action() == CharacterVisualComponent.ACTION_MEDITATE:
		visual.end_action()


## The dantian of the frame being drawn, in this node's space.
func _core() -> Vector2:
	var visual := _visual()
	if visual != null and visual.has_anchor(CharacterVisualProfileData.POINT_CORE):
		return visual.position + visual.anchor_point(CharacterVisualProfileData.POINT_CORE)
	return Vector2(0.0, -16.0)


func _visual() -> CharacterVisualComponent:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("CharacterVisualComponent") as CharacterVisualComponent

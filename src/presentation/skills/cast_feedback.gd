extends Node2D
class_name CastFeedback
## CastFeedback — Aetheria presentation (what a technique LOOKS like, Phase 15).
##
## Bound by the `SkillRuntime`; reads its `CastStateMachine` and signals and decides nothing. Two
## techniques, two presentation FAMILIES (`MOTION_DESIGN_CONTRACT.md` M-2.1, energy law: source →
## gather → focus → release → propagate → impact → dissipate), each element in its one permanent
## colour (`COMBAT_DESIGN.md` §3):
##
##   * PHONG (Thanh Phong Chưởng) — air: pale-green motes are drawn IN to the palm while the seal
##     gathers; at the release a wide crescent of wind sweeps the cone it actually hits, dust is
##     thrown along it, and the map's `WindField` carries the gust outward through the grass.
##   * LÔI (Lôi Chỉ) — current: violet sparks crackle at the fingertip, building through the
##     CHANNEL; at the release a jagged bolt runs from the hand along its real path (the
##     runtime's analytic bolt, drawn in WORLD space), and bursts where it strikes.
##
## The body: the visual's CAST action, each phase owning a quarter of the sheet whatever its
## authored length. A broken cast fizzles (a grey puff) — a refusal is visible, not silent.

const PHONG := Color(0.62, 0.90, 0.72)
const PHONG_LIGHT := Color(0.86, 1.0, 0.90)
const LOI := Color(0.74, 0.62, 1.0)
const LOI_LIGHT := Color(0.95, 0.92, 1.0)
const FIZZLE := Color(0.62, 0.64, 0.68)

const RELEASE_SECONDS := 0.45
const IMPACT_SECONDS := 0.3
const FIZZLE_SECONDS := 0.35
const GUST_PX := 5.0

var _runtime: SkillRuntime = null
var _time: float = 0.0
var _release_age: float = -1.0
var _released: TechniqueData = null
var _release_facing: Vector2 = Vector2.RIGHT
var _release_core: Vector2 = Vector2.ZERO
var _fizzle_age: float = -1.0
## Bolt strikes being drawn: [world position, age].
var _impacts: Array = []
## The world-space layer for bolts and their strikes (a bolt that has left the hand does not
## follow the caster).
var _world_layer: Node2D = null


func _ready() -> void:
	z_index = 1
	_world_layer = Node2D.new()
	_world_layer.name = "WorldLayer"
	_world_layer.top_level = true
	_world_layer.z_index = 2
	_world_layer.draw.connect(_draw_world)
	add_child(_world_layer)
	set_process(false)


func bind_runtime(runtime: SkillRuntime) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		for pair in [[_runtime.cast_started, _on_started], [_runtime.cast_released, _on_released],
				[_runtime.cast_interrupted, _on_interrupted], [_runtime.bolt_struck, _on_struck],
				[_runtime.cast_refused, _on_refused]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	_runtime = runtime
	if runtime == null:
		_end_cast_action()
		return
	runtime.cast_started.connect(_on_started)
	runtime.cast_released.connect(_on_released)
	runtime.cast_interrupted.connect(_on_interrupted)
	runtime.bolt_struck.connect(_on_struck)
	runtime.cast_refused.connect(_on_refused)


func _on_started(_technique_id: StringName) -> void:
	var visual := _visual()
	if visual != null:
		visual.play_action(CharacterVisualComponent.ACTION_CAST)
	set_process(true)


func _on_released(technique_id: StringName, _hits: int) -> void:
	_released = _runtime.catalog().entry(technique_id)
	_release_age = 0.0
	_release_facing = _runtime.cast_facing()
	_release_core = _core()
	if _released != null and _released.element == &"elem_phong" and is_inside_tree():
		var field := get_tree().get_first_node_in_group(WindField.GROUP) as WindField
		if field != null:
			field.impulse(global_position + _release_facing * 20.0, GUST_PX,
				_released.skill.range_px * 2.5)
	set_process(true)


func _on_interrupted(_technique_id: StringName) -> void:
	_end_cast_action()
	_fizzle_age = 0.0
	set_process(true)


func _on_refused(_technique_id: StringName, _reason: StringName) -> void:
	_fizzle_age = 0.0
	set_process(true)


func _on_struck(world_position: Vector2) -> void:
	_impacts.append([world_position, 0.0])
	set_process(true)


func is_animating() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	advance(delta)


## Advance the presentation by `delta` (public for tests).
func advance(delta: float) -> void:
	_time += delta
	var casting := _runtime != null and is_instance_valid(_runtime) and _runtime.casting() != null
	if casting:
		_drive_cast_action()
	elif _visual() != null and _visual().current_action() == CharacterVisualComponent.ACTION_CAST:
		_end_cast_action()
	if _release_age >= 0.0:
		_release_age += delta
		if _release_age >= RELEASE_SECONDS:
			_release_age = -1.0
	if _fizzle_age >= 0.0:
		_fizzle_age += delta
		if _fizzle_age >= FIZZLE_SECONDS:
			_fizzle_age = -1.0
	for impact in _impacts:
		impact[1] = float(impact[1]) + delta
	_impacts = _impacts.filter(func(i: Array) -> bool: return float(i[1]) < IMPACT_SECONDS)
	queue_redraw()
	_world_layer.queue_redraw()
	var bolts_flying := _runtime != null and is_instance_valid(_runtime) \
		and not _runtime.bolts().is_empty()
	if not casting and _release_age < 0.0 and _fizzle_age < 0.0 and _impacts.is_empty() \
			and not bolts_flying:
		set_process(false)


## The CAST action's progress: each phase owns a quarter of the sheet.
func cast_progress() -> float:
	if _runtime == null or _runtime.casting() == null:
		return 0.0
	var fsm := _runtime.cast_state()
	var quarter := 0
	match fsm.state():
		CastStateMachine.State.CHANNEL:
			quarter = 1
		CastStateMachine.State.RELEASE:
			quarter = 2
		CastStateMachine.State.RECOVER:
			quarter = 3
	return (float(quarter) + fsm.phase_progress() * 0.99) * 0.25


func _drive_cast_action() -> void:
	var visual := _visual()
	if visual == null:
		return
	if visual.current_action() != CharacterVisualComponent.ACTION_CAST:
		visual.play_action(CharacterVisualComponent.ACTION_CAST)
	visual.drive_action(cast_progress())


func _end_cast_action() -> void:
	var visual := _visual()
	if visual != null and visual.current_action() == CharacterVisualComponent.ACTION_CAST:
		visual.end_action()


func _draw() -> void:
	var technique: TechniqueData = _runtime.casting() if _runtime != null \
		and is_instance_valid(_runtime) else null
	if technique != null:
		var state := _runtime.cast_state().state()
		if state == CastStateMachine.State.PREPARE or state == CastStateMachine.State.CHANNEL:
			_draw_gather(technique, state)
	if _release_age >= 0.0 and _released != null and _released.element == &"elem_phong":
		_draw_gust()
	if _fizzle_age >= 0.0:
		var t := _fizzle_age / FIZZLE_SECONDS
		var puff := FIZZLE
		puff.a = 0.7 * (1.0 - t)
		var at := _palm()
		for i in 5:
			var dir := Vector2.from_angle(float(i) * TAU / 5.0 - PI * 0.5)
			draw_rect(Rect2((at + dir * (2.0 + 6.0 * t)).round(), Vector2.ONE), puff)


## PREPARE / CHANNEL: gather at the hand, in the element's own way.
func _draw_gather(technique: TechniqueData, state: int) -> void:
	var palm := _palm()
	var fsm := _runtime.cast_state()
	var build := fsm.phase_progress() * (0.5 if state == CastStateMachine.State.PREPARE else 1.0)
	if state == CastStateMachine.State.CHANNEL:
		build = 0.5 + 0.5 * fsm.phase_progress()
	if technique.element == &"elem_phong":
		for i in 6:
			var angle := _time * 7.0 + float(i) * TAU / 6.0
			var radius := lerpf(14.0, 3.0, fposmod(_time * 1.6 + float(i) / 6.0, 1.0))
			var mote := PHONG
			mote.a = 0.4 + 0.5 * build
			draw_rect(Rect2((palm + Vector2.from_angle(angle) * radius).round(), Vector2.ONE),
				mote)
		var ring := PHONG
		ring.a = 0.35 * build
		draw_arc(palm, 4.0 + 2.0 * sin(_time * 12.0), 0.0, TAU, 12, ring, 1.0)
	else:
		# Lôi: short jagged arcs leaping off the fingertip, more and longer as the channel builds.
		var count := 2 + int(build * 4.0)
		for i in count:
			var seed_angle := float(int(_time * 20.0) * 7 + i * 3) * 1.37
			var dir := Vector2.from_angle(seed_angle)
			var mid := palm + dir * 3.0 + dir.orthogonal() * 2.0
			var tip := palm + dir * (4.0 + 5.0 * build)
			var spark := LOI_LIGHT if i % 2 == 0 else LOI
			spark.a = 0.6 + 0.4 * build
			draw_line(palm.round(), mid.round(), spark, 1.0)
			draw_line(mid.round(), tip.round(), spark, 1.0)
		var glow := LOI
		glow.a = 0.3 + 0.5 * build
		draw_rect(Rect2(palm - Vector2(1, 1), Vector2(3, 3)), glow)


## PHONG release: the wind crescent sweeps the cone the hit test covered, with thrown dust.
func _draw_gust() -> void:
	var t := clampf(_release_age / RELEASE_SECONDS, 0.0, 1.0)
	var skill := _released.skill
	var half := deg_to_rad(skill.arc_degrees * 0.5)
	var centre := Vector2(0, -10)
	var angle := _release_facing.angle()
	for k in 3:
		var radius := lerpf(10.0, skill.range_px, clampf(t * 1.3 - float(k) * 0.12, 0.0, 1.0))
		var arc := PHONG_LIGHT if k == 0 else PHONG
		arc.a = (0.85 - 0.2 * float(k)) * (1.0 - t)
		draw_arc(centre, radius, angle - half, angle + half, 16, arc, 2.0 if k == 0 else 1.0)
	for i in 8:
		var dir := Vector2.from_angle(angle - half + 2.0 * half * float(i) / 7.0)
		var dust := Color(0.78, 0.72, 0.6, 0.7 * (1.0 - t))
		draw_rect(Rect2((centre + dir * lerpf(8.0, skill.range_px * 0.9, t)).round(), Vector2.ONE),
			dust)


## World space: bolts in flight and their strikes.
func _draw_world() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		for bolt in _runtime.bolts():
			var start: Vector2 = bolt["start"]
			var head: Vector2 = bolt["position"]
			_draw_lightning(start, head, int(bolt["id"]))
	for impact in _impacts:
		var t := float(impact[1]) / IMPACT_SECONDS
		var at: Vector2 = impact[0]
		var flash := LOI_LIGHT
		flash.a = 0.9 * (1.0 - t)
		_world_layer.draw_circle(at, 3.0 + 6.0 * t, Color(LOI, 0.35 * (1.0 - t)))
		for i in 6:
			var dir := Vector2.from_angle(float(i) * TAU / 6.0 + 0.4)
			_world_layer.draw_line(at.round(), (at + dir * (3.0 + 9.0 * t)).round(), flash, 1.0)


func _draw_lightning(from: Vector2, to: Vector2, bolt_seed: int) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var side := dir.orthogonal()
	var points := PackedVector2Array([from.round()])
	var steps := maxi(2, int(length / 10.0))
	var phase := int(_time * 30.0)
	for i in range(1, steps):
		var jitter := float(((bolt_seed * 13 + i * 7 + phase) % 7) - 3)
		points.append((from + dir * (length * float(i) / float(steps)) + side * jitter).round())
	points.append(to.round())
	_world_layer.draw_polyline(points, Color(LOI, 0.55), 3.0)
	_world_layer.draw_polyline(points, LOI_LIGHT, 1.0)


func _visual() -> CharacterVisualComponent:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("CharacterVisualComponent") as CharacterVisualComponent


func _palm() -> Vector2:
	var visual := _visual()
	if visual != null and visual.has_anchor(CharacterVisualProfileData.POINT_PALM):
		return visual.position + visual.anchor_point(CharacterVisualProfileData.POINT_PALM)
	return Vector2(0, -20)


func _core() -> Vector2:
	var visual := _visual()
	if visual != null and visual.has_anchor(CharacterVisualProfileData.POINT_CORE):
		return visual.position + visual.anchor_point(CharacterVisualProfileData.POINT_CORE)
	return Vector2(0, -16)

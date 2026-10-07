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

const RELEASE_SECONDS := 0.5
## Leaf and dust flecks the gust carries (the world answering the technique, D-062 §25).
const LEAF := Color(0.42, 0.62, 0.34)
const DUST := Color(0.78, 0.72, 0.60)
const IMPACT_SECONDS := 0.3
const FIZZLE_SECONDS := 0.35
const GUST_PX := 5.0

var _runtime: SkillRuntime = null
var _time: float = 0.0
var _release_age: float = -1.0
var _released: TechniqueData = null
var _release_facing: Vector2 = Vector2.RIGHT
var _release_core: Vector2 = Vector2.ZERO
## Where the release LEFT the body: the gust is born at the striking hand (source law), not at
## an offset from the feet.
var _release_palm: Vector2 = Vector2(0, -20)
var _fizzle_age: float = -1.0
## Bolt strikes being drawn: [world position, age].
var _impacts: Array = []
## Bolts still in flight last frame, by id: [start, head] (to leave an afterimage on landing).
var _live_bolts: Dictionary = {}
## The lightning's AFTERIMAGE: a bolt that has landed stays burnt on the eye for a moment, so
## its whole path reads (TRAVEL) even when it crossed the yard in a quarter second.
## [start, end, age, seed].
var _trails: Array = []
const TRAIL_SECONDS := 0.16
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
	_release_palm = _palm()
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


## Landed bolts whose afterimage is still on screen (public for tests).
func afterimage_count() -> int:
	return _trails.size()


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
	_track_bolts(delta)
	queue_redraw()
	_world_layer.queue_redraw()
	var bolts_flying := _runtime != null and is_instance_valid(_runtime) \
		and not _runtime.bolts().is_empty()
	if not casting and _release_age < 0.0 and _fizzle_age < 0.0 and _impacts.is_empty() \
			and not bolts_flying and _trails.is_empty():
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
		# GATHER: three streams of air spiral IN to the palm, tightening as the channel builds;
		# the motes are pairs (a lit head, a paler tail) so the inward motion reads at 1x.
		for k in 3:
			var base_angle := _time * 6.0 + float(k) * TAU / 3.0
			var points := PackedVector2Array()
			for j in 5:
				var u := float(j) / 4.0
				var radius := lerpf(16.0 - 6.0 * build, 2.0, u)
				points.append((palm + Vector2.from_angle(base_angle + u * 2.2) * radius).round())
			var stream := PHONG
			stream.a = 0.35 + 0.55 * build
			draw_polyline(points, stream, 1.0)
			var head := PHONG_LIGHT
			head.a = stream.a
			draw_rect(Rect2(points[0], Vector2.ONE), head)
		var ring := PHONG_LIGHT
		ring.a = 0.25 + 0.55 * build
		draw_arc(palm, 3.0 + 1.5 * sin(_time * 14.0), 0.0, TAU, 12, ring, 1.0)
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


## PHONG release: a WIND BLADE — a solid crescent, thick at its middle and thin at its horns —
## leaves the striking hand and sweeps the cone the hit test actually covered, two thinner
## echoes behind it, speed lines along the strike, and the leaves and dust it lifts. The element's
## own hue with a lit leading edge; no glow, no screen-wide wash (aetheria_style.yaml §6).
func _draw_gust() -> void:
	var t := clampf(_release_age / RELEASE_SECONDS, 0.0, 1.0)
	var skill := _released.skill
	var half := deg_to_rad(skill.arc_degrees * 0.5)
	var origin := _release_palm
	var angle := _release_facing.angle()
	var fade := 1.0 - t * t
	for k in 3:
		var travel := clampf(t * 1.25 - float(k) * 0.14, 0.0, 1.0)
		if travel <= 0.0:
			continue
		var radius := lerpf(6.0, skill.range_px, travel)
		var thickness := (5.0 if k == 0 else 2.5) * (1.0 - travel * 0.5)
		var body := PHONG
		body.a = (0.8 if k == 0 else 0.45) * fade
		_draw_crescent(origin, radius, angle, half * (0.6 + 0.4 * travel), thickness, body,
			PHONG_LIGHT if k == 0 else Color(0, 0, 0, 0), fade)
	# speed lines: the strike's direction, drawn once and thinning
	for i in 4:
		var side := (float(i) - 1.5) * 0.18
		var dir := Vector2.from_angle(angle + side)
		var from := origin + dir * lerpf(4.0, skill.range_px * 0.5, t)
		var to := from + dir * (10.0 + 8.0 * (1.0 - t))
		var line := PHONG_LIGHT
		line.a = 0.6 * fade
		draw_line(from.round(), to.round(), line, 1.0)
	# what the gust lifts: leaves and dust thrown outward across the cone, tumbling
	for i in 10:
		var u := float(i) / 9.0
		var dir := Vector2.from_angle(angle - half + 2.0 * half * u)
		var reach := lerpf(10.0, skill.range_px * (0.75 + 0.3 * fposmod(u * 7.3, 1.0)), t)
		var at := origin + dir * reach + Vector2(0, -3.0 * sin(t * PI + u * 5.0))
		var fleck := LEAF if i % 3 == 0 else DUST
		fleck.a = 0.85 * fade
		draw_rect(Rect2(at.round(), Vector2(2, 1) if i % 2 == 0 else Vector2.ONE), fleck)


## A filled crescent band centred on `origin`: `radius` out, spanning `angle ± half`, thickest
## (`thickness`) at its middle and tapering to the horns, with an optional lit outer edge.
func _draw_crescent(origin: Vector2, radius: float, angle: float, half: float,
		thickness: float, body: Color, edge: Color, fade: float) -> void:
	var outer := crescent_edge(origin, radius, angle, half, thickness)
	var polygon := crescent_polygon(origin, radius, angle, half, thickness)
	if thickness >= 1.0 and not Geometry2D.triangulate_polygon(polygon).is_empty():
		draw_colored_polygon(polygon, body)
	if edge.a > 0.0:
		var lit := edge
		lit.a = 0.9 * fade
		var snapped := PackedVector2Array()
		for p in outer:
			snapped.append(p.round())
		draw_polyline(snapped, lit, 1.0)


const CRESCENT_STEPS := 14


## The crescent's outer edge (public for tests).
static func crescent_edge(origin: Vector2, radius: float, angle: float, half: float,
		thickness: float) -> PackedVector2Array:
	return _crescent_side(origin, radius, angle, half, thickness, 0.5)


## The crescent's outline as one polygon: the outer edge out, the inner edge back. The horns keep
## a sliver of width so the band never collapses to a line — a zero-width horn made the polygon
## degenerate and the triangulation fail in a real capture (public for tests).
static func crescent_polygon(origin: Vector2, radius: float, angle: float, half: float,
		thickness: float) -> PackedVector2Array:
	var polygon := _crescent_side(origin, radius, angle, half, thickness, 0.5)
	var inner := _crescent_side(origin, radius, angle, half, thickness, -0.5)
	for i in range(inner.size() - 1, -1, -1):
		polygon.append(inner[i])
	return polygon


static func _crescent_side(origin: Vector2, radius: float, angle: float, half: float,
		thickness: float, side: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in CRESCENT_STEPS + 1:
		var u := float(i) / float(CRESCENT_STEPS)
		var a := angle - half + 2.0 * half * u
		var w := maxf(0.6, thickness * sin(PI * u))
		points.append(origin + Vector2.from_angle(a) * (radius + w * side))
	return points


## Remember every bolt in flight; one that has vanished from the runtime LANDED — keep its
## whole path as a fading afterimage.
func _track_bolts(delta: float) -> void:
	var seen := {}
	if _runtime != null and is_instance_valid(_runtime):
		for bolt in _runtime.bolts():
			var id := int(bolt["id"])
			seen[id] = true
			_live_bolts[id] = [bolt["start"], bolt["position"]]
	for id in _live_bolts.keys():
		if not seen.has(id):
			var path: Array = _live_bolts[id]
			_trails.append([path[0], path[1], 0.0, id])
			_live_bolts.erase(id)
	for trail in _trails:
		trail[2] = float(trail[2]) + delta
	_trails = _trails.filter(func(t: Array) -> bool: return float(t[2]) < TRAIL_SECONDS)


## World space: bolts in flight, their afterimages, and their strikes.
func _draw_world() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		for bolt in _runtime.bolts():
			var start: Vector2 = bolt["start"]
			var head: Vector2 = bolt["position"]
			_draw_lightning(start, head, int(bolt["id"]), 1.0)
	for trail in _trails:
		var fade := 1.0 - float(trail[2]) / TRAIL_SECONDS
		_draw_lightning(trail[0], trail[1], int(trail[3]), fade)
	for impact in _impacts:
		var t := float(impact[1]) / IMPACT_SECONDS
		var at: Vector2 = impact[0]
		var flash := LOI_LIGHT
		flash.a = 0.95 * (1.0 - t)
		_world_layer.draw_circle(at, 4.0 + 7.0 * t, Color(LOI, 0.45 * (1.0 - t)))
		_world_layer.draw_circle(at, maxf(0.0, 3.0 - 6.0 * t), flash)
		for i in 8:
			var dir := Vector2.from_angle(float(i) * TAU / 8.0 + 0.4)
			var reach := (5.0 if i % 2 == 0 else 3.0) + 11.0 * t
			var kink := at + dir * reach * 0.55 + dir.orthogonal() * 1.5
			_world_layer.draw_line(at.round(), kink.round(), flash, 1.0)
			_world_layer.draw_line(kink.round(), (at + dir * reach).round(), flash, 1.0)


## A jagged bolt from `from` to `to`: a violet body, a white-hot core, and a short fork that
## breaks off a kink — current, never a straight laser. `fade` dims an afterimage.
func _draw_lightning(from: Vector2, to: Vector2, bolt_seed: int, fade: float) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var side := dir.orthogonal()
	var points := PackedVector2Array([from.round()])
	var steps := maxi(2, int(length / 9.0))
	var phase := int(_time * 30.0)
	for i in range(1, steps):
		var jitter := float(((bolt_seed * 13 + i * 7 + phase) % 9) - 4)
		points.append((from + dir * (length * float(i) / float(steps)) + side * jitter).round())
	points.append(to.round())
	_world_layer.draw_polyline(points, Color(LOI, 0.6 * fade), 4.0)
	_world_layer.draw_polyline(points, Color(LOI_LIGHT, fade), 2.0 if fade > 0.6 else 1.0)
	if points.size() > 3:
		var kink: Vector2 = points[points.size() / 2]
		var fork_dir := (dir + side * (0.8 if bolt_seed % 2 == 0 else -0.8)).normalized()
		var fork_mid := kink + fork_dir * 7.0 + side * 2.0
		var fork_end := kink + fork_dir * 13.0
		_world_layer.draw_polyline(PackedVector2Array([kink, fork_mid.round(), fork_end.round()]),
			Color(LOI, 0.75 * fade), 1.0)


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

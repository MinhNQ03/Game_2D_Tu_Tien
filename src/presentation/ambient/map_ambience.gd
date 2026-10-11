extends Node2D
class_name MapAmbience
## MapAmbience — Aetheria presentation (a map's light, D-073 §3).
##
## Lives in a map scene at `Visual/Ambience`, with the map's `AmbienceLight`s under it. It is
## handed the id of an AMBIENCE ("" = the map as authored) and wears it: a tint over the whole
## playfield (a `CanvasModulate` — a multiply, never a layer drawn over the fight) and the
## lanterns and vein lit as that profile says.
##
## IT HOLDS NO TRUTH. Which ambience applies is derived by `WorldRuntime` from the story's
## current beat every time the map is entered and every time the story moves; nothing here is
## saved, nothing reads a clock, and no rule of the game asks this node anything.
##
## MOTION (`MOTION_DESIGN_CONTRACT.md`): entering a map shows its light at once — the player
## arrives INTO a night, it does not fall on them at the door. A change while the player
## stands in the map (dusk coming on) eases over the profile's own seconds. `pulse()` is the
## one event: a vein giving way — its light flares and settles, and the grass is pushed flat
## in a ring through the map's `WindField`. `_process` runs only while something is unsteady.

const GROUP := &"map_ambience"
const PROFILE_PATH := "res://data/ambience/ambience_%s.tres"
## A tint darker than this (mean of its channels) would hide the playfield: refused.
const MIN_TINT_LEVEL := 0.42
## The flare of a pulse: how far above its profile energy a vein jumps, and for how long.
## Kept under 2x: at 2.6x the pool burned out to white over a sixth of the frame in the real
## window (`aetheria_style.yaml` §6 forbids a screen-wide glow).
const PULSE_GAIN := 0.9
const PULSE_SECONDS := 1.4
## How hard, and how far, a pulse pushes the grass.
const PULSE_WIND_PX := 5.0
const PULSE_WIND_RADIUS := 260.0

var _modulate: CanvasModulate = null
var _lights: Array[AmbienceLight] = []
var _profile: AmbienceProfileData = null
var _ambience_id: StringName = &""
var _tween: Tween = null
var _time: float = 0.0
var _pulse_left: float = 0.0
## 0..1 while a change eases in; lights follow it.
var _blend: float = 1.0
var _applied_once: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	_modulate = CanvasModulate.new()
	_modulate.name = "Tint"
	_modulate.color = Color.WHITE
	add_child(_modulate)
	for child in get_children():
		if child is AmbienceLight:
			_lights.append(child as AmbienceLight)
	set_process(false)


## Could this map wear `ambience_id`? ("" always can: it is the map as authored.)
static func profile_exists(ambience_id: StringName) -> bool:
	return ambience_id == &"" or ResourceLoader.exists(PROFILE_PATH % ambience_id)


func ambience_id() -> StringName:
	return _ambience_id


## The tint the playfield is multiplied by right now (white by day).
func tint() -> Color:
	return _modulate.color if _modulate != null else Color.WHITE


func lights() -> Array[AmbienceLight]:
	return _lights


## Wear `ambience_id` ("" = the map as authored). The first call on a map shows it at once;
## a later change eases in. Asking for what is already worn does nothing.
func apply(ambience_id: StringName) -> void:
	if _applied_once and ambience_id == _ambience_id:
		return
	var profile: AmbienceProfileData = null
	if ambience_id != &"":
		profile = load(PROFILE_PATH % ambience_id) as AmbienceProfileData \
			if ResourceLoader.exists(PROFILE_PATH % ambience_id) else null
		if profile == null or not profile.is_valid() \
				or profile.tint_level() < MIN_TINT_LEVEL:
			push_error("[ambience] '%s' is not a usable ambience; keeping the map as authored"
				% ambience_id)
			profile = null
			ambience_id = &""
	var ease_in := _applied_once and is_inside_tree() \
		and (profile.transition_seconds if profile != null else _leaving_seconds()) > 0.0
	_applied_once = true
	_ambience_id = ambience_id
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var target := profile.tint if profile != null else Color.WHITE
	var seconds := profile.transition_seconds if profile != null else _leaving_seconds()
	_profile = profile
	if ease_in:
		_blend = 0.0
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_modulate, "color", target, seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(self, "_blend", 1.0, seconds)
		_tween.chain().tween_callback(_settle)
	else:
		_modulate.color = target
		_blend = 1.0
	_light_all()
	_settle()


## The vein gives way: its light flares and settles, and the grass is pushed flat in a ring.
## Presentation only; it is told when the story's encounter begins and decides nothing.
func pulse() -> void:
	var origin := Vector2.ZERO
	var veins := 0
	for light in _lights:
		if light.role == AmbienceLight.ROLE_VEIN:
			origin += light.global_position
			veins += 1
	if veins == 0:
		return
	_pulse_left = PULSE_SECONDS
	var wind := get_tree().get_first_node_in_group(WindField.GROUP) as WindField \
		if is_inside_tree() else null
	if wind != null:
		wind.impulse(origin / float(veins), PULSE_WIND_PX, PULSE_WIND_RADIUS)
	set_process(true)


func is_pulsing() -> bool:
	return _pulse_left > 0.0


func _leaving_seconds() -> float:
	return _profile.transition_seconds if _profile != null else 0.0


func _process(delta: float) -> void:
	advance(delta)


## Advance the unsteady parts by `delta` seconds. PUBLIC and delta-driven so a test steps it
## with exact deltas (L-016) instead of waiting on wall-clock frames.
func advance(delta: float) -> void:
	_time += delta
	_pulse_left = maxf(0.0, _pulse_left - delta)
	_light_all()
	_settle()


## Run only while something moves: an easing change, an unsteady lantern, a pulsing vein.
func _settle() -> void:
	var unsteady := _profile != null and (_profile.lantern_flicker > 0.0
		or _profile.vein_pulse > 0.0)
	set_process(unsteady or _pulse_left > 0.0 or (_tween != null and _tween.is_running()))


func _light_all() -> void:
	for i in _lights.size():
		var light := _lights[i]
		var energy := 0.0
		if _profile != null:
			if light.role == AmbienceLight.ROLE_VEIN:
				light.color = _profile.vein_color
				energy = _profile.vein_energy \
					* (1.0 - _profile.vein_pulse * (0.5 + 0.5 * sin(_time * 1.9 + float(i))))
				if _pulse_left > 0.0:
					energy *= 1.0 + PULSE_GAIN * (_pulse_left / PULSE_SECONDS)
			else:
				light.color = _profile.lantern_color
				# A guttering lantern: two slow sines out of step (deterministic, no RNG).
				var gutter := 0.5 + 0.25 * sin(_time * 7.3 + float(i) * 2.1) \
					+ 0.25 * sin(_time * 12.7 + float(i) * 0.7)
				energy = _profile.lantern_energy * (1.0 - _profile.lantern_flicker * gutter)
		energy *= _blend
		light.energy = energy
		light.enabled = energy > 0.0

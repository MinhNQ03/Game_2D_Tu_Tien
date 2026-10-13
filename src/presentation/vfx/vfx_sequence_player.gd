extends Node2D
class_name VfxSequencePlayer
## VfxSequencePlayer — Aetheria presentation (plays a Blender-rendered PNG frame
## sequence: `assets/vfx/qi_gather`, `attack_slash`, `vein_erupt`).
##
## WHY IT EXISTS. The VFX grammar (MOTION_DESIGN_CONTRACT M-2.1) wants layered
## energy — core beam, shards, particles, ground glow — which `draw_line` calls
## cannot do well. These sequences are rendered once in Blender (CYCLES,
## emission, transparent film) and played back here as plain sprites: cheap,
## deterministic, and exactly what the artist approved.
##
## IT IS PURE PRESENTATION. It never triggers itself: `play()` is called by the
## owning presentation node when gameplay says the moment happened (VFX follows
## gameplay authority). `advance()` is public so tests drive the clock, like
## every presentation clock here (M-5.4). Looping is an explicit opt-in for
## ambient effects; one-shot is the default and emits `finished`.
##
## THE ANCHOR. Each sequence documents one canvas pixel that is the effect's
## physical point (the feet the qi sinks into, the hand the slash leaves, the
## fissure the eruption rises from). The sprite is offset by `-anchor_px` so
## that pixel sits exactly at this node's position — put the node where the
## point is in the world.
##
## IT COSTS NOTHING WHEN IDLE. `_process` is off until `play()` and switched
## off again when the sequence ends or `stop()` is called.

## Emitted when a one-shot sequence plays its last frame.
signal finished

## Folder holding `frame_00.png` … `frame_<count-1>.png` (Blender render output).
@export var sequence_dir: String = ""
## How many frames the sequence holds; files are numbered from 0.
@export var frame_count: int = 16
## Playback speed. The rendered sequences are authored at 12 fps.
@export var fps: float = 12.0
## When true the sequence wraps instead of finishing (ambient use only).
@export var loop: bool = false
## The canvas pixel pinned at this node's position (documented per sequence).
@export var anchor_px: Vector2 = Vector2.ZERO

## Float accumulation guard: at exactly `fps` Hz, repeated `delta` additions can
## land an ulp below a frame boundary (e.g. 5.9999999 instead of 6.0) and stick a
## frame. 1e-4 of a frame (~8 us at 12 fps) only ever corrects that noise.
const FRAME_EPSILON := 0.0001

var _frames: Array[Texture2D] = []
var _sprite: Sprite2D = null
var _elapsed: float = 0.0
var _playing: bool = false


func _ready() -> void:
	# Transient VFX layer (style DNA §9b depth): above the y-sorted world,
	# below UI.
	z_index = 1
	_sprite = Sprite2D.new()
	_sprite.name = "SequenceSprite"
	_sprite.offset = -anchor_px
	add_child(_sprite)
	_load_frames()
	_sprite.visible = false
	set_process(false)


func play() -> void:
	## Play the sequence from its first frame. Safe to call while playing:
	## it restarts.
	if _frames.is_empty():
		push_error("VfxSequencePlayer: no frames loaded from '%s'" % sequence_dir)
		return
	_elapsed = 0.0
	_playing = true
	_sprite.visible = true
	_show_frame(0)
	set_process(true)


func stop() -> void:
	## Stop and hide. The node keeps its loaded frames and costs nothing.
	_playing = false
	_sprite.visible = false
	set_process(false)


func is_playing() -> bool:
	return _playing


## How many frames loaded (for wiring checks and tests).
func frame_total() -> int:
	return _frames.size()


## The texture of frame `idx`, clamped (for tests).
func frame_texture(idx: int) -> Texture2D:
	if _frames.is_empty():
		return null
	return _frames[clampi(idx, 0, _frames.size() - 1)]


## The frame that would show after `elapsed` seconds of playback, for tests.
func frame_at(elapsed: float) -> int:
	if _frames.is_empty():
		return -1
	var idx := int(elapsed * fps + FRAME_EPSILON)
	if loop:
		return idx % _frames.size()
	return mini(idx, _frames.size() - 1)


## Advance the playback clock by `delta` (public for tests; `_process` calls it).
func advance(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return
	_elapsed += delta
	var idx := int(_elapsed * fps + FRAME_EPSILON)
	if idx >= _frames.size():
		if loop:
			# Nudge past the boundary before fmod: _elapsed can sit an ulp
			# below the loop duration, and fmod would then "wrap" to itself.
			_elapsed = fmod(_elapsed + FRAME_EPSILON / fps, _frames.size() / fps)
			_show_frame(int(_elapsed * fps + FRAME_EPSILON))
		else:
			_show_frame(_frames.size() - 1)
			stop()
			finished.emit()
		return
	_show_frame(idx)


func _process(delta: float) -> void:
	advance(delta)


func _show_frame(idx: int) -> void:
	_sprite.texture = _frames[clampi(idx, 0, _frames.size() - 1)]


func _load_frames() -> void:
	_frames.clear()
	if sequence_dir.is_empty():
		return
	for i in frame_count:
		var path := "%s/frame_%02d.png" % [sequence_dir, i]
		var tex := load(path) as Texture2D
		if tex == null:
			push_error("VfxSequencePlayer: missing frame '%s'" % path)
			_frames.clear()
			return
		_frames.append(tex)

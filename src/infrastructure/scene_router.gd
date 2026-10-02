extends Node
## SceneRouter — Aetheria infrastructure (autoload "SceneRouter").
##
## THE single entry point for scene/map transitions. Gameplay/UI must not scatter
## `get_tree().change_scene_to_file(...)` across the project. SceneRouter knows HOW to
## move between scenes; it does NOT decide WHY (that is gameplay's job).
##
## It swaps the *active content scene* under a host node (set by the bootstrap: `Main/World`)
## rather than calling `change_scene_to_file`, which would also tear down autoloads and the
## Main/Systems/World/UI shell. This keeps autoloads + the shell stable across transitions.
##
## Content is addressed by a stable `scene_key` resolved through a registry (data-driven,
## no hard-coded map content — CORE-05). Scenes are registered with
## `register_scene(key, path)`.
##
## Safety (scene-transition is high-risk): guards duplicate/stale requests, frees the old
## scene (no orphan), reports explicit success/failure, and never leaves the game in an
## unusable half-transitioned state. State that must survive a transition lives in
## GameState, never on the outgoing scene.

signal transition_started(from_key: String, to_key: String)
signal transition_completed(to_key: String)
signal transition_failed(to_key: String, reason: String)

var _scene_registry: Dictionary = {}      # scene_key(String) -> res path(String)
var _scene_host: Node = null              # where content scenes are parented
var _current_scene: Node = null           # the active content scene (owned here)
var _current_key: String = ""
var _transitioning: bool = false


# --- Setup (called once by the bootstrap) ---

func set_scene_host(host: Node) -> void:
	assert(host != null, "SceneRouter scene host must not be null")
	_scene_host = host


func register_scene(scene_key: String, scene_path: String) -> void:
	if scene_key == "":
		push_error("[router] cannot register empty scene_key")
		return
	_scene_registry[scene_key] = scene_path


func is_registered(scene_key: String) -> bool:
	return _scene_registry.has(scene_key)


func get_current_key() -> String:
	return _current_key


## The active content scene instance (or null). Lets a coordinator wire to the scene's
## signals without guessing at child indices.
func get_current_scene() -> Node:
	return _current_scene


func is_transitioning() -> bool:
	return _transitioning


# --- Transition ---------------------------------------------------------------

## Request a transition to `scene_key`. Returns true if the transition completed, false if
## it was rejected or failed (with a reason emitted via transition_failed + EventBus).
## Opaque world_id/map_id are recorded in GameState on success (no single-world assumption).
func request_transition(
		scene_key: String,
		world_id: StringName = &"",
		map_id: StringName = &"") -> bool:
	# --- validate ---
	if _transitioning:
		_fail(scene_key, "a transition is already in progress")
		return false
	if _scene_host == null:
		_fail(scene_key, "no scene host set (call set_scene_host first)")
		return false
	if not _scene_registry.has(scene_key):
		_fail(scene_key, "scene_key not registered")
		return false
	var path: String = _scene_registry[scene_key]
	if not ResourceLoader.exists(path):
		_fail(scene_key, "scene resource missing: %s" % path)
		return false

	# --- begin ---
	_transitioning = true
	var from_key := _current_key
	var bus := _bus()
	transition_started.emit(from_key, scene_key)
	if bus != null:
		bus.call("emit_scene_transition_started", from_key, scene_key)

	# --- load ---
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		_transitioning = false
		_fail(scene_key, "failed to load PackedScene: %s" % path)
		return false
	var instance := packed.instantiate()
	if instance == null:
		_transitioning = false
		_fail(scene_key, "failed to instantiate: %s" % path)
		return false

	# --- replace (free old first, no orphan) ---
	_free_current_scene()
	_scene_host.add_child(instance)
	_current_scene = instance
	_current_key = scene_key

	# --- complete ---
	var gs := _game_state()
	if gs != null:
		gs.call("set_current_location", world_id, map_id, scene_key)
	_transitioning = false
	transition_completed.emit(scene_key)
	if bus != null:
		bus.call("emit_scene_transition_completed", scene_key)
	return true


## Frees and clears the current content scene without loading a new one (e.g. returning to
## a menu that lives in the UI layer). Safe to call when nothing is loaded.
func clear_current_scene() -> void:
	_free_current_scene()
	_current_key = ""


func _free_current_scene() -> void:
	if _current_scene != null and is_instance_valid(_current_scene):
		if _current_scene.get_parent() != null:
			_current_scene.get_parent().remove_child(_current_scene)
		_current_scene.queue_free()
	_current_scene = null


func _fail(scene_key: String, reason: String) -> void:
	push_error("[router] transition to '%s' failed: %s" % [scene_key, reason])
	transition_failed.emit(scene_key, reason)
	var bus := _bus()
	if bus != null:
		bus.call("emit_scene_transition_failed", scene_key, reason)


func _bus() -> Node:
	return get_node_or_null("/root/EventBus")


func _game_state() -> Node:
	return get_node_or_null("/root/GameState")

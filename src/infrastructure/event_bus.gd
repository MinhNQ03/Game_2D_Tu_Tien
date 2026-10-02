extends Node
## EventBus — Aetheria infrastructure (autoload "EventBus").
##
## Minimal global notification backbone. Emitters emit; listeners connect. Emitters never
## import or reference their listeners (`.kiro/steering/03-architecture.md`). This is NOT
## global state, NOT a service locator, and must NEVER run business logic — it only
## declares signals and offers thin emit helpers for logging/consistency.
##
## Scope rule (Phase 01): only signals a current Phase 1 producer+consumer actually needs
## exist here. Do not add speculative gameplay events (combat/quest/sect/...) until the
## phase that owns them is implemented.
##
## Local, component-to-owner communication should use direct signals, not the EventBus.

# --- Lifecycle / boot ---
signal game_booted()

# --- Scene transition (owned/emitted by SceneRouter; others only listen) ---
signal scene_transition_started(from_key: String, to_key: String)
signal scene_transition_completed(to_key: String)
signal scene_transition_failed(to_key: String, reason: String)

# --- Localization ---
signal language_changed(language_code: String)


## Optional structured debug logging for emits. Off by default to avoid log spam
## (`docs/DEBUGGING.md`). A developer can toggle it for a session.
var debug_log: bool = false


func _log(event_name: String, detail: String = "") -> void:
	if debug_log:
		if detail == "":
			print("[event] %s" % event_name)
		else:
			print("[event] %s — %s" % [event_name, detail])


# --- Thin emit helpers (keep emit sites consistent + one logging point) -----------------
# These are conveniences; callers may also emit the signals directly. They never mutate
# any state beyond emitting.

func emit_game_booted() -> void:
	_log("game_booted")
	game_booted.emit()


func emit_scene_transition_started(from_key: String, to_key: String) -> void:
	_log("scene_transition_started", "%s -> %s" % [from_key, to_key])
	scene_transition_started.emit(from_key, to_key)


func emit_scene_transition_completed(to_key: String) -> void:
	_log("scene_transition_completed", to_key)
	scene_transition_completed.emit(to_key)


func emit_scene_transition_failed(to_key: String, reason: String) -> void:
	_log("scene_transition_failed", "%s (%s)" % [to_key, reason])
	scene_transition_failed.emit(to_key, reason)


func emit_language_changed(language_code: String) -> void:
	_log("language_changed", language_code)
	language_changed.emit(language_code)

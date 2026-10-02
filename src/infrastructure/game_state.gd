extends Node
## GameState — Aetheria infrastructure (autoload "GameState").
##
## Owns the APPLICATION LIFECYCLE state machine and the RUNTIME SESSION state. It is the
## single source of truth for "where in the app are we" and "what identifies the current
## run". It is intentionally small — NOT a dumping ground.
##
## Hard rules (`.kiro/steering/03-architecture.md`):
## - No presentation/UI/node references stored here.
## - Does NOT save itself to disk. It exposes to_dict()/from_dict() so a future
##   SaveService can serialize the session; GameState never knows the on-disk format.
## - Lifecycle transitions are explicit; illegal transitions are rejected loudly.
## - Mutated only through intent-revealing methods, not arbitrary public fields.
##
## Multi-world note (CORE-05): session carries opaque `current_world_id` / `current_map_id`
## / `current_scene_key`. Nothing here assumes a single world or hard-codes a map.

enum Phase {
	BOOT,
	INITIALIZING,
	READY,
	MENU,
	STARTING_SESSION,
	RUNNING,
	TRANSITIONING,
	PAUSED,
}

## Allowed lifecycle transitions. Anything not listed is rejected (loud failure).
const _ALLOWED := {
	Phase.BOOT: [Phase.INITIALIZING],
	Phase.INITIALIZING: [Phase.READY],
	Phase.READY: [Phase.MENU],
	Phase.MENU: [Phase.STARTING_SESSION],
	Phase.STARTING_SESSION: [Phase.RUNNING, Phase.MENU],  # MENU = abort/back out
	Phase.RUNNING: [Phase.TRANSITIONING, Phase.PAUSED, Phase.MENU],
	Phase.TRANSITIONING: [Phase.RUNNING, Phase.MENU],
	Phase.PAUSED: [Phase.RUNNING, Phase.MENU],
}

signal phase_changed(old_phase: Phase, new_phase: Phase)

var _phase: Phase = Phase.BOOT

# --- Runtime session state (only fields with a concrete Phase 1 use) ---
var _session_active: bool = false
var _run_id: String = ""
var _current_world_id: StringName = &""
var _current_map_id: StringName = &""
var _current_scene_key: String = ""


# --- Lifecycle ---------------------------------------------------------------

func get_phase() -> Phase:
	return _phase


func phase_name() -> String:
	return Phase.keys()[_phase]


## True if `_phase -> target` is a declared legal transition.
func can_transition_to(target: Phase) -> bool:
	return _ALLOWED.get(_phase, []).has(target)


## Central lifecycle mutation. Rejects illegal transitions loudly and returns false so a
## caller can handle it; it does not silently no-op into a wrong state.
func transition_to(target: Phase) -> bool:
	if target == _phase:
		return true
	if not can_transition_to(target):
		push_error("[gamestate] illegal transition %s -> %s" % [
			Phase.keys()[_phase], Phase.keys()[target]])
		return false
	var old := _phase
	_phase = target
	phase_changed.emit(old, target)
	return true


# --- Boot sequence helpers (used by the bootstrap) ---

func begin_initialization() -> bool:
	return transition_to(Phase.INITIALIZING)


func mark_ready() -> bool:
	return transition_to(Phase.READY)


func enter_menu() -> bool:
	# Valid from READY (first boot) and from RUNNING/TRANSITIONING/PAUSED (return to menu).
	return transition_to(Phase.MENU)


# --- Session ----------------------------------------------------------------

func is_session_active() -> bool:
	return _session_active


func get_run_id() -> String:
	return _run_id


func get_current_world_id() -> StringName:
	return _current_world_id


func get_current_map_id() -> StringName:
	return _current_map_id


func get_current_scene_key() -> String:
	return _current_scene_key


## Begin a fresh run. Moves MENU -> STARTING_SESSION, mints a run_id, clears session
## fields. Caller (gameplay/bootstrap) then loads the first scene and calls
## confirm_session_running(). Returns false if not allowed from the current phase.
func start_new_game() -> bool:
	if not transition_to(Phase.STARTING_SESSION):
		return false
	_session_active = true
	_run_id = _mint_run_id()
	_current_world_id = &""
	_current_map_id = &""
	_current_scene_key = ""
	return true


## Confirm the first scene is up and the session is live (STARTING_SESSION -> RUNNING).
func confirm_session_running() -> bool:
	return transition_to(Phase.RUNNING)


## End the current session and return to menu. Clears session fields.
func end_session() -> bool:
	if not transition_to(Phase.MENU):
		return false
	_session_active = false
	_run_id = ""
	_current_world_id = &""
	_current_map_id = &""
	_current_scene_key = ""
	return true


## Record the current location. Called by SceneRouter on a successful transition so the
## authoritative "where are we" lives here, not on the outgoing scene (CORE-03/transition
## safety). Opaque IDs — no single-world assumption (CORE-05).
func set_current_location(world_id: StringName, map_id: StringName, scene_key: String) -> void:
	_current_world_id = world_id
	_current_map_id = map_id
	_current_scene_key = scene_key


# --- Transition lifecycle (phase side; SceneRouter owns the mechanics) ---

func begin_transition() -> bool:
	return transition_to(Phase.TRANSITIONING)


func complete_transition() -> bool:
	return transition_to(Phase.RUNNING)


# --- Pause ---

func pause_gameplay() -> bool:
	return transition_to(Phase.PAUSED)


func resume_gameplay() -> bool:
	return transition_to(Phase.RUNNING)


# --- Persistence seam (SaveService will call these; GameState never touches disk) ---
#
# INVARIANT: the lifecycle phase is RUNTIME-ONLY and is never serialized. A save
# describes an *in-progress run's identity + location*, not "which menu/transition screen
# was on". Likewise `session_active` is NOT persisted: it is DERIVED from whether a run
# identity exists, so a snapshot can never resurrect the contradictory
# `phase == BOOT && session_active == true` state the old format allowed.
#
# A snapshot is only meaningful for a run that was actually underway, so `to_dict()`
# refuses to serialize when there is no active session (fail loud in dev), and
# `hydrate_session()` refuses to graft a run onto a live lifecycle.

## Serializable snapshot of the current RUN (identity + location). Never the phase.
## Only valid while a session is active; returns an empty dict otherwise (a non-run has
## nothing to save) and warns, so callers don't silently persist a phantom run.
func to_dict() -> Dictionary:
	if not _session_active:
		push_warning("[gamestate] to_dict() called with no active session; nothing to save")
		return {}
	return {
		"run_id": _run_id,
		"current_world_id": String(_current_world_id),
		"current_map_id": String(_current_map_id),
		"current_scene_key": _current_scene_key,
	}


## Rehydrate run identity + location from a saved snapshot. This loads DATA only; it does
## NOT drive the lifecycle. The caller (future SaveService / load flow) is responsible for
## putting the lifecycle into RUNNING via the normal transitions afterwards. `session_active`
## is derived here (a snapshot with a run_id means a run exists), never read from the blob.
##
## Guard: refuses to run unless the lifecycle is at a load-safe phase (MENU/READY), so a
## load cannot be grafted onto a mid-session/mid-transition state and corrupt it. Returns
## false (loudly) on an empty/invalid snapshot or an unsafe phase.
func hydrate_session(data: Dictionary) -> bool:
	if _phase != Phase.MENU and _phase != Phase.READY:
		push_error("[gamestate] hydrate_session rejected: unsafe phase %s" % phase_name())
		return false
	var run_id := String(data.get("run_id", ""))
	if run_id == "":
		push_error("[gamestate] hydrate_session rejected: snapshot has no run_id")
		return false
	_run_id = run_id
	_current_world_id = StringName(data.get("current_world_id", ""))
	_current_map_id = StringName(data.get("current_map_id", ""))
	_current_scene_key = String(data.get("current_scene_key", ""))
	_session_active = true  # derived: a run identity exists
	return true


## Back-compat alias for the persistence seam name used elsewhere. Delegates to
## hydrate_session; kept so a single public verb ("from_dict") still exists for symmetry
## with to_dict(). Does NOT fabricate lifecycle state.
func from_dict(data: Dictionary) -> bool:
	return hydrate_session(data)


func _mint_run_id() -> String:
	# Opaque, stable-per-run identity. Not derived from node paths/addresses (CORE-04).
	var t := Time.get_unix_time_from_system()
	var r := randi() % 100000
	return "run_%d_%05d" % [int(t), r]

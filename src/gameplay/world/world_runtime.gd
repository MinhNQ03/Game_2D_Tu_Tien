extends Node
class_name WorldRuntime
## WorldRuntime — Aetheria gameplay (world-session coordinator).
##
## A NODE (not an autoload — the autoload budget is frozen at 5, D-017), hung under
## `Main/Systems` (D-010). It owns the "WHY/WHEN" of map movement + the per-session player
## lifecycle; `SceneRouter` (autoload) still owns the "HOW" of swapping content scenes, and
## `GameState` (autoload) still owns the authoritative "WHERE" (`set_current_location`, fed
## by the router). WorldRuntime adds no parallel transition path and no parallel location
## store (`docs/ARCHITECTURE.md` §9).
##
## Responsibilities:
##   - load a small MapData catalog and register each map's `scene_key -> scene path` with
##     SceneRouter;
##   - own ONE persistent `Player` for the session (kept parented to this node between maps
##     so a SceneRouter content-swap can't free it), re-parenting it into each map on
##     arrival and positioning it at the requested named spawn point;
##   - resolve `request_map_transition(to_map_id, entry_point)` through SceneRouter.
##
## It is NOT World Simulation (that is Phase 08) — just map load/unload + player placement.
## D-003 is resolved to "one PackedScene per map via SceneRouter" (D-021).

## Opaque world grouping id for this session's maps (recorded in GameState via the router).
const WORLD_ID := &"world_main"

## Phase-03 map catalog: the MapData resource + the content scene it registers. Code-level
## wiring (which .tres pairs with which .tscn); the authored CONTENT lives in the .tres.
const MAP_CATALOG := [
	{"data": "res://data/maps/map_hub.tres", "scene": "res://src/gameplay/maps/hub_map.tscn"},
	{"data": "res://data/maps/map_field.tres", "scene": "res://src/gameplay/maps/field_map.tscn"},
]

## The map the session starts in.
const START_MAP_ID := &"map_hub"

const PlayerScene := preload("res://src/gameplay/entities/player.tscn")

## Emitted when the player asks to leave the world back to the menu (bubbled up from the
## active map). Main connects to this (scene-agnostic first-scene return contract).
signal return_to_menu_requested()

var _router: Node = null
var _game_state: Node = null
var _catalog: Dictionary = {}        # map_id(StringName) -> MapData
var _player: Node = null             # the persistent per-session Player
var _active_map: Node = null         # the currently loaded map scene (owned by SceneRouter)
var _session_active: bool = false


func _ready() -> void:
	_router = get_node_or_null("/root/SceneRouter")
	_game_state = get_node_or_null("/root/GameState")


## Begin a world session: build + validate the catalog, register scenes with the router,
## spawn the persistent player, and enter the start map. Returns false (loudly) on any
## required failure so the caller (Main) can recover rather than limp on half-wired.
func start_session() -> bool:
	if _router == null:
		push_error("[world] cannot start session: SceneRouter missing")
		return false
	if not _build_catalog():
		return false
	_register_scenes()
	_spawn_player()
	_session_active = true
	if not _enter_map(START_MAP_ID, &""):
		push_error("[world] failed to enter start map %s" % START_MAP_ID)
		return false
	return true


## End the world session: detach + free the persistent player and clear the active map.
## Safe to call more than once.
func end_session() -> void:
	_session_active = false
	_detach_player()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_active_map = null
	if _router != null:
		_router.call("clear_current_scene")


func is_session_active() -> bool:
	return _session_active


func get_current_map_id() -> StringName:
	if _game_state != null:
		return _game_state.call("get_current_map_id")
	return &""


## The live persistent player (or null). For tests/coordinator wiring.
func get_player() -> Node:
	return _player


# --- Map catalog ------------------------------------------------------------

func _build_catalog() -> bool:
	_catalog.clear()
	for entry in MAP_CATALOG:
		var data: MapData = load(entry["data"]) as MapData
		if data == null:
			push_error("[world] catalog entry failed to load: %s" % entry["data"])
			return false
		if not data.is_valid():
			push_error("[world] invalid MapData %s: %s" % [entry["data"], str(data.validation_errors())])
			return false
		_catalog[data.id] = data
	return true


func _register_scenes() -> void:
	for entry in MAP_CATALOG:
		var data: MapData = load(entry["data"]) as MapData
		if data != null:
			_router.call("register_scene", data.scene_key, entry["scene"])


# --- Player lifecycle (persistent across maps) ------------------------------

func _spawn_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = PlayerScene.instantiate()
	# Parent to WorldRuntime (under Systems) so a SceneRouter content swap can't free it.
	add_child(_player)


## Remove the player from whatever map currently holds it, parking it back under
## WorldRuntime so the next content-scene free can't take it with it.
func _detach_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var parent := _player.get_parent()
	if parent != null and parent != self:
		parent.remove_child(_player)
		add_child(_player)


# --- Map transitions --------------------------------------------------------

## Public intent: go to `to_map_id`, arriving at its named `entry_point`. Called by the
## active map when the player uses an exit. Returns false on an unknown map or a failed
## router transition (the caller/map stays put).
func request_map_transition(to_map_id: StringName, entry_point: StringName) -> bool:
	if not _session_active:
		push_warning("[world] map transition requested with no active session")
		return false
	return _enter_map(to_map_id, entry_point)


func _enter_map(map_id: StringName, entry_point: StringName) -> bool:
	var data: MapData = _catalog.get(map_id)
	if data == null:
		push_error("[world] unknown map_id: %s" % map_id)
		return false

	# Park the player back under WorldRuntime BEFORE the router frees the old map scene,
	# so the persistent player is never freed with the content scene. (Freeing the old map
	# also drops its signal connections to us — no stale connection leak.)
	_detach_player()

	var ok: bool = _router.call("request_transition", data.scene_key, WORLD_ID, map_id)
	if not ok:
		push_error("[world] router rejected transition to %s" % map_id)
		return false

	_active_map = _router.call("get_current_scene")
	_place_player_in_active_map(entry_point)
	_wire_active_map()
	return true


## Reparent the persistent player into the active map's player host and position it at the
## named spawn marker (`entry_point`), falling back to the map's default spawn.
func _place_player_in_active_map(entry_point: StringName) -> void:
	if _active_map == null or _player == null:
		return
	# The map exposes where the player goes + where to stand.
	var host: Node = _active_map
	if _active_map.has_method("get_player_host"):
		var h: Node = _active_map.call("get_player_host")
		if h != null:
			host = h
	if _player.get_parent() != null:
		_player.get_parent().remove_child(_player)
	host.add_child(_player)

	if _active_map.has_method("get_spawn_position"):
		var pos: Vector2 = _active_map.call("get_spawn_position", entry_point)
		if _player is Node2D:
			(_player as Node2D).global_position = pos


func _wire_active_map() -> void:
	if _active_map == null:
		return
	if _active_map.has_signal("exit_requested") \
			and not _active_map.is_connected("exit_requested", _on_map_exit_requested):
		_active_map.connect("exit_requested", _on_map_exit_requested)
	if _active_map.has_signal("return_to_menu_requested") \
			and not _active_map.is_connected("return_to_menu_requested", _on_map_return_to_menu):
		_active_map.connect("return_to_menu_requested", _on_map_return_to_menu)


func _on_map_exit_requested(to_map_id: StringName, entry_point: StringName) -> void:
	request_map_transition(to_map_id, entry_point)


func _on_map_return_to_menu() -> void:
	return_to_menu_requested.emit()

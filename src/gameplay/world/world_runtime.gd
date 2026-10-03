extends Node
class_name WorldRuntime
## WorldRuntime — Aetheria gameplay (world-session coordinator).
##
## A NODE (not an autoload — the autoload budget is frozen at 5, D-017), hung under
## `Main/Systems` (D-010). It owns the "WHY/WHEN" of map movement + the per-session player
## lifecycle; `SceneRouter` (autoload) owns the "HOW" of swapping content scenes, and
## `GameState` (autoload) owns the authoritative "WHERE". WorldRuntime adds no parallel
## transition path and no parallel location store (`docs/ARCHITECTURE.md` §9).
##
## DATA-DRIVEN (D-022): WorldRuntime knows ONLY the catalog resource path. It loads a
## `MapCatalog`, validates it at the boundary, registers each map's `scene_key -> scene_path`
## with SceneRouter, and builds a `map_id -> MapData` lookup. Adding a map = author MapData +
## scene + add to the catalog — NO edit here. There are no hard-coded map ids or paths.
##
## Responsibilities:
##   - load + validate the MapData catalog, register scenes with SceneRouter;
##   - own ONE persistent `Player` for the session (parented to this node between maps so a
##     SceneRouter content-swap can't free it), re-parenting it into each map on arrival and
##     positioning it at the requested named spawn;
##   - resolve `request_map_transition(to_map_id, entry_point)` through SceneRouter
##     TRANSACTIONALLY: on failure, nothing changes (current map, player, location all
##     restored); on success, the old map is freed and the SAME player persists.
##
## It is NOT World Simulation (that is Phase 08) — just map load/unload + player placement.

## Opaque world grouping id for this session's maps (recorded in GameState via the router).
const WORLD_ID := &"world_main"

## The ONLY content reference WorldRuntime holds: the data-driven map catalog (D-022).
const MAP_CATALOG_PATH := "res://data/maps/map_catalog.tres"

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


## Begin a world session: load + validate the catalog, register scenes with the router,
## spawn the persistent player, and enter the start map. Returns false (loudly) on any
## required failure so the caller (Main) can recover rather than limp on half-wired.
func start_session() -> bool:
	if _router == null:
		push_error("[world] cannot start session: SceneRouter missing")
		return false
	if not _load_catalog():
		return false
	_register_scenes()
	_spawn_player()
	_session_active = true
	if not _enter_map(START_MAP_ID, &""):
		push_error("[world] failed to enter start map %s" % START_MAP_ID)
		# Unwind the half-started session so we don't leave a player with no map.
		end_session()
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


## The currently loaded map scene (or null). For tests/coordinator wiring.
func get_active_map() -> Node:
	return _active_map


# --- Map catalog (data-driven; D-022) ---------------------------------------

## Load the catalog resource, validate it at the boundary, and build the map_id lookup.
## Fails loud + returns false on a missing/invalid catalog (no silent half-start).
func _load_catalog() -> bool:
	_catalog.clear()
	if not ResourceLoader.exists(MAP_CATALOG_PATH):
		push_error("[world] map catalog missing: %s" % MAP_CATALOG_PATH)
		return false
	var catalog: MapCatalog = load(MAP_CATALOG_PATH) as MapCatalog
	if catalog == null:
		push_error("[world] map catalog failed to load as MapCatalog: %s" % MAP_CATALOG_PATH)
		return false
	if not catalog.is_valid():
		push_error("[world] invalid map catalog: %s" % str(catalog.validation_errors()))
		return false
	_catalog = catalog.build_lookup()
	return not _catalog.is_empty()


## Register every map's `scene_key -> scene_path` with SceneRouter (from the catalog data).
func _register_scenes() -> void:
	for map_id in _catalog:
		var map_data: MapData = _catalog[map_id]
		_router.call("register_scene", map_data.scene_key, map_data.scene_path)


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


# --- Map transitions (transactional; D-022) ---------------------------------

## Public intent: go to `to_map_id`, arriving at its named `entry_point`. Called by the
## active map when the player uses an exit. Returns false on an unknown map or a failed
## router transition (the caller/map stays put, fully restored).
func request_map_transition(to_map_id: StringName, entry_point: StringName) -> bool:
	if not _session_active:
		push_warning("[world] map transition requested with no active session")
		return false
	return _enter_map(to_map_id, entry_point)


## Enter `map_id` at `entry_point`, TRANSACTIONALLY.
##
## Snapshot the player's current placement BEFORE touching anything. Park the player under
## WorldRuntime so the router's free of the old scene can't take it. If the router rejects
## the transition, restore everything: the old map is still alive (the router does not free
## on a rejected request), so re-parent the player back into it at its old position, and the
## active map / GameState location are unchanged. On success, the old scene is freed by the
## router and the SAME player is placed in the new map.
func _enter_map(map_id: StringName, entry_point: StringName) -> bool:
	var data: MapData = _catalog.get(map_id)
	if data == null:
		push_error("[world] unknown map_id: %s" % map_id)
		return false

	# --- snapshot for rollback -------------------------------------------------
	var prev_parent: Node = null
	if _player != null and is_instance_valid(_player):
		prev_parent = _player.get_parent()
	var prev_position := Vector2.ZERO
	if _player is Node2D:
		prev_position = (_player as Node2D).global_position

	# Park the player under WorldRuntime BEFORE the router frees the old map scene, so the
	# persistent player is never freed with the content scene.
	_detach_player()

	var ok: bool = _router.call("request_transition", data.scene_key, WORLD_ID, map_id)
	if not ok:
		# ROLLBACK: the router rejected the request and did NOT free the old scene, so the
		# previous map is still alive. Put the player back exactly where it was.
		push_error("[world] router rejected transition to %s; rolling back" % map_id)
		_restore_player(prev_parent, prev_position)
		# _active_map / GameState location unchanged (router didn't touch them on failure).
		return false

	# --- success: bind new map, place player, wire -----------------------------
	_active_map = _router.call("get_current_scene")
	_bind_active_map(data)
	_place_player_in_active_map(entry_point)
	_wire_active_map()
	# The old scene was freed by the router's _free_current_scene(); nothing to do here.
	return true


## Restore the player into a previous parent at a previous position (rollback path). If the
## previous parent is gone (shouldn't happen on a rejected transition), park under self.
func _restore_player(prev_parent: Node, prev_position: Vector2) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var target := prev_parent if (prev_parent != null and is_instance_valid(prev_parent)) else self
	if _player.get_parent() != target:
		if _player.get_parent() != null:
			_player.get_parent().remove_child(_player)
		target.add_child(_player)
	if _player is Node2D:
		(_player as Node2D).global_position = prev_position


## Hand the active map its authoritative MapData (camera limits, HUD, exit binding).
func _bind_active_map(data: MapData) -> void:
	if _active_map != null and _active_map.has_method("apply_map_data"):
		_active_map.call("apply_map_data", data)


## Reparent the persistent player into the active map's player host and position it at the
## named spawn marker (`entry_point`), via the map's data-driven spawn resolution.
func _place_player_in_active_map(entry_point: StringName) -> void:
	if _active_map == null or _player == null:
		return
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

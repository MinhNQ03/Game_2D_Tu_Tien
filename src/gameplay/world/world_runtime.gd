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

## The player's authoritative character definition (data). The session builds ONE
## CharacterState from this and binds the persistent Player to it (D-023,
## `docs/CHARACTER_SYSTEM.md` §6). Changing the player's starting identity/stats is a content
## edit to this `.tres`, not a code edit.
const PLAYER_TEMPLATE_PATH := "res://data/characters/player_default.tres"

## The player's fixed per-save instance id. The player is a Character
## (`docs/SAVE_FORMAT.md` characters.player_instance_id); the id is stable so a save keys the
## player's CharacterState consistently.
const PLAYER_INSTANCE_ID := &"player"

const PlayerScene := preload("res://src/gameplay/entities/player.tscn")

## Emitted when the player asks to leave the world back to the menu (bubbled up from the
## active map). Main connects to this (scene-agnostic first-scene return contract).
signal return_to_menu_requested()

var _router: Node = null
var _game_state: Node = null
var _catalog: Dictionary = {}        # map_id(StringName) -> MapData
var _start_map_id: StringName = &""  # data-driven start map, read from the catalog (D-023)
var _player: Node = null             # the persistent per-session Player
var _player_character: CharacterState = null  # the player's ONE authoritative state (D-023)
## The session's character population (Phase 08). The player is registered here at spawn, and
## `WorldSimulationRuntime` adds its authored cast to the SAME collection — so "who exists in
## this world" has one answer and every service that needs a character resolver gets the same
## one (`docs/CHARACTER_SYSTEM.md` §10; before this, the bootstrap hand-wrote two closures
## that each knew about the player only).
##
## It lives here rather than in the simulation because the world coordinator already owned the
## only character there was; moving it into the simulation would have made the simulation the
## de-facto owner of the whole cast, which is the "universal state holder" shape that subsystem
## must not take.
var _characters: CharacterRegistry = null
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
	_characters = CharacterRegistry.new()
	if not _spawn_player():
		push_error("[world] failed to spawn player; aborting session")
		end_session()
		return false
	_session_active = true
	if not _enter_map(_start_map_id, &""):
		push_error("[world] failed to enter start map %s" % _start_map_id)
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
	# Drop the authoritative player state with the session. A later save phase persists it
	# BEFORE end_session; the runtime reference is cleared here (RefCounted is freed when the
	# last reference goes).
	_player_character = null
	if _characters != null:
		_characters.clear()
	_characters = null
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


## The player's ONE authoritative CharacterState for this session (or null). The HUD reads
## identity from here; a save would serialize its persistent tier. It is NOT recreated on a
## map transition — the same instance persists for the whole session (D-023 invariant).
func get_player_character() -> CharacterState:
	return _player_character


## The session's character population (or null before a session starts).
##
## The sect, faction and world-simulation sessions all take their character resolver from
## this ONE collection, so a character that exists is resolvable by every service rather than
## by whichever closure happened to capture it (Phase 08).
func get_character_registry() -> CharacterRegistry:
	return _characters


## The currently loaded map scene (or null). For tests/coordinator wiring.
func get_active_map() -> Node:
	return _active_map


## A COPY of the session's `map_id -> MapData` lookup (empty before a session starts).
##
## Handed to the world simulation, which needs the map GRAPH to compute LOD bands ("one hop
## from the player" is a `MapData.exits` question). A copy, so a consumer cannot edit the
## session's catalog; the `MapData` resources inside are shared and read-only by convention,
## exactly as they are for the active map.
func get_map_lookup() -> Dictionary:
	return _catalog.duplicate()


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
	# The start map is data-driven (D-023): read it from the validated catalog. Validation
	# already guaranteed it resolves to a real map, so no second check is needed here.
	_start_map_id = catalog.start_map_id
	return not _catalog.is_empty()


## Register every map's `scene_key -> scene_path` with SceneRouter (from the catalog data).
func _register_scenes() -> void:
	for map_id in _catalog:
		var map_data: MapData = _catalog[map_id]
		_router.call("register_scene", map_data.scene_key, map_data.scene_path)


# --- Player lifecycle (persistent across maps) ------------------------------

## Build the ONE authoritative player CharacterState from the player template (data) and the
## persistent Player node that realizes it, binding the state to the node BEFORE it enters
## the tree so `_ready()` initializes the composition from the single source of truth (D-023).
## Returns false (loud) on a missing/invalid template so the session fails closed rather than
## spawning a player with no authoritative state. Idempotent: a second call with a live player
## is a no-op.
func _spawn_player() -> bool:
	if _player != null and is_instance_valid(_player):
		return true

	var template := load(PLAYER_TEMPLATE_PATH) as CharacterTemplateData
	if template == null:
		push_error("[world] player template missing/invalid: %s" % PLAYER_TEMPLATE_PATH)
		return false
	_player_character = CharacterState.create_from_template(template, PLAYER_INSTANCE_ID)
	if _player_character == null:
		push_error("[world] failed to build player CharacterState from template")
		return false
	# The player is a Character like any other (`CHARACTER_SYSTEM.md` §1), so they go in the
	# same registry the simulated cast does. Failing here is fatal: an unregistered player
	# would be invisible to every service's character resolver, so the sect session could not
	# enrol them even though they demonstrably exist.
	if _characters == null or not _characters.add(_player_character):
		push_error("[world] failed to register the player in the character registry")
		return false

	_player = PlayerScene.instantiate()
	# Bind the authoritative state BEFORE add_child so the Player's _ready() reads from it.
	if _player.has_method("bind_character_state"):
		_player.call("bind_character_state", _player_character)
	# Pass the template's VISUAL profile ref (presentation; NOT on the domain CharacterState,
	# Phase 05 / D-026) so the Player renders its data-driven sprite instead of a hard-coded
	# scene sprite. Also set BEFORE add_child so _ready() resolves it.
	if _player.has_method("set_visual_profile_from_ref"):
		_player.call("set_visual_profile_from_ref", template.sprite_set_ref)
	# Parent to WorldRuntime (under Systems) so a SceneRouter content swap can't free it.
	add_child(_player)
	return true


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
	# Refresh the map's HUD now that the persistent player (and its CharacterState) is parented
	# into the map, so the identity plate reflects the live character (D-023).
	if _active_map != null and _active_map.has_method("refresh_hud"):
		_active_map.call("refresh_hud")
	# Push the player's sect membership view into the new map's HUD (Phase 06). Read from the
	# SectRuntime sibling (optional, null-safe) so a fresh HUD on each map still shows the
	# player's sect. WorldRuntime stays sect-agnostic beyond forwarding a read-only view.
	_push_sect_view_to_active_map()
	# And the politics of that sect (Phase 07), read from the FactionRuntime sibling — same
	# optional, null-safe, forward-a-read-only-view contract.
	_push_politics_view_to_active_map()
	# THE WORLD-SIMULATION BEAT (Phase 08). Arriving in a map is the one explicit beat on
	# which simulated time passes, and it is announced from here because this is where "the
	# player is now in map X" becomes true. Done AFTER the views above so the sim view pushed
	# below reflects the ticks this arrival just caused.
	_notify_world_sim_arrival(map_id)
	_push_world_sim_view_to_active_map()
	# The old scene was freed by the router's _free_current_scene(); nothing to do here.
	return true


## Tell the world simulation the player arrived in `map_id` (Phase 08).
##
## Null-safe at every hop, like the sect/politics pushes: no WorldSimulationRuntime or no
## session simply means no simulated time passes. WorldRuntime stays simulation-agnostic
## beyond reporting the arrival — it does not know what a tick is, how many the arrival costs
## (that is authored on the sim catalog) or what the simulation does with them.
func _notify_world_sim_arrival(map_id: StringName) -> void:
	var sim := _find_world_sim_runtime()
	if sim == null:
		return
	sim.call("on_player_arrived", map_id)


## Push the read-only world-simulation view into the active map's HUD (Phase 08).
func _push_world_sim_view_to_active_map() -> void:
	if _active_map == null or not _active_map.has_method("set_world_sim_view"):
		return
	var sim := _find_world_sim_runtime()
	if sim == null:
		return
	_active_map.call("set_world_sim_view", sim.call("get_view"))


## Locate the WorldSimulationRuntime among this node's siblings under Main/Systems (or null).
## Same direct-sibling lookup as the sect/faction ones: no `/root`, no deep walk, resolved once
## per transition rather than per frame.
func _find_world_sim_runtime() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling is WorldSimulationRuntime:
			return sibling
	return null


## Push the player's sect view into the CURRENT map's HUD (Phase 06). Public so the
## coordinator (Main) can call it once the sect session has started — the START map loads
## inside start_session(), BEFORE Main starts the sect session, so the first push there is a
## no-op; Main calls this right after _start_sect_session() to populate the hub HUD.
func refresh_active_map_sect_view() -> void:
	_push_sect_view_to_active_map()


## Push the politics view of the player's sect into the CURRENT map's HUD (Phase 07). Public
## for the same reason as the sect refresh above: the hub map is already loaded by the time
## Main starts the faction session, so the in-transition push was a no-op and Main calls this
## once immediately afterwards.
func refresh_active_map_politics_view() -> void:
	_push_politics_view_to_active_map()


## Announce the player's CURRENT map to the world simulation and push the resulting view
## (Phase 08). Public for the same reason the two refreshes above are: the hub map is already
## loaded and the player already placed by the time `Main` starts the simulation session, so
## the in-transition notification was a no-op and `Main` calls this once immediately after.
func refresh_active_map_world_sim_view() -> void:
	_notify_world_sim_arrival(get_current_map_id())
	_push_world_sim_view_to_active_map()


## Find the optional FactionRuntime sibling and push the read-only politics view of the
## PLAYER'S sect into the active map's HUD.
##
## Which sect's politics to show is decided here, by asking SectRuntime which sect the player
## belongs to — the faction subsystem is deliberately not given a notion of "the current
## sect", because a faction landscape exists per sect and inventing a default inside
## FactionRuntime would make the panel's subject implicit. Null-safe at every hop: no
## FactionRuntime, no session, or no player sect simply means no politics is pushed and the
## panel shows its localized empty state.
func _push_politics_view_to_active_map() -> void:
	if _active_map == null or not _active_map.has_method("set_politics_view"):
		return
	var faction_runtime := _find_faction_runtime()
	if faction_runtime == null or not faction_runtime.call("is_session_active"):
		return
	var sect_runtime := _find_sect_runtime()
	if sect_runtime == null or not sect_runtime.call("is_session_active"):
		return
	var sect_id: StringName = sect_runtime.call("get_player_sect_id")
	if sect_id == &"":
		return
	_active_map.call("set_politics_view", faction_runtime.call("get_politics_view", sect_id))


## Locate the FactionRuntime among this node's siblings under Main/Systems (or null). Same
## direct-sibling lookup as the sect one: no /root, no deep walk, resolved per transition.
func _find_faction_runtime() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling is FactionRuntime:
			return sibling
	return null


## Find the optional SectRuntime sibling (under the same Systems parent) and push the player's
## read-only membership view into the active map's HUD. Null-safe: if there is no SectRuntime
## (or no active session), nothing happens — the map simply shows no sect chip.
func _push_sect_view_to_active_map() -> void:
	if _active_map == null or not _active_map.has_method("set_sect_view"):
		return
	var sect_runtime := _find_sect_runtime()
	if sect_runtime == null or not sect_runtime.call("is_session_active"):
		return
	_active_map.call("set_sect_view", sect_runtime.call("get_player_membership_view"))


## Locate the SectRuntime among this node's siblings under Main/Systems (or null). A direct
## sibling lookup — no /root, no deep tree walk, resolved once per transition (not per frame).
func _find_sect_runtime() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling is SectRuntime:
			return sibling
	return null


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

extends Node2D
class_name MapBase
## MapBase — Aetheria gameplay (per-map coordinator; attached to every map scene).
##
## The gameplay-layer coordinator for ONE map (hub, field, …), the Phase-03 successor to
## the Phase-02 `PlayerSandbox` first-scene contract. `WorldRuntime` calls `apply_map_data`
## right after the scene loads, handing it the authoritative `MapData` (D-022). From that
## data MapBase:
##   - configures the Camera2D limits from `MapData.bounds` (data-driven; not scene magic),
##   - shows the localized map name from `MapData.name_key`,
##   - binds each `MapExitZone` (which carries only `exit_id`) to its `MapExit` destination,
##   - resolves named spawn markers for arrival (`get_spawn_position`).
##
## On the semantic `interact` intent (via InputService — never raw keys) while the player
## stands in an exit zone, it emits `exit_requested(to_map_id, entry_point)` read from the
## AUTHORITATIVE `MapExit` (not from the scene). It emits `return_to_menu_requested` on the
## `open_menu` system intent.
##
## It owns NO transition mechanics (SceneRouter) and NO location truth (GameState) and does
## not reach into the player's internals — it only emits intents. State is throwaway; carried
## state lives in GameState (`docs/ARCHITECTURE.md` §9). It is a COORDINATOR, not a God
## Object: no combat/NPC/quest/story logic lives here.
##
## Expected child nodes (by name): `Camera2D`, `PlayerHost` (Node2D), `Spawns` (Node2D of
## Marker2D), `Exits` (Node2D of MapExitZone), `HUD/MapLabel` (Label), a visual root.

## Intent to leave to another map. WorldRuntime resolves it through SceneRouter.
signal exit_requested(to_map_id: StringName, entry_point: StringName)
## Intent to leave the world back to the menu (same contract the sandbox/prologue used).
signal return_to_menu_requested()

const INTERACT_ACTION := &"interact"
const OPEN_MENU_ACTION := &"open_menu"

const GameplayHUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")

var _input: Node = null
var _map_data: MapData = null          # authoritative data for THIS map (set by WorldRuntime)
var _active_exit: MapExit = null       # the exit (data) the player currently stands in
var _active_zone: MapExitZone = null   # which zone set _active_exit (for exit tracking)
var _hud: GameplayHUD = null           # presentation overlay (name/map/hints); owned here
var _sect_view: SectMembershipView = null  # cached read-only sect view (Phase 06); pushed in


func _ready() -> void:
	_input = get_node_or_null("/root/InputService")

	if _input != null:
		_input.call("set_gameplay_context")

	# Boundary walls occupy the WORLD collision layer from the single source of truth
	# (`CollisionLayers`), not scene magic numbers (L-002/L-014). Static targets detect
	# nothing (mask 0); the player's mask includes WORLD so it stays inside the map.
	var walls := get_node_or_null("Walls")
	if walls == null:
		var collision := get_node_or_null("Collision")
		if collision != null:
			walls = collision.get_node_or_null("Walls")
	if walls != null:
		for wall in walls.get_children():
			if wall is StaticBody2D:
				wall.collision_layer = CollisionLayers.WORLD
				wall.collision_mask = 0

	# Track which exit zone the player is standing in (sensor Area2D body enter/exit).
	var exits := get_node_or_null("Exits")
	if exits != null:
		for zone in exits.get_children():
			if zone is MapExitZone:
				zone.body_entered.connect(_on_exit_body_entered.bind(zone))
				zone.body_exited.connect(_on_exit_body_exited.bind(zone))

	_setup_hud()
	_refresh_hud()


## Bind the authoritative MapData to this scene (called by WorldRuntime after load). Drives
## camera limits from bounds, the HUD name, and the exit-zone → MapExit binding. Idempotent.
func apply_map_data(map_data: MapData) -> void:
	_map_data = map_data
	if map_data == null:
		push_error("[map] apply_map_data got null MapData")
		return
	_configure_camera_limits(map_data.bounds)
	_validate_exit_zones(map_data)
	_refresh_hud()


## The bound MapData (or null if WorldRuntime has not called apply_map_data yet).
func get_map_data() -> MapData:
	return _map_data


## Re-read view state into the HUD. Called by WorldRuntime AFTER the persistent player is
## parented into this map, so the HUD identity plate reflects the now-present CharacterState
## (apply_map_data runs before the player is placed, so the HUD can't read it there).
func refresh_hud() -> void:
	_refresh_hud()


## Push the player's read-only sect membership view into the HUD (Phase 06). Called by
## WorldRuntime (which reads SectRuntime) after the player is placed + on membership changes.
## MapBase stays sect-agnostic about the DATA SOURCE — it just forwards a view to its HUD.
func set_sect_view(view: SectMembershipView) -> void:
	_sect_view = view
	if _hud != null:
		_hud.set_sect_view(view)


# --- Camera (data-driven limits from MapData.bounds; shared zoom baseline) ---

## Shared camera zoom baseline for all maps. At 2x, the 16px pixel-art tiles
## (`06-art-assets.md`) read at a comfortable size on the default window without per-map
## tuning. It is a single baseline (not per-MapData) by decision (D-023): a map's framing
## differs by its `bounds`, not by a bespoke zoom. Integer factor keeps pixels crisp.
const CAMERA_ZOOM := Vector2(2.0, 2.0)

func _configure_camera_limits(bounds: Rect2) -> void:
	var cam := get_node_or_null("Camera2D")
	if cam == null or not (cam is Camera2D):
		return
	var camera := cam as Camera2D
	camera.zoom = CAMERA_ZOOM
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.position.x + bounds.size.x)
	camera.limit_bottom = int(bounds.position.y + bounds.size.y)


# --- Exit-zone binding (zones carry exit_id; data owns destination) ----------

## Verify every MapExitZone references an exit_id that resolves in the MapData (fail loud on
## a dangling reference — a content bug). Does not mutate the scene; MapBase resolves the
## destination lazily when the player interacts.
func _validate_exit_zones(map_data: MapData) -> void:
	var exits := get_node_or_null("Exits")
	if exits == null:
		return
	for zone in exits.get_children():
		if zone is MapExitZone:
			var ez := zone as MapExitZone
			if map_data.find_exit(ez.exit_id) == null:
				push_error("[map] exit zone '%s' references unknown exit_id '%s' in map '%s'" % [
					ez.name, ez.exit_id, map_data.id])


# --- Player host + spawns ----------------------------------------------------

## Where WorldRuntime parents the persistent player. Falls back to self if no PlayerHost.
func get_player_host() -> Node:
	var host := get_node_or_null("PlayerHost")
	return host if host != null else self


## Resolve a named spawn marker to a world position.
##   - entry_point empty → use the MapData `default_spawn_id`.
##   - entry_point explicit → the marker MUST exist; a missing explicit spawn is a CONTENT
##     bug and is reported loudly (NO silent fallback to default — D-022 spawn contract).
## Returns the marker's global_position, or the map origin as a last resort after a loud
## error so the player is still placed somewhere valid rather than crashing.
func get_spawn_position(entry_point: StringName) -> Vector2:
	var spawns := get_node_or_null("Spawns")
	var wanted := entry_point
	var is_explicit := entry_point != &""
	if not is_explicit:
		wanted = _map_data.default_spawn_id if _map_data != null else &""
	if spawns == null or wanted == &"":
		push_error("[map] cannot resolve spawn '%s' (no Spawns node or empty id)" % wanted)
		return global_position
	var marker := spawns.get_node_or_null(String(wanted))
	if marker == null:
		# Explicit entry point that doesn't exist is a content bug — fail loud, do NOT
		# silently fall back to the default spawn (that would hide broken exit wiring).
		push_error("[map] spawn marker '%s' not found in map '%s'%s" % [
			wanted, (_map_data.id if _map_data != null else &""),
			" (explicit entry_point)" if is_explicit else " (default_spawn_id)"])
		return global_position
	if marker is Node2D:
		return (marker as Node2D).global_position
	return global_position


# --- Semantic input (via InputService only) ----------------------------------

func _unhandled_input(_event: InputEvent) -> void:
	if _input == null:
		return
	# Return to menu (system action, allowed above gameplay). Null-check viewport + emit
	# LAST (L-013: emitting can synchronously unload this scene).
	if _input.call("is_system_action_just_pressed", OPEN_MENU_ACTION):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return_to_menu_requested.emit()
		return
	# Use the exit the player is standing in (gameplay action, gated on GAMEPLAY context).
	# Destination comes from the AUTHORITATIVE MapExit data, not the scene (D-022).
	if _active_exit != null and _input.call("is_gameplay_action_just_pressed", INTERACT_ACTION):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		var dest: StringName = _active_exit.to_map_id
		var entry: StringName = _active_exit.entry_point
		exit_requested.emit(dest, entry)


func _on_exit_body_entered(body: Node, zone: MapExitZone) -> void:
	if not _is_player(body):
		return
	# Resolve the zone's exit_id to the authoritative MapExit in this map's data.
	var resolved: MapExit = _map_data.find_exit(zone.exit_id) if _map_data != null else null
	if resolved == null:
		push_error("[map] player entered exit zone '%s' but exit_id '%s' does not resolve" % [
			zone.name, zone.exit_id])
		return
	_active_exit = resolved
	_active_zone = zone
	_refresh_hud()


func _on_exit_body_exited(body: Node, zone: MapExitZone) -> void:
	if _active_zone == zone and _is_player(body):
		_active_exit = null
		_active_zone = null
		_refresh_hud()


func _is_player(body: Node) -> bool:
	return body is Player


# --- HUD (presentation overlay; owned here, self-localizing) -----------------
# MapBase OWNS a GameplayHUD overlay and PUSHES view data into it (map name, player identity,
# interact availability). The HUD renders + self-refreshes on language change (it is pure
# presentation). The map's own `HUD` CanvasLayer (if the scene has one) is hidden so the new
# overlay is the single HUD — the old `HUD/MapLabel` is superseded, not duplicated (L-002).

func _setup_hud() -> void:
	# Hide the scene's legacy HUD plate (the pre-Phase-04 MapLabel) if present; the GameplayHUD
	# overlay replaces it. We don't delete it so the .tscn stays untouched/portable.
	var legacy := get_node_or_null("HUD")
	if legacy != null and legacy is CanvasLayer:
		(legacy as CanvasLayer).visible = false

	_hud = GameplayHUDScript.new() as GameplayHUD
	_hud.name = "GameplayHUD"
	add_child(_hud)


func _refresh_hud() -> void:
	if _hud == null:
		return
	# MapData.name_key is a String; the HUD takes a StringName key. Convert explicitly so both
	# ternary branches share a type (and no implicit String/StringName coercion warning).
	var map_name_key: StringName = StringName(_map_data.name_key) if _map_data != null else &""
	_hud.set_map_name(map_name_key)
	_hud.set_character(_find_player_character())
	_hud.set_interact_available(_active_exit != null)
	# Re-apply the cached sect view so a fresh HUD (new map) still shows the player's sect.
	if _sect_view != null:
		_hud.set_sect_view(_sect_view)


## Read the authoritative player CharacterState from the player realized in this map (or null
## if the player is not yet parented / is not a Character). Presentation reads a VIEW only.
func _find_player_character() -> CharacterState:
	var host := get_player_host()
	if host == null:
		return null
	for child in host.get_children():
		if child is Player:
			return (child as Player).get_character_state()
	return null

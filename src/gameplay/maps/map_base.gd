extends Node2D
class_name MapBase
## MapBase — Aetheria gameplay (per-map coordinator; attached to every map scene).
##
## The gameplay-layer coordinator for ONE map (hub, field, …), the Phase-03 successor to
## the Phase-02 `PlayerSandbox` first-scene contract. It:
##   - exposes a `PlayerHost` where WorldRuntime parents the persistent player, and resolves
##     named spawn markers (`get_spawn_position(entry_point)`),
##   - detects the player standing in a `MapExitZone` and, on the semantic `interact` intent
##     (via InputService — never raw keys), emits `exit_requested(to_map_id, entry_point)`,
##   - emits `return_to_menu_requested` on the `open_menu` system intent,
##   - sets the GAMEPLAY input context on enter and shows a localized map-name HUD.
##
## It owns NO transition mechanics (SceneRouter) and NO location truth (GameState) and does
## not reach into the player's internals — it only emits intents. State is throwaway: carried
## state lives in GameState (`docs/ARCHITECTURE.md` §9).
##
## Expected child nodes (by name): `PlayerHost` (Node2D), `Spawns` (Node2D of Marker2D),
## `Exits` (Node2D of MapExitZone), `HUD/MapLabel` (Label). Camera/tiles are scene content.

## Intent to leave to another map. WorldRuntime resolves it through SceneRouter.
signal exit_requested(to_map_id: StringName, entry_point: StringName)
## Intent to leave the world back to the menu (same contract the sandbox/prologue used).
signal return_to_menu_requested()

## Localization key for this map's display name. Set per map scene (never a literal).
@export var map_name_key: String = ""

const INTERACT_ACTION := &"interact"
const OPEN_MENU_ACTION := &"open_menu"
const DEFAULT_SPAWN := &"spawn_default"

var _input: Node = null
var _bus: Node = null
var _active_exit: MapExitZone = null   # the exit zone the player currently stands in


func _ready() -> void:
	_input = get_node_or_null("/root/InputService")
	_bus = get_node_or_null("/root/EventBus")

	if _input != null:
		_input.call("set_gameplay_context")

	# Boundary walls occupy the WORLD collision layer from the single source of truth
	# (`CollisionLayers`), not scene magic numbers (L-002/L-014). Static targets detect
	# nothing (mask 0); the player's mask includes WORLD so it stays inside the map.
	var walls := get_node_or_null("Walls")
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

	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)

	_refresh_hud()


func _exit_tree() -> void:
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)


## Where WorldRuntime parents the persistent player. Falls back to self if no PlayerHost.
func get_player_host() -> Node:
	var host := get_node_or_null("PlayerHost")
	return host if host != null else self


## Resolve a named spawn marker to a world position, falling back to the default spawn and
## then to the map origin. Returns global_position so the caller can place the player.
func get_spawn_position(entry_point: StringName) -> Vector2:
	var spawns := get_node_or_null("Spawns")
	if spawns != null:
		var wanted := String(entry_point) if entry_point != &"" else String(DEFAULT_SPAWN)
		var marker := spawns.get_node_or_null(wanted)
		if marker == null:
			marker = spawns.get_node_or_null(String(DEFAULT_SPAWN))
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
	if _active_exit != null and _input.call("is_gameplay_action_just_pressed", INTERACT_ACTION):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		var dest: StringName = _active_exit.to_map_id
		var entry: StringName = _active_exit.entry_point
		exit_requested.emit(dest, entry)


func _on_exit_body_entered(body: Node, zone: MapExitZone) -> void:
	if _is_player(body):
		_active_exit = zone
		_refresh_hud()


func _on_exit_body_exited(body: Node, zone: MapExitZone) -> void:
	if _active_exit == zone and _is_player(body):
		_active_exit = null
		_refresh_hud()


func _is_player(body: Node) -> bool:
	return body is Player


# --- HUD (localized; presentation only) --------------------------------------

func _refresh_hud() -> void:
	var label := get_node_or_null("HUD/MapLabel")
	if label == null or not (label is Label):
		return
	var loc := get_node_or_null("/root/Localization")
	var map_name := map_name_key
	if loc != null and map_name_key != "":
		map_name = String(loc.call("t", map_name_key))
	var hint := ""
	if loc != null:
		hint = String(loc.call("t", "UI_MAP_INTERACT_HINT")) if _active_exit != null \
			else String(loc.call("t", "UI_MAP_RETURN_HINT"))
	(label as Label).text = "%s\n%s" % [map_name, hint]


func _on_language_changed(_language_code: String) -> void:
	_refresh_hud()

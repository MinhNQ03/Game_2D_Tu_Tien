extends Resource
class_name MapExit
## MapExit — Aetheria data (content Resource).
##
## One edge in the map graph (`docs/DATA_SCHEMA.md` §3 `MapData.exits` → `{ to_map_id,
## entry_point }`). DATA only — no behavior. A map's exit says "if the player uses this
## exit, go to map `to_map_id` and arrive at its named spawn `entry_point`". The gameplay
## coordinator (`WorldRuntime`) reads these; the Resource never performs a transition.
##
## `entry_point` is a stable spawn-marker name the destination map resolves on arrival
## (`docs/GAME_FLOW.md` §3.6 "arrival from SceneRouter"). ids never change once shipped
## (`DATA_SCHEMA.md` §0).

## The destination map's `MapData.id` (StringName). Must be non-empty for a usable exit.
@export var to_map_id: StringName = &""

## The named spawn marker in the destination map to place the player at on arrival.
## Empty means "use the destination's default spawn".
@export var entry_point: StringName = &""


func is_valid() -> bool:
	return to_map_id != &""


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if to_map_id == &"":
		errors.append("to_map_id must be set")
	return errors

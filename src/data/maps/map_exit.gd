extends Resource
class_name MapExit
## MapExit — Aetheria data (content Resource).
##
## One edge in the map graph (`docs/DATA_SCHEMA.md` §3 `MapData.exits`). DATA only — no
## behavior. A map's exit says "the exit identified by `id` leads to map `to_map_id`, and
## the player arrives at its named spawn `entry_point`". The gameplay coordinator
## (`WorldRuntime`) reads these; the Resource never performs a transition.
##
## AUTHORITATIVE DESTINATION DATA (D-022): a map scene's `MapExitZone` references an exit by
## `id` only — the destination (`to_map_id` + `entry_point`) lives HERE, not duplicated in
## the scene. This removes the identity drift the Phase-03 reopen flagged (a zone could point
## somewhere different from the data).
##
## `entry_point` is a stable spawn-marker name the destination map resolves on arrival
## (`docs/GAME_FLOW.md` §3.6). ids never change once shipped (`DATA_SCHEMA.md` §0).

## Stable id for this exit, unique within its owning MapData (e.g. &"exit_to_field"). A
## `MapExitZone` in the map scene references this id; MapBase binds the two at load time.
@export var id: StringName = &""

## The destination map's `MapData.id` (StringName). Must be non-empty for a usable exit.
@export var to_map_id: StringName = &""

## The named spawn marker in the destination map to place the player at on arrival.
## Empty means "use the destination map's default spawn".
@export var entry_point: StringName = &""


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be set")
	if to_map_id == &"":
		errors.append("to_map_id must be set")
	return errors

extends Resource
class_name MapData
## MapData — Aetheria data (content Resource).
##
## The authored definition of one map (`docs/DATA_SCHEMA.md` §3 `MapData (map_*)`). DATA
## only — no gameplay behavior lives here (`04-coding-standards.md`). The `WorldRuntime`
## coordinator reads a catalog of these to register scenes with `SceneRouter` and resolve
## map-to-map transitions.
##
## PHASE 03 SUBSET of the documented schema: `id`, `name_key`, `scene_key`, `exits`. The
## declared-but-unused DATA_SCHEMA fields (`tileset_ref`, `spawn_tables`, `music`) are
## deferred to the phase that first consumes them (spawn tables → Enemy AI, Phase 10) —
## no speculative fields now (`03-architecture.md` anti-over-engineering).
##
## NOTE (schema addition, logged in `DECISIONS.md` D-021): `scene_key` is added to the
## documented shape. The schema listed `scene: PackedScene`, but transitions go through
## `SceneRouter` which addresses content by a stable string `scene_key` (registry key);
## MapData is the catalog that maps a `map_id` to its `scene_key`. `world_id` is NOT a
## MapData field — it is a session/grouping id carried in `GameState` and passed to the
## router, not authored per map.

## Stable unique id within the `map_*` type (e.g. `&"map_hub"`). IDS NEVER CHANGE ONCE
## SHIPPED (`DATA_SCHEMA.md` §0) — renaming is a breaking content change + a save migration.
@export var id: StringName = &""

## Localization key for the map's display name (never a literal string — `07-localization.md`).
@export var name_key: String = ""

## The `SceneRouter` registry key for this map's content scene. `WorldRuntime` registers
## `scene_key -> scene path` with the router; a transition is `request_transition(scene_key…)`.
@export var scene_key: String = ""

## Outgoing edges to other maps. Each is a `MapExit { to_map_id, entry_point }`.
@export var exits: Array[MapExit] = []


## True when the map is well-formed enough to register + transition to.
func is_valid() -> bool:
	return validation_errors().is_empty()


## Returns the list of invariant violations (empty == valid). Content loaded from disk is
## external input and is validated at the boundary (`04-coding-standards.md`).
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be set")
	if name_key == "":
		errors.append("name_key must be set (localization key)")
	if scene_key == "":
		errors.append("scene_key must be set (SceneRouter registry key)")
	for i in exits.size():
		var map_exit: MapExit = exits[i]
		if map_exit == null:
			errors.append("exits[%d] is null" % i)
		elif not map_exit.is_valid():
			errors.append("exits[%d]: %s" % [i, str(map_exit.validation_errors())])
	return errors


## The exit whose destination is `to_map_id`, or null if this map has no such exit.
func find_exit_to(to_map_id: StringName) -> MapExit:
	for map_exit in exits:
		if map_exit != null and map_exit.to_map_id == to_map_id:
			return map_exit
	return null

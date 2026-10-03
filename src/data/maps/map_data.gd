extends Resource
class_name MapData
## MapData — Aetheria data (content Resource).
##
## The AUTHORITATIVE definition of one map (`docs/DATA_SCHEMA.md` §3 `MapData (map_*)`).
## DATA only — no gameplay behavior lives here (`04-coding-standards.md`). A `MapCatalog`
## aggregates these; `WorldRuntime` reads the catalog to register scenes with `SceneRouter`
## and resolve map-to-map transitions. The map is the source of truth for its identity,
## content scene, playable bounds, default spawn, and exits — scenes do not re-author these.
##
## Fields (D-021 + Phase-03 reopen D-022):
##   - `id`           — stable `map_*` identity (never changes once shipped).
##   - `name_key`     — localization key for the display name.
##   - `scene_key`    — stable `SceneRouter` registry key (string identity for the scene).
##   - `scene_path`   — the resource path of the content scene (the implementation ref the
##                      router registers against the `scene_key`).
##   - `bounds`       — the playable area (Rect2); the camera limits derive from this.
##   - `default_spawn_id` — the spawn marker used when an exit specifies no `entry_point`.
##   - `exits`        — outgoing edges (`MapExit`), each with a stable `id`.
##
## `world_id` is NOT a MapData field — it is a session/grouping id carried in `GameState`
## and passed to the router, not authored per map. `tileset_ref`/`spawn_tables`/`music` from
## the DATA_SCHEMA sketch are deferred to the phase that first consumes them (no speculative
## fields — `03-architecture.md`).

## Stable unique id within the `map_*` type (e.g. `&"map_hub"`). IDS NEVER CHANGE ONCE
## SHIPPED (`DATA_SCHEMA.md` §0) — renaming is a breaking content change + a save migration.
@export var id: StringName = &""

## Localization key for the map's display name (never a literal string — `07-localization.md`).
@export var name_key: String = ""

## The `SceneRouter` registry key for this map's content scene (stable string identity).
@export var scene_key: String = ""

## The resource path of the content scene registered under `scene_key`. The one place the
## map↔scene binding is authored; `WorldRuntime` registers `scene_key -> scene_path`.
@export var scene_path: String = ""

## The playable area of this map in world coordinates. The active map's Camera2D limits are
## configured from this (source of truth — not duplicated per scene).
@export var bounds: Rect2 = Rect2()

## The spawn marker id used when arriving with no explicit `entry_point` (e.g. first entry).
@export var default_spawn_id: StringName = &""

## Outgoing edges to other maps. Each is a `MapExit { id, to_map_id, entry_point }`.
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
	if scene_path == "":
		errors.append("scene_path must be set")
	elif not ResourceLoader.exists(scene_path):
		errors.append("scene_path does not exist: %s" % scene_path)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		errors.append("bounds must have a positive size (got %s)" % str(bounds))
	if default_spawn_id == &"":
		errors.append("default_spawn_id must be set")
	var seen_exit_ids := {}
	for i in exits.size():
		var map_exit: MapExit = exits[i]
		if map_exit == null:
			errors.append("exits[%d] is null" % i)
			continue
		if not map_exit.is_valid():
			errors.append("exits[%d]: %s" % [i, str(map_exit.validation_errors())])
		if map_exit.id != &"":
			if seen_exit_ids.has(map_exit.id):
				errors.append("duplicate exit id '%s'" % map_exit.id)
			seen_exit_ids[map_exit.id] = true
	return errors


## The exit whose stable id is `exit_id`, or null. Used by MapBase to bind a scene's
## `MapExitZone` (which carries only `exit_id`) to its authoritative destination data.
func find_exit(exit_id: StringName) -> MapExit:
	for map_exit in exits:
		if map_exit != null and map_exit.id == exit_id:
			return map_exit
	return null


## The exit whose destination is `to_map_id`, or null. Kept for graph queries/tests.
func find_exit_to(to_map_id: StringName) -> MapExit:
	for map_exit in exits:
		if map_exit != null and map_exit.to_map_id == to_map_id:
			return map_exit
	return null

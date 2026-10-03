extends Resource
class_name MapCatalog
## MapCatalog — Aetheria data (content Resource).
##
## The authored list of every map in a world grouping (D-022). This is the DATA-DRIVEN
## source of truth that replaces the hard-coded map/path list that used to live in
## `WorldRuntime`. Adding a map is: author a `MapData` + its content scene, then add the
## `MapData` to this catalog — NO core code edit (the extensibility rule, `02-game-design.md`
## / `03-architecture.md`). `WorldRuntime` only knows the catalog's resource path.
##
## DATA only — no behavior. `WorldRuntime` reads `maps`, validates the catalog at the
## boundary, registers each `scene_key -> scene_path` with `SceneRouter`, and builds its
## runtime `map_id -> MapData` lookup.

## Every map in this world grouping. Order is not significant; identity is by `MapData.id`.
@export var maps: Array[MapData] = []

## The map a new session starts in (data-driven, D-023). Replaces the hard-coded
## `WorldRuntime.START_MAP_ID`: changing the start map is now a content edit here, not a code
## edit (the extensibility rule, `02-game-design.md`). Must resolve to one of `maps`' ids.
@export var start_map_id: StringName = &""


func is_valid() -> bool:
	return validation_errors().is_empty()


## Validates catalog-level invariants (in addition to each MapData's own validation):
##   - no null entries; each MapData valid
##   - map ids unique; scene_keys unique
##   - every exit's `to_map_id` resolves to a map in THIS catalog (no dangling edges)
## Content loaded from disk is external input, validated at the boundary (`04-coding-standards.md`).
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen_ids := {}
	var seen_scene_keys := {}
	for i in maps.size():
		var map_data: MapData = maps[i]
		if map_data == null:
			errors.append("maps[%d] is null" % i)
			continue
		if not map_data.is_valid():
			errors.append("maps[%d] (%s): %s" % [i, map_data.id, str(map_data.validation_errors())])
		if map_data.id != &"":
			if seen_ids.has(map_data.id):
				errors.append("duplicate map id '%s'" % map_data.id)
			seen_ids[map_data.id] = true
		if map_data.scene_key != "":
			if seen_scene_keys.has(map_data.scene_key):
				errors.append("duplicate scene_key '%s'" % map_data.scene_key)
			seen_scene_keys[map_data.scene_key] = true
	# Second pass: every exit destination must resolve to a map in this catalog.
	for map_data in maps:
		if map_data == null:
			continue
		for map_exit in map_data.exits:
			if map_exit == null:
				continue
			if map_exit.to_map_id != &"" and not seen_ids.has(map_exit.to_map_id):
				errors.append("map '%s' exit '%s' targets unknown map '%s'" % [
					map_data.id, map_exit.id, map_exit.to_map_id])
	# The start map must be set and resolve to a real map (data-driven session start, D-023).
	if start_map_id == &"":
		errors.append("start_map_id must be set")
	elif not seen_ids.has(start_map_id):
		errors.append("start_map_id '%s' does not resolve to any map in the catalog" % start_map_id)
	return errors


## Build a `map_id (StringName) -> MapData` dictionary. Call once (e.g. at session start),
## not per frame (`05-performance-testing.md`). Returns an empty dict if the catalog is
## invalid; callers validate first and fail loud.
func build_lookup() -> Dictionary:
	var lookup := {}
	for map_data in maps:
		if map_data != null and map_data.id != &"":
			lookup[map_data.id] = map_data
	return lookup

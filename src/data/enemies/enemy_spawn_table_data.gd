extends Resource
class_name EnemySpawnTableData
## EnemySpawnTableData — Aetheria data (what spawns in one map, Phase 10).
##
## One table per map. Each row names an `EnemyData` and a world position, so populating a map
## is reading a list — and adding another creature to the field is **a row**, not a line of
## code. That is the Phase-10 exit criterion ("add a new enemy via data only") expressed as a
## resource rather than as an intention.
##
## ROWS ARE A PARALLEL-ARRAY PAIR, NOT AN ARRAY OF SUB-RESOURCES. `enemies[i]` spawns at
## `positions[i]`. A `SpawnEntryData` sub-resource would be tidier to describe and would mean a
## separate `.tres` per spawn point for a table that has three of them; the pair keeps one
## authored file per map. `is_valid()` enforces the lengths match, because a mismatch is the
## one failure mode this shape introduces and it must not be silent.
##
## SPAWN ORDER IS THE AUTHORED ORDER, which is what makes a populated map DETERMINISTIC: the
## same table always produces the same entities with the same ids in the same sequence, so a
## seeded run is reproducible and a future authoritative server assigns the same identities.

## The map this table populates (`MapData.id`).
@export var map_id: StringName = &""

## Creatures to spawn, index-aligned with `positions`.
@export var enemies: Array[EnemyData] = []

## World positions, index-aligned with `enemies`.
##
## A `PackedVector2Array`, not an `Array[Vector2]`: packed storage avoids a Variant per entry,
## and — the reason it is called out — a typed `@export` silently REFUSES a value of the wrong
## array type (L-026). Authoring `PackedVector2Array(...)` into an `Array[Vector2]` left this
## field empty while `enemies` had two rows, and the only thing that caught it was the
## length check in `is_valid()`. The export type now matches the `.tres` syntax it is
## authored with.
@export var positions: PackedVector2Array = PackedVector2Array()


func size() -> int:
	return enemies.size()


## True when the table is usable. Rejects a length mismatch loudly rather than spawning the
## shorter prefix: a table that silently drops its last row is a map that is quietly emptier
## than it was authored to be.
func is_valid() -> bool:
	var problems: Array[String] = []
	if map_id == &"":
		problems.append("map_id is empty")
	if enemies.size() != positions.size():
		problems.append("enemies (%d) and positions (%d) must be the same length"
			% [enemies.size(), positions.size()])
	for i in enemies.size():
		if enemies[i] == null:
			problems.append("row %d has a null EnemyData" % i)
		elif not enemies[i].is_valid():
			problems.append("row %d ('%s') is an invalid EnemyData" % [i, enemies[i].id])
	if problems.is_empty():
		return true
	push_error("[spawn-table] '%s' is invalid: %s" % [map_id, "; ".join(problems)])
	return false


## A stable, unique instance id for row `index`.
##
## Derived from the map and the row rather than from a counter or a random value, so the same
## table always produces the same ids: a save, a replay and (later) a server all name the same
## creature the same way. A counter would renumber everything when a row is inserted.
func instance_id_for(index: int) -> StringName:
	if index < 0 or index >= enemies.size() or enemies[index] == null:
		return &""
	return StringName("%s__%s__%d" % [map_id, enemies[index].id, index])

extends Resource
class_name RelationshipConfigData
## RelationshipConfigData — Aetheria data (relationship tuning Resource).
##
## The SINGLE SOURCE OF TRUTH for relationship dimension ranges + history capacity
## (`docs/RELATIONSHIP_SYSTEM.md` §2, `04-coding-standards.md` no magic numbers). The
## `RelationshipService` reads defaults/min/max FROM HERE; no range is hard-coded in the
## mutation logic. Re-balancing is a data edit to the authored `.tres`; adding a dimension is
## a data edit here, not a change in ten business-logic files.
##
## DATA only — no behavior beyond boundary validation. Each dimension is authored as a
## `{ id, default, min, max }` entry; the shape is a plain Dictionary (kept simple — a nested
## Resource per dimension would be over-engineering for six scalars). `history_capacity`
## bounds every edge's change log so it can never grow without limit.

## Authored dimension specs. Each entry is a Dictionary:
##   { "id": StringName, "default": int, "min": int, "max": int }
## Order is not significant; identity is by `id`.
@export var dimensions: Array[Dictionary] = []

## Max history entries kept per edge (0 = history disabled). Must be >= 0.
@export var history_capacity: int = 32


func is_valid() -> bool:
	return validation_errors().is_empty()


## Validate at the boundary (content from disk is external input, `04-coding-standards.md`):
##   - at least one dimension
##   - each entry has a non-empty id, and ints for default/min/max
##   - min <= default <= max
##   - dimension ids unique
##   - history_capacity >= 0
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if dimensions.is_empty():
		errors.append("at least one dimension must be configured")
	if history_capacity < 0:
		errors.append("history_capacity must be >= 0 (got %d)" % history_capacity)
	var seen := {}
	for i in dimensions.size():
		var spec: Dictionary = dimensions[i]
		var dim_id := String(spec.get("id", ""))
		if dim_id == "":
			errors.append("dimensions[%d] has an empty id" % i)
			continue
		if seen.has(dim_id):
			errors.append("duplicate dimension id '%s'" % dim_id)
		seen[dim_id] = true
		if not (spec.has("default") and spec.has("min") and spec.has("max")):
			errors.append("dimension '%s' must define default/min/max" % dim_id)
			continue
		var dmin := int(spec["min"])
		var dmax := int(spec["max"])
		var ddef := int(spec["default"])
		if dmin > dmax:
			errors.append("dimension '%s': min %d > max %d" % [dim_id, dmin, dmax])
		if ddef < dmin or ddef > dmax:
			errors.append("dimension '%s': default %d not in [%d, %d]" % [
				dim_id, ddef, dmin, dmax])
	return errors


# --- Lookups (built once; not per frame) -------------------------------------

## True if `dimension` is a configured dimension.
func has_dimension(dimension: StringName) -> bool:
	return _find(dimension) != null


## The configured ids (Array[StringName]), in authored order. For seeding + tests.
func dimension_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for spec in dimensions:
		out.append(StringName(String(spec.get("id", ""))))
	return out


func get_default(dimension: StringName) -> int:
	var spec: Variant = _find(dimension)
	return int((spec as Dictionary).get("default", 0)) if spec != null else 0


func get_min(dimension: StringName) -> int:
	var spec: Variant = _find(dimension)
	return int((spec as Dictionary).get("min", 0)) if spec != null else 0


func get_max(dimension: StringName) -> int:
	var spec: Variant = _find(dimension)
	return int((spec as Dictionary).get("max", 0)) if spec != null else 0


## Clamp `value` into `dimension`'s configured range. If the dimension is unknown, returns
## the value unchanged (callers validate `has_dimension` first and fail loud).
func clamp_value(dimension: StringName, value: int) -> int:
	var spec: Variant = _find(dimension)
	if spec == null:
		return value
	var d: Dictionary = spec
	return clampi(value, int(d["min"]), int(d["max"]))


## A `{ dimension_id(String) -> default(int) }` map for seeding a new edge's dimensions.
func defaults_map() -> Dictionary:
	var out := {}
	for spec in dimensions:
		var dim_id := String(spec.get("id", ""))
		if dim_id != "":
			out[dim_id] = int(spec.get("default", 0))
	return out


func _find(dimension: StringName) -> Variant:
	var target := String(dimension)
	for spec in dimensions:
		if String(spec.get("id", "")) == target:
			return spec
	return null

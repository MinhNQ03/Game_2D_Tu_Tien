extends RefCounted
class_name RelationshipEdge
## RelationshipEdge — Aetheria domain (one relationship between two endpoints).
##
## The data of a single relationship (`docs/RELATIONSHIP_SYSTEM.md` §4): a stable `id`, two
## typed `RelationshipEndpoint`s, a qualitative `relationship_type`, the quantitative
## `dimensions` (affinity/trust/respect/fear/rivalry/debt — values interpreted by the config,
## not hard-coded here), `symmetric`/`known` flags, and a bounded `history` log.
##
## Pure domain `RefCounted` — no Node/presentation. It is a passive data holder: it does NOT
## clamp, validate ranges, or decide the dimension set. All of that is owned by
## `RelationshipConfigData` + `RelationshipService` (the single mutation path). The edge only
## stores and serializes. `dimensions` is kept private-by-convention (`_dimensions`) and
## mutated ONLY by the service via `set_dimension_raw` so no caller does
## `edge.dimensions["trust"] += 20` (`docs/RELATIONSHIP_SYSTEM.md` §8 mutation ownership).

var id: StringName = &""
var from_ref: RelationshipEndpoint = null
var to_ref: RelationshipEndpoint = null
var relationship_type: StringName = &"STRANGER"
var symmetric: bool = false
var known: bool = false

## Dimension values, keyed by dimension id (String). Private-by-convention: read via
## `get_dimension`, write ONLY via the service (`set_dimension_raw`). Starts empty; the
## service seeds defaults from the config at creation.
var _dimensions: Dictionary = {}

## Bounded change log. Each entry is a plain Dictionary
## `{ dimension, old_value, new_value, delta, cause }`. Capacity enforced by the service from
## config; the edge just stores + trims the tail.
var _history: Array = []


# --- Dimension access (read public; write only via service) ------------------

## Current value of `dimension` (as stored, from this edge's `from_ref` perspective).
## Returns `default_value` if the dimension isn't present. The service passes the config
## default so a never-touched dimension still reads sensibly.
func get_dimension(dimension: StringName, default_value: int = 0) -> int:
	return int(_dimensions.get(String(dimension), default_value))


## True if the edge carries a stored value for `dimension`.
func has_dimension(dimension: StringName) -> bool:
	return _dimensions.has(String(dimension))


## A COPY of the dimension map (so callers can read all values without being able to mutate
## the edge's internal dict). Keys are Strings.
func get_dimensions_copy() -> Dictionary:
	return _dimensions.duplicate()


## INTERNAL mutation — only the RelationshipService calls this (it has already validated the
## dimension against the config and clamped the value). Not for general callers.
func set_dimension_raw(dimension: StringName, value: int) -> void:
	_dimensions[String(dimension)] = value


## Seed the whole dimension map at creation (service passes the config defaults). Replaces
## any existing values. Keys stored as String.
func seed_dimensions(defaults: Dictionary) -> void:
	_dimensions = {}
	for key in defaults:
		_dimensions[String(key)] = int(defaults[key])


## INTERNAL: load the raw dimension + history data verbatim (used by `from_dict`). The store
## validates ranges after; this only transfers plain data into the private fields.
func load_raw(dimensions_data: Dictionary, history_data: Array) -> void:
	_dimensions = {}
	for key in dimensions_data:
		_dimensions[String(key)] = int(dimensions_data[key])
	_history = history_data.duplicate(true)


# --- History (append + bounded; service drives) -----------------------------

## Append a history entry and trim to `capacity` newest entries (service passes the config
## capacity). `capacity <= 0` disables history entirely (cleared). The entry is plain data.
func append_history(entry: Dictionary, capacity: int) -> void:
	if capacity <= 0:
		_history = []
		return
	_history.append(entry)
	while _history.size() > capacity:
		_history.pop_front()  # drop the oldest; keep the newest `capacity` entries


## A COPY of the history log (plain-data entries). Newest-last.
func get_history_copy() -> Array:
	return _history.duplicate(true)


func history_size() -> int:
	return _history.size()


# --- Serialization (plain data; deterministic) -------------------------------

## Serialize to plain data. Dimension keys are emitted sorted so a snapshot is byte-stable
## (`docs/RELATIONSHIP_SYSTEM.md` §6, deterministic ordering).
func to_dict() -> Dictionary:
	var dims := {}
	var keys := _dimensions.keys()
	keys.sort()
	for key in keys:
		dims[key] = int(_dimensions[key])
	var from_data: Variant = null
	if from_ref != null:
		from_data = from_ref.to_dict()
	var to_data: Variant = null
	if to_ref != null:
		to_data = to_ref.to_dict()
	return {
		"id": String(id),
		"from": from_data,
		"to": to_data,
		"relationship_type": String(relationship_type),
		"symmetric": symmetric,
		"known": known,
		"dimensions": dims,
		"history": _history.duplicate(true),
	}


## Build an edge from plain data WITHOUT range/dimension-set validation (that is the store's
## job, which has the config). Returns null on a structurally malformed payload (missing id,
## unparseable endpoints) so the store can fail closed. History is copied verbatim as data.
static func from_dict(data: Variant) -> RelationshipEdge:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data
	var edge_id := StringName(String(dict.get("id", "")))
	if edge_id == &"":
		return null
	var from_ep := RelationshipEndpoint.from_dict(dict.get("from"))
	var to_ep := RelationshipEndpoint.from_dict(dict.get("to"))
	if from_ep == null or to_ep == null:
		return null
	var edge := RelationshipEdge.new()
	edge.id = edge_id
	edge.from_ref = from_ep
	edge.to_ref = to_ep
	edge.relationship_type = StringName(String(dict.get("relationship_type", "STRANGER")))
	edge.symmetric = bool(dict.get("symmetric", false))
	edge.known = bool(dict.get("known", false))
	var dims_in: Variant = dict.get("dimensions", {})
	var hist_in: Variant = dict.get("history", [])
	var dims_dict: Dictionary = dims_in if typeof(dims_in) == TYPE_DICTIONARY else {}
	var hist_arr: Array = hist_in if typeof(hist_in) == TYPE_ARRAY else []
	edge.load_raw(dims_dict, hist_arr)
	return edge

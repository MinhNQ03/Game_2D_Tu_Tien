extends RefCounted
class_name RelationshipStore
## RelationshipStore — Aetheria domain (the canonical relationship graph).
##
## The SINGLE source of truth for all relationship edges (`docs/RELATIONSHIP_SYSTEM.md` §1).
## It OWNS the edges and two indexes so queries are not full scans
## (`05-performance-testing.md`):
##   - `_by_id`:        edge id (String)      -> RelationshipEdge
##   - `_by_endpoint`:  endpoint compare_key  -> Array[edge id]  (both ends of each edge)
##
## Symmetric edges are stored in CANONICAL endpoint order (smaller `compare_key` is `from`),
## so `A-B` and `B-A` resolve to ONE edge and a duplicate symmetric create is rejected
## (`docs/RELATIONSHIP_SYSTEM.md` §4). The store holds the `RelationshipConfigData` so it can
## seed new edges' dimensions and validate on hydrate.
##
## Pure domain `RefCounted` — no Node/presentation/SceneTree. It does NOT emit signals or run
## mutation rules; the `RelationshipService` is the mutation path (§8) and the observable
## surface. The store exposes graph structure + a low-level `set_dimension` used ONLY by the
## service (which clamps + logs history first). It never exposes its raw internal dicts.

var _config: RelationshipConfigData = null
var _by_id: Dictionary = {}         # String(edge_id) -> RelationshipEdge
var _by_endpoint: Dictionary = {}   # String(endpoint compare_key) -> Array[String edge_id]


func _init(config: RelationshipConfigData = null) -> void:
	_config = config


func get_config() -> RelationshipConfigData:
	return _config


func edge_count() -> int:
	return _by_id.size()


# --- Canonicalization --------------------------------------------------------

## For a symmetric edge, order the endpoints canonically (smaller compare_key first) so the
## same pair always maps to one edge regardless of which side the caller named. Directed edges
## keep their given order. Returns `[from, to]`.
static func canonical_order(
		a: RelationshipEndpoint, b: RelationshipEndpoint, symmetric: bool) -> Array:
	if symmetric and a.compare_to(b) > 0:
		return [b, a]
	return [a, b]


## A stable key for the UNORDERED pair (used to detect a symmetric duplicate): the two
## endpoints' compare_keys joined in sorted order, so A-B and B-A share a key.
static func _pair_key(a: RelationshipEndpoint, b: RelationshipEndpoint) -> String:
	var ka := a.compare_key()
	var kb := b.compare_key()
	return "%s|%s" % [ka, kb] if ka <= kb else "%s|%s" % [kb, ka]


# --- Creation / removal (structure only; service seeds dimensions) ----------

## Insert an already-built edge into the graph + indexes. Rejects (returns false) a null edge,
## a duplicate id, or — for a symmetric edge — an existing edge between the same pair. The
## caller (service) is responsible for canonical ordering + seeding; `add_edge` only indexes.
func add_edge(edge: RelationshipEdge) -> bool:
	if edge == null or edge.id == &"" or edge.from_ref == null or edge.to_ref == null:
		return false
	var key := String(edge.id)
	if _by_id.has(key):
		return false
	if edge.symmetric and find_symmetric_between(edge.from_ref, edge.to_ref) != null:
		return false
	_by_id[key] = edge
	_index_endpoint(edge.from_ref, key)
	_index_endpoint(edge.to_ref, key)
	return true


## Remove an edge by id, updating both indexes. Returns true if an edge was removed.
func remove_edge(edge_id: StringName) -> bool:
	var key := String(edge_id)
	var edge: RelationshipEdge = _by_id.get(key)
	if edge == null:
		return false
	_by_id.erase(key)
	_deindex_endpoint(edge.from_ref, key)
	_deindex_endpoint(edge.to_ref, key)
	return true


# --- Queries (indexed) -------------------------------------------------------

func get_edge(edge_id: StringName) -> RelationshipEdge:
	return _by_id.get(String(edge_id))


func has_edge(edge_id: StringName) -> bool:
	return _by_id.has(String(edge_id))


## Find a DIRECTED edge from `from_ep` to `to_ep` (exact order), or null. If `include_symmetric`
## is true, also returns a symmetric edge joining the pair (either stored order).
func find_between(
		from_ep: RelationshipEndpoint,
		to_ep: RelationshipEndpoint,
		include_symmetric: bool = true) -> RelationshipEdge:
	for key in _edge_ids_for(from_ep):
		var edge: RelationshipEdge = _by_id[key]
		if edge.symmetric:
			if include_symmetric and _joins_pair(edge, from_ep, to_ep):
				return edge
		elif edge.from_ref.equals(from_ep) and edge.to_ref.equals(to_ep):
			return edge
	return null


## Find the symmetric edge between the (unordered) pair, or null. Ignores directed edges.
func find_symmetric_between(
		a: RelationshipEndpoint, b: RelationshipEndpoint) -> RelationshipEdge:
	for key in _edge_ids_for(a):
		var edge: RelationshipEdge = _by_id[key]
		if edge.symmetric and _joins_pair(edge, a, b):
			return edge
	return null


## All edges touching `endpoint` (either end), as a fresh Array[RelationshipEdge]. Indexed —
## no full-graph scan.
func find_for_endpoint(endpoint: RelationshipEndpoint) -> Array:
	var out: Array = []
	for key in _edge_ids_for(endpoint):
		out.append(_by_id[key])
	return out


## All edge ids, sorted (deterministic). For serialization + tests.
func edge_ids_sorted() -> Array:
	var keys := _by_id.keys()
	keys.sort()
	return keys


# --- Low-level dimension write (service-only) --------------------------------

## Set a dimension's RAW value on an edge (the service has already validated the dimension
## and clamped the value). Returns false if the edge is unknown. Not for general callers.
func set_dimension(edge_id: StringName, dimension: StringName, value: int) -> bool:
	var edge: RelationshipEdge = _by_id.get(String(edge_id))
	if edge == null:
		return false
	edge.set_dimension_raw(dimension, value)
	return true


# --- Serialization (deterministic) + hydrate (fail-closed) -------------------

## Serialize the whole graph to plain data. Edges are emitted sorted by id so the snapshot is
## byte-stable (`docs/RELATIONSHIP_SYSTEM.md` §6). No Node/Resource reference, no presentation.
func to_dict() -> Dictionary:
	var edges := []
	for key in edge_ids_sorted():
		edges.append((_by_id[key] as RelationshipEdge).to_dict())
	return {"edges": edges}


## Replace the whole graph from plain data, validating at the boundary and FAILING CLOSED
## (returns false, leaves the store UNCHANGED) on any malformed entry: non-dict payload,
## duplicate edge id, unparseable/invalid endpoint, unknown dimension, out-of-range value,
## or a symmetric-pair duplicate. Rebuilds both indexes on success. Never asserts/aborts
## (`04-coding-standards.md`: boundary validators degrade, the owner fails closed).
func hydrate(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[relationship] hydrate: payload is not a Dictionary")
		return false
	var edges_in: Variant = (data as Dictionary).get("edges", [])
	if typeof(edges_in) != TYPE_ARRAY:
		push_error("[relationship] hydrate: 'edges' is not an Array")
		return false

	# Build into a staging graph first; only commit if the WHOLE payload is valid.
	var staged_by_id := {}
	var staged_by_endpoint := {}
	var staged_pairs := {}  # symmetric pair_key -> true (duplicate-pair guard)
	for entry in (edges_in as Array):
		var edge := RelationshipEdge.from_dict(entry)
		if edge == null:
			push_error("[relationship] hydrate: malformed edge entry")
			return false
		if not edge.from_ref.is_valid() or not edge.to_ref.is_valid():
			push_error("[relationship] hydrate: invalid endpoint on edge '%s'" % edge.id)
			return false
		var key := String(edge.id)
		if staged_by_id.has(key):
			push_error("[relationship] hydrate: duplicate edge id '%s'" % key)
			return false
		if not _validate_edge_dimensions(edge):
			return false  # error already pushed with detail
		if edge.symmetric:
			var pk := _pair_key(edge.from_ref, edge.to_ref)
			if staged_pairs.has(pk):
				push_error("[relationship] hydrate: duplicate symmetric pair for edge '%s'" % key)
				return false
			staged_pairs[pk] = true
		staged_by_id[key] = edge
		_index_endpoint_into(staged_by_endpoint, edge.from_ref, key)
		_index_endpoint_into(staged_by_endpoint, edge.to_ref, key)

	# Commit atomically.
	_by_id = staged_by_id
	_by_endpoint = staged_by_endpoint
	return true


# --- Internal helpers --------------------------------------------------------

## Validate every stored dimension on `edge` against the config (known dimension + in range).
func _validate_edge_dimensions(edge: RelationshipEdge) -> bool:
	if _config == null:
		return true  # no config to validate against (not expected in a real session)
	for dim_key in edge.get_dimensions_copy():
		var dim := StringName(String(dim_key))
		if not _config.has_dimension(dim):
			push_error("[relationship] hydrate: edge '%s' has unknown dimension '%s'"
				% [edge.id, String(dim)])
			return false
		var value := edge.get_dimension(dim)
		if value != _config.clamp_value(dim, value):
			push_error("[relationship] hydrate: edge '%s' dimension '%s' value %d out of range"
				% [edge.id, String(dim), value])
			return false
	return true


func _joins_pair(
		edge: RelationshipEdge, a: RelationshipEndpoint, b: RelationshipEndpoint) -> bool:
	return (edge.from_ref.equals(a) and edge.to_ref.equals(b)) \
		or (edge.from_ref.equals(b) and edge.to_ref.equals(a))


func _edge_ids_for(endpoint: RelationshipEndpoint) -> Array:
	return _by_endpoint.get(endpoint.compare_key(), [])


func _index_endpoint(endpoint: RelationshipEndpoint, edge_id: String) -> void:
	_index_endpoint_into(_by_endpoint, endpoint, edge_id)


func _deindex_endpoint(endpoint: RelationshipEndpoint, edge_id: String) -> void:
	var k := endpoint.compare_key()
	if not _by_endpoint.has(k):
		return
	var ids: Array = _by_endpoint[k]
	ids.erase(edge_id)
	if ids.is_empty():
		_by_endpoint.erase(k)


static func _index_endpoint_into(
		index: Dictionary, endpoint: RelationshipEndpoint, edge_id: String) -> void:
	var k := endpoint.compare_key()
	if not index.has(k):
		index[k] = []
	var ids: Array = index[k]
	if not ids.has(edge_id):
		ids.append(edge_id)

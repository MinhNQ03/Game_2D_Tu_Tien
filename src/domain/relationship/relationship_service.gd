extends RefCounted
class_name RelationshipService
## RelationshipService — Aetheria domain (the single relationship mutation path + observer).
##
## Owns a `RelationshipStore` + a `RelationshipConfigData` (ranges/defaults) + an optional
## `event_kind -> RelationshipRuleData` lookup. It is the ONLY way relationship state changes
## (`docs/RELATIONSHIP_SYSTEM.md` §8): no caller mutates an edge's dimension dict directly.
## Every mutation validates, clamps to the config range, writes bounded history on a REAL
## change, and emits the domain signal `relationship_changed` so UI/other systems can react
## without the service knowing about them.
##
## Pure domain `RefCounted` — the signal is a GDScript signal, NOT an EventBus Node signal
## (`03-architecture.md`: domain must not depend on presentation/infra; a bridge, if ever
## needed, lives in a higher layer). Deterministic: same inputs on the same starting state
## give the same result; no RNG, no global mutable state.

## Observable change. `dimension` is the dimension id; `old_value`/`new_value` are from the
## stored (canonical `from`) perspective; `cause` is the event/command id (may be empty).
signal relationship_changed(
	edge_id: StringName, dimension: StringName, old_value: int, new_value: int, cause: StringName)

var _store: RelationshipStore = null
var _config: RelationshipConfigData = null
var _rules: Dictionary = {}  # event_kind(StringName) -> RelationshipRuleData


func _init(store: RelationshipStore, config: RelationshipConfigData) -> void:
	_store = store
	_config = config


func get_store() -> RelationshipStore:
	return _store


## Install the event→delta rule lookup (built from a validated `RelationshipRuleCatalog`).
func set_rules(rule_lookup: Dictionary) -> void:
	_rules = rule_lookup


# --- Edge creation (the ONLY way an edge is born) ---------------------------

## Create an edge with id `edge_id` between `from_ep` and `to_ep`. For a symmetric edge the
## endpoints are stored in canonical order (`docs/RELATIONSHIP_SYSTEM.md` §4) so A-B and B-A
## are one edge. Dimensions are seeded from the config defaults. Returns the new edge, or null
## (loud) on an invalid endpoint, a duplicate id, or a duplicate symmetric pair. Does NOT emit
## `relationship_changed` (creation is not a dimension change; callers that want a baseline
## event apply a delta/event afterward).
func create_edge(
		edge_id: StringName,
		from_ep: RelationshipEndpoint,
		to_ep: RelationshipEndpoint,
		relationship_type: StringName = &"STRANGER",
		symmetric: bool = false,
		known: bool = false) -> RelationshipEdge:
	if edge_id == &"":
		push_error("[relationship] create_edge requires a non-empty id")
		return null
	if from_ep == null or not from_ep.is_valid() or to_ep == null or not to_ep.is_valid():
		push_error("[relationship] create_edge '%s' needs two valid endpoints" % edge_id)
		return null
	if from_ep.equals(to_ep):
		push_error("[relationship] create_edge '%s' cannot link an endpoint to itself" % edge_id)
		return null
	if _store.has_edge(edge_id):
		push_error("[relationship] create_edge '%s' rejected: id already exists" % edge_id)
		return null

	var ordered := RelationshipStore.canonical_order(from_ep, to_ep, symmetric)
	var edge := RelationshipEdge.new()
	edge.id = edge_id
	edge.from_ref = ordered[0]
	edge.to_ref = ordered[1]
	edge.relationship_type = relationship_type
	edge.symmetric = symmetric
	edge.known = known
	edge.seed_dimensions(_config.defaults_map())

	if not _store.add_edge(edge):
		push_error("[relationship] create_edge '%s' rejected by store (duplicate pair?)" % edge_id)
		return null
	return edge


## Remove an edge (and its index entries). Returns true if one was removed.
func remove_edge(edge_id: StringName) -> bool:
	return _store.remove_edge(edge_id)


## Retype an EXISTING edge IN PLACE: only `relationship_type` is rewritten. Everything else
## is preserved — `id`, `from_ref`/`to_ref` (so the canonical order and the endpoint indexes
## are untouched), `symmetric`, `known`, every `dimensions` value, and the whole `history`.
##
## This exists so a caller that needs to CHANGE a qualitative type never has to
## remove-then-recreate: that pattern destroys the edge first, so a failure on the recreate
## leg leaves NOTHING behind (the mirror's own data is gone even though the caller then
## "rolls back"). Here a failure is detected BEFORE any write, so the old edge survives 100%
## intact. Fails LOUD + returns false on an unknown edge, a missing store, or an empty type;
## it never creates an edge. Returns true (no-op) when the edge already has that type.
##
## Does NOT emit `relationship_changed` — that signal reports a DIMENSION change and carries
## int old/new values; the qualitative type is not a dimension. No consumer exists for a
## type-change event yet, so no speculative signal is added (`03-architecture.md`, L-005).
func set_relationship_type(edge_id: StringName, relationship_type: StringName) -> bool:
	if relationship_type == &"":
		push_error("[relationship] set_relationship_type '%s': empty type" % edge_id)
		return false
	if _store == null:
		push_error("[relationship] set_relationship_type '%s': no store" % edge_id)
		return false
	var edge: RelationshipEdge = _store.get_edge(edge_id)
	if edge == null:
		push_error("[relationship] set_relationship_type on unknown edge '%s'" % edge_id)
		return false
	edge.relationship_type = relationship_type
	return true


# --- Mutation (the single path; clamp + history + signal) -------------------

## Apply a `delta` to `dimension` on edge `edge_id`, attributing `cause`. Returns true if the
## edge changed. Fails LOUD + returns false (never silently creates an edge) if the edge is
## unknown or the dimension is not configured. A zero-effect delta (0, or already clamped at a
## bound in the pushing direction) is a NO-OP: no history, no signal, returns false.
func apply_delta(
		edge_id: StringName,
		dimension: StringName,
		delta: int,
		cause: StringName = &"") -> bool:
	var edge: RelationshipEdge = _store.get_edge(edge_id)
	if edge == null:
		push_error("[relationship] apply_delta on unknown edge '%s'" % edge_id)
		return false
	if not _config.has_dimension(dimension):
		push_error("[relationship] apply_delta unknown dimension '%s' on edge '%s'" % [
			String(dimension), edge_id])
		return false
	var old_value := edge.get_dimension(dimension, _config.get_default(dimension))
	var new_value := _config.clamp_value(dimension, old_value + delta)
	if new_value == old_value:
		return false  # zero-effect: no history noise, no fake change event
	_store.set_dimension(edge_id, dimension, new_value)
	edge.append_history({
		"dimension": String(dimension),
		"old_value": old_value,
		"new_value": new_value,
		"delta": new_value - old_value,  # effective (post-clamp) delta
		"cause": String(cause),
	}, _config.history_capacity)
	relationship_changed.emit(edge_id, dimension, old_value, new_value, cause)
	return true


## Set `dimension` to an absolute `value` (clamped). Convenience over apply_delta for callers
## that know the target value (e.g. hydrate-adjacent tooling); same no-op/signal/history rules.
func set_dimension(
		edge_id: StringName,
		dimension: StringName,
		value: int,
		cause: StringName = &"") -> bool:
	var edge: RelationshipEdge = _store.get_edge(edge_id)
	if edge == null:
		push_error("[relationship] set_dimension on unknown edge '%s'" % edge_id)
		return false
	if not _config.has_dimension(dimension):
		push_error("[relationship] set_dimension unknown dimension '%s'" % String(dimension))
		return false
	var old_value := edge.get_dimension(dimension, _config.get_default(dimension))
	return apply_delta(edge_id, dimension, value - old_value, cause)


# --- Perspective-aware read (debt sign flip on reverse symmetric query) -----

## Read `dimension` as seen BY `viewer` looking at the edge. For a symmetric edge queried
## from the non-canonical side, the signed `debt` dimension is NEGATED so each side reads
## "how much the other owes me" (`docs/RELATIONSHIP_SYSTEM.md` debt perspective); the
## non-directional dimensions are returned unchanged. Directed edges are always read as
## stored. Returns the config default if the dimension is unset.
func read_dimension_as(
		edge_id: StringName, viewer: RelationshipEndpoint, dimension: StringName) -> int:
	var edge: RelationshipEdge = _store.get_edge(edge_id)
	if edge == null:
		push_error("[relationship] read_dimension_as on unknown edge '%s'" % edge_id)
		return 0
	var stored := edge.get_dimension(dimension, _config.get_default(dimension))
	if edge.symmetric and dimension == &"debt" and viewer != null \
			and viewer.equals(edge.to_ref) and not edge.from_ref.equals(edge.to_ref):
		return -stored  # reverse perspective: the sign of a debt flips
	return stored


# --- Event → deltas (deterministic, data-driven) ----------------------------

## Apply the authored rule for `event_kind` to edge `edge_id`, attributing the event as the
## cause. Each delta in the rule goes through `apply_delta` (so clamp + history + signal still
## happen per dimension). Returns true if ANY dimension changed. Fails loud + returns false if
## the edge is unknown or no rule maps the event. Honors the rule's optional type gate.
## DETERMINISTIC: no RNG; the same event on the same starting state yields the same result.
func apply_event(edge_id: StringName, event_kind: StringName) -> bool:
	var edge: RelationshipEdge = _store.get_edge(edge_id)
	if edge == null:
		push_error("[relationship] apply_event on unknown edge '%s'" % edge_id)
		return false
	var rule: RelationshipRuleData = _rules.get(event_kind)
	if rule == null:
		push_error("[relationship] no rule for event '%s'" % String(event_kind))
		return false
	if not rule.applies_to_type(edge.relationship_type):
		return false  # rule gated to a different relationship_type; not an error
	var changed := false
	# Apply deltas in sorted dimension order so the sequence (and thus history order) is
	# deterministic regardless of Dictionary iteration order.
	var dims: Array = rule.dimension_deltas.keys()
	dims.sort()
	for dim_key in dims:
		var dim := StringName(String(dim_key))
		var delta := int(rule.dimension_deltas[dim_key])
		if apply_delta(edge_id, dim, delta, event_kind):
			changed = true
	return changed

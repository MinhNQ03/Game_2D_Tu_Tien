extends RefCounted
class_name RegardRules
## RegardRules — Aetheria domain (how one character regards another, read and moved).
##
## The ONE statement of a rule two systems apply: a conversation's answer (Phase 18) and a
## reward's regard part (Phase 19) both move "how `from_id` regards `to_id`" on one dimension.
## The regard lives in the relationship graph and is changed only through
## `RelationshipService`; this class only says WHICH edge that is — the pair's directed edge
## from `from_id`, or their symmetric one — and when a missing edge is created (only when the
## move would actually change something). Static and stateless: it owns nothing.

## The type of an edge an exchange between two people creates: they have now dealt.
const EDGE_TYPE := &"ACQUAINTED"
const EDGE_ID_FORMAT := "rel_regard__%s__%s"


## The edge that carries `from_id`'s regard for `to_id`, or null.
static func edge_between(relationship: RelationshipService, from_id: StringName,
		to_id: StringName) -> RelationshipEdge:
	var store := relationship.get_store() if relationship != null else null
	if store == null or from_id == &"" or to_id == &"" or from_id == to_id:
		return null
	return store.find_between(RelationshipEndpoint.for_character(from_id),
		RelationshipEndpoint.for_character(to_id), true)


## How `from_id` regards `to_id` on `dimension`. No edge is the dimension's default.
static func read(relationship: RelationshipService, config: RelationshipConfigData,
		from_id: StringName, to_id: StringName, dimension: StringName) -> int:
	if relationship == null or config == null or not config.has_dimension(dimension):
		return 0
	var edge := edge_between(relationship, from_id, to_id)
	if edge == null:
		return config.get_default(dimension)
	return relationship.read_dimension_as(edge.id,
		RelationshipEndpoint.for_character(from_id), dimension)


## Would `move` be carried out? THE rule `move` itself decides by — it asks this first — so a
## caller that must know before it commits anything (a story decision with several
## consequences, D-073 §2) can ask without changing the graph, and "yes" here means `move`
## will answer `ok`. False for an unknown dimension, for nobody or for oneself, and when the
## pair has no edge, needs one, and the id that edge would take is already another pair's.
static func can_move(relationship: RelationshipService, config: RelationshipConfigData,
		from_id: StringName, to_id: StringName, dimension: StringName, delta: int) -> bool:
	if relationship == null or config == null or not config.has_dimension(dimension):
		return false
	if from_id == &"" or to_id == &"" or from_id == to_id:
		return false
	var store := relationship.get_store()
	if store == null:
		return false
	if edge_between(relationship, from_id, to_id) != null:
		return true
	var before := config.get_default(dimension)
	return config.clamp_value(dimension, before + delta) == before \
		or not store.has_edge(StringName(EDGE_ID_FORMAT % [from_id, to_id]))


## Move `from_id`'s regard for `to_id` by `delta`. Returns { ok, old_value, new_value }:
## `ok` is false (and nothing changed, nothing was created) whenever `can_move` says so. A
## move that would move nothing — already at the bound — is `ok` and creates no edge.
static func move(relationship: RelationshipService, config: RelationshipConfigData,
		from_id: StringName, to_id: StringName, dimension: StringName, delta: int,
		cause: StringName) -> Dictionary:
	var result := {"ok": false, "old_value": 0, "new_value": 0}
	if not can_move(relationship, config, from_id, to_id, dimension, delta):
		return result
	var before := read(relationship, config, from_id, to_id, dimension)
	result["old_value"] = before
	result["new_value"] = before
	var edge := edge_between(relationship, from_id, to_id)
	if edge == null:
		if config.clamp_value(dimension, before + delta) == before:
			result["ok"] = true
			return result
		edge = relationship.create_edge(StringName(EDGE_ID_FORMAT % [from_id, to_id]),
			RelationshipEndpoint.for_character(from_id),
			RelationshipEndpoint.for_character(to_id), EDGE_TYPE, false, true)
		if edge == null:
			return result
	relationship.apply_delta(edge.id, dimension, delta, cause)
	result["ok"] = true
	result["new_value"] = read(relationship, config, from_id, to_id, dimension)
	return result

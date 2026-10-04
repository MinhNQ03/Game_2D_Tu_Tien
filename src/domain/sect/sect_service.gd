extends RefCounted
class_name SectService
## SectService — Aetheria domain (the single sect mutation path + observer).
##
## Owns a `SectStore` and is the ONLY way sect state changes (`docs/SECT_SYSTEM.md` §9): no
## caller edits a `SectState` array/dict directly. Every mutation validates the membership /
## economy invariants (§5–§7, §12), applies the change, keeps the derived caches in sync, and
## emits a domain signal so UI/other systems react without the service knowing them.
##
## Pure domain `RefCounted` — the signals are GDScript signals, NOT EventBus Node signals
## (`03-architecture.md`: domain must not depend on presentation/infra). Deterministic.
##
## MEMBERSHIP AUTHORITY (D-015): the Sect ROSTER is the source of truth. A character's
## `CharacterState.sect_id`/`sect_rank` is a DERIVED cache this service writes on
## join/leave/rank. `sync_character_cache()` rebuilds the cache FROM the roster (roster wins).
##
## CHARACTER SEAM (§11): the service does not reach into `/root` or the tree. It is given a
## `character_resolver` Callable `(StringName) -> CharacterState` (or null). It uses it to (a)
## reject joining a non-existent character, and (b) write the derived cache. A null resolver
## means "character checks disabled" (pure unit tests of roster logic without characters).
##
## RELATIONSHIP MIRROR (§14): alliances/enemies are mirrored to Sect↔Sect edges in the shared
## `RelationshipService`. A diplomacy mutation is TRANSACTIONAL across both stores: if the
## relationship mutation fails, the sect mutation is rolled back so the two never diverge.
##
## Templates (for rank-ladder validation) are REGISTERED in-memory alongside the state via
## `register_sect(state, template)` — the service never loads from disk, so it is fully
## testable with `.new()` content and has no `/root`/filesystem dependency.

## A member joined a sect at a rank.
signal member_joined(sect_id: StringName, character_id: StringName, rank_id: StringName)
## A member left a sect.
signal member_left(sect_id: StringName, character_id: StringName)
## A member's rank changed.
signal member_rank_changed(sect_id: StringName, character_id: StringName, rank_id: StringName)
## Leadership changed (new_leader may be &"" when cleared).
signal leader_changed(sect_id: StringName, new_leader: StringName)
## A resource quantity changed.
signal resource_changed(sect_id: StringName, resource_id: StringName, quantity: int)
## Reputation changed for a scope.
signal reputation_changed(sect_id: StringName, scope: StringName, value: int)
## Influence changed.
signal influence_changed(sect_id: StringName, value: int)
## A declared alliance/enmity changed (relation is &"ALLY"/&"ENEMY"/&"NONE").
signal diplomacy_changed(sect_id: StringName, other_sect_id: StringName, relation: StringName)

## Relationship edge types used for the Sect↔Sect mirror (§14).
const REL_TYPE_ALLY := &"ALLY"
const REL_TYPE_ENEMY := &"ENEMY"

var _store: SectStore = null
## RelationshipService used for the Sect↔Sect mirror. May be null (mirror disabled) only in
## narrow unit tests; a real session always provides it.
var _relationship: RelationshipService = null
## `(StringName character_id) -> CharacterState` (or null). See CHARACTER SEAM above.
var _character_resolver: Callable = Callable()
## sect_id(String) -> SectTemplateData (for rank-ladder validation). In-memory, no disk.
var _templates: Dictionary = {}


func _init(store: SectStore) -> void:
	_store = store


func get_store() -> SectStore:
	return _store


## The relationship graph store backing the Sect↔Sect mirror (or null if no mirror / no
## store). For tests + read-only inspection of mirrored edges.
func get_relationship_store() -> RelationshipStore:
	return _relationship.get_store() if _relationship != null else null


## Install the RelationshipService for the alliance/enemy mirror (§14).
func set_relationship_service(service: RelationshipService) -> void:
	_relationship = service


## Install the character resolver seam (§11). The Callable takes a StringName instance_id and
## returns a `CharacterState` (or null if that character does not exist).
func set_character_resolver(resolver: Callable) -> void:
	_character_resolver = resolver


# --- Sect registration -------------------------------------------------------

## Register a SectState (+ its template, for rank validation) into the store (the "create"
## path). Returns true on success; false (loud) on a null state/template or a duplicate id
## (the store reports). Does NOT mirror diplomacy yet — `apply_default_diplomacy()` runs once
## ALL sects are registered so both ends of each pair exist.
func register_sect(state: SectState, template: SectTemplateData) -> bool:
	if state == null:
		push_error("[sect] register_sect got null state")
		return false
	if template == null or not template.is_valid():
		push_error("[sect] register_sect '%s': null/invalid template"
			% (state.id if state else &""))
		return false
	if not _store.add(state):
		return false
	_templates[String(state.id)] = template
	return true


## After all sects are registered, mirror each sect's DECLARED allies/enemies into the
## relationship graph (§14). Idempotent: a pair already mirrored is skipped (no duplicate
## edge). Only mirrors a pair when BOTH sects exist (a dangling reference is skipped, not
## mirrored). Call once at session start.
func apply_default_diplomacy() -> void:
	if _relationship == null:
		return
	for sect in _store.all():
		var s := sect as SectState
		for ally in s.ally_sect_ids():
			if _store.has(ally):
				_ensure_edge(s.id, ally, REL_TYPE_ALLY)
		for enemy in s.enemy_sect_ids():
			if _store.has(enemy):
				_ensure_edge(s.id, enemy, REL_TYPE_ENEMY)


# --- Membership (the roster is authoritative, D-015) ------------------------

## A character joins `sect_id` at `rank_id` (defaults to the ladder's lowest rank when empty).
## Rejects (loud, false): unknown sect, unknown rank, a character already a member (duplicate
## join), a character the resolver cannot find (no fake character — §10), or a sect joining
## itself. On success writes the roster AND the character's derived cache, emits member_joined.
func join_member(
		sect_id: StringName, character_id: StringName, rank_id: StringName = &"") -> bool:
	var sect := _require_sect(sect_id, "join_member")
	if sect == null:
		return false
	if character_id == &"":
		push_error("[sect] join_member: empty character id")
		return false
	if StringName(String(character_id)) == sect_id:
		push_error("[sect] join_member: a sect cannot add itself as a member")
		return false
	if sect.is_member(character_id):
		push_error("[sect] join_member: '%s' already in sect '%s'" % [character_id, sect_id])
		return false
	var template := _template_for(sect)
	var resolved_rank := rank_id
	if resolved_rank == &"":
		var low := template.lowest_rank() if template != null else null
		resolved_rank = low.rank_id if low != null else &""
	if template == null or not template.has_rank(resolved_rank):
		push_error("[sect] join_member: rank '%s' not in sect '%s' ladder"
			% [resolved_rank, sect_id])
		return false
	# Character must exist (if a resolver is installed) — never invent a character (§10).
	if not _character_exists(character_id):
		push_error("[sect] join_member: character '%s' does not exist" % character_id)
		return false
	sect.write_member_rank(character_id, resolved_rank)
	_write_character_cache(character_id, sect_id, resolved_rank)
	member_joined.emit(sect_id, character_id, resolved_rank)
	return true


## A character leaves `sect_id`. Rejects (loud) an unknown sect or a non-member. Clears the
## character's derived cache. If the leaver was the leader, leadership is cleared (a later
## succession rule can reassign — Phase 07).
func leave_member(sect_id: StringName, character_id: StringName) -> bool:
	var sect := _require_sect(sect_id, "leave_member")
	if sect == null:
		return false
	if not sect.is_member(character_id):
		push_error("[sect] leave_member: '%s' not in sect '%s'" % [character_id, sect_id])
		return false
	var was_leader := sect.leader_ref == character_id
	sect.erase_member(character_id)
	_clear_character_cache(character_id)
	member_left.emit(sect_id, character_id)
	if was_leader:
		leader_changed.emit(sect_id, sect.leader_ref)
	return true


## Change a member's rank. Rejects (loud) unknown sect, non-member, or an unknown rank.
## Updates the derived cache + emits member_rank_changed.
func change_rank(sect_id: StringName, character_id: StringName, rank_id: StringName) -> bool:
	var sect := _require_sect(sect_id, "change_rank")
	if sect == null:
		return false
	if not sect.is_member(character_id):
		push_error("[sect] change_rank: '%s' not in sect '%s'" % [character_id, sect_id])
		return false
	var template := _template_for(sect)
	if template == null or not template.has_rank(rank_id):
		push_error("[sect] change_rank: rank '%s' not in sect '%s' ladder" % [rank_id, sect_id])
		return false
	sect.write_member_rank(character_id, rank_id)
	_write_character_cache(character_id, sect_id, rank_id)
	member_rank_changed.emit(sect_id, character_id, rank_id)
	return true


## Assign (or transfer) leadership to `character_id`, who MUST already be a member. The change
## is transactional: there is never more than one leader (the single `leader_ref` field) and a
## former leader stays a member at their current rank. Pass &"" to clear leadership. An elder
## promoted to leader is removed from the elder list (leader and elder are disjoint, §7).
func assign_leader(sect_id: StringName, character_id: StringName) -> bool:
	var sect := _require_sect(sect_id, "assign_leader")
	if sect == null:
		return false
	if character_id != &"" and not sect.is_member(character_id):
		push_error("[sect] assign_leader: '%s' not in sect '%s'" % [character_id, sect_id])
		return false
	if character_id != &"":
		sect.erase_elder(character_id)  # leader and elder are mutually exclusive
	sect.write_leader(character_id)
	leader_changed.emit(sect_id, character_id)
	return true


## Mark a member as an elder. Rejects (loud) unknown sect, non-member, or the current leader
## (leader and elder are disjoint, §7).
func assign_elder(sect_id: StringName, character_id: StringName) -> bool:
	var sect := _require_sect(sect_id, "assign_elder")
	if sect == null:
		return false
	if not sect.is_member(character_id):
		push_error("[sect] assign_elder: '%s' not in sect '%s'" % [character_id, sect_id])
		return false
	if sect.leader_ref == character_id:
		push_error("[sect] assign_elder: '%s' is the leader (cannot also be elder)" % character_id)
		return false
	sect.insert_elder(character_id)
	return true


## Remove a member's elder status (they stay a disciple). Rejects an unknown sect.
func remove_elder(sect_id: StringName, character_id: StringName) -> bool:
	var sect := _require_sect(sect_id, "remove_elder")
	if sect == null:
		return false
	sect.erase_elder(character_id)
	return true


# --- Economy / holdings (§12) ------------------------------------------------

## Add `delta` (may be negative) to `resource_id`, clamped at 0 (never negative, §12). Returns
## the new quantity, or -1 (loud) on an unknown sect. Emits resource_changed on a real change.
func adjust_resource(sect_id: StringName, resource_id: StringName, delta: int) -> int:
	var sect := _require_sect(sect_id, "adjust_resource")
	if sect == null:
		return -1
	if resource_id == &"":
		push_error("[sect] adjust_resource: empty resource id")
		return -1
	var old_value := sect.get_resource(resource_id)
	var new_value := maxi(0, old_value + delta)
	if new_value == old_value:
		return old_value
	sect.write_resource(resource_id, new_value)
	resource_changed.emit(sect_id, resource_id, new_value)
	return new_value


## Set reputation for `scope` (clamped to [-100, 100], §12). Emits on a real change. Loud +
## false on unknown sect.
func set_reputation(sect_id: StringName, scope: StringName, value: int) -> bool:
	var sect := _require_sect(sect_id, "set_reputation")
	if sect == null:
		return false
	if scope == &"":
		push_error("[sect] set_reputation: empty scope")
		return false
	var clamped := clampi(value, SectState.REP_MIN, SectState.REP_MAX)
	if clamped == sect.get_reputation(scope):
		return true
	sect.write_reputation(scope, clamped)
	reputation_changed.emit(sect_id, scope, clamped)
	return true


## Add `delta` to reputation for `scope` (clamped). Convenience over set_reputation.
func adjust_reputation(sect_id: StringName, scope: StringName, delta: int) -> bool:
	var sect := _require_sect(sect_id, "adjust_reputation")
	if sect == null:
		return false
	return set_reputation(sect_id, scope, sect.get_reputation(scope) + delta)


## Add `delta` to influence, clamped at 0 (never negative, §12). Emits on a real change.
func adjust_influence(sect_id: StringName, delta: int) -> int:
	var sect := _require_sect(sect_id, "adjust_influence")
	if sect == null:
		return -1
	var new_value := maxi(0, sect.influence + delta)
	if new_value == sect.influence:
		return sect.influence
	sect.influence = new_value
	influence_changed.emit(sect_id, new_value)
	return new_value


## Add a controlled region (unique). Loud + false on unknown sect or empty region id.
func add_territory(sect_id: StringName, region_id: StringName) -> bool:
	var sect := _require_sect(sect_id, "add_territory")
	if sect == null:
		return false
	if region_id == &"":
		push_error("[sect] add_territory: empty region id")
		return false
	sect.insert_territory(region_id)
	return true


## Remove a controlled region. Loud + false on unknown sect.
func remove_territory(sect_id: StringName, region_id: StringName) -> bool:
	var sect := _require_sect(sect_id, "remove_territory")
	if sect == null:
		return false
	sect.erase_territory(region_id)
	return true


# --- Diplomacy (transactional Sect↔Sect mirror, §14) ------------------------

## Declare `sect_id` and `other_sect_id` ALLIES. TRANSACTIONAL across the sect store + the
## relationship graph: the symmetric Sect↔Sect edge is created/retyped FIRST; only if that
## succeeds is the declared-ally state written on BOTH sects. If the relationship mutation
## fails, NOTHING changes in the sect store (§14 rollback). Rejects self-pairing, unknown
## sects, or a duplicate alliance.
func add_alliance(sect_id: StringName, other_sect_id: StringName) -> bool:
	return _set_diplomacy(sect_id, other_sect_id, REL_TYPE_ALLY)


## Declare two sects ENEMIES (same transactional contract as add_alliance).
func add_enemy(sect_id: StringName, other_sect_id: StringName) -> bool:
	return _set_diplomacy(sect_id, other_sect_id, REL_TYPE_ENEMY)


## Remove any declared alliance/enmity between the pair and drop the mirrored edge.
func clear_diplomacy(sect_id: StringName, other_sect_id: StringName) -> bool:
	var a := _require_sect(sect_id, "clear_diplomacy")
	var b := _require_sect(other_sect_id, "clear_diplomacy")
	if a == null or b == null:
		return false
	a.erase_ally(other_sect_id)
	a.erase_enemy(other_sect_id)
	b.erase_ally(sect_id)
	b.erase_enemy(sect_id)
	if _relationship != null:
		_relationship.remove_edge(edge_id(sect_id, other_sect_id))
	diplomacy_changed.emit(sect_id, other_sect_id, &"NONE")
	return true


func _set_diplomacy(sect_id: StringName, other_sect_id: StringName, relation: StringName) -> bool:
	var a := _require_sect(sect_id, "set_diplomacy")
	var b := _require_sect(other_sect_id, "set_diplomacy")
	if a == null or b == null:
		return false
	if sect_id == other_sect_id:
		push_error("[sect] diplomacy: a sect cannot ally/enemy itself ('%s')" % sect_id)
		return false
	var want_ally := relation == REL_TYPE_ALLY
	# Duplicate declaration guard.
	if want_ally and a.is_ally(other_sect_id):
		push_error("[sect] add_alliance: '%s' already allied with '%s'" % [sect_id, other_sect_id])
		return false
	if not want_ally and a.is_enemy(other_sect_id):
		push_error("[sect] add_enemy: '%s' already enemy of '%s'" % [sect_id, other_sect_id])
		return false

	# RELATIONSHIP FIRST (§14): create/retype the symmetric edge. If it fails, abort BEFORE
	# touching sect state, so the two stores never diverge.
	if _relationship != null and not _ensure_edge(sect_id, other_sect_id, relation):
		push_error("[sect] diplomacy rollback: relationship edge mutation failed for %s<->%s"
			% [sect_id, other_sect_id])
		return false

	# Sect state second: declared diplomacy is symmetric on both sects. Clear the opposite
	# relation first so a pair is never both ally and enemy.
	if want_ally:
		a.erase_enemy(other_sect_id)
		b.erase_enemy(sect_id)
		a.insert_ally(other_sect_id)
		b.insert_ally(sect_id)
	else:
		a.erase_ally(other_sect_id)
		b.erase_ally(sect_id)
		a.insert_enemy(other_sect_id)
		b.insert_enemy(sect_id)
	diplomacy_changed.emit(sect_id, other_sect_id, relation)
	return true


## Ensure a symmetric Sect↔Sect relationship edge of `relation` exists between the pair, with
## a deterministic stable id. If an edge already exists with a different type, it is removed
## and recreated with the new type (so ally→enemy flips cleanly). Returns false if the
## relationship service rejects creation. No duplicate edge for the same pair.
func _ensure_edge(sect_id: StringName, other_sect_id: StringName, relation: StringName) -> bool:
	if _relationship == null:
		return true
	var edge_id := edge_id(sect_id, other_sect_id)
	var store := _relationship.get_store()
	var existing: RelationshipEdge = store.get_edge(edge_id) if store != null else null
	if existing != null:
		if existing.relationship_type == relation:
			return true  # already the right edge; idempotent
		_relationship.remove_edge(edge_id)
	var from_ep := RelationshipEndpoint.for_sect(sect_id)
	var to_ep := RelationshipEndpoint.for_sect(other_sect_id)
	var edge := _relationship.create_edge(edge_id, from_ep, to_ep, relation, true, true)
	return edge != null


## Deterministic, stable edge id for a Sect↔Sect pair: endpoints sorted so A-B and B-A map to
## the SAME id (one edge per pair, §14).
static func edge_id(a: StringName, b: StringName) -> StringName:
	var sa := String(a)
	var sb := String(b)
	if sa <= sb:
		return StringName("sect_rel:%s|%s" % [sa, sb])
	return StringName("sect_rel:%s|%s" % [sb, sa])


# --- Character derived-cache sync (D-015) -----------------------------------

## Rebuild the derived cache (`CharacterState.sect_id`/`sect_rank`) for every member of every
## sect FROM the authoritative roster (roster wins, D-015). Call after hydrate or whenever the
## cache might have drifted. Characters the resolver cannot find are skipped (logged), not
## invented.
func sync_character_cache() -> void:
	if not _character_resolver.is_valid():
		return
	for sect in _store.all():
		var s := sect as SectState
		for member in s.member_refs():
			_write_character_cache(member, s.id, s.rank_of(member))


func _write_character_cache(
		character_id: StringName, sect_id: StringName, rank_id: StringName) -> void:
	if not _character_resolver.is_valid():
		return
	var cs: CharacterState = _character_resolver.call(character_id)
	if cs == null:
		push_warning("[sect] cache sync: character '%s' not resolvable" % character_id)
		return
	cs.sect_id = sect_id
	cs.sect_rank = rank_id


func _clear_character_cache(character_id: StringName) -> void:
	if not _character_resolver.is_valid():
		return
	var cs: CharacterState = _character_resolver.call(character_id)
	if cs == null:
		return
	cs.sect_id = &""
	cs.sect_rank = &""


func _character_exists(character_id: StringName) -> bool:
	# No resolver installed = character checks disabled (roster-only unit tests).
	if not _character_resolver.is_valid():
		return true
	return _character_resolver.call(character_id) != null


# --- Internal helpers --------------------------------------------------------

func _require_sect(sect_id: StringName, who: String) -> SectState:
	var sect := _store.get_sect(sect_id)
	if sect == null:
		push_error("[sect] %s: unknown sect '%s'" % [who, sect_id])
	return sect


## The registered SectTemplateData for a sect (for rank validation), or null (loud) if the
## sect was somehow added without a template.
func _template_for(sect: SectState) -> SectTemplateData:
	var template: SectTemplateData = _templates.get(String(sect.id))
	if template == null:
		push_error("[sect] no registered template for sect '%s'" % sect.id)
	return template

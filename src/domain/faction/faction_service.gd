extends RefCounted
class_name FactionService
## FactionService — Aetheria domain (the single faction mutation path + the politics rules).
##
## Owns a `FactionStore` and is the ONLY way faction state changes (`docs/SECT_SYSTEM.md` §7,
## D-042). Every mutation validates its invariants, applies the change, keeps the derived
## caches in sync, and emits a domain signal so UI and other systems react without this
## service knowing them.
##
## Pure domain `RefCounted`: GDScript signals, not EventBus (`03-architecture.md` — domain
## must not depend on infra/presentation). No Node, no `/root`, no filesystem.
##
## THREE SEAMS IT READS AND NEVER DUPLICATES
##   1. `SectStore` (read-only) — the single membership authority (D-015). A character may
##      only take a faction's side if the PARENT SECT's roster already lists them. This
##      service never adds anyone to a sect and never second-guesses the roster.
##   2. `RelationshipService` — the shared relationship graph. Faction↔Faction standing is an
##      EDGE there, carrying the six frozen dimensions and the history log (CL-12). There is
##      deliberately NO faction-side affinity/trust/respect/fear/rivalry/debt storage: a
##      second copy would be a second answer to "how does A feel about B", which is the exact
##      defect D-015 had to undo for sect membership. §7 left this representation open; D-042
##      pins it to the graph.
##   3. `character_resolver` — a `(StringName) -> CharacterState` Callable, so the service can
##      reject enrolling a character that does not exist and write the derived
##      `CharacterState.faction_id` cache WITHOUT reaching into `/root` or the tree (§11). A
##      null resolver means "character checks disabled" (pure roster unit tests).
##
## DETERMINISM (hard requirement, and Phase 07 must not anticipate Phase 08's RNG seam —
## D-040). Every rule below is a pure function of stored integers, and every ordering comes
## from an explicit sort with a documented tie-break. There is no `rand*()` call anywhere in
## this file, and none may be added: the politics outcomes are asserted in tests by exact
## value, and `dominant_faction_of` would otherwise return a different answer per run on a
## tie, making a save non-reproducible.

## A character took a faction's side.
signal member_joined(faction_id: StringName, character_id: StringName)
## A character left a faction.
signal member_left(faction_id: StringName, character_id: StringName)
## Faction leadership changed (new_leader may be &"" when cleared).
signal leader_changed(faction_id: StringName, new_leader: StringName)
## A faction's weight within its sect changed.
signal influence_changed(faction_id: StringName, value: int)
## A faction resource quantity changed.
signal resource_changed(faction_id: StringName, resource_id: StringName, quantity: int)
## A declared internal alignment changed (relation is &"ALLIED"/&"RIVAL"/&"NONE").
signal politics_changed(
	faction_id: StringName, other_faction_id: StringName, relation: StringName)

## Relationship edge types used for the Faction↔Faction mirror. Faction-owned, exactly as
## `SectService` owns `ALLY`/`ENEMY`: there is no central relationship-type registry, and a
## distinct vocabulary keeps a faction rivalry from being mistaken for a sect war when the
## graph is read generically.
const REL_TYPE_ALLIED := &"FACTION_ALLIED"
const REL_TYPE_RIVAL := &"FACTION_RIVAL"

## Edge-id namespace. MUST differ from `SectService`'s `"sect_rel:"` or the two mirrors would
## collide on a pair and `create_edge` would reject the second one as a duplicate id.
const EDGE_PREFIX := "faction_rel:"

## How close the top two factions' influence must be for a sect's politics to count as
## CONTESTED. A named constant, not a literal at the comparison site
## (`04-coding-standards.md` no magic numbers); the value is a design tuning knob and the one
## place to change it.
const CONTESTED_MARGIN := 10

var _store: FactionStore = null
## Read-only view of sect membership — the authority this service defers to (D-015). May be
## null only in narrow unit tests that exercise nothing membership-related.
var _sects: SectStore = null
## The shared relationship graph for the Faction↔Faction mirror. May be null ONLY in a
## landscape that declares no politics and mutates none — pure roster/influence work (D-047).
## Every politics path (`apply_default_politics`, `add_alliance`, `add_rivalry`,
## `clear_politics`) fails closed without it rather than skipping the mirror.
var _relationship: RelationshipService = null
## `(StringName character_id) -> CharacterState` (or null).
var _character_resolver: Callable = Callable()
## faction_id(String) -> FactionTemplateData (for goal validation + the view). In-memory.
var _templates: Dictionary = {}


func _init(store: FactionStore) -> void:
	_store = store


func get_store() -> FactionStore:
	return _store


## Install the read-only sect membership authority (D-015).
func set_sect_store(store: SectStore) -> void:
	_sects = store


## Install the RelationshipService backing the Faction↔Faction mirror.
func set_relationship_service(service: RelationshipService) -> void:
	_relationship = service


## Install the character resolver seam (§11).
func set_character_resolver(resolver: Callable) -> void:
	_character_resolver = resolver


## The relationship graph store backing the mirror (or null). For tests + read-only
## inspection of mirrored edges.
func get_relationship_store() -> RelationshipStore:
	return _relationship.get_store() if _relationship != null else null


## The registered template for a faction (or null, loud) — for goals + presentation.
func template_for(faction_id: StringName) -> FactionTemplateData:
	var template: FactionTemplateData = _templates.get(String(faction_id))
	if template == null:
		push_error("[faction] no registered template for faction '%s'" % faction_id)
	return template


# --- Registration ------------------------------------------------------------

## Register a FactionState (+ its template) into the store. Returns true on success; false
## (loud) on a null state/template, an invalid template, or a duplicate id (the store
## reports). Does NOT mirror politics yet — `apply_default_politics()` runs once ALL factions
## are registered so both ends of each declared pair exist.
func register_faction(state: FactionState, template: FactionTemplateData) -> bool:
	if state == null:
		push_error("[faction] register_faction got null state")
		return false
	if template == null or not template.is_valid():
		push_error("[faction] register_faction '%s': null/invalid template" % state.id)
		return false
	if state.parent_sect_id != template.parent_sect_id:
		push_error("[faction] register_faction '%s': state parent sect '%s' disagrees with "
			% [state.id, state.parent_sect_id]
			+ "template parent sect '%s'" % template.parent_sect_id)
		return false
	if not _store.add(state):
		return false
	_templates[String(state.id)] = template
	return true


## Every registered faction's parent sect must exist in the sect store, and no faction may
## claim a sect id as its own id. Returns false (loud) on the first violation.
##
## This is the cross-store check neither the catalog nor the store can perform: the catalog
## cannot see sects, and the store cannot either. It runs at session start and after hydrate,
## because a faction whose parent sect does not exist has no roster to draw members from and
## no sect whose politics it is part of — every later query about it would silently return
## empty rather than reporting the broken reference.
func validate_against_sects() -> bool:
	if _sects == null:
		push_error("[faction] validate_against_sects: no SectStore installed")
		return false
	for faction in _store.all():
		var f := faction as FactionState
		if not _sects.has(f.parent_sect_id):
			push_error("[faction] faction '%s' names unknown parent sect '%s'"
				% [f.id, f.parent_sect_id])
			return false
		if _sects.has(f.id):
			push_error("[faction] faction id '%s' collides with a sect id" % f.id)
			return false
	return true


## After all factions are registered, mirror each one's DECLARED allies/rivals into the
## relationship graph as symmetric Faction↔Faction edges. Idempotent. Call once at session
## start.
##
## FAILS CLOSED rather than degrading silently, for the reason D-038 recorded for sect
## diplomacy: a DANGLING declaration (a named faction not in the store) or a declaration with
## NO relationship service installed means the mirror is MISSING, not disabled — the faction
## state would claim a rivalry the graph has no record of, and the two stores would have
## diverged from the first frame. It also rejects a cross-sect declaration: internal politics
## stay inside one sect (the catalog checks this too, but a hydrated save never went through
## the catalog).
func apply_default_politics() -> bool:
	if _relationship == null:
		for faction in _store.all():
			var f0 := faction as FactionState
			if not f0.allied_faction_ids().is_empty() or not f0.rival_faction_ids().is_empty():
				push_error("[faction] apply_default_politics: faction '%s' declares politics "
					% f0.id + "but no RelationshipService is installed to mirror it into")
				return false
		return true
	for faction in _store.all():
		var f := faction as FactionState
		for other in f.allied_faction_ids():
			if not _mirror_declared(f, other, REL_TYPE_ALLIED):
				return false
		for other in f.rival_faction_ids():
			if not _mirror_declared(f, other, REL_TYPE_RIVAL):
				return false
	return true


func _mirror_declared(
		faction: FactionState, other: StringName, relation: StringName) -> bool:
	var other_state := _store.get_faction(other)
	if other_state == null:
		push_error("[faction] apply_default_politics: faction '%s' declares %s with unknown "
			% [faction.id, relation] + "faction '%s'" % other)
		return false
	if other_state.parent_sect_id != faction.parent_sect_id:
		push_error("[faction] apply_default_politics: '%s' (sect '%s') declares %s with '%s' "
			% [faction.id, faction.parent_sect_id, relation, other]
			+ "(sect '%s'): internal politics must stay inside one sect"
			% other_state.parent_sect_id)
		return false
	if not _ensure_edge(faction.id, other, relation):
		push_error("[faction] apply_default_politics: %s mirror failed for %s<->%s"
			% [relation, faction.id, other])
		return false
	return true


# --- Membership (the SECT roster is the authority, D-015) -------------------

## `character_id` takes `faction_id`'s side.
##
## Rejects (loud, false): unknown faction; empty character id; a character the resolver cannot
## find (§10 — never invent a character); a character who is NOT on the parent sect's roster;
## a character already in this faction; and a character already holding a seat in ANOTHER
## faction of the same sect.
##
## The sect-roster check is the heart of this method. A faction is a group INSIDE a sect, so
## "member of the Reform faction but not of Thanh Vân Tông" is not a state the world can hold
## — and allowing it would make `FactionState._member_refs` an independent membership source
## competing with the roster, which is precisely what D-015 settled. The one-seat-per-sect
## rule is what keeps `CharacterState.faction_id` a valid single value rather than a list.
func join_member(faction_id: StringName, character_id: StringName) -> bool:
	var faction := _require_faction(faction_id, "join_member")
	if faction == null:
		return false
	if character_id == &"":
		push_error("[faction] join_member: empty character id")
		return false
	if not _character_exists(character_id):
		push_error("[faction] join_member: character '%s' does not exist" % character_id)
		return false
	if _sects == null:
		push_error("[faction] join_member: no SectStore installed, so membership in the "
			+ "parent sect cannot be verified; refusing to enrol")
		return false
	var sect := _sects.get_sect(faction.parent_sect_id)
	if sect == null:
		push_error("[faction] join_member '%s': parent sect '%s' is not in the sect store"
			% [faction_id, faction.parent_sect_id])
		return false
	if not sect.is_member(character_id):
		push_error("[faction] join_member: '%s' is not a member of sect '%s', so they cannot "
			% [character_id, faction.parent_sect_id]
			+ "take a side inside it (the sect roster is the membership authority, D-015)")
		return false
	if faction.is_member(character_id):
		push_error("[faction] join_member: '%s' already in faction '%s'"
			% [character_id, faction_id])
		return false
	var held := _store.faction_of_member(faction.parent_sect_id, character_id)
	if held != null:
		push_error("[faction] join_member: '%s' already holds a seat in faction '%s' of sect "
			% [character_id, held.id]
			+ "'%s'; leave it first (one faction per sect)" % faction.parent_sect_id)
		return false
	faction.insert_member(character_id)
	_write_character_cache(character_id, faction_id)
	member_joined.emit(faction_id, character_id)
	return true


## `character_id` leaves `faction_id`. Rejects (loud) an unknown faction or a non-member.
## Clears the character's derived cache. If the leaver was the leader, leadership is cleared.
func leave_member(faction_id: StringName, character_id: StringName) -> bool:
	var faction := _require_faction(faction_id, "leave_member")
	if faction == null:
		return false
	if not faction.is_member(character_id):
		push_error("[faction] leave_member: '%s' not in faction '%s'"
			% [character_id, faction_id])
		return false
	var was_leader := faction.leader_ref == character_id
	faction.erase_member(character_id)
	_clear_character_cache(character_id)
	member_left.emit(faction_id, character_id)
	if was_leader:
		leader_changed.emit(faction_id, faction.leader_ref)
	return true


## Assign (or clear, with &"") a faction's leader. The leader MUST already be a member of
## that faction — leadership is drawn from the people who took its side, never imposed from
## outside, and an outside leader would also be invisible to `member_refs()`.
func assign_leader(faction_id: StringName, character_id: StringName) -> bool:
	var faction := _require_faction(faction_id, "assign_leader")
	if faction == null:
		return false
	if character_id == &"":
		if faction.leader_ref == &"":
			return true  # idempotent: already leaderless, no fake change event
		faction.write_leader(&"")
		leader_changed.emit(faction_id, &"")
		return true
	if not faction.is_member(character_id):
		push_error("[faction] assign_leader: '%s' is not a member of faction '%s'"
			% [character_id, faction_id])
		return false
	if faction.leader_ref == character_id:
		return true  # idempotent
	faction.write_leader(character_id)
	leader_changed.emit(faction_id, character_id)
	return true


# --- Politics mutation -------------------------------------------------------

## Move a faction's influence by `delta`, clamped to [INFLUENCE_MIN, INFLUENCE_MAX]. Returns
## the new value, or -1 on an unknown faction. No signal when the clamped value is unchanged
## (a no-op is not an event — the same rule the sect economy mutators follow).
func adjust_influence(faction_id: StringName, delta: int) -> int:
	var faction := _require_faction(faction_id, "adjust_influence")
	if faction == null:
		return -1
	var before := faction.influence
	faction.write_influence(before + delta)
	if faction.influence != before:
		influence_changed.emit(faction_id, faction.influence)
	return faction.influence


## Set a faction resource to an absolute quantity (floored at 0). Returns the new quantity, or
## -1 on an unknown faction. No signal when unchanged.
func set_resource(faction_id: StringName, resource_id: StringName, quantity: int) -> int:
	var faction := _require_faction(faction_id, "set_resource")
	if faction == null:
		return -1
	if resource_id == &"":
		push_error("[faction] set_resource '%s': empty resource id" % faction_id)
		return -1
	var before := faction.get_resource(resource_id)
	faction.write_resource(resource_id, quantity)
	var after := faction.get_resource(resource_id)
	if after != before:
		resource_changed.emit(faction_id, resource_id, after)
	return after


## Declare two factions of the SAME sect ALLIED. Transactional across the faction store and
## the relationship graph, in that order of safety: the symmetric edge is created/retyped
## FIRST and the faction-side declarations are written only if that succeeded, so a rejected
## mirror leaves nothing changed (L-023 / the §14 rollback contract).
##
## REQUIRES a `RelationshipService` and fails closed without one (D-047) — see `_set_politics`.
func add_alliance(faction_id: StringName, other_faction_id: StringName) -> bool:
	return _set_politics(faction_id, other_faction_id, REL_TYPE_ALLIED)


## Declare two factions of the same sect RIVALS (same transactional + fail-closed contract).
func add_rivalry(faction_id: StringName, other_faction_id: StringName) -> bool:
	return _set_politics(faction_id, other_faction_id, REL_TYPE_RIVAL)


## Clear any declared alignment between the pair and drop the mirrored edge.
##
## RELATIONSHIP FIRST, with its result CHECKED, then the faction side — so the two can never
## diverge. Outcomes:
##   * nothing declared on either side -> idempotent true, the graph is not read or written
##     (so an unrelated edge authored by another system is never touched), and NO signal,
##     because nothing changed;
##   * declared and cleanly mirrored -> edge removed, then both declarations cleared, then
##     `politics_changed(..., NONE)`;
##   * declared but NOT cleanly unmirrorable -> false with NOTHING mutated and no signal.
##     That covers: no relationship service, the expected edge missing, the edge carrying a
##     type this mirror does not own, and the two factions disagreeing about the relation.
##
## An edge of an UNRELATED type is left alone rather than deleted: this mirror only owns the
## FACTION_ALLIED/FACTION_RIVAL edges it created, and destroying another system's graph data
## to satisfy a faction-side clear would be worse than refusing.
func clear_politics(faction_id: StringName, other_faction_id: StringName) -> bool:
	var a := _require_faction(faction_id, "clear_politics")
	var b := _require_faction(other_faction_id, "clear_politics")
	if a == null or b == null:
		return false

	var a_allied := a.is_allied_with(other_faction_id)
	var a_rival := a.is_rival_of(other_faction_id)
	var b_allied := b.is_allied_with(faction_id)
	var b_rival := b.is_rival_of(faction_id)
	if not (a_allied or a_rival or b_allied or b_rival):
		return true  # nothing declared: idempotent no-op, graph untouched

	if a_allied != b_allied or a_rival != b_rival:
		push_error("[faction] clear_politics '%s'<->'%s': the two factions disagree about the "
			% [faction_id, other_faction_id]
			+ "declared relation (allied %s/%s, rival %s/%s); refusing to clear"
			% [a_allied, b_allied, a_rival, b_rival])
		return false

	var declared: StringName = REL_TYPE_ALLIED if a_allied else REL_TYPE_RIVAL
	if _relationship == null:
		push_error("[faction] clear_politics '%s'<->'%s': '%s' is declared but no "
			% [faction_id, other_faction_id, declared]
			+ "RelationshipService is installed to unmirror it; refusing to clear")
		return false
	var eid := edge_id(faction_id, other_faction_id)
	var store := _relationship.get_store()
	var existing: RelationshipEdge = store.get_edge(eid) if store != null else null
	if existing == null:
		push_error("[faction] clear_politics '%s'<->'%s': '%s' is declared but the mirrored "
			% [faction_id, other_faction_id, declared]
			+ "edge '%s' is missing; refusing to clear" % eid)
		return false
	if existing.relationship_type != declared:
		push_error("[faction] clear_politics '%s'<->'%s': edge '%s' carries type '%s', not the "
			% [faction_id, other_faction_id, eid, existing.relationship_type]
			+ "declared '%s'; refusing to destroy unrelated graph state" % declared)
		return false
	if not _relationship.remove_edge(eid):
		push_error("[faction] clear_politics '%s'<->'%s': removing the mirrored edge '%s' was "
			% [faction_id, other_faction_id, eid] + "rejected; faction state left unchanged")
		return false

	a.erase_allied(other_faction_id)
	a.erase_rival(other_faction_id)
	b.erase_allied(faction_id)
	b.erase_rival(faction_id)
	politics_changed.emit(faction_id, other_faction_id, &"NONE")
	return true


## The single politics-mutation path behind `add_alliance()` / `add_rivalry()`.
##
## FAILS CLOSED WITHOUT THE GRAPH (D-047). Declared faction politics and the mirrored
## Faction↔Faction relationship edge are one fact stored in two places, so the mirror is not an
## optional decoration on a mutation — it is half of it. This used to let a null
## `RelationshipService` mean "skip the mirror and succeed anyway": the faction state then
## recorded a rivalry that the graph had no edge for, the two stores were divergent from that
## moment on, and `clear_politics()` could never undo it (it fails closed, correctly, on
## exactly that state — so the pair was stuck declared forever). Every gate was green because
## the call returned `true`.
##
## It is the same hole D-038 closed in `apply_default_politics()` and D-037/L-025 closed in the
## session starters, reached through a different door: "the dependency is absent, so the step
## is skipped" is only legitimate when it is genuinely legal for the dependency to be absent.
## For a politics MUTATION it never is. The one remaining legitimate no-RelationshipService
## landscape is unchanged: a session or unit test that declares no politics and mutates none —
## pure roster/influence work, which touches no edge.
func _set_politics(
		faction_id: StringName, other_faction_id: StringName, relation: StringName) -> bool:
	var a := _require_faction(faction_id, "set_politics")
	var b := _require_faction(other_faction_id, "set_politics")
	if a == null or b == null:
		return false
	if faction_id == other_faction_id:
		push_error("[faction] politics: a faction cannot align with itself ('%s')" % faction_id)
		return false
	if a.parent_sect_id != b.parent_sect_id:
		push_error("[faction] politics: '%s' (sect '%s') and '%s' (sect '%s') are in different "
			% [faction_id, a.parent_sect_id, other_faction_id, b.parent_sect_id]
			+ "sects; internal politics must stay inside one sect")
		return false
	# The graph is a PRECONDITION of the mutation, checked before any other rule so the
	# rejection reason is the missing mirror rather than an incidental duplicate-declaration
	# hit. Nothing below this point can run without somewhere to mirror into.
	if _relationship == null:
		push_error("[faction] politics '%s'<->'%s': no RelationshipService is installed, so "
			% [faction_id, other_faction_id]
			+ "'%s' could not be mirrored into the relationship graph; refusing to declare "
			% relation + "it (declared politics and the mirrored edge are one fact, D-042)")
		return false
	var want_allied := relation == REL_TYPE_ALLIED
	if want_allied and a.is_allied_with(other_faction_id):
		push_error("[faction] add_alliance: '%s' already allied with '%s'"
			% [faction_id, other_faction_id])
		return false
	if not want_allied and a.is_rival_of(other_faction_id):
		push_error("[faction] add_rivalry: '%s' already rival of '%s'"
			% [faction_id, other_faction_id])
		return false

	# RELATIONSHIP FIRST. If it fails, abort BEFORE touching faction state.
	if not _ensure_edge(faction_id, other_faction_id, relation):
		push_error("[faction] politics rollback: relationship edge mutation failed for %s<->%s"
			% [faction_id, other_faction_id])
		return false

	# Faction state second, symmetric on both sides. Clear the opposite relation first so a
	# pair is never both allied and rival.
	if want_allied:
		a.erase_rival(other_faction_id)
		b.erase_rival(faction_id)
		a.insert_allied(other_faction_id)
		b.insert_allied(faction_id)
	else:
		a.erase_allied(other_faction_id)
		b.erase_allied(faction_id)
		a.insert_rival(other_faction_id)
		b.insert_rival(faction_id)
	politics_changed.emit(faction_id, other_faction_id, relation)
	return true


## Ensure a symmetric Faction↔Faction edge of `relation` exists for the pair.
##
## NON-DESTRUCTIVE BY CONTRACT (L-023): an existing edge of the WRONG type is RETYPED IN
## PLACE via `RelationshipService.set_relationship_type()`, never removed and recreated.
## Remove-then-create destroys the edge on the first leg, so a failure on the create leg
## leaves no edge at all — the caller's "rollback" then restores the faction side while the
## edge's dimensions and history are already gone. Retyping means a rejected mutation leaves
## the previous edge fully intact: same id, endpoints, symmetric/known flags, every dimension
## value and the whole history.
##
## A missing `RelationshipService` is a FAILURE here, not a skip (D-047). Both callers already
## refuse to proceed without one, so this is defence in depth: the previous `return true` was
## the mechanism by which a mutation could report success while performing only its
## faction-side half, and leaving it in place would let a future third caller reopen that hole
## without touching this function.
func _ensure_edge(
		faction_id: StringName, other_faction_id: StringName, relation: StringName) -> bool:
	if _relationship == null:
		push_error("[faction] _ensure_edge %s<->%s: no RelationshipService installed; a "
			% [faction_id, other_faction_id]
			+ "politics mirror cannot be skipped, so this fails rather than reporting success")
		return false
	var eid := edge_id(faction_id, other_faction_id)
	var store := _relationship.get_store()
	var existing: RelationshipEdge = store.get_edge(eid) if store != null else null
	if existing != null:
		if existing.relationship_type == relation:
			return true  # already the right edge; idempotent
		return _relationship.set_relationship_type(eid, relation)
	var from_ep := RelationshipEndpoint.for_faction(faction_id)
	var to_ep := RelationshipEndpoint.for_faction(other_faction_id)
	var edge := _relationship.create_edge(eid, from_ep, to_ep, relation, true, true)
	return edge != null


## Deterministic, stable edge id for a Faction↔Faction pair: endpoints sorted so A-B and B-A
## map to the SAME id (one edge per pair). Namespaced so it can never collide with the sect
## mirror's `"sect_rel:"` ids.
static func edge_id(a: StringName, b: StringName) -> StringName:
	var sa := String(a)
	var sb := String(b)
	if sa <= sb:
		return StringName("%s%s|%s" % [EDGE_PREFIX, sa, sb])
	return StringName("%s%s|%s" % [EDGE_PREFIX, sb, sa])


# --- Derived politics rules (DETERMINISTIC; pure reads) ---------------------
#
# These are the "rules over data" §7 asks for, and they are the reason influence is a bounded
# weight rather than an open-ended score. Each is a pure function of stored integers with an
# explicit tie-break, so the same faction landscape always yields the same answer — which is
# what makes a save reproducible and these outcomes assertable by exact value in tests.

## Total declared influence of every faction in `sect_id` (0 when the sect has none).
func total_influence_of_sect(sect_id: StringName) -> int:
	var total := 0
	for faction in _store.factions_of_sect(sect_id):
		total += (faction as FactionState).influence
	return total


## `faction_id`'s share of its parent sect's total faction influence, as an integer percent in
## [0, 100]. Returns 0 for an unknown faction or when the sect's factions all sit at 0
## influence (nobody holds sway, so nobody has a share — not a division by zero).
##
## Integer arithmetic with explicit rounding, never a float: a float share would make the
## serialized/compared value platform-dependent at the last bit, and these numbers are
## asserted exactly and shown to the player.
func influence_share(faction_id: StringName) -> int:
	var faction := _store.get_faction(faction_id)
	if faction == null:
		return 0
	var total := total_influence_of_sect(faction.parent_sect_id)
	if total <= 0:
		return 0
	return roundi(float(faction.influence) * 100.0 / float(total))


## The faction currently holding the most sway in `sect_id`, or null when the sect has no
## factions or they all sit at 0 influence.
##
## TIE-BREAK: equal influence resolves to the lexicographically smaller faction id. An
## arbitrary-but-FIXED rule is the point — without it, two factions at equal influence would
## return whichever the store happened to iterate first, so "who leads the sect" could change
## between runs on identical data and a reloaded save could disagree with the save it came
## from. The tie-break is not a judgement about which faction deserves to win; `is_contested`
## is how a caller asks whether the lead is actually meaningful.
func dominant_faction_of(sect_id: StringName) -> FactionState:
	var best: FactionState = null
	for faction in _store.factions_of_sect(sect_id):
		var f := faction as FactionState
		if f.influence <= 0:
			continue
		if best == null:
			best = f
			continue
		if f.influence > best.influence:
			best = f
		elif f.influence == best.influence and String(f.id) < String(best.id):
			best = f
	return best


## True when the top two factions in `sect_id` are within `CONTESTED_MARGIN` influence of each
## other — i.e. the sect's direction is genuinely in dispute rather than settled.
##
## A sect with fewer than two factions at non-zero influence is NOT contested: there is no
## second party to contest it.
func is_contested(sect_id: StringName) -> bool:
	var top := 0
	var second := 0
	for faction in _store.factions_of_sect(sect_id):
		var value := (faction as FactionState).influence
		if value <= 0:
			continue
		if value > top:
			second = top
			top = value
		elif value > second:
			second = value
	if top <= 0 or second <= 0:
		return false
	return (top - second) <= CONTESTED_MARGIN


## The faction (within `sect_id`) that `character_id` has taken the side of, or null.
func faction_of(sect_id: StringName, character_id: StringName) -> FactionState:
	return _store.faction_of_member(sect_id, character_id)


# --- Character derived-cache sync (mirrors D-015 for faction_id) ------------

## Rebuild `CharacterState.faction_id` for every faction member FROM the authoritative faction
## rosters. Call after hydrate or whenever the cache might have drifted; the roster wins.
##
## It deliberately does NOT clear the cache of characters who are in no faction: this service
## does not know the full character population (there is no CharacterRegistry until §11/P-17),
## so it can only correct the characters it can see. A character whose cache names a faction
## they are not in is caught by `verify_character_cache()` instead, which the session start
## calls — reporting the drift rather than silently papering over it.
func sync_character_cache() -> void:
	if not _character_resolver.is_valid():
		return
	for faction in _store.all():
		var f := faction as FactionState
		for member in f.member_refs():
			_write_character_cache(member, f.id)


## True when every faction member's derived `CharacterState.faction_id` agrees with the
## authoritative roster. Reports each disagreement loudly. Used by the session start as a
## post-condition, the same way `SectRuntime` verifies the sect cache.
func verify_character_cache() -> bool:
	if not _character_resolver.is_valid():
		return true  # character checks disabled; nothing to verify against
	var consistent := true
	for faction in _store.all():
		var f := faction as FactionState
		for member in f.member_refs():
			var cs: CharacterState = _character_resolver.call(member)
			if cs == null:
				push_error("[faction] cache check: member '%s' of '%s' does not resolve"
					% [member, f.id])
				consistent = false
				continue
			if cs.faction_id != f.id:
				push_error("[faction] cache check: '%s' is in faction '%s' but their cache "
					% [member, f.id] + "says '%s'" % cs.faction_id)
				consistent = false
	return consistent


func _write_character_cache(character_id: StringName, faction_id: StringName) -> void:
	if not _character_resolver.is_valid():
		return
	var cs: CharacterState = _character_resolver.call(character_id)
	if cs == null:
		push_warning("[faction] cache sync: character '%s' not resolvable" % character_id)
		return
	cs.faction_id = faction_id


func _clear_character_cache(character_id: StringName) -> void:
	if not _character_resolver.is_valid():
		return
	var cs: CharacterState = _character_resolver.call(character_id)
	if cs == null:
		return
	cs.faction_id = &""


func _character_exists(character_id: StringName) -> bool:
	# No resolver installed = character checks disabled (roster-only unit tests).
	if not _character_resolver.is_valid():
		return true
	return _character_resolver.call(character_id) != null


# --- Internal helpers --------------------------------------------------------

func _require_faction(faction_id: StringName, who: String) -> FactionState:
	var faction := _store.get_faction(faction_id)
	if faction == null:
		push_error("[faction] %s: unknown faction '%s'" % [who, faction_id])
	return faction

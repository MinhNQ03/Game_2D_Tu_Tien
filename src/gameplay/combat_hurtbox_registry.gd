extends RefCounted
class_name CombatHurtboxRegistry
## CombatHurtboxRegistry — Aetheria GAMEPLAY (who can be hit right now, Phase 09).
##
## The session's answer to "what targets exist". An attacker asks this instead of asking the
## physics engine, which is what makes combat resolvable — and testable — without a physics
## frame (D-007; see the note in `collision_layers.gd` for why no sensor layers exist).
##
## IT LIVES IN `gameplay`, NOT `domain`, AND THAT PLACEMENT IS THE POINT. Its whole API is
## typed on `HurtboxComponent`, which is a `Node`. A domain class referring to a node type is
## an UPWARD dependency — `03-architecture.md` is explicit that dependencies point downward
## only — and it shipped in `src/domain/combat/` for exactly as long as it took the review
## pass to read the import list. The distinction is worth stating because it is the seam that
## keeps the rest of combat clean: `CombatService`, `AttackStateMachine` and `DamageRules` are
## genuinely domain (plain vectors, dictionaries and Resources, no node anywhere), and they
## stay testable headless because of it. This class is the gameplay-side collection that feeds
## them, so it is the right place for the node types to appear — and the wrong place for any
## combat RULE to appear.
##
## It is the combat twin of `CharacterRegistry` (Phase 08): one collection that owns the
## answer to an existence question, so no other system has to keep a parallel list and the two
## cannot disagree. `WorldRuntime` owning a set of live characters and combat owning a second,
## separately-maintained set of live targets is exactly the kind of duplicated truth D-015
## exists to prevent.
##
## ORDER IS DETERMINISTIC. `targets()` returns entries sorted by `entity_id`, never in
## registration order. That matters more than it looks: `CombatService` draws one random value
## per target it hits, so an order that depended on which entity happened to enter the tree
## first would make the crit sequence depend on scene load order — and a replay from a seed
## would diverge from the run it replayed.
##
## IT HOLDS NO OWNERSHIP. Entries are registered and unregistered by the hurtboxes themselves
## on tree enter/exit, and the registry never frees anything. A registry that freed its
## members would be a second owner of nodes the scene tree already owns.

## entity_id(String) -> HurtboxComponent. Keyed by id rather than stored as a list so a
## double registration is impossible by construction instead of by a scan.
var _entries: Dictionary = {}


## Add a hurtbox. Rejects an id-less or duplicate registration LOUDLY: a duplicate would make
## one entity get hit twice per swing, which reads as random double damage.
func register(hurtbox: HurtboxComponent) -> bool:
	if hurtbox == null:
		push_error("[combat-registry] refusing to register a null hurtbox")
		return false
	var key := String(hurtbox.entity_id)
	if key == "":
		push_error("[combat-registry] refusing to register a hurtbox with no entity_id")
		return false
	var existing: HurtboxComponent = _entries.get(key)
	if existing != null and existing != hurtbox:
		push_error(("[combat-registry] '%s' is already registered by a different hurtbox; "
			+ "two hurtboxes with one id would take two hits per swing") % key)
		return false
	_entries[key] = hurtbox
	return true


## Remove a hurtbox. Removing one that was never registered is a no-op, not an error: a node
## leaving the tree after a failed registration is normal teardown, and a loud complaint there
## would fire on every shutdown.
func unregister(hurtbox: HurtboxComponent) -> void:
	if hurtbox == null:
		return
	var key := String(hurtbox.entity_id)
	if _entries.get(key) == hurtbox:
		_entries.erase(key)


func has(entity_id: StringName) -> bool:
	return _entries.has(String(entity_id))


func get_hurtbox(entity_id: StringName) -> HurtboxComponent:
	return _entries.get(String(entity_id))


## How many hurtboxes are registered, including any whose entity has since been freed.
## `targets()` is the number that can actually be hit.
func size() -> int:
	return _entries.size()


## Every TARGETABLE hurtbox, sorted by entity id. Entries whose entity is gone or dead are
## skipped — and a stale entry (entity freed without its hurtbox leaving the tree) is dropped
## here rather than left to produce a hit on something that no longer exists.
func targetable(exclude_id: StringName = &"") -> Array[HurtboxComponent]:
	var out: Array[HurtboxComponent] = []
	var keys: Array = _entries.keys()
	keys.sort()
	var stale: Array[String] = []
	for key in keys:
		var hurtbox: HurtboxComponent = _entries[key]
		if hurtbox == null or not is_instance_valid(hurtbox):
			stale.append(String(key))
			continue
		if String(key) == String(exclude_id):
			continue
		if not hurtbox.is_targetable():
			continue
		out.append(hurtbox)
	for key in stale:
		_entries.erase(key)
	return out


## The target records `CombatService.resolve_hit()` consumes, in the same deterministic order.
##
## `exclude_id` keeps an attacker out of its own swing. That is not a convenience: without it
## every attack would hit the attacker, because the attacker is always within its own reach.
func targets(exclude_id: StringName = &"") -> Array:
	var out: Array = []
	for hurtbox in targetable(exclude_id):
		out.append(hurtbox.to_target())
	return out


## Drop every entry. For session teardown: the registry is per-session, and a registry that
## outlived its session would hand the next one targets from the last.
func clear() -> void:
	_entries.clear()

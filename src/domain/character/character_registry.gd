extends RefCounted
class_name CharacterRegistry
## CharacterRegistry — Aetheria domain (the session's character population, by instance id).
##
## The piece `docs/CHARACTER_SYSTEM.md` §10 listed as missing: "the character registry implied
## by a multi-character world". Phase 08 is the phase that implies it — a world simulation
## with one character in it is not a world — so it lands here, as the smallest thing that
## satisfies the need.
##
## WHAT IT IS: a keyed collection of authoritative `CharacterState`s and ONE resolver source.
## `SectService` and `FactionService` already depend on a `(StringName) -> CharacterState`
## resolver seam so they can validate membership and maintain the derived
## `CharacterState.sect_id`/`faction_id` caches without reaching into `/root` (§11). Before
## this class, the bootstrap satisfied that seam with two hand-written lambdas that each knew
## about exactly one character — the player — which was correct while the player was the only
## character and becomes wrong the moment the world has a cast.
##
## WHAT IT IS NOT: a manager, and not a system that decides anything. It stores, finds and
## serializes; it has no rules, emits no signals, and knows nothing about sects, factions,
## simulation or presentation. The authority over a character's FIELDS stays where it already
## is — the sect roster owns membership (D-015), the simulation owns `sim_state`, combat will
## own current HP — and this collection owns only "who exists".
##
## It maps directly onto `docs/SAVE_FORMAT.md`'s `characters.by_instance_id` + the separate
## `player_instance_id`, which is why `add()` takes no notion of a "main" character: being the
## player is a fact the session holds, not a property of a row in this table.

## instance_id(String) -> CharacterState.
var _by_id: Dictionary = {}


## Register `state`. Returns false (loud) on null, an empty instance id, or a duplicate —
## never silently replacing an existing character, because a replaced `CharacterState` would
## leave every component and service still holding the OLD object while the registry answered
## with the new one. Two live answers to "who is this" is the exact defect this class exists
## to prevent.
func add(state: CharacterState) -> bool:
	if state == null:
		push_error("[characters] add got null state")
		return false
	if state.instance_id == &"":
		push_error("[characters] add: state has an empty instance_id")
		return false
	var key := String(state.instance_id)
	if _by_id.has(key):
		push_error("[characters] add: '%s' is already registered; replacing a live "
			% key + "CharacterState would leave two answers to who that character is")
		return false
	_by_id[key] = state
	return true


## Remove a character. Returns true if one was removed. Deliberately present and deliberately
## unused by Phase 08: a character LEAVING the world is a life-state change
## (`CharacterState.life_state` = DEAD/MISSING/ASCENDED), not a deletion — the world remembers
## the dead. This exists for session teardown and hydrate-replacement only.
func remove(instance_id: StringName) -> bool:
	return _by_id.erase(String(instance_id))


func has(instance_id: StringName) -> bool:
	return _by_id.has(String(instance_id))


## The authoritative state for `instance_id`, or null. QUIET on a miss: this is the shape the
## service resolver seam expects ("null means no such character, reject the operation"), so a
## miss is a normal answer here and the CALLER reports it with its own context.
func get_character(instance_id: StringName) -> CharacterState:
	return _by_id.get(String(instance_id))


func count() -> int:
	return _by_id.size()


## Every registered instance id, sorted — so any iteration over the population is
## deterministic regardless of registration order.
func ids_sorted() -> Array[StringName]:
	var keys: Array = _by_id.keys()
	keys.sort()
	var out: Array[StringName] = []
	for key in keys:
		out.append(StringName(String(key)))
	return out


## Every registered character, in sorted id order.
func all() -> Array[CharacterState]:
	var out: Array[CharacterState] = []
	for instance_id in ids_sorted():
		out.append(_by_id[String(instance_id)])
	return out


## A `(StringName) -> CharacterState` Callable over this registry — the resolver seam
## `SectService.set_character_resolver` / `FactionService.set_character_resolver` /
## `WorldSimulationService.set_character_resolver` take.
##
## Handing out ONE resolver backed by ONE collection is the point: the alternative (each
## caller writing its own lambda) is how the bootstrap ended up with two closures that each
## knew about a single character, so a service could reject a character that demonstrably
## existed. The Callable captures `self`, so anything that STORES it keeps this registry alive
## — a test that holds the resolver on a field must clear it in `after_each`, or the capture
## closes a reference cycle that GDScript's reference counting will never collect (L-030).
func resolver() -> Callable:
	return func(instance_id: StringName) -> CharacterState:
		return get_character(instance_id)


# --- Serialization (`docs/SAVE_FORMAT.md` characters.by_instance_id) ---------

## Serialize every character's persistent tier, keyed by instance id (sorted for a byte-stable
## snapshot).
func to_dict() -> Dictionary:
	var by_instance_id := {}
	for instance_id in ids_sorted():
		var state: CharacterState = _by_id[String(instance_id)]
		by_instance_id[String(instance_id)] = state.to_dict()
	return {"by_instance_id": by_instance_id}


## Replace the population from a snapshot, ATOMICALLY: every row is parsed into a staging
## table and the registry is only written once all of them validated, so a rejected payload
## leaves the existing population untouched rather than half-replaced (L-024).
func hydrate(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[characters] hydrate: payload is not a Dictionary")
		return false
	var rows: Variant = (data as Dictionary).get("by_instance_id", null)
	if typeof(rows) != TYPE_DICTIONARY:
		push_error("[characters] hydrate: 'by_instance_id' is not a Dictionary")
		return false
	var staged := {}
	var keys: Array = (rows as Dictionary).keys()
	keys.sort()
	for key in keys:
		var key_type := typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME:
			push_error("[characters] hydrate: instance id key must be a String/StringName "
				+ "(got %s)" % type_string(key_type))
			return false
		# The ROW's type is checked here rather than left to `CharacterState.from_dict`,
		# because that method's parameter is statically typed `Dictionary`: passing an int
		# would be a GDScript VM error, which ABORTS the calling function instead of returning
		# false — so a corrupt save would crash the load path rather than fail it closed, and
		# in a test it would be silently reported as a pass (L-026).
		var row: Variant = (rows as Dictionary)[key]
		if typeof(row) != TYPE_DICTIONARY:
			push_error("[characters] hydrate: row '%s' is not a Dictionary (got %s)"
				% [String(key), type_string(typeof(row))])
			return false
		var state := CharacterState.new()
		if not state.from_dict(row):
			push_error("[characters] hydrate: row '%s' is malformed" % String(key))
			return false
		if String(state.instance_id) != String(key):
			push_error("[characters] hydrate: key '%s' disagrees with its row's instance_id "
				% String(key) + "'%s'" % state.instance_id)
			return false
		staged[String(key)] = state
	_by_id = staged
	return true


## Drop every character (session teardown).
func clear() -> void:
	_by_id.clear()

extends RefCounted
class_name CharacterState
## CharacterState — Aetheria domain (authoritative character instance).
##
## The single AUTHORITATIVE, serializable, presentation-free source of truth for one
## character in a running game (`docs/CHARACTER_SYSTEM.md` §3–§4, D-011). The player is a
## Character, so the player's identity + stats + life state live HERE, not in the Player
## node — the node is only a runtime realization/view bound to this state
## (`src/gameplay/entities/player.gd`, §6).
##
## It is a `RefCounted` DOMAIN object with NO Godot Node / scene / presentation dependency
## (`03-architecture.md`: domain must not import presentation). It is built from a
## `CharacterTemplateData` (data) via `create_from_template()` and carries the mutable
## PERSISTENT tier that a save round-trips.
##
## Three-tier partition (`docs/CHARACTER_SYSTEM.md` §3) is honored strictly:
##   - PERSISTENT (serialized): identity, origin, age, profession, cultivation CONTRACT
##     fields, current stats, current_hp, traits, goals, sect cache, reputation, secrets,
##     story_flags, life_state, death_cause.
##   - RUNTIME (NOT serialized): nothing lives here yet (no AI/pathing in Phase 04).
##   - PRESENTATION (NOT serialized): never stored here at all (no sprite/portrait frame).
## `to_dict()`/`from_dict()` therefore (de)serialize the PERSISTENT tier ONLY — never a
## Node, position, camera, scene, or any presentation field (L-001: never serialize
## runtime-only lifecycle; here we persist identity + data, derive views elsewhere).
##
## Phase 04 scope: identity + stats + life-state. The cultivation/relationship/sect/world-sim
## fields are stored as CONTRACT (so saves + later phases have a stable shape) but carry NO
## mechanics here (`03-architecture.md` anti-over-engineering).

## Life state of the character (`docs/CHARACTER_SYSTEM.md` §5). Phase 04 implements the
## ALIVE→DEAD transition; MISSING/ASCENDED are contract values a later phase (world sim /
## story) drives. DEAD is terminal within a save: there is NO UI/gameplay revive in Phase 04.
enum LifeState { ALIVE, DEAD, MISSING, ASCENDED }


# --- Identity (persistent) ---------------------------------------------------

## Unique id for THIS instance within a save (`docs/SAVE_FORMAT.md` characters.by_instance_id).
var instance_id: StringName = &""

## The `CharacterTemplateData.id` this instance was built from (content reference).
var template_id: StringName = &""

## Localization keys for display (resolved by presentation; never literal strings here).
var name_key: StringName = &""
var title_key: StringName = &""

## Mirror of the template's enum ints (CharacterTemplateData.Gender/AgeCategory/Profession).
## Stored as ints so the domain layer carries no dependency on the data class' enums at the
## type level; the data class remains the vocabulary owner.
var gender: int = 0


# --- Origin / age / profession (persistent) ----------------------------------

var origin_key: StringName = &""
var bloodline_key: StringName = &""
var age: int = 0
var age_category: int = 0
var profession: int = 0


# --- Level / XP progression (persistent authority, Phase 11) -----------------
#
# CUMULATIVE LIFETIME XP, and the ONLY stored progression number. The character's LEVEL is
# not stored anywhere: it is derived from this value and the authored `ProgressionCurveData`
# by `ProgressionService.level_of()`. Two consequences worth stating where the field lives:
#
#   * a stored level could disagree with stored XP, and this cannot — the same reasoning that
#     made sect membership a derived cache with one authority (D-015) and that L-032 records
#     as a general preference;
#   * a commit therefore writes ONE integer, so an XP grant is atomic by construction rather
#     than by careful ordering (see `ProgressionService.grant_xp`).
#
# It is deliberately NOT `cultivation_progress` below. Level is the fine-grained
# combat-derived axis; cảnh giới is the chunky capability-granting one, and
# `docs/PROGRESSION_CULTIVATION_DESIGN.md` §1 forbids collapsing them into one number.
# **Level is never an access gate** (C-002), so nothing in the domain may branch on it.

var xp: int = 0


## Set the authoritative cumulative XP. Clamped at 0, because XP is monotonic by design and a
## negative total is not a state this game has.
##
## THIS IS A STORAGE BOUNDARY, NOT A GAMEPLAY MUTATOR (D-055). The split is:
##
##   * `ProgressionService.grant_xp()` is the only **semantic progression mutation authority**
##     — it decides what the new total should be, from the authored curve.
##   * this setter is the only place the **invariant** (`xp >= 0`) is enforced, which is why it
##     lives next to the field rather than in the service, exactly as `set_current_hp` does.
##
## So "the only thing that writes XP" is two statements, not one: the service is the only thing
## that DECIDES a new XP value, and this is the only thing that STORES one. No gameplay,
## runtime or presentation code may call this — `tests/unit/progression/
## test_progression_authority.gd` walks `src/` and fails if any production file outside this
## class and the service mutates XP. It stays public and keeps its name because GDScript has no
## package-private, and a capability object to fake one would be more machinery than the rule
## is worth; the structural guard is what enforces it.
func set_total_xp(value: int) -> void:
	xp = maxi(0, value)


# --- Cultivation CONTRACT (persistent; mechanics are a later phase) ----------

## Current cảnh giới id (starts from the template's `starting_realm`). CONTRACT only.
var realm_id: StringName = &""

## Progress toward the next realm. CONTRACT only — no breakthrough math in Phase 04.
var cultivation_progress: int = 0

## Known công pháp ids. CONTRACT only.
var technique_ids: Array[StringName] = []


# --- Stats (persistent authority) --------------------------------------------
# The authoritative current stat numbers. Seeded from the template's base StatBlock at
# creation; the runtime StatsComponent is only a VIEW of these
# (`src/gameplay/components/stats_component.gd`). `max_hp` here is the authority for the
# HealthComponent's maximum; `current_hp` is the authoritative current health that the
# HealthComponent syncs back into on damage/heal/death.

var max_hp: int = 1
var attack: int = 0
var defense: int = 0
var move_speed: float = 0.0

## Current health. 0 <= current_hp <= max_hp. Seeded to max_hp (full) at creation.
var current_hp: int = 1


# --- Personality / motivation / goals (persistent) ---------------------------

var traits: Array[StringName] = []
var motivation_key: StringName = &""

## Structured goals ({ kind, target_id, priority, state }). CONTRACT only in Phase 04.
var goals: Array = []


# --- Affiliation DERIVED cache (persistent cache; authority = SectState, D-015) ----

var sect_id: StringName = &""
var faction_id: StringName = &""
var sect_rank: StringName = &""


# --- Reputation / secrets / story flags (persistent) -------------------------

var reputation: Dictionary = {}
var secrets: Array = []
var story_flags: Dictionary = {}


# --- Life state (persistent) -------------------------------------------------

var life_state: int = LifeState.ALIVE

## Optional cause set ONLY on a valid transition into DEAD. Empty while ALIVE.
var death_cause: StringName = &""


# --- Schedule / sim CONTRACT (persistent; world sim is a later phase) --------

var schedule_ref: StringName = &""
var sim_state: Dictionary = {}


# --- Construction ------------------------------------------------------------

## Build an authoritative CharacterState from a validated template. Fails LOUD and returns
## null on a missing/invalid template (the caller must handle null and fail closed —
## `04-coding-standards.md` error handling). `instance_id` is the unique per-save id for
## this realization; the caller owns id allocation (e.g. the player uses a fixed id).
static func create_from_template(
		template: CharacterTemplateData,
		new_instance_id: StringName) -> CharacterState:
	if template == null:
		push_error("[character] create_from_template with null template")
		return null
	if not template.is_valid():
		push_error("[character] invalid template: %s" % str(template.validation_errors()))
		return null
	if new_instance_id == &"":
		push_error("[character] create_from_template requires a non-empty instance_id")
		return null

	var state := CharacterState.new()
	state.instance_id = new_instance_id
	state.template_id = template.id
	state.name_key = template.name_key
	state.title_key = template.title_key
	state.gender = template.gender
	state.origin_key = template.origin_key
	state.bloodline_key = template.bloodline_key
	state.age = template.age
	state.age_category = template.age_category
	state.profession = template.profession
	# A fresh character has earned nothing. The LEVEL this corresponds to is whatever the
	# authored curve's `min_level` is — derived, not written here, so a curve that starts at a
	# level other than 1 needs no change to character creation.
	state.xp = 0
	state.realm_id = template.starting_realm
	state.cultivation_progress = 0
	state.technique_ids = template.starting_technique_ids.duplicate()
	# Stats are copied (value semantics): the state OWNS its current numbers; mutating them
	# later must never write back into the shared template resource.
	state.max_hp = template.base_stats.max_hp
	state.attack = template.base_stats.attack
	state.defense = template.base_stats.defense
	state.move_speed = template.base_stats.move_speed
	state.current_hp = state.max_hp
	state.traits = template.default_traits.duplicate()
	state.motivation_key = template.motivation_key
	state.goals = template.default_goals.duplicate(true)
	state.sect_id = template.default_sect_id
	state.faction_id = template.default_faction_id
	state.sect_rank = &""
	state.schedule_ref = template.schedule_ref
	state.life_state = LifeState.ALIVE
	state.death_cause = &""
	return state


# --- Life-state rules (domain) -----------------------------------------------

func is_alive() -> bool:
	return life_state == LifeState.ALIVE


func is_dead() -> bool:
	return life_state == LifeState.DEAD


## Transition ALIVE → DEAD exactly once. Returns true on a real transition, false (loud) if
## the character is not currently ALIVE — DEAD is terminal and there is NO revive in Phase 04,
## so a second kill is rejected rather than silently re-dying (mirrors HealthComponent's
## "died once per life" invariant). `death_cause` is recorded ONLY on a valid transition.
func mark_dead(cause: StringName = &"") -> bool:
	if life_state != LifeState.ALIVE:
		push_warning("[character] mark_dead rejected: life_state is %d, not ALIVE" % life_state)
		return false
	life_state = LifeState.DEAD
	death_cause = cause
	current_hp = 0
	return true


# --- Current-HP authority ----------------------------------------------------

## Set the authoritative current health, clamped to [0, max_hp]. The runtime HealthComponent
## calls this so the domain stays the single source of truth for health; it does NOT itself
## change life_state (death is an explicit `mark_dead()` decision by the owner).
func set_current_hp(value: int) -> void:
	current_hp = clampi(value, 0, max_hp)


func get_health_fraction() -> float:
	if max_hp <= 0:
		return 0.0
	return float(current_hp) / float(max_hp)


# --- Serialization (PERSISTENT tier only) ------------------------------------

## Serialize the PERSISTENT tier to a plain Dictionary (`docs/SAVE_FORMAT.md`). NEVER writes
## a Node, position, camera, scene, or presentation field (L-001). Enum ints are written as
## ints; StringName as String for JSON-friendliness (`docs/SAVE_FORMAT.md` §lean = JSON).
func to_dict() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"template_id": String(template_id),
		"name_key": String(name_key),
		"title_key": String(title_key),
		"gender": gender,
		"origin_key": String(origin_key),
		"bloodline_key": String(bloodline_key),
		"age": age,
		"age_category": age_category,
		"profession": profession,
		"xp": xp,
		"realm_id": String(realm_id),
		"cultivation_progress": cultivation_progress,
		"technique_ids": _string_name_array_to_strings(technique_ids),
		"max_hp": max_hp,
		"attack": attack,
		"defense": defense,
		"move_speed": move_speed,
		"current_hp": current_hp,
		"traits": _string_name_array_to_strings(traits),
		"motivation_key": String(motivation_key),
		"goals": goals.duplicate(true),
		"sect_id": String(sect_id),
		"faction_id": String(faction_id),
		"sect_rank": String(sect_rank),
		"reputation": reputation.duplicate(true),
		"secrets": secrets.duplicate(true),
		"story_flags": story_flags.duplicate(true),
		"life_state": life_state,
		"death_cause": String(death_cause),
		"schedule_ref": String(schedule_ref),
		"sim_state": sim_state.duplicate(true),
	}


## Hydrate the PERSISTENT tier from a Dictionary (data-only hydrate, L-001). Validates the
## snapshot at the boundary and fails LOUD + returns false on a structurally invalid payload
## (missing instance_id, HP range, bad life_state) rather than reconstructing an impossible
## state. Missing optional keys fall back to safe defaults. The caller drives any runtime
## wiring afterward (the Player re-binds the component view).
func from_dict(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[character] from_dict: not a Dictionary")
		return false
	var in_instance_id := StringName(String(data.get("instance_id", "")))
	if in_instance_id == &"":
		push_error("[character] from_dict: missing instance_id")
		return false
	var in_life_state := int(data.get("life_state", LifeState.ALIVE))
	if in_life_state < 0 or in_life_state >= LifeState.size():
		push_error("[character] from_dict: life_state out of range (%d)" % in_life_state)
		return false
	var in_max_hp := int(data.get("max_hp", 1))
	if in_max_hp <= 0:
		push_error("[character] from_dict: max_hp must be > 0 (got %d)" % in_max_hp)
		return false
	var in_current_hp := int(data.get("current_hp", in_max_hp))
	if in_current_hp < 0 or in_current_hp > in_max_hp:
		push_error("[character] from_dict: current_hp %d out of [0, %d]" % [
				in_current_hp, in_max_hp])
		return false
	# XP is type-CHECKED before it is converted, not coerced (L-024). `int("250")`,
	# `int(250.0)` and `int(true)` all succeed and all yield a plausible total, so a payload
	# with the wrong TYPE in this field would otherwise be accepted as legitimate progress —
	# and because the level is DERIVED from this number, a corrupt total silently becomes a
	# corrupt level too. A missing key is still legal and means "no XP earned" (0), which is
	# what keeps pre-Phase-11 saves loadable.
	var raw_xp: Variant = data.get("xp", 0)
	if typeof(raw_xp) != TYPE_INT:
		push_error("[character] from_dict: xp must be an int, got %s"
			% type_string(typeof(raw_xp)))
		return false
	var in_xp := int(raw_xp)
	if in_xp < 0:
		push_error("[character] from_dict: xp must be >= 0 (got %d)" % in_xp)
		return false

	instance_id = in_instance_id
	template_id = StringName(String(data.get("template_id", "")))
	name_key = StringName(String(data.get("name_key", "")))
	title_key = StringName(String(data.get("title_key", "")))
	gender = int(data.get("gender", 0))
	origin_key = StringName(String(data.get("origin_key", "")))
	bloodline_key = StringName(String(data.get("bloodline_key", "")))
	age = int(data.get("age", 0))
	age_category = int(data.get("age_category", 0))
	profession = int(data.get("profession", 0))
	xp = in_xp
	realm_id = StringName(String(data.get("realm_id", "")))
	cultivation_progress = int(data.get("cultivation_progress", 0))
	technique_ids = _strings_to_string_name_array(data.get("technique_ids", []))
	max_hp = in_max_hp
	attack = int(data.get("attack", 0))
	defense = int(data.get("defense", 0))
	move_speed = float(data.get("move_speed", 0.0))
	current_hp = in_current_hp
	traits = _strings_to_string_name_array(data.get("traits", []))
	motivation_key = StringName(String(data.get("motivation_key", "")))
	goals = (data.get("goals", []) as Array).duplicate(true)
	sect_id = StringName(String(data.get("sect_id", "")))
	faction_id = StringName(String(data.get("faction_id", "")))
	sect_rank = StringName(String(data.get("sect_rank", "")))
	reputation = (data.get("reputation", {}) as Dictionary).duplicate(true)
	secrets = (data.get("secrets", []) as Array).duplicate(true)
	story_flags = (data.get("story_flags", {}) as Dictionary).duplicate(true)
	life_state = in_life_state
	death_cause = StringName(String(data.get("death_cause", "")))
	schedule_ref = StringName(String(data.get("schedule_ref", "")))
	sim_state = (data.get("sim_state", {}) as Dictionary).duplicate(true)
	return true


# --- Helpers -----------------------------------------------------------------

static func _string_name_array_to_strings(arr: Array[StringName]) -> Array:
	var out: Array = []
	for item in arr:
		out.append(String(item))
	return out


static func _strings_to_string_name_array(arr) -> Array[StringName]:
	var out: Array[StringName] = []
	if arr is Array:
		for item in arr:
			out.append(StringName(String(item)))
	return out

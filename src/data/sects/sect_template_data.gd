extends Resource
class_name SectTemplateData
## SectTemplateData — Aetheria data (content Resource, `sect_*`).
##
## The DATA-ONLY *definition* of a sect (`docs/SECT_SYSTEM.md` §3–§4, `docs/DATA_SCHEMA.md`).
## A `SectState` (domain, authoritative) is instantiated from this template. Adding a sect =
## author a new `.tres`; no engine change (the extensibility invariant, `02-game-design.md`).
##
## All display text is a localization KEY (`07-localization.md`); there are NO literal
## user-facing strings here. The rank ladder is authored as ordered `SectRankData` entries so
## the rank vocabulary is content, not code (§4). This is DATA, not behavior: no gameplay
## logic, no Node dependency — only boundary validation.
##
## Phase 06 scope: identity, doctrine, ranks, resources, territory, reputation, influence,
## default alliances/enemies. Factions/techniques/rules/secrets/events (SECT_SYSTEM §4/§7)
## are deliberately NOT modeled here — those belong to Phase 07 (Faction/Politics) and later
## content phases (`03-architecture.md` anti-over-engineering; no speculative fields).

## Sect archetype vocabulary (closed set so presentation/rules can rely on it). Kept as an
## enum, not a free StringName, so content cannot invent a type with no handling.
enum SectType { ORTHODOX, DEMONIC, NEUTRAL, HIDDEN }


# --- Identity ----------------------------------------------------------------

## Stable content id (`sect_*`). Unique within the sect catalog; never changes once shipped.
@export var id: StringName = &""

## Localization key for the display name. Required.
@export var name_key: StringName = &""

## Localization key for the sect's doctrine/philosophy. Required (shapes conduct + teaching).
@export var doctrine_key: StringName = &""

## Presentation emblem ref (resource path resolved by the presentation layer). Optional at
## the data boundary — a sect with no emblem renders a neutral placeholder. NOT copied into
## the domain SectState (presentation stays out of domain, `03-architecture.md`).
@export var emblem_ref: String = ""

@export var sect_type: SectType = SectType.ORTHODOX

## Power tier (minor … great sect). 1-based; higher = greater. Must be >= 1.
@export var tier: int = 1


# --- Rank ladder (ordered; array order = official progression, §4) ----------

@export var rank_ladder: Array[SectRankData] = []


# --- Starting economy / holdings (seed a new SectState) ----------------------

## Starting resources `{ resource_id(String) -> quantity(int >= 0) }` (spirit stones, pills,
## materials, manpower). Integer counts only — no float resource quantities (§12).
@export var starting_resources: Dictionary = {}

## Starting controlled region/map ids. Unique, non-empty ids.
@export var starting_territory: Array[StringName] = []

## Seed reputation `{ scope(String) -> value(int in [-100, 100]) }` (§12 default range).
@export var reputation_seed: Dictionary = {}

## Seed political influence in the wider world. Must be >= 0 (§12).
@export var influence_seed: int = 0


# --- Default diplomacy (mirrored to Sect↔Sect relationship edges at runtime) -

## Default allied sect ids. Unique; must not contain this sect's own id.
@export var default_ally_sect_ids: Array[StringName] = []

## Default enemy sect ids. Unique; must not contain this sect's own id; disjoint from allies.
@export var default_enemy_sect_ids: Array[StringName] = []


# --- Reputation range contract (§12) -----------------------------------------
const REPUTATION_MIN := -100
const REPUTATION_MAX := 100


# --- Validation (boundary) ---------------------------------------------------

func is_valid() -> bool:
	return validation_errors().is_empty()


## Loud, specific boundary validation (`08-ai-review-protocol`): every invariant from
## SECT_SYSTEM §3–§5 and the prompt §3 is checked with a precise message naming the field.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be non-empty")
	if name_key == &"":
		errors.append("name_key must be non-empty")
	if doctrine_key == &"":
		errors.append("doctrine_key must be non-empty")
	if sect_type < 0 or sect_type >= SectType.size():
		errors.append("sect_type enum out of range (got %d)" % sect_type)
	if tier < 1:
		errors.append("tier must be >= 1 (got %d)" % tier)
	if influence_seed < 0:
		errors.append("influence_seed must be >= 0 (got %d)" % influence_seed)

	_validate_rank_ladder(errors)
	_validate_resources(errors)
	_validate_territory(errors)
	_validate_reputation(errors)
	_validate_diplomacy(errors)
	return errors


## Rank ladder: non-empty, each rank valid, rank ids unique, authorities non-negative.
func _validate_rank_ladder(errors: Array[String]) -> void:
	if rank_ladder.is_empty():
		errors.append("rank_ladder must have at least one rank")
		return
	var seen := {}
	for i in rank_ladder.size():
		var rank := rank_ladder[i]
		if rank == null:
			errors.append("rank_ladder[%d] is null" % i)
			continue
		if not rank.is_valid():
			errors.append("rank_ladder[%d] invalid: %s" % [i, str(rank.validation_errors())])
			continue
		var rid := String(rank.rank_id)
		if seen.has(rid):
			errors.append("duplicate rank_id '%s' in rank_ladder" % rid)
		seen[rid] = true


func _validate_resources(errors: Array[String]) -> void:
	for key in starting_resources:
		if String(key) == "":
			errors.append("starting_resources has an empty resource id")
		var qty: Variant = starting_resources[key]
		if typeof(qty) != TYPE_INT:
			errors.append("starting_resources['%s'] must be an int" % String(key))
		elif int(qty) < 0:
			errors.append("starting_resources['%s'] must be >= 0 (got %d)"
				% [String(key), int(qty)])


func _validate_territory(errors: Array[String]) -> void:
	var seen := {}
	for region in starting_territory:
		if region == &"":
			errors.append("starting_territory contains an empty region id")
			continue
		var r := String(region)
		if seen.has(r):
			errors.append("duplicate territory id '%s'" % r)
		seen[r] = true


func _validate_reputation(errors: Array[String]) -> void:
	for scope in reputation_seed:
		if String(scope) == "":
			errors.append("reputation_seed has an empty scope")
		var value: Variant = reputation_seed[scope]
		if typeof(value) != TYPE_INT:
			errors.append("reputation_seed['%s'] must be an int" % String(scope))
		elif int(value) < REPUTATION_MIN or int(value) > REPUTATION_MAX:
			errors.append("reputation_seed['%s'] %d out of [%d, %d]" % [
				String(scope), int(value), REPUTATION_MIN, REPUTATION_MAX])


## Diplomacy: ally/enemy lists each unique, neither contains this sect's own id, and the two
## lists are disjoint (a sect cannot be both a default ally AND a default enemy).
func _validate_diplomacy(errors: Array[String]) -> void:
	var allies := {}
	for a in default_ally_sect_ids:
		if a == id:
			errors.append("default_ally_sect_ids contains this sect's own id '%s'" % String(id))
		if allies.has(String(a)):
			errors.append("duplicate ally id '%s'" % String(a))
		allies[String(a)] = true
	var enemies := {}
	for e in default_enemy_sect_ids:
		if e == id:
			errors.append("default_enemy_sect_ids contains this sect's own id '%s'" % String(id))
		if enemies.has(String(e)):
			errors.append("duplicate enemy id '%s'" % String(e))
		enemies[String(e)] = true
	for a in allies:
		if enemies.has(a):
			errors.append("sect id '%s' is in BOTH default allies and enemies" % a)


# --- Lookups (built from validated data) -------------------------------------

## Ordered rank ids (array order = progression). For seeding + tests.
func rank_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for rank in rank_ladder:
		if rank != null:
			out.append(rank.rank_id)
	return out


## True if `rank_id` exists in this ladder.
func has_rank(rank_id: StringName) -> bool:
	return find_rank(rank_id) != null


## The SectRankData for `rank_id`, or null.
func find_rank(rank_id: StringName) -> SectRankData:
	for rank in rank_ladder:
		if rank != null and rank.rank_id == rank_id:
			return rank
	return null


## The lowest-authority rank (the entry rank a new disciple joins at), or null if empty.
func lowest_rank() -> SectRankData:
	var best: SectRankData = null
	for rank in rank_ladder:
		if rank == null:
			continue
		if best == null or rank.authority < best.authority:
			best = rank
	return best


## The highest-authority rank (the leader rank), or null if empty.
func highest_rank() -> SectRankData:
	var best: SectRankData = null
	for rank in rank_ladder:
		if rank == null:
			continue
		if best == null or rank.authority > best.authority:
			best = rank
	return best

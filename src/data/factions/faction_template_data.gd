extends Resource
class_name FactionTemplateData
## FactionTemplateData — Aetheria data (the DEFINITION of one internal sect faction).
##
## A faction is a political group INSIDE a parent sect (`docs/SECT_SYSTEM.md` §7): it has its
## own stance, goals, influence weight and holdings, and it argues with its siblings about
## what the sect should be. This Resource is the authored definition; `FactionState` is the
## runtime instance built from it, and `FactionService` is the only thing that mutates that.
##
## Adding a faction is authoring one `.tres` + its catalog entry + two locale rows. No core
## code changes (`02-game-design.md` extensibility rule).
##
## WHAT IS DELIBERATELY NOT HERE
##   * No roster. Membership is drawn from the PARENT SECT's roster, which stays the single
##     membership authority (D-015): a faction member must already be a sect member, so a
##     template that authored its own members could name people the sect never admitted.
##   * No leader. The only character that exists in a Phase-07 session is the player, and
##     inventing NPC leaders here would fabricate characters that no `CharacterState` backs
##     (§10: never invent a character). Factions ship leaderless; P-17 authors the NPCs and
##     the service assigns leadership through the one mutation path.
##   * No attitude scalars. `docs/SECT_SYSTEM.md` §7 sketched `attitude_toward_player` and
##     `attitudes_toward_factions` as inline dictionaries and left the representation open
##     ("a detail to pin when the Faction phase is built"). D-042 pins it: those standings
##     are RELATIONSHIP EDGES in the shared graph, because `affinity` and `rivalry` are two
##     of the six frozen relationship dimensions (CL-12) and a second copy here would be a
##     second source of truth for "how A feels about B" — the exact defect D-015 had to undo
##     for sect membership. Declared starting politics live in the two id lists below and are
##     MIRRORED into the graph at session start, the same way sect diplomacy is.

## Where a faction sits relative to its own sect's current orthodoxy. A closed set so rules
## and presentation can rely on it; never a free `StringName`.
##
## IMPORTANT: this is a POLITICAL POSITION, not a morality rating. `RADICAL` does not mean
## evil and `LOYALIST` does not mean good — `docs/WORLD_BIBLE.md` §8 requires every sect to
## hold a defensible internal disagreement, and C-005 forbids authoring any group as simply
## good or simply evil. A stance says which direction a faction pushes, nothing more.
enum Stance { LOYALIST, REFORMIST, RADICAL, NEUTRAL }

## Influence is a WEIGHT WITHIN THE SECT, so it is bounded rather than open-ended like
## `SectState.influence` (which measures standing in the wider world). A bounded scale is
## what makes "share of the sect" a meaningful, comparable number.
const INFLUENCE_MIN := 0
const INFLUENCE_MAX := 100


# --- Identity ----------------------------------------------------------------

## Stable content id (`faction_*`). Unique across the whole faction catalog — NOT merely
## within its parent sect, so an edge id or a save reference never needs the parent to
## disambiguate it.
@export var id: StringName = &""

## The `SectTemplateData.id` this faction lives inside. Required: a faction with no parent
## sect is not a faction, it is an organisation, and nothing in Phase 07 models those.
@export var parent_sect_id: StringName = &""

## Localization key for the display name. Required.
@export var name_key: StringName = &""

## Localization key for this faction's own reading of the sect's doctrine — the argument it
## is actually making. Required: a faction with no stated position cannot be disagreed with
## on the merits, which is what `WORLD_BIBLE.md` §8 demands of authored content.
@export var doctrine_key: StringName = &""

## Presentation emblem ref, resolved by the UI. Optional. NOT copied into the domain
## `FactionState` (presentation stays out of domain, `03-architecture.md`).
@export var emblem_ref: String = ""

@export var stance: Stance = Stance.NEUTRAL


# --- Politics seed -----------------------------------------------------------

## Structured goals this faction pursues (§7). At least one: a faction that wants nothing has
## no politics to simulate.
@export var goals: Array[FactionGoalData] = []

## Starting weight within the parent sect, in [INFLUENCE_MIN, INFLUENCE_MAX].
@export var influence_seed: int = 0

## Faction-controlled holdings `{ resource_id(String) -> quantity(int >= 0) }`. Integer counts
## only, matching the sect economy contract (§12).
@export var starting_resources: Dictionary = {}


# --- Declared internal politics (mirrored to relationship edges at runtime) ---
#
# Both lists name OTHER FACTIONS, and the catalog enforces that every named faction shares
# this faction's `parent_sect_id`: these are factions arguing inside one sect, not sects
# doing diplomacy. Cross-sect politics is `SectState`'s declared ally/enemy, already shipped.

## Factions this one is aligned with at session start. Unique; must not contain itself.
@export var default_allied_faction_ids: Array[StringName] = []

## Factions this one is in open rivalry with at session start. Unique; must not contain
## itself; disjoint from the allied list.
@export var default_rival_faction_ids: Array[StringName] = []


# --- Validation (boundary) ---------------------------------------------------

func is_valid() -> bool:
	return validation_errors().is_empty()


## Loud, specific boundary validation naming the exact field (`08-ai-review-protocol.md`).
## Everything checkable from THIS template alone is checked here; anything requiring a view
## of the other templates (do the named factions exist? do they share a parent? is the pair
## symmetric?) belongs to `FactionCatalog`, and anything requiring the sect world (does the
## parent sect exist?) belongs to `FactionRuntime`, which is the first place all three are
## visible at once.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be non-empty")
	if parent_sect_id == &"":
		errors.append("parent_sect_id must be non-empty")
	if name_key == &"":
		errors.append("name_key must be non-empty")
	if doctrine_key == &"":
		errors.append("doctrine_key must be non-empty")
	if stance < 0 or stance >= Stance.size():
		errors.append("stance enum out of range (got %d)" % stance)
	if influence_seed < INFLUENCE_MIN or influence_seed > INFLUENCE_MAX:
		errors.append("influence_seed %d out of [%d, %d]"
			% [influence_seed, INFLUENCE_MIN, INFLUENCE_MAX])
	if id != &"" and parent_sect_id != &"" and id == parent_sect_id:
		errors.append("id must differ from parent_sect_id ('%s')" % String(id))

	_validate_goals(errors)
	_validate_resources(errors)
	_validate_politics(errors)
	return errors


## Goals: non-empty list, each entry valid, goal ids unique within this faction.
##
## Goal priorities are NOT required to be unique or strictly ordered (unlike a sect rank
## ladder, where array order IS the progression and so must agree with `authority`). Two
## goals a faction weighs equally is a legitimate authored position, so only the ids are
## constrained.
func _validate_goals(errors: Array[String]) -> void:
	if goals.is_empty():
		errors.append("goals must have at least one entry (a faction with no goal has no "
			+ "politics to resolve)")
		return
	var seen := {}
	for i in goals.size():
		var goal := goals[i]
		if goal == null:
			errors.append("goals[%d] is null" % i)
			continue
		if not goal.is_valid():
			errors.append("goals[%d] invalid: %s" % [i, str(goal.validation_errors())])
			continue
		var gid := String(goal.goal_id)
		if seen.has(gid):
			errors.append("duplicate goal_id '%s' in goals" % gid)
		seen[gid] = true


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


func _validate_politics(errors: Array[String]) -> void:
	var allied := {}
	for other in default_allied_faction_ids:
		if other == &"":
			errors.append("default_allied_faction_ids contains an empty id")
			continue
		if other == id:
			errors.append("default_allied_faction_ids contains this faction itself")
			continue
		var key := String(other)
		if allied.has(key):
			errors.append("duplicate allied faction id '%s'" % key)
		allied[key] = true
	var rivals := {}
	for other in default_rival_faction_ids:
		if other == &"":
			errors.append("default_rival_faction_ids contains an empty id")
			continue
		if other == id:
			errors.append("default_rival_faction_ids contains this faction itself")
			continue
		var key := String(other)
		if rivals.has(key):
			errors.append("duplicate rival faction id '%s'" % key)
		if allied.has(key):
			errors.append("'%s' is declared both allied and rival" % key)
		rivals[key] = true


# --- Lookups -----------------------------------------------------------------

func goal_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for goal in goals:
		if goal != null:
			out.append(goal.goal_id)
	return out


func has_goal(goal_id: StringName) -> bool:
	return goal_ids().has(goal_id)


func find_goal(goal_id: StringName) -> FactionGoalData:
	for goal in goals:
		if goal != null and goal.goal_id == goal_id:
			return goal
	return null


## This faction's goals ordered by descending priority, ties broken by `goal_id` so the order
## is DETERMINISTIC. Presentation and rules both read goals in this order; without the tie
## break, two equal-priority goals could render in either order between runs.
func goals_by_priority() -> Array[FactionGoalData]:
	var sorted: Array[FactionGoalData] = []
	for goal in goals:
		if goal != null:
			sorted.append(goal)
	sorted.sort_custom(_compare_goals)
	return sorted


static func _compare_goals(a: FactionGoalData, b: FactionGoalData) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	return String(a.goal_id) < String(b.goal_id)

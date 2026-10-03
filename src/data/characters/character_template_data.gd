extends Resource
class_name CharacterTemplateData
## CharacterTemplateData — Aetheria data (content Resource, `char_*`).
##
## The DATA-ONLY *definition* of a character archetype / spawn template
## (`docs/CHARACTER_SYSTEM.md` §4, `docs/DATA_SCHEMA.md` §3b). The player is itself a
## Character, so the player's starting identity + base stats are authored as a
## `CharacterTemplateData` `.tres` (`data/characters/player_default.tres`), NOT hard-coded.
##
## This holds the *defaults* a `CharacterState` (domain, authoritative) is instantiated
## from — identity, origin, age, profession, starting cultivation CONTRACT fields, base
## stats, personality defaults, default sect/faction, schedule ref. All display strings are
## localization **keys** (`07-localization.md`); there are NO literal user-facing strings.
##
## This is DATA, not behavior: it carries no gameplay logic, no Node dependency, and does
## NOT implement cultivation/level/XP mechanics — `starting_realm`/`starting_technique_ids`
## are CONTRACT fields the later cultivation phase consumes; Phase 04 only stores + validates
## them (`03-architecture.md` anti-over-engineering, data vs. domain split).
##
## Adding a new named NPC or generic archetype = author a new `.tres`; no engine change
## (the extensibility invariant, `02-game-design.md`).

## Gender is a small closed vocabulary; UNSPECIFIED is the safe default for a template that
## does not care. Kept as an enum (not a free StringName) so content can't invent values the
## presentation layer has no sprite/pronoun data for.
enum Gender { UNSPECIFIED, MALE, FEMALE }

## Age bracket (lifespan extends with realm in a tu tiên setting). Optional per template;
## UNKNOWN means "don't assert an age bracket for this template".
enum AgeCategory { UNKNOWN, CHILD, YOUTH, ADULT, ELDER, ANCIENT }

## Profession drives (future) schedule + services (`docs/WORLD_SIMULATION.md`). CULTIVATOR
## is the default for the player and most story characters.
enum Profession { CULTIVATOR, ALCHEMIST, BLACKSMITH, MERCHANT, FARMER, SCHOLAR }


# --- Identity ----------------------------------------------------------------

## Stable content id (`char_*`). Unique within the character catalog; never changes once
## shipped (changing it is a breaking content change — `07-localization.md` key discipline).
@export var id: StringName = &""

## Localization key for the display name. Required (every character has a name).
@export var name_key: StringName = &""

## Localization key for an optional title/epithet (e.g. "Outer Disciple"). May be empty.
@export var title_key: StringName = &""

@export var gender: Gender = Gender.UNSPECIFIED

## Presentation refs (resource paths / set ids resolved by the presentation layer). Optional
## at this phase — the prototype player uses the scene's own sprite. Kept so content can
## point at a portrait / sprite set without a code change later.
@export var portrait_ref: String = ""
@export var sprite_set_ref: String = ""


# --- Origin ------------------------------------------------------------------

## Localization key for birthplace/background. Optional.
@export var origin_key: StringName = &""

## Localization key for an optional special bloodline. Optional.
@export var bloodline_key: StringName = &""


# --- Age ---------------------------------------------------------------------

## Age in years. Optional; <= 0 means "unspecified" and pairs with AgeCategory.UNKNOWN.
@export var age: int = 0

@export var age_category: AgeCategory = AgeCategory.UNKNOWN


# --- Profession --------------------------------------------------------------

@export var profession: Profession = Profession.CULTIVATOR


# --- Cultivation (CONTRACT fields; mechanics implemented in a later phase) ----

## Starting cảnh giới id. CONTRACT only in Phase 04 — stored + validated, no breakthrough
## math here (that is the cultivation phase, `docs/DATA_SCHEMA.md` progression). May be empty
## (a mortal with no realm yet).
@export var starting_realm: StringName = &""

## Starting công pháp ids. CONTRACT only in Phase 04 (no technique system yet).
@export var starting_technique_ids: Array[StringName] = []


# --- Stats -------------------------------------------------------------------

## The authored base/max stats shared shape (`StatBlock`). This is the authoritative numeric
## source a `CharacterState` copies its starting stats from; the runtime `StatsComponent` is
## only a view of it (`src/gameplay/components/stats_component.gd`). Required + must be valid.
@export var base_stats: StatBlock = null


# --- Personality / Motivation ------------------------------------------------

## Personality trait vocabulary ids (e.g. PROUD/LOYAL/GREEDY/CAUTIOUS). Influence (future)
## AI/dialogue selection; not hard-coded behavior. Optional.
@export var default_traits: Array[StringName] = []

## Localization/vocabulary key for the character's core drive. Optional.
@export var motivation_key: StringName = &""

## Default structured goals (`{ kind, target_id, priority }`), seeded into a new
## `CharacterState.goals` (`docs/DATA_SCHEMA.md` §3b). CONTRACT only in Phase 04 — stored +
## copied, no goal/world-sim logic yet. Optional (empty = no authored goals).
@export var default_goals: Array = []


# --- Default affiliations (optional) -----------------------------------------

## Default sect membership id. DERIVED cache seed only — the authority is the SectState
## roster (D-015). Optional; empty = unaffiliated.
@export var default_sect_id: StringName = &""

## Default internal faction id within the sect. Optional.
@export var default_faction_id: StringName = &""


# --- Schedule (world sim CONTRACT) -------------------------------------------

## Data-defined daily/weekly routine id (`docs/WORLD_SIMULATION.md`). CONTRACT only in
## Phase 04 (no world simulation yet). Optional.
@export var schedule_ref: StringName = &""


# --- Validation (boundary) ---------------------------------------------------

## True when every invariant holds. Content loaded from disk is external input and must be
## validated at the boundary before a `CharacterState` is built from it
## (`04-coding-standards.md` error handling).
func is_valid() -> bool:
	return validation_errors().is_empty()


## Returns the list of invariant violations (empty == valid). Loud, specific messages so a
## malformed template fails with the exact field, not a vague boolean (`08-ai-review-protocol`).
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be non-empty")
	if name_key == &"":
		errors.append("name_key must be non-empty (every character has a display name)")
	if base_stats == null:
		errors.append("base_stats (StatBlock) is required")
	elif not base_stats.is_valid():
		errors.append("base_stats invalid: %s" % str(base_stats.validation_errors()))
	if age < 0:
		errors.append("age must be >= 0 (got %d)" % age)
	# Enum @export values are constrained by the inspector, but a hand-edited .tres could
	# carry an out-of-range int — validate the boundary rather than trust the editor.
	if gender < 0 or gender >= Gender.size():
		errors.append("gender enum out of range (got %d)" % gender)
	if age_category < 0 or age_category >= AgeCategory.size():
		errors.append("age_category enum out of range (got %d)" % age_category)
	if profession < 0 or profession >= Profession.size():
		errors.append("profession enum out of range (got %d)" % profession)
	return errors

extends Resource
class_name EnemyData
## EnemyData — Aetheria data (one creature's authored identity, Phase 10).
##
## CONTENT, not behaviour. It describes WHAT a creature is — its name, its threat, its stats,
## how far it sees, what it swings, how it looks — and references the `AiProfileData` that
## tunes HOW it behaves. It contains no logic and, deliberately, **no behaviour-selecting
## enum**: a creature does not carry a `behaviour_type` that a brain switches on, because that
## is AI logic smuggled into content. A genuinely new behaviour is a new brain state (code,
## with a test); a different flavour of an existing one is an `AiProfileData`.
##
## THE EXTENSIBILITY TEST THIS RESOURCE EXISTS TO PASS: adding a second creature must be a
## `.tres` plus a spawn-table row, with no `if enemy_id == ...` anywhere
## (`02-game-design.md`). If a new creature needs code, the design is wrong now.
##
## WHY NO `CharacterState`. Phase 04's `CharacterState` is the authoritative record of a
## PERSON — identity, realm, sect membership, relationships, a place in the world simulation's
## cast. A low-tier frontier beast is none of those: it has no sect, no relationships, nothing
## to remember between encounters, and putting it in the character registry would make the
## world simulation's population include wildlife. So an enemy is a RUNTIME entity built from
## a `StatBlock`, and nothing about it is persistent. The day a creature needs to be remembered
## (a named boss, a tamed pet — Phase 16) that creature gets a `CharacterState`, and this
## resource is not in its way.

## Stable content id (`enemy_*`). Also the spawn-table key and the hurtbox id prefix.
@export var id: StringName = &""

## Localization key for the display name. A key, never a literal (`07-localization.md`).
@export var name_key: StringName = &""

## Localization key for the threat RATING shown to the player (e.g. "frontier / low").
##
## A rating is ADVISORY, never a gate: `02-game-design.md` is explicit that level is never an
## access gate and that where a number must communicate difficulty it is a threat rating. It is
## a localization key rather than an int so it reads as a judgement ("dangerous for a mortal")
## instead of inviting a numeric comparison the design forbids.
@export var threat_key: StringName = &""

## Authored combat stats. Same `StatBlock` the player and the training post use — one stat
## vocabulary, so `DamageRules` needs no creature-specific path.
@export var stats: StatBlock = null

## Damageable radius in pixels, added to an attacker's reach (`CombatService`). Describes the
## creature's SIZE, so it belongs here and not in the attack.
@export var hurt_radius: float = 11.0

## The behaviour tuning this creature uses.
@export var ai_profile: AiProfileData = null

## The attack it swings. An `AttackData`, exactly as the player's — so enemy damage goes
## through the same formula, the same lifecycle and the same crit roll.
@export var attack: AttackData = null

## Distance it tries to close to before swinging, in pixels.
##
## Derived-but-authored on purpose: it is usually a little under the attack's `reach_pixels`,
## and `is_valid()` REJECTS a value beyond reach, because a creature that stops outside its own
## reach swings at the air forever and reads as broken rather than as difficult.
@export var engage_distance: float = 24.0

## Presentation profile (`CharacterVisualProfileData`). A presentation reference on a data
## resource is allowed — the DOMAIN never sees it; only the gameplay layer resolves it when it
## realizes the entity (the same shape as `CharacterTemplateData.sprite_set_ref`, D-026).
@export var visual_profile: CharacterVisualProfileData = null

## Spawn category, for a spawn table to filter on (`field`, `dungeon`, `elite`, …). A
## StringName rather than an enum so a new category is content.
@export var spawn_category: StringName = &"field"

## XP granted for defeating this creature (Phase 11).
##
## THE WHOLE REWARD SEAM IS THIS ONE FIELD. Tuning what a creature is worth, or giving a new
## creature a reward, is editing a `.tres` — there is no reward table, no reward formula and
## no `if enemy_id == ...` in the progression service, which is the extensibility rule this
## resource already exists to satisfy (`02-game-design.md`).
##
## 0 is LEGAL and means "worth nothing": a harmless critter that exists for atmosphere should
## not be forced to hand out progress. Negative is rejected — XP is monotonic by design
## (`ProgressionService` refuses a negative grant too, so this is the authoring-side half of
## the same invariant).
##
## It is XP and nothing else. A creature does not grant cultivation progress, realm advance,
## knowledge or items here; those are other systems' phases and would each need their own
## owner. Putting them on this field would make it a generic "rewards" bag whose consumers
## could not be tested independently.
@export var xp_reward: int = 0


## True when every authored field is usable, and loud about which is not.
##
## Fail-closed at the data boundary: the OWNER decides what to do with a false (the spawner
## refuses to spawn), and this never aborts the process, so one bad `.tres` degrades instead of
## taking the game down (L-014).
func is_valid() -> bool:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if name_key == &"":
		problems.append("name_key is empty (the HUD would have nothing to show)")
	if stats == null:
		problems.append("stats is null")
	elif not stats.is_valid():
		problems.append("stats is an invalid StatBlock")
	if hurt_radius <= 0.0:
		problems.append("hurt_radius must be > 0 (got %.1f)" % hurt_radius)
	if ai_profile == null:
		problems.append("ai_profile is null")
	elif not ai_profile.is_valid():
		problems.append("ai_profile '%s' is invalid" % ai_profile.id)
	if attack == null:
		problems.append("attack is null")
	elif not attack.is_valid():
		problems.append("attack '%s' is invalid" % attack.id)
	if engage_distance <= 0.0:
		problems.append("engage_distance must be > 0 (got %.1f)" % engage_distance)
	elif attack != null and engage_distance > attack.reach_pixels:
		# A creature that stops outside its own reach swings at nothing forever.
		problems.append(("engage_distance (%.1f) exceeds the attack's reach (%.1f), so it "
			+ "would stop short and swing at the air") % [engage_distance, attack.reach_pixels])
	if xp_reward < 0:
		problems.append(("xp_reward must be >= 0 (got %d); XP is monotonic, so a negative "
			+ "reward would take progress away for winning a fight") % xp_reward)
	if visual_profile == null:
		problems.append("visual_profile is null (it would render as nothing)")
	if problems.is_empty():
		return true
	push_error("[enemy] '%s' is invalid: %s" % [id, "; ".join(problems)])
	return false

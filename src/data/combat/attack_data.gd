extends Resource
class_name AttackData
## AttackData — Aetheria data (one attack's authored definition, Phase 09).
##
## CONTENT, not behaviour (`03-architecture.md`: the data layer describes, the domain decides).
## It carries the TIMING of the four-state lifecycle, the GEOMETRY of the hit window, and the
## damage SCALARS the domain rule multiplies in. It runs no state machine, touches no node and
## resolves no hit; `AttackStateMachine` owns the timing and `DamageRules`/`CombatService` own
## the math.
##
## WHY TIMING IS DATA. D-007 resolves the combat model as REAL-TIME ACTION, which makes
## windup/active/recovery the primary balance levers — a heavy attack is "slow start, long
## reach, long recovery" and a jab is the opposite, and that is the same three numbers with
## different values. The extensibility rule (`02-game-design.md`) requires a new attack to be
## authorable as a `.tres`, so none of these may be a constant in a script.
##
## WHAT IS DELIBERATELY NOT HERE, each waiting for the phase with a real consumer:
##   * **Status effects / knockback / stagger.** They need an effect system to apply them.
##   * **Elemental type and resistances.** They need the resistance side of the formula.
##   * **Technique / equipment multipliers.** Those scalars belong to công pháp and equipment,
##     which own their own data; this resource must not grow a copy of them.
##   * **An animation reference.** The data layer names no sprite (`06-art-assets.md`); the
##     one deliberate exception is `body_action` (D-063 A3), a presentation SEMANTIC like
##     `weapon_family` — the name of the body the swing is performed with, resolved to a
##     sheet by presentation with fallback, never a sheet reference itself.
##   * **Multi-hit sequences and combo links.** A second attack is a second resource; chaining
##     is a rule, and no rule needs it yet.

## Stable content id (`attack_*`). Also the key a catalog/animation lookup uses, so it must be
## unique among attacks.
@export var id: StringName = &""

## Localization key for the attack's display name. A key, never a literal
## (`07-localization.md`). Empty is legal for an attack the UI never names.
@export var name_key: StringName = &""

# --- Timing: the four-state lifecycle, in seconds -----------------------------
#
# READY --try_begin()--> WINDUP --windup_seconds--> ACTIVE --active_seconds-->
# RECOVERY --recovery_seconds--> READY
#
# WINDUP is the commitment window (the attack is started and cannot yet hit), ACTIVE is the
# only window in which a hit can land, RECOVERY is the cost of having attacked. All three must
# be > 0: a zero-length WINDUP makes an attack unreactable, a zero-length ACTIVE can be stepped
# over entirely by one long frame, and a zero-length RECOVERY makes attacking free.

## Commitment delay before the hit window opens.
@export var windup_seconds: float = 0.12

## How long the hit window stays open. The hitbox exists for exactly this long.
@export var active_seconds: float = 0.08

## Lockout after the hit window closes, before the attacker is READY again.
@export var recovery_seconds: float = 0.20

## The canon weapon families (CL-10). An attack made WITH a weapon names its family, so a
## technique's weapon compatibility (P15) and the swing's look (a blade's trail, not a palm's air)
## read one fact. Empty = unarmed (the palm strike, a bite).
const WEAPON_FAMILIES: Array[StringName] = [&"weapon_kiem", &"weapon_dao", &"weapon_thuong",
	&"weapon_cung", &"weapon_phap_truong"]

@export var weapon_family: StringName = &""

## The bodies an attack may name (D-063 A3 review): `&"attack"` is the palm strike every
## profile authors, `&"slash"` the sword cut. Anything else is a content typo — refused at
## the boundary so it can never silently masquerade as a normal attack. Presentation reads
## this (with fallback) but never extends it; a new body is a data change first.
const BODY_ACTIONS: Array[StringName] = [&"attack", &"slash"]

## Which BODY the swing is performed with (D-063 A3): the presentation action name the
## `CharacterVisualComponent` plays for this attack. `&"attack"` is the palm strike every
## profile authors; `&"slash"` is the sword cut only sword-wielding looks carry. A profile
## without the named sheet falls back to the `attack` sheet, so an enemy or NPC keeps its
## body. Must name a supported body (`BODY_ACTIONS`): the data layer names a body,
## presentation resolves the sheet.
@export var body_action: StringName = &"attack"

## How much of its normal speed the attacker keeps while the swing is in flight (WINDUP, ACTIVE
## and RECOVERY), in [0, 1] (D-057B). 1.0 moves freely, 0.0 roots the attacker.
##
## COMMITMENT IS GAMEPLAY, and this is where it is authored. Before it existed the player ran
## at full speed through every swing, so the palm-strike pose slid across the floor at 180px/s —
## the floating-feet defect (`MOTION_DESIGN_CONTRACT.md` M-3.5) — and a swing cost nothing
## positionally. A low value makes the strike a planted commitment (a small drift still reads as
## the drawn step-in); presentation reads nothing from it. The movers — `Player` and
## `AIComponent` — multiply their speed by `AttackComponent.movement_scale()`.
@export_range(0.0, 1.0) var committed_move_scale: float = 1.0

# --- Geometry of the hit window ----------------------------------------------

## How far in front of the attacker the hit window reaches, in pixels. On the project's 16px
## grid (`06-art-assets.md`) this is read in whole tiles: 24 is one and a half tiles.
@export var reach_pixels: float = 24.0

## Full width of the hit arc, in degrees, centred on the attacker's facing. 180 is a half-plane
## in front; 360 would be a ring. Keeping it < 360 is what makes FACING matter, which is the
## point of an action model.
@export var arc_degrees: float = 120.0

# --- Damage scalars (multiplied in by `DamageRules`) -------------------------

## Multiplier on the attacker's attack stat for this attack. 1.0 = a plain hit.
@export var power_multiplier: float = 1.0

## Chance this attack crits, as a WHOLE PERCENT in [0, 100]. Rolled from the seeded COMBAT
## stream, never from an unseeded generator, so a combat sequence is reproducible.
##
## Authored in percent rather than as a 0..1 fraction because that is the unit
## `RngStream.next_chance()` consumes. A fraction here would need a `float -> int percent`
## conversion at the roll, which silently rounds authored content (0.125 becomes 13%) — a
## balance value quietly changing between the `.tres` and the die roll is exactly the kind of
## drift that is invisible in review.
@export_range(0, 100) var critical_chance_percent: int = 0

## Damage multiplier applied on a critical hit. Must be >= 1.0 — a "crit" that reduces damage
## is a content bug, and silently allowing it would make a balance mistake invisible.
@export var critical_multiplier: float = 1.5


## Every content problem with this attack, as human-readable strings. Pure: no errors are
## emitted, so catalogs, tools and tests can call it freely. `is_valid()` is the loud
## boundary wrapper around this.
func validation_errors() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if windup_seconds <= 0.0:
		problems.append("windup_seconds must be > 0 (got %.3f)" % windup_seconds)
	if active_seconds <= 0.0:
		problems.append("active_seconds must be > 0 (got %.3f)" % active_seconds)
	if recovery_seconds <= 0.0:
		problems.append("recovery_seconds must be > 0 (got %.3f)" % recovery_seconds)
	if committed_move_scale < 0.0 or committed_move_scale > 1.0:
		problems.append("committed_move_scale must be in [0, 1] (got %.3f)"
			% committed_move_scale)
	if weapon_family != &"" and not WEAPON_FAMILIES.has(weapon_family):
		problems.append("weapon_family '%s' is not canon (CL-10)" % weapon_family)
	if not BODY_ACTIONS.has(body_action):
		var want := PackedStringArray()
		for b in BODY_ACTIONS:
			want.append(String(b))
		problems.append("body_action '%s' is not a supported body (expected one of: %s)"
			% [String(body_action), ", ".join(want)])
	if reach_pixels <= 0.0:
		problems.append("reach_pixels must be > 0 (got %.2f)" % reach_pixels)
	if arc_degrees <= 0.0 or arc_degrees > 360.0:
		problems.append("arc_degrees must be in (0, 360] (got %.1f)" % arc_degrees)
	if power_multiplier <= 0.0:
		problems.append("power_multiplier must be > 0 (got %.3f)" % power_multiplier)
	if critical_chance_percent < 0 or critical_chance_percent > 100:
		problems.append("critical_chance_percent must be in [0, 100] (got %d)"
			% critical_chance_percent)
	if critical_multiplier < 1.0:
		problems.append("critical_multiplier must be >= 1.0 (got %.3f)" % critical_multiplier)
	return problems


## True when every authored field is usable. Loud about WHICH field is wrong, because a
## content error that only says "invalid" sends the author looking through the whole file.
##
## Fail-closed validation at the data boundary (`04-coding-standards.md`): the OWNER decides
## what to do with a false (the catalog/component refuses to arm the attack); this never
## aborts the process, so a bad `.tres` degrades instead of taking the game down (L-014).
func is_valid() -> bool:
	var problems := validation_errors()
	if problems.is_empty():
		return true
	push_error("[attack] '%s' is invalid: %s" % [id, "; ".join(problems)])
	return false


## Total seconds one full cycle takes, READY to READY. The attack's real cost in an action
## model, and the number a balance pass compares between attacks.
func total_seconds() -> float:
	return windup_seconds + active_seconds + recovery_seconds

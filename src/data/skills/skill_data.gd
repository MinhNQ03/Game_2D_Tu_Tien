extends Resource
class_name SkillData
## SkillData — Aetheria data (an activatable ability a technique unlocks, Phase 15).
##
## `DATA_SCHEMA.md` §3 SkillData, shaped for a real-time action game. A skill is ONE `CAST` action
## with four authored phases — PREPARE → CHANNEL → RELEASE → RECOVER (`PRESENTATION_ARCHITECTURE_
## CONTRACT.md` §5) — timed by `CastStateMachine`, never by presentation. It spends linh khí
## (`qi_cost`), has a `cooldown`, and DELIVERS its force one of two ways:
##   * CONE — the hit test is the SAME one a swing uses (`CombatService.resolve_hit`, from an
##     `AttackData` built from this skill), so there is no second hit formula;
##   * BOLT — an analytic projectile (no physics body): it travels `bolt_speed` up to `range_px`
##     and strikes the first living target within `bolt_radius` of its path; damage comes from
##     `DamageRules`, the one damage owner.
## Effects a hit applies are gameplay: `knockback_px` displaces the target's BODY (collision-
## aware), `stun_seconds` (Choáng) suspends its decisions and cancels its swing.

enum Delivery { CONE, BOLT }

## The four canon elements (COMBAT_DESIGN.md §3: Hỏa · Thủy · Phong · Lôi), a closed set —
## not the Ngũ Hành.
const ELEMENTS: Array[StringName] = [&"elem_hoa", &"elem_thuy", &"elem_phong", &"elem_loi"]

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var element: StringName = &""
@export var qi_cost: int = 10
@export var cooldown: float = 2.0
@export var prepare_seconds: float = 0.2
@export var channel_seconds: float = 0.0
@export var release_seconds: float = 0.1
@export var recover_seconds: float = 0.3
@export var power_multiplier: float = 1.0
@export var delivery: Delivery = Delivery.CONE
@export var range_px: float = 48.0
@export var arc_degrees: float = 90.0
@export var bolt_speed: float = 400.0
@export var bolt_radius: float = 9.0
@export var knockback_px: float = 0.0
@export var stun_seconds: float = 0.0
@export var icon: Texture2D = null


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or not String(id).begins_with("skill_"):
		errors.append("id must be a non-empty 'skill_*' id")
	if not ELEMENTS.has(element):
		errors.append("element '%s' is not one of the four canon elements (COMBAT_DESIGN §3)"
			% element)
	if qi_cost < 0 or cooldown < 0.0:
		errors.append("qi_cost and cooldown are >= 0")
	if prepare_seconds <= 0.0 or release_seconds <= 0.0 or recover_seconds <= 0.0 \
			or channel_seconds < 0.0:
		errors.append("prepare, release and recover must be > 0 (channel may be 0)")
	if power_multiplier <= 0.0 or range_px <= 0.0:
		errors.append("power and range must be > 0")
	if delivery == Delivery.CONE and (arc_degrees <= 0.0 or arc_degrees > 360.0):
		errors.append("a cone needs arc_degrees in (0, 360]")
	if delivery == Delivery.BOLT and (bolt_speed <= 0.0 or bolt_radius <= 0.0):
		errors.append("a bolt needs speed and radius > 0")
	if knockback_px < 0.0 or stun_seconds < 0.0:
		errors.append("effects are >= 0")
	if icon == null:
		errors.append("a skill on the dock needs an icon")
	return errors


## The swing-geometry twin of a CONE skill, so the hit test is `CombatService`'s own.
func as_attack() -> AttackData:
	var attack := AttackData.new()
	attack.id = StringName("attack_" + String(id))
	attack.windup_seconds = prepare_seconds + channel_seconds
	attack.active_seconds = release_seconds
	attack.recovery_seconds = recover_seconds
	attack.reach_pixels = range_px
	attack.arc_degrees = arc_degrees
	attack.power_multiplier = power_multiplier
	attack.critical_chance_percent = 0
	attack.critical_multiplier = 1.0
	return attack


func total_seconds() -> float:
	return prepare_seconds + channel_seconds + release_seconds + recover_seconds

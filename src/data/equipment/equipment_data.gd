extends Resource
class_name EquipmentData
## EquipmentData — Aetheria data (something worn or wielded, Phase 14).
##
## `DATA_SCHEMA.md` §3 EquipmentData: a slot, stat modifiers, an optional realm gate. Two things
## an equipment piece may change, each owned by its own system:
##   * NUMBERS — `attack_bonus` / `defense_bonus` enter the existing damage formula through
##     `StatsComponent` (the attacker's attack, the target's defense), never a second formula;
##   * the ATTACK itself — a weapon brings its own `AttackData` (`attack`), so a Kiếm swings with
##     a Kiếm's reach, arc and timing; its `weapon_family` is canon (CL-10).
## And one thing it changes in presentation only: a garment may name the visual profile the
## body is drawn with (`body_visual`) — a whole drawn set, so the robe is pixel-exact on every
## frame, facing and action rather than a tint over the old one.

enum Slot { WEAPON, BODY }

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var slot: Slot = Slot.WEAPON
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
## WEAPON: the attack this weapon swings with (its `weapon_family` must be canon).
@export var attack: AttackData = null
## BODY: the visual profile the wearer is drawn with (presentation only).
@export var body_visual: CharacterVisualProfileData = null
@export var required_realm: StringName = &""
@export var required_layer: int = 0


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or not String(id).begins_with("equip_"):
		errors.append("id must be a non-empty 'equip_*' id (got '%s')" % id)
	if name_key == &"":
		errors.append("name_key is empty")
	if attack_bonus < 0 or defense_bonus < 0:
		errors.append("bonuses are >= 0 (a cursed item is a design, not a sign error)")
	if slot == Slot.WEAPON:
		if attack == null or not attack.is_valid():
			errors.append("a weapon needs a valid AttackData")
		elif not AttackData.WEAPON_FAMILIES.has(attack.weapon_family):
			errors.append("weapon family '%s' is not canon (CL-10)" % attack.weapon_family)
	if slot == Slot.BODY and body_visual != null and not body_visual.is_valid():
		errors.append("body_visual is invalid")
	return errors

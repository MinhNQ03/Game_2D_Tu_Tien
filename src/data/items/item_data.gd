extends Resource
class_name ItemData
## ItemData — Aetheria data (one kind of item, Phase 13).
##
## CONTENT, not behaviour (`DATA_SCHEMA.md` §3 ItemData). What USING it does is named by
## `use_kind` + `use_amount` and executed by `InventoryRuntime`, which asks the owning system —
## health heals through the body, qi is absorbed through `CultivationService`, a manual teaches
## through the Knowledge Core. An item never reaches into another system's state itself.
##
## Every item has a SINK (`ECONOMY_CRAFTING_DESIGN.md` §2): a pill and a spirit stone are burned
## by use; a manual is consumed when read; equipment is worn (P14).

enum Category { CONSUMABLE, MATERIAL, MANUAL, EQUIPMENT }

## What using it does. NONE = not usable from the inventory (equipment is equipped, P14).
enum UseKind { NONE, HEAL, ABSORB_QI, READ }

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var desc_key: StringName = &""
@export var icon: Texture2D = null
@export var category: Category = Category.CONSUMABLE
@export var stack_max: int = 1
@export var use_kind: UseKind = UseKind.NONE
## HEAL: hit points. ABSORB_QI: tu vi (before the body's efficiency).
@export var use_amount: int = 0
## READ: the knowledge ids reading it teaches (through `KnowledgeService`).
@export var teaches: Array[StringName] = []
## EQUIPMENT: the `EquipmentData` it is (P14).
@export var equipment: Resource = null


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or not String(id).begins_with("item_"):
		errors.append("id must be a non-empty 'item_*' id (got '%s')" % id)
	if name_key == &"" or desc_key == &"":
		errors.append("name_key and desc_key are required")
	if stack_max < 1:
		errors.append("stack_max must be >= 1")
	if icon == null:
		errors.append("an item the player holds must have an icon")
	match use_kind:
		UseKind.HEAL, UseKind.ABSORB_QI:
			if use_amount <= 0:
				errors.append("a HEAL / ABSORB_QI item needs use_amount > 0")
		UseKind.READ:
			if teaches.is_empty():
				errors.append("a READ item must teach something")
	if category == Category.EQUIPMENT and equipment == null:
		errors.append("an EQUIPMENT item must reference its EquipmentData")
	return errors

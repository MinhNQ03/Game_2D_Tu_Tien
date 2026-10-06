extends Resource
class_name RealmData
## RealmData — Aetheria data (one CẢNH GIỚI: a macro realm and its layers, Phase 12).
##
## CONTENT, not behaviour. The realm hierarchy's MEANING is frozen canon (`CANON_LEDGER.md`
## CL-02/CL-03, `PROGRESSION_CULTIVATION_DESIGN.md` §2-§4); everything numeric here — costs,
## perception radii, capacities — is tuning data that §11 explicitly leaves unfrozen. The one
## owner of the rules that read it is `CultivationService`.
##
## LAYERS. A numbered realm has `layer_count` (9) layers; PHÀM has 0 (no layers: the
## baseline), and the two structural tiers (THÁI THIÊN, VÔ THIÊN) are `structural` — they exist
## to keep the ladder open (CL-15) and can never be attempted.
##
## PER-LAYER ARRAYS hold one entry per layer (index 0 = layer 1). A realm with no layers (PHÀM)
## holds exactly ONE entry, its own baseline. So `size() == max(1, layer_count)` for every
## per-layer array — the validator enforces it, because an array one short would make layer 9
## read a default nobody authored.
##
## WHAT A STEP COSTS. `step_costs[i]` is the tu vi required to advance OUT of layer i+1 (or out
## of PHÀM, for its single entry): the last entry is the cost of breaking into the NEXT realm.
##
## WHAT A STEP GIVES (the capability contract, §4: never just a bigger number). Every layer moves
## at least one NON-DAMAGE dimension, and the validator refuses a realm whose layers move none:
##   * `perception_px` — how far the cultivator SENSES qi (Hậu Thiên: "sense qi nearby");
##   * `qi_capacity` — the linh khí the body can hold (P15 techniques spend it);
##   * `gather_efficiency` — how much of a vein's flow the body actually keeps.

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var desc_key: StringName = &""

## Ladder position (PHÀM = 0). Unique within the ladder; the ladder is ordered by it.
@export var order: int = 0

## 9 for a numbered realm, 0 for PHÀM and the structural tiers.
@export var layer_count: int = 0

## A structural tier exists for meaning only; it is never attemptable.
@export var structural: bool = false

## Tu vi to advance out of each layer (see above). Empty for a structural tier.
@export var step_costs: PackedInt32Array = PackedInt32Array()

## Knowledge ids a cultivator must hold to ENTER this realm (its layer 1). Read through the
## Knowledge Core — never copied (D-040 / C-012).
@export var entry_knowledge: Array[StringName] = []

## Capability per layer (see above).
@export var perception_px: PackedFloat32Array = PackedFloat32Array()
@export var qi_capacity: PackedInt32Array = PackedInt32Array()
@export var gather_efficiency: PackedFloat32Array = PackedFloat32Array()


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	if name_key == &"":
		errors.append("name_key is empty")
	if layer_count < 0:
		errors.append("layer_count must be >= 0 (got %d)" % layer_count)
	if structural:
		if layer_count != 0:
			errors.append("a structural tier has no layers")
		return errors
	var rows := entries()
	if step_costs.size() != rows:
		errors.append("step_costs holds %d entries, expected %d" % [step_costs.size(), rows])
	for cost in step_costs:
		if cost <= 0:
			errors.append("every step cost must be > 0 (got %d)" % cost)
			break
	if perception_px.size() != rows:
		errors.append("perception_px holds %d entries, expected %d"
			% [perception_px.size(), rows])
	if qi_capacity.size() != rows:
		errors.append("qi_capacity holds %d entries, expected %d" % [qi_capacity.size(), rows])
	if gather_efficiency.size() != rows:
		errors.append("gather_efficiency holds %d entries, expected %d"
			% [gather_efficiency.size(), rows])
	if not errors.is_empty():
		return errors
	for i in range(1, rows):
		var moved := (perception_px[i] > perception_px[i - 1]
			or qi_capacity[i] > qi_capacity[i - 1]
			or gather_efficiency[i] > gather_efficiency[i - 1])
		if not moved:
			errors.append(("layer %d moves no non-damage dimension over layer %d — nine layers "
				+ "of nothing is forbidden (PROGRESSION_CULTIVATION_DESIGN.md §3)") % [i + 1, i])
	return errors


## How many per-layer entries this realm authors: its layers, or 1 for a layerless realm.
func entries() -> int:
	return maxi(1, layer_count)


## Index into the per-layer arrays for `layer` (1-based; 0 for a layerless realm).
func row_for(layer: int) -> int:
	if layer_count == 0:
		return 0
	return clampi(layer - 1, 0, layer_count - 1)

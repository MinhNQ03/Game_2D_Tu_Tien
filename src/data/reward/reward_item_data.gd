extends Resource
class_name RewardItemData
## RewardItemData — Aetheria data (one kind of item a reward hands over, Phase 19).

@export var item: ItemData = null
@export var count: int = 1


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if item == null:
		errors.append("names no item")
	if count < 1 or count > RewardData.MAX_ITEM_COUNT:
		errors.append("count %d is outside 1..%d" % [count, RewardData.MAX_ITEM_COUNT])
	return errors

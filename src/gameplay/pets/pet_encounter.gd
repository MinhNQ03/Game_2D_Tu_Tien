extends WorldInteractable
class_name PetEncounter
## PetEncounter — Aetheria gameplay (a stray creature the player can befriend, Phase 16).
##
## How the first linh thú is met: an ordinary frontier animal keeping to the edge of the
## village, drawn with its own `PetData.visual_profile`, that the player walks up to and
## befriends with the interact key. It EXPOSES the opportunity; `PetRuntime` owns the result
## (ownership lives in `PetStore`) and hides this node once the pet is owned, on every map
## arrival, so a befriended stray is never offered twice.
##
## INTANGIBLE_BY_DESIGN: a small living animal that steps aside — it has no body, so it can
## never wedge the player against the fence it sits by. Its reach is a distance, as always.

const KIND := &"pet_encounter"
const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

## The pet this stray becomes.
@export var pet: PetData = null

var _visual: CharacterVisualComponent = null


func _init() -> void:
	prompt_key = &"UI_HUD_PET_BEFRIEND"
	reach_px = 26.0


func _ready() -> void:
	if pet == null or not pet.is_valid():
		push_error("[pet-encounter] '%s' has no valid PetData; nothing can be befriended" % name)
		visible = false
		return
	_visual = VisualComponentScript.new() as CharacterVisualComponent
	_visual.name = "CharacterVisualComponent"
	add_child(_visual)
	if not _visual.setup(pet.visual_profile):
		_visual.queue_free()
		_visual = null


func interaction_kind() -> StringName:
	return KIND


func interaction_id() -> StringName:
	return pet.id if pet != null else &""


func is_available() -> bool:
	return visible and pet != null

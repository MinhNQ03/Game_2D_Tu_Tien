extends WorldInteractable
class_name KnowledgeSource
## KnowledgeSource — Aetheria gameplay (something in the world that can TEACH, Phase 12).
##
## A stele, later a scroll rack or a mural: a thing the player reads, which grants named
## knowledge through `KnowledgeService` — never by setting a flag of its own (D-040 / C-012). It
## EXPOSES an opportunity (`ROADMAP.md` P17 wording); the Knowledge Core owns the result.
##
## Authored in a map under `KnowledgeSources`. `MapBase` tracks which source the player stands
## within `reach_px` of (a distance test, headless-safe) and, on the semantic `interact` intent,
## announces `knowledge_source_read(source)`; `WorldRuntime` forwards it to the
## `KnowledgeRuntime`, which grants each id in order. Reading twice teaches nothing new: the
## service is idempotent.

## The stable id recorded as the knowledge's source (where it was learned).
@export var source_id: StringName = &""

## What reading it teaches, in order.
@export var grants: Array[StringName] = []

## `reach_px` and `prompt_key` are the `WorldInteractable` contract (Phase 16); a source's verb
## defaults to "Read" unless its scene authors another.
const KIND := &"knowledge_source"


func _init() -> void:
	prompt_key = &"UI_HUD_READ_ACTION"


func _ready() -> void:
	if source_id == &"" or grants.is_empty():
		push_error("[knowledge-source] '%s' teaches nothing (source_id '%s', %d grants)"
			% [name, source_id, grants.size()])


func interaction_kind() -> StringName:
	return KIND


func interaction_id() -> StringName:
	return source_id

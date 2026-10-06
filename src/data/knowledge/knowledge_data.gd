extends Resource
class_name KnowledgeData
## KnowledgeData — Aetheria data (one named piece of TRI THỨC, Phase 12).
##
## Knowledge is the third progression concept (`CANON_LEDGER.md` CL-14,
## `PROGRESSION_CULTIVATION_DESIGN.md` §7): discrete and named, never a score; permanent; it may
## gate, and it must also pay off when it does not gate. This resource only DESCRIBES a piece of
## knowledge — whether the player holds it is `KnowledgeStore`'s, and only `KnowledgeService`
## may change that (D-040 / C-012).

## What KIND of knowing it is. Presentation reads it to phrase the moment ("you learned a
## method" reads differently from "you noticed something").
enum Kind { METHOD, RECORD, OBSERVATION }

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var desc_key: StringName = &""
@export var kind: Kind = Kind.RECORD


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or not String(id).begins_with("know_"):
		errors.append("id must be a non-empty 'know_*' id (got '%s')" % id)
	if name_key == &"":
		errors.append("name_key is empty")
	if desc_key == &"":
		errors.append("desc_key is empty — knowledge must say what was learned")
	return errors

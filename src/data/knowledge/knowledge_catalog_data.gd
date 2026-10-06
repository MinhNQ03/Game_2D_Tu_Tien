extends Resource
class_name KnowledgeCatalogData
## KnowledgeCatalogData — Aetheria data (every piece of knowledge that exists, Phase 12).
##
## The catalog is what makes a grant DETERMINISTIC and checkable: `KnowledgeService` refuses an
## id the catalog does not name, so a typo in a producer is a loud refusal rather than a phantom
## entry nobody can ever query. Small on purpose (§7a): authored for cultivation's prerequisites
## and its non-gating payoffs, until the content producers (P17-P20) arrive.

@export var id: StringName = &""
@export var entries: Array[KnowledgeData] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	if entries.is_empty():
		errors.append("the catalog names no knowledge")
	var seen := {}
	for entry in entries:
		if entry == null:
			errors.append("a null entry")
			continue
		for reason in entry.validation_errors():
			errors.append("%s: %s" % [entry.id, reason])
		if seen.has(entry.id):
			errors.append("'%s' is listed twice" % entry.id)
		seen[entry.id] = true
	return errors


func has(knowledge_id: StringName) -> bool:
	return entry(knowledge_id) != null


func entry(knowledge_id: StringName) -> KnowledgeData:
	for e in entries:
		if e != null and e.id == knowledge_id:
			return e
	return null

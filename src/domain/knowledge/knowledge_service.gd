extends RefCounted
class_name KnowledgeService
## KnowledgeService — Aetheria domain (the ONE mutation path for knowledge, Phase 12, D-040).
##
## Every producer — a stele today; dialogue, quests and story from P18-P20 — grants knowledge by
## calling `grant()` here, and every consumer — cultivation today, techniques in P15 — READS it
## here. Nothing keeps its own copy. Deterministic: a grant depends only on the catalog and the
## store, never on time or chance.
##
## It emits nothing. The per-session `KnowledgeRuntime` announces `knowledge_gained` from a
## `GRANTED` result, exactly as `ProgressionRuntime` announces what `ProgressionService` decided —
## a domain service stays a plain, testable RefCounted.

const GRANTED := &"granted"
const ALREADY_KNOWN := &"already_known"
const UNKNOWN_ID := &"unknown_id"
const NOT_READY := &"not_ready"

var _catalog: KnowledgeCatalogData = null
var _store: KnowledgeStore = null


func _init(catalog: KnowledgeCatalogData = null, store: KnowledgeStore = null) -> void:
	if catalog == null or store == null:
		return
	if not catalog.is_valid():
		push_error("[knowledge] refusing an invalid catalog '%s': %s"
			% [catalog.id, str(catalog.validation_errors())])
		return
	_catalog = catalog
	_store = store


func is_ready() -> bool:
	return _catalog != null and _store != null


func catalog() -> KnowledgeCatalogData:
	return _catalog


func store() -> KnowledgeStore:
	return _store


## Grant `knowledge_id`, learned from `source_id`. Returns GRANTED, ALREADY_KNOWN (idempotent: a
## second reading of the same stele teaches nothing new), UNKNOWN_ID (refused loudly — the
## catalog does not name it) or NOT_READY.
func grant(knowledge_id: StringName, source_id: StringName) -> StringName:
	if not is_ready():
		return NOT_READY
	if not _catalog.has(knowledge_id):
		push_error("[knowledge] refusing to grant '%s': it is not in the catalog" % knowledge_id)
		return UNKNOWN_ID
	if _store.knows(knowledge_id):
		return ALREADY_KNOWN
	_store.record(knowledge_id, source_id)
	return GRANTED


func knows(knowledge_id: StringName) -> bool:
	return is_ready() and _store.knows(knowledge_id)


## True when every id in `required` is held (an empty requirement is always met).
func knows_all(required: Array[StringName]) -> bool:
	for knowledge_id in required:
		if not knows(knowledge_id):
			return false
	return true


## The held knowledge of one KIND, in acquisition order (a journal reads this).
func query(kind: KnowledgeData.Kind) -> Array[KnowledgeData]:
	var out: Array[KnowledgeData] = []
	if not is_ready():
		return out
	for knowledge_id in _store.known_ids():
		var entry := _catalog.entry(knowledge_id)
		if entry != null and entry.kind == kind:
			out.append(entry)
	return out

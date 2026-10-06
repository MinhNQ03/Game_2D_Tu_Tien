extends Node
class_name KnowledgeRuntime
## KnowledgeRuntime — Aetheria gameplay (the per-session home of the Knowledge Core, Phase 12).
##
## A per-session node under `Main/Systems`, exactly like `ProgressionRuntime` — NOT an autoload
## (the budget is frozen at five) and not a global manager. It owns, for one session, the
## player's `KnowledgeStore`, the one `KnowledgeService` that may change it, and the authored
## catalog, and it ANNOUNCES what the service decided:
##
##   `knowledge_gained(knowledge_id, source_id)` — once per id, ever; a second grant of the same
##   id is ALREADY_KNOWN and announces nothing.
##
## Producers call `grant()` (a stele today, via `WorldRuntime`); consumers read `get_service()`
## (cultivation today, techniques in P15). Nobody else holds a copy (D-040 / C-012).
##
## PERSISTENCE: `to_dict()` / `from_dict()` delegate to the store, validated against the catalog
## (SAVE_FORMAT: knowledge serializes through its own boundary). No save system exists yet; the
## boundary is what a save will call.

signal knowledge_gained(knowledge_id: StringName, source_id: StringName)

const CATALOG_PATH := "res://data/knowledge/knowledge_catalog.tres"

var _catalog: KnowledgeCatalogData = null
var _store: KnowledgeStore = null
var _service: KnowledgeService = null
var _session_active: bool = false


## Begin a session with an EMPTY store (a new run knows nothing). Fails closed and loud: a
## session whose knowledge cannot be granted is one where the first stele silently teaches
## nothing — a game that looks fine and cannot progress (L-025).
func start_session() -> bool:
	if _session_active:
		push_error("[knowledge-rt] start_session called while a session is already active")
		return false
	if not ResourceLoader.exists(CATALOG_PATH):
		return _fail_start("the knowledge catalog is missing: %s" % CATALOG_PATH)
	var catalog := load(CATALOG_PATH) as KnowledgeCatalogData
	if catalog == null:
		return _fail_start("%s did not load as a KnowledgeCatalogData" % CATALOG_PATH)
	if not catalog.is_valid():
		return _fail_start("the knowledge catalog is invalid: %s"
			% str(catalog.validation_errors()))
	var store := KnowledgeStore.new()
	var service := KnowledgeService.new(catalog, store)
	if not service.is_ready():
		return _fail_start("the KnowledgeService refused the catalog")
	_catalog = catalog
	_store = store
	_service = service
	_session_active = true
	return true


func _fail_start(reason: String) -> bool:
	push_error("[knowledge-rt] knowledge session NOT started: %s" % reason)
	return false


func end_session() -> void:
	_catalog = null
	_store = null
	_service = null
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_service() -> KnowledgeService:
	return _service


func get_catalog() -> KnowledgeCatalogData:
	return _catalog


## Grant one id through the service, announcing it when it was new. Returns the service's
## outcome (`KnowledgeService.GRANTED` / `ALREADY_KNOWN` / `UNKNOWN_ID` / `NOT_READY`).
func grant(knowledge_id: StringName, source_id: StringName) -> StringName:
	if not _session_active:
		push_error("[knowledge-rt] a grant of '%s' arrived with no active session" % knowledge_id)
		return KnowledgeService.NOT_READY
	var outcome := _service.grant(knowledge_id, source_id)
	if outcome == KnowledgeService.GRANTED:
		knowledge_gained.emit(knowledge_id, source_id)
	return outcome


## Grant every id `source` teaches, in order. Returns the ids that were NEW.
func read_source(source_id: StringName, grants: Array[StringName]) -> Array[StringName]:
	var learned: Array[StringName] = []
	for knowledge_id in grants:
		if grant(knowledge_id, source_id) == KnowledgeService.GRANTED:
			learned.append(knowledge_id)
	return learned


func to_dict() -> Dictionary:
	return _store.to_dict() if _store != null else {}


## Restore a store from a save payload. All-or-nothing, validated against the catalog; restoring
## announces nothing (it is not learning).
func from_dict(data: Dictionary) -> bool:
	if not _session_active:
		push_error("[knowledge-rt] from_dict with no active session")
		return false
	return _store.from_dict(data, _catalog)

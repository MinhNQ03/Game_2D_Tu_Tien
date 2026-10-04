extends Node
class_name RelationshipRuntime
## RelationshipRuntime — Aetheria gameplay (per-session owner of the relationship graph).
##
## A node under `Main/Systems` (a SIBLING of `WorldRuntime`, NOT an autoload — D-017 autoload
## budget is unchanged). It owns the domain `RelationshipStore` + `RelationshipService` +
## `RelationshipConfigData` for the running session and SURVIVES map transitions (the
## SceneRouter only swaps the content scene under `Main/World`; everything under
## `Main/Systems` persists). This is the runtime home of relationship state
## (`docs/RELATIONSHIP_SYSTEM.md` §11, D-026).
##
## Scope discipline: it knows NOTHING about presentation, dialogue, quests, or sect politics
## (those are later phases and would reach IN to it, never the other way). It is a thin
## session wrapper around the pure-domain service; WorldRuntime stays the map/player
## coordinator and is NOT turned into a God object (`03-architecture.md`).

const CONFIG_PATH := "res://data/relationship/relationship_config.tres"
const RULES_PATH := "res://data/relationship/relationship_rules.tres"

var _config: RelationshipConfigData = null
var _store: RelationshipStore = null
var _service: RelationshipService = null
var _session_active: bool = false


## Begin a relationship session: load + validate the config and rule catalog, then build a
## fresh empty store + service. Returns false (loud) on a missing/invalid config.
##
## FATAL at the caller since Phase 06 (D-037). In Phase 05 this was advisory — nothing
## consumed the graph, so Main logged a failure and carried on. The sect session now MIRRORS
## Sect↔Sect diplomacy into this graph, so a missing graph means the sect world would start
## half-wired (sect state declaring enemies no relationship edge records). Main therefore
## aborts New Game and unwinds to the menu on false.
##
## Idempotent: a second call with an active session is a no-op returning true.
func start_session() -> bool:
	if _session_active and _service != null:
		return true
	_config = _load_config()
	if _config == null:
		return false
	_store = RelationshipStore.new(_config)
	_service = RelationshipService.new(_store, _config)
	var rules := _load_rules()
	if not rules.is_empty():
		_service.set_rules(rules)
	_session_active = true
	return true


## End the relationship session: drop the store/service (RefCounted, freed with the last
## reference). Safe to call more than once.
func end_session() -> void:
	_session_active = false
	_service = null
	_store = null
	_config = null


func is_session_active() -> bool:
	return _session_active


## The session's RelationshipService (or null before a session starts). The mutation + query
## entry point for any future consumer (none in Phase 05).
func get_service() -> RelationshipService:
	return _service


## The session's RelationshipStore (or null). For read-only queries + save serialization.
func get_store() -> RelationshipStore:
	return _store


func get_config() -> RelationshipConfigData:
	return _config


# --- Loading (boundary-validated) -------------------------------------------

func _load_config() -> RelationshipConfigData:
	if not ResourceLoader.exists(CONFIG_PATH):
		push_error("[relationship] config missing: %s" % CONFIG_PATH)
		return null
	var cfg := load(CONFIG_PATH) as RelationshipConfigData
	if cfg == null:
		push_error("[relationship] config failed to load as RelationshipConfigData")
		return null
	if not cfg.is_valid():
		push_error("[relationship] invalid config: %s" % str(cfg.validation_errors()))
		return null
	return cfg


## Load + validate the rule catalog, returning its `event_kind -> rule` lookup. Returns an
## empty dict (not an error) if the catalog is absent — events simply won't resolve until
## content is authored. A PRESENT-but-INVALID catalog is reported loudly and ignored.
func _load_rules() -> Dictionary:
	if not ResourceLoader.exists(RULES_PATH):
		return {}
	var cat := load(RULES_PATH) as RelationshipRuleCatalog
	if cat == null:
		push_error("[relationship] rules failed to load as RelationshipRuleCatalog")
		return {}
	if not cat.is_valid():
		push_error("[relationship] invalid rule catalog: %s" % str(cat.validation_errors()))
		return {}
	return cat.build_lookup()

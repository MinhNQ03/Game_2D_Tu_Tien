extends TestCase
## The KNOWLEDGE CORE (Phase 12, D-040 / C-012): `KnowledgeStore` + `KnowledgeService` +
## `KnowledgeRuntime`. Exit criteria (`ROADMAP.md` P12): grant / query / persist round-trips,
## only the service mutates the collection, and a cultivation prerequisite reads it.

const CATALOG := "res://data/knowledge/knowledge_catalog.tres"
const RuntimeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")


func _service() -> KnowledgeService:
	return KnowledgeService.new(load(CATALOG), KnowledgeStore.new())


func test_the_shipped_catalog_is_valid() -> void:
	var catalog: KnowledgeCatalogData = load(CATALOG)
	assert_true(catalog.is_valid(), "catalog validates: %s" % str(catalog.validation_errors()))
	assert_true(catalog.has(&"know_dan_khi_quyet"), "the breathing method exists")


func test_a_grant_is_deterministic_idempotent_and_refuses_unknown_ids() -> void:
	var service := _service()
	assert_false(service.knows(&"know_dan_khi_quyet"), "a new run knows nothing")
	assert_eq(service.grant(&"know_dan_khi_quyet", &"src_a"), KnowledgeService.GRANTED,
		"the first grant is granted")
	assert_true(service.knows(&"know_dan_khi_quyet"), "and is then known")
	assert_eq(service.store().source_of(&"know_dan_khi_quyet"), &"src_a", "with its source")
	assert_eq(service.grant(&"know_dan_khi_quyet", &"src_b"), KnowledgeService.ALREADY_KNOWN,
		"a second grant teaches nothing")
	assert_eq(service.store().source_of(&"know_dan_khi_quyet"), &"src_a",
		"and does not rewrite where it was learned")
	assert_eq(service.grant(&"know_not_real", &"x"), KnowledgeService.UNKNOWN_ID,
		"an id the catalog does not name is refused")
	assert_eq(service.store().count(), 1, "nothing phantom was recorded")


func test_query_by_kind_in_acquisition_order() -> void:
	var service := _service()
	service.grant(&"know_lac_ha_stele_record", &"s")
	service.grant(&"know_dan_khi_quyet", &"s")
	var methods := service.query(KnowledgeData.Kind.METHOD)
	assert_eq(methods.size(), 1, "one METHOD held")
	assert_eq(methods[0].id, &"know_dan_khi_quyet", "the breathing method")
	assert_eq(service.query(KnowledgeData.Kind.RECORD).size(), 1, "one RECORD held")


func test_persistence_round_trips_and_rejects_corrupt_payloads() -> void:
	var service := _service()
	service.grant(&"know_dan_khi_quyet", &"source_lac_ha_stele")
	service.grant(&"know_lac_ha_stele_record", &"source_lac_ha_stele")
	var saved := service.store().to_dict()
	var restored := KnowledgeStore.new()
	assert_true(restored.from_dict(saved, load(CATALOG)), "a saved store restores")
	assert_eq(restored.known_ids(), service.store().known_ids(), "same ids, same order")
	assert_eq(restored.source_of(&"know_dan_khi_quyet"), &"source_lac_ha_stele", "same sources")
	var phantom := {"known": [{"id": "know_forged", "source": "x"}]}
	assert_false(restored.from_dict(phantom, load(CATALOG)), "an uncatalogued id is refused")
	assert_eq(restored.count(), 2, "and the store was left untouched")
	var twice := {"known": [{"id": "know_dan_khi_quyet", "source": "a"},
		{"id": "know_dan_khi_quyet", "source": "b"}]}
	assert_false(restored.from_dict(twice, load(CATALOG)), "a duplicate row is refused")
	assert_false(restored.from_dict({"known": [{"id": 7, "source": "a"}]}, load(CATALOG)),
		"a wrongly typed id is refused (L-024)")


func test_the_runtime_announces_each_new_id_once() -> void:
	var runtime: KnowledgeRuntime = RuntimeScript.new()
	add_to_tree(runtime)
	assert_true(runtime.start_session(), "the session starts")
	var heard: Array = []
	runtime.knowledge_gained.connect(func(id: StringName, _s: StringName) -> void: heard.append(id))
	var learned := runtime.read_source(&"source_lac_ha_stele",
		[&"know_dan_khi_quyet", &"know_lac_ha_stele_record"] as Array[StringName])
	assert_eq(learned.size(), 2, "the stele teaches both")
	assert_eq(runtime.read_source(&"source_lac_ha_stele",
		[&"know_dan_khi_quyet"] as Array[StringName]).size(), 0, "a second reading teaches nothing")
	assert_eq(heard, [&"know_dan_khi_quyet", &"know_lac_ha_stele_record"],
		"knowledge_gained fired once per id, in order")
	runtime.end_session()
	assert_null(runtime.get_service(), "the session's service is dropped on end")
	free_node(runtime)


## STRUCTURAL: only the service records into the store (Story/Quest never own knowledge).
func test_only_the_service_mutates_the_collection() -> void:
	var offenders: Array[String] = []
	_walk("res://src", offenders)
	assert_eq(offenders, [] as Array[String],
		"only KnowledgeService may call KnowledgeStore.record(): %s" % str(offenders))


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_walk(full, out)
		elif entry.ends_with(".gd") and not full.ends_with("knowledge_service.gd") \
				and not full.ends_with("knowledge_store.gd"):
			if ".record(" in FileAccess.get_file_as_string(full):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

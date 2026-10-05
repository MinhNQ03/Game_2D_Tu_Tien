extends TestCase
## Unit tests for `CharacterRegistry` (Phase 08) — the session's character population and the
## ONE resolver source every service takes.
##
## What is worth testing here is not storage but the two refusals: it must never REPLACE a
## live `CharacterState` (two live answers to "who is this" is the defect it exists to
## prevent), and its hydrate must be atomic. Plus the resolver, because the whole reason this
## class exists is that the bootstrap used to hand each service its own closure that knew
## about exactly one character.

const RegistryScript := preload("res://src/domain/character/character_registry.gd")
const CharacterTemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

const ALICE := &"char_alice"
const BOB := &"char_bob"


func _template(tid: StringName = &"char_t") -> CharacterTemplateData:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 20
	stats.attack = 3
	stats.defense = 1
	stats.move_speed = 100.0
	var t: CharacterTemplateData = CharacterTemplateScript.new()
	t.id = tid
	t.name_key = &"NAME"
	t.base_stats = stats
	return t


func _character(cid: StringName) -> CharacterState:
	return CharacterState.create_from_template(_template(), cid)


func _registry() -> CharacterRegistry:
	return RegistryScript.new()


# === 1-3. Registration ======================================================

func test_01_add_and_find() -> void:
	var registry := _registry()
	assert_eq(registry.count(), 0, "a fresh registry is empty")
	assert_true(registry.add(_character(ALICE)), "a valid character registers")
	assert_eq(registry.count(), 1, "the count reflects it")
	assert_true(registry.has(ALICE), "has() finds it")
	assert_not_null(registry.get_character(ALICE), "and so does get_character")
	assert_null(registry.get_character(&"nobody"),
		"an unknown id resolves to null QUIETLY — that is the resolver contract services "
		+ "expect, and the caller reports it with its own context")


## A duplicate is REFUSED rather than replacing the existing state. A replacement would leave
## every component and service still holding the OLD `CharacterState` while the registry
## answered with the new one — two live answers to "who is this character".
func test_02_a_duplicate_is_refused_not_replaced() -> void:
	var registry := _registry()
	var original := _character(ALICE)
	original.current_hp = 7
	assert_true(registry.add(original), "the first add succeeds")
	var replacement := _character(ALICE)
	assert_false(registry.add(replacement), "a second add with the same id is REFUSED")
	assert_eq(registry.get_character(ALICE).get_instance_id(), original.get_instance_id(),
		"and the ORIGINAL object is still the one the registry answers with")
	assert_eq(registry.get_character(ALICE).current_hp, 7, "with its state intact")


func test_03_add_rejects_malformed_input() -> void:
	var registry := _registry()
	assert_false(registry.add(null), "a null state is rejected")
	var anonymous := _character(ALICE)
	anonymous.instance_id = &""
	assert_false(registry.add(anonymous), "a state with no instance_id is rejected")
	assert_eq(registry.count(), 0, "and nothing was stored by either rejection")


# === 4-5. Deterministic iteration ===========================================

## Every iteration must be sorted, so anything built by walking the population (a save
## snapshot, an enrolment order, a test assertion) is reproducible regardless of the order
## characters happened to be added in.
func test_04_iteration_is_sorted_not_insertion_ordered() -> void:
	var registry := _registry()
	registry.add(_character(&"char_zz"))
	registry.add(_character(ALICE))
	registry.add(_character(&"char_mm"))
	var ids := registry.ids_sorted()
	assert_eq(ids.size(), 3, "all three are listed")
	assert_eq(String(ids[0]), "char_alice", "sorted, not insertion-ordered")
	assert_eq(String(ids[1]), "char_mm", "second")
	assert_eq(String(ids[2]), "char_zz", "third")
	var all := registry.all()
	assert_eq(all.size(), 3, "all() returns every character")
	assert_eq(all[0].instance_id, ALICE, "in the same sorted order")


func test_05_remove_and_clear() -> void:
	var registry := _registry()
	registry.add(_character(ALICE))
	registry.add(_character(BOB))
	assert_true(registry.remove(ALICE), "remove reports success")
	assert_false(registry.remove(ALICE), "removing twice reports false")
	assert_eq(registry.count(), 1, "one character remains")
	registry.clear()
	assert_eq(registry.count(), 0, "clear empties the population")


# === 6. The resolver seam ===================================================

## The resolver is the point of the class: ONE Callable, backed by ONE collection, that every
## service takes. It must answer for every registered character and null for the rest.
func test_06_the_resolver_answers_for_the_whole_population() -> void:
	var registry := _registry()
	registry.add(_character(ALICE))
	registry.add(_character(BOB))
	var resolve := registry.resolver()
	assert_true(resolve.is_valid(), "the resolver is a usable Callable")
	var alice: CharacterState = resolve.call(ALICE)
	assert_not_null(alice, "it resolves the first character")
	assert_eq(alice.instance_id, ALICE, "to the right one")
	assert_not_null(resolve.call(BOB), "and the second — not just whichever one a closure "
		+ "happened to capture, which is the bug this replaced")
	assert_null(resolve.call(&"nobody"), "and null for an unknown id")
	# A character added AFTER the resolver was handed out must still resolve: the Callable is
	# a view onto the live collection, not a snapshot of it. The world simulation relies on
	# this — it adds its cast after the sect service already holds the resolver.
	registry.add(_character(&"char_late"))
	assert_not_null(resolve.call(&"char_late"),
		"a character added after the resolver was created still resolves")


# === 7-8. Serialization =====================================================

func test_07_the_population_round_trips() -> void:
	var registry := _registry()
	var alice := _character(ALICE)
	alice.current_hp = 11
	alice.sect_id = &"sect_a"
	registry.add(alice)
	registry.add(_character(BOB))
	var snapshot := registry.to_dict()

	var restored := _registry()
	assert_true(restored.hydrate(snapshot), "the snapshot hydrates")
	assert_eq(restored.count(), 2, "both characters came back")
	assert_eq(restored.get_character(ALICE).current_hp, 11, "with their persistent state")
	assert_eq(restored.get_character(ALICE).sect_id, &"sect_a", "including the derived cache")
	assert_eq(str(restored.to_dict()), str(snapshot), "and the round trip is byte-stable")


## Hydrate is ATOMIC: a rejected payload must leave the existing population untouched rather
## than half-replaced.
func test_08_hydrate_fails_closed_and_atomically() -> void:
	var registry := _registry()
	registry.add(_character(ALICE))
	var before := str(registry.to_dict())

	assert_false(registry.hydrate("not a dict"), "a non-dict payload is rejected")
	assert_false(registry.hydrate({}), "a payload with no by_instance_id is rejected")
	assert_false(registry.hydrate({"by_instance_id": []}),
		"a non-dict by_instance_id is rejected")
	assert_false(registry.hydrate({"by_instance_id": {"x": 5}}),
		"a malformed row is rejected")
	assert_false(registry.hydrate({"by_instance_id": {"x": {"instance_id": "y"}}}),
		"a key that disagrees with its row's instance_id is rejected")
	assert_eq(str(registry.to_dict()), before,
		"and the population is byte-identical after every rejection")

	# A good payload with MORE rows than before replaces the whole population at once.
	var bigger := _registry()
	bigger.add(_character(ALICE))
	bigger.add(_character(BOB))
	assert_true(registry.hydrate(bigger.to_dict()), "a valid payload hydrates")
	assert_eq(registry.count(), 2, "and replaces the population wholesale")

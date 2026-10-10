extends TestCase
## Unit tests for the Phase-16 pet DATA and DOMAIN: `PetData`, `PetCatalogData`, `PetStore`
## and `PetService`. No scene tree, no node, no autoload — the rules of owning a pet are
## decided by plain objects, which is what lets them be tested here at all.

const PetDataScript := preload("res://src/data/pets/pet_data.gd")
const PetCatalogScript := preload("res://src/data/pets/pet_catalog_data.gd")
const PetStoreScript := preload("res://src/domain/pet/pet_store.gd")
const PetServiceScript := preload("res://src/domain/pet/pet_service.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")
const CurveScript := preload("res://src/data/progression/progression_curve_data.gd")

const CATALOG_PATH := "res://data/pets/pet_catalog.tres"
const HOUND := &"pet_hoang_khuyen"


func _shipped() -> PetCatalogData:
	return load(CATALOG_PATH) as PetCatalogData


## A SECOND pet, built from the shipped one's parts with different numbers. Nothing but data
## differs — which is the claim: a new linh thú is content, never a code branch.
func _second_pet() -> PetData:
	var base := _shipped().entry(HOUND)
	var pet: PetData = PetDataScript.new()
	pet.id = &"pet_test_crane"
	pet.name_key = &"PET_TEST_CRANE_NAME"
	pet.desc_key = &"PET_TEST_CRANE_DESC"
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 20
	stats.attack = 11
	stats.defense = 0
	stats.move_speed = 240.0
	pet.stats = stats
	var growth: StatBlock = StatBlockScript.new()
	growth.max_hp = 2
	growth.attack = 3
	growth.defense = 1
	pet.growth = growth
	var curve: ProgressionCurveData = CurveScript.new()
	curve.id = &"curve_test_crane"
	curve.min_level = 1
	curve.xp_to_next = [10, 20]
	pet.progression_curve = curve
	pet.xp_share_percent = 100
	pet.ai_profile = base.ai_profile
	pet.attack = base.attack
	pet.engage_distance = base.engage_distance
	pet.hurt_radius = 7.0
	pet.visual_profile = base.visual_profile
	pet.recall_seconds = 3.0
	return pet


func _two_pet_catalog() -> PetCatalogData:
	var catalog: PetCatalogData = PetCatalogScript.new()
	var entries: Array[PetData] = [_shipped().entry(HOUND), _second_pet()]
	catalog.entries = entries
	return catalog


func _service(catalog: PetCatalogData = null) -> PetService:
	return PetServiceScript.new(catalog if catalog != null else _shipped(), PetStoreScript.new())


# === Data ====================================================================

func test_the_shipped_catalog_and_first_pet_are_valid() -> void:
	var catalog := _shipped()
	assert_not_null(catalog, "the pet catalog loads")
	if catalog == null:
		return
	assert_eq(catalog.validation_errors(), [] as Array[String], "and is valid")
	var hound := catalog.entry(HOUND)
	assert_not_null(hound, "the first frontier pet is listed")
	if hound == null:
		return
	assert_true(String(hound.id).begins_with("pet_"), "ids use the pet_ prefix")
	assert_true(hound.ai_profile.follow_radius > 0.0, "its profile follows an owner")
	assert_true(hound.engage_distance <= hound.attack.reach_pixels,
		"it stops inside its own reach")
	assert_true(hound.stats.attack < 20,
		"the first pet is HUMBLE: weaker than the mortal player's own strike (20)")


func test_pet_data_rejects_each_broken_field() -> void:
	var cases := {
		"id without the prefix": func(p: PetData) -> void: p.id = &"hound",
		"empty name": func(p: PetData) -> void: p.name_key = &"",
		"empty description": func(p: PetData) -> void: p.desc_key = &"",
		"no stats": func(p: PetData) -> void: p.stats = null,
		"no growth": func(p: PetData) -> void: p.growth = null,
		"no curve": func(p: PetData) -> void: p.progression_curve = null,
		"no AI profile": func(p: PetData) -> void: p.ai_profile = null,
		"no attack": func(p: PetData) -> void: p.attack = null,
		"no visual": func(p: PetData) -> void: p.visual_profile = null,
		"engage beyond reach": func(p: PetData) -> void: p.engage_distance = 999.0,
		"zero hurt radius": func(p: PetData) -> void: p.hurt_radius = 0.0,
		"negative recall": func(p: PetData) -> void: p.recall_seconds = -1.0,
		"xp share above 100": func(p: PetData) -> void: p.xp_share_percent = 101,
		"duplicate skill": func(p: PetData) -> void:
			var twice: Array[StringName] = [&"tech_a", &"tech_a"]
			p.skills = twice,
	}
	for label in cases:
		var pet := _second_pet()
		assert_true(pet.is_valid(), "the fixture starts valid (%s)" % label)
		(cases[label] as Callable).call(pet)
		assert_false(pet.is_valid(), "rejected: %s" % label)


func test_a_non_following_profile_and_an_unknown_skill_are_rejected() -> void:
	var pet := _second_pet()
	pet.ai_profile = load("res://data/enemies/ai_frontier_skirmisher.tres") as AiProfileData
	assert_false(pet.is_valid(), "an enemy profile (no follow_radius) cannot drive a pet")
	pet = _second_pet()
	var skills: Array[StringName] = [&"tech_does_not_exist"]
	pet.skills = skills
	var known: Array[StringName] = [&"tech_loi_chi"]
	assert_true(pet.validation_errors().is_empty(), "with no catalog only the shape is checked")
	assert_false(pet.validation_errors(known).is_empty(),
		"against the technique catalog an unknown skill id is rejected")


func test_the_catalog_rejects_empty_null_and_duplicate_entries() -> void:
	var catalog: PetCatalogData = PetCatalogScript.new()
	assert_false(catalog.is_valid(), "an empty catalog is not a catalog")
	var twice: Array[PetData] = [_second_pet(), _second_pet()]
	catalog.entries = twice
	assert_false(catalog.is_valid(), "duplicate ids are rejected")
	var holed: Array[PetData] = [_second_pet(), null]
	catalog.entries = holed
	assert_false(catalog.is_valid(), "a null entry is rejected")
	assert_null(catalog.entry(&"pet_nobody"), "an unknown id resolves to null, not a guess")


## D-064: the level is DERIVED from XP through the pet's curve; stats are derived from the level.
func test_level_and_stats_are_derived_from_xp() -> void:
	var pet := _second_pet()                       # curve [10, 20]: L2 at 10, L3 at 30
	assert_eq(pet.level_for_xp(0), 1, "no XP is the first level")
	assert_eq(pet.level_for_xp(9), 1, "just under the threshold stays")
	assert_eq(pet.level_for_xp(10), 2, "the threshold advances")
	assert_eq(pet.level_for_xp(30), 3, "the cumulative threshold advances again")
	assert_eq(pet.level_for_xp(999999), 3, "and the ceiling holds")
	var at_three := pet.stats_at(3)
	assert_eq(at_three.max_hp, 24, "hp = base 20 + 2 per level above the first")
	assert_eq(at_three.attack, 17, "attack = base 11 + 3 x 2")
	assert_eq(at_three.defense, 2, "defense = base 0 + 1 x 2")
	assert_eq(at_three.move_speed, 240.0, "pace never grows")
	assert_eq(pet.stats.max_hp, 20, "the authored base block is never mutated")
	assert_eq(pet.stats_at(-5).max_hp, 20, "a level below the first clamps to the base")


# === Service =================================================================

func test_acquire_activate_and_their_refusals() -> void:
	var service := _service(_two_pet_catalog())
	assert_eq(service.acquire(&"pet_nobody"), PetService.REFUSE_UNKNOWN_PET, "unknown is refused")
	assert_eq(service.activate(HOUND), PetService.REFUSE_NOT_OWNED,
		"cannot activate an unowned pet")
	assert_eq(service.store().owned_count(), 0, "a refusal changed nothing")
	assert_eq(service.acquire(HOUND), &"", "the first acquisition succeeds")
	assert_eq(service.acquire(HOUND), PetService.REFUSE_ALREADY_OWNED, "the second is refused")
	assert_eq(service.store().owned_count(), 1, "and did not duplicate it")
	assert_null(service.active_pet(), "owning is not activating")
	assert_eq(service.activate(HOUND), &"", "an owned pet activates")
	assert_eq(service.activate(HOUND), &"", "activating again is idempotent")
	assert_eq(service.active_pet().id, HOUND, "and it is the active pet")
	assert_eq(service.acquire(&"pet_test_crane"), &"", "a second pet is owned beside it")
	assert_eq(service.active_pet().id, HOUND, "without stealing the active slot")
	service.deactivate()
	assert_null(service.active_pet(), "deactivate clears the active pet")
	assert_eq(service.store().owned_count(), 2, "and keeps both owned")


func test_xp_grants_level_once_and_stop_at_the_ceiling() -> void:
	var service := _service(_two_pet_catalog())
	service.acquire(&"pet_test_crane")
	var crane := &"pet_test_crane"
	assert_false(bool(service.earn_xp(HOUND, 5)["accepted"]), "an unowned pet earns nothing")
	assert_false(bool(service.earn_xp(&"pet_nobody", 5)["accepted"]), "nor an unknown one")
	var first := service.earn_xp(crane, 9)
	assert_true(bool(first["accepted"]), "an owned pet earns XP")
	assert_eq(service.level_of(crane), 1, "9 XP is still level 1")
	var second := service.earn_xp(crane, 1)
	assert_eq(int(second["level_before"]), 1, "the result names the level before")
	assert_eq(int(second["level_after"]), 2, "and after")
	assert_eq(service.stats_of(crane).attack, 14, "derived stats follow the derived level")
	var huge := service.earn_xp(crane, 1000000)
	assert_eq(int(huge["xp_after"]), 30, "the total is capped at the ceiling's cumulative XP")
	assert_eq(service.level_of(crane), 3, "at the curve's last level")
	var beyond := service.earn_xp(crane, 5)
	assert_false(bool(beyond["accepted"]), "a maxed pet refuses further XP")
	assert_eq(service.store().xp_of(crane), 30, "and stores nothing more")
	assert_eq(service.level_of(HOUND), 0, "an unowned pet has no level")
	assert_null(service.stats_of(HOUND), "and no stats")


# === Store serialization =====================================================

func test_the_store_round_trips_as_plain_data() -> void:
	var catalog := _two_pet_catalog()
	var service := _service(catalog)
	service.acquire(&"pet_test_crane")
	service.acquire(HOUND)
	service.earn_xp(HOUND, 42)
	service.activate(HOUND)
	var data := service.store().to_dict()
	assert_true(JSON.stringify(data) != "", "it is plain data (JSON-serializable)")
	for row in data["owned"]:
		assert_false((row as Dictionary).has("level"),
			"no level is stored: it is derived from xp (D-064)")
		assert_eq((row as Dictionary).size(), 2, "a row is exactly { pet_id, xp }")
	var restored: PetStore = PetStoreScript.new()
	# A deep copy through the engine's own text form, so nothing is shared with the source.
	var wire: Dictionary = str_to_var(var_to_str(data))
	assert_true(restored.from_dict(wire, catalog), "the payload is accepted")
	assert_eq(restored.to_dict(), data, "and re-serializes identically")
	assert_eq(restored.owned_ids(), service.store().owned_ids(), "ownership ORDER survives")
	assert_eq(restored.xp_of(HOUND), 42, "XP survives")
	assert_eq(restored.active_id(), HOUND, "the active pet survives")
	assert_eq(PetServiceScript.new(catalog, restored).level_of(HOUND),
		service.level_of(HOUND), "the derived level is the same after a round trip")


func test_hydration_is_atomic_and_rejects_every_malformed_payload() -> void:
	var catalog := _two_pet_catalog()
	var good := {"schema": 1, "owned": [{"pet_id": "pet_hoang_khuyen", "xp": 7}],
		"active_pet": "pet_hoang_khuyen"}
	var bad := {
		"missing schema": {"owned": [], "active_pet": ""},
		"future schema": {"schema": 2, "owned": [], "active_pet": ""},
		"owned not an array": {"schema": 1, "owned": {}, "active_pet": ""},
		"row not a dictionary": {"schema": 1, "owned": [3], "active_pet": ""},
		"row with a stored level": {"schema": 1,
			"owned": [{"pet_id": "pet_hoang_khuyen", "xp": 1, "level": 9}], "active_pet": ""},
		"unknown pet": {"schema": 1, "owned": [{"pet_id": "pet_nobody", "xp": 1}],
			"active_pet": ""},
		"duplicate pet": {"schema": 1, "owned": [{"pet_id": "pet_hoang_khuyen", "xp": 1},
			{"pet_id": "pet_hoang_khuyen", "xp": 2}], "active_pet": ""},
		"negative xp": {"schema": 1, "owned": [{"pet_id": "pet_hoang_khuyen", "xp": -1}],
			"active_pet": ""},
		"integral float xp (L-024: a float is rejected even when whole)": {"schema": 1,
			"owned": [{"pet_id": "pet_hoang_khuyen", "xp": 7.0}], "active_pet": ""},
		"float schema": {"schema": 1.0, "owned": [], "active_pet": ""},
		"fractional xp": {"schema": 1, "owned": [{"pet_id": "pet_hoang_khuyen", "xp": 1.5}],
			"active_pet": ""},
		"xp as text": {"schema": 1, "owned": [{"pet_id": "pet_hoang_khuyen", "xp": "7"}],
			"active_pet": ""},
		"active pet not owned": {"schema": 1, "owned": [], "active_pet": "pet_hoang_khuyen"},
		"active pet not text": {"schema": 1, "owned": [], "active_pet": 4},
	}
	for label in bad:
		var store: PetStore = PetStoreScript.new()
		assert_true(store.from_dict(good, catalog), "the store starts from a good state")
		var before := store.to_dict()
		assert_false(store.from_dict(bad[label], catalog), "rejected: %s" % label)
		assert_eq(store.to_dict(), before, "and the store is untouched (%s)" % label)
	var empty: PetStore = PetStoreScript.new()
	assert_false(empty.from_dict(good, null), "no catalog: nothing can be validated, so refuse")

extends TestCase
## Unit tests for CharacterTemplateData — the DATA definition a character is built from
## (`docs/CHARACTER_SYSTEM.md` §4). Covers validation at the content boundary and that the
## shipped player template is well-formed. Pure data: no tree, no autoloads (D-019).

const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")
const PLAYER_TEMPLATE_PATH := "res://data/characters/player_default.tres"


## A helper: a minimal VALID template (non-empty id + name_key + a valid StatBlock).
func _valid_template() -> Resource:
	var stats := StatBlockScript.new()
	stats.max_hp = 50
	stats.attack = 10
	stats.defense = 2
	stats.move_speed = 120.0
	var t := TemplateScript.new()
	t.id = &"char_test"
	t.name_key = &"CHARACTER_TEST_NAME"
	t.base_stats = stats
	return t


func test_valid_template_passes() -> void:
	var t := _valid_template()
	assert_true(t.is_valid(), "a complete template is valid")
	assert_true(t.validation_errors().is_empty(), "no errors on a valid template")


func test_missing_id_fails() -> void:
	var t := _valid_template()
	t.id = &""
	assert_false(t.is_valid(), "empty id is invalid")


func test_missing_name_key_fails() -> void:
	var t := _valid_template()
	t.name_key = &""
	assert_false(t.is_valid(), "empty name_key is invalid (every character has a name)")


func test_missing_base_stats_fails() -> void:
	var t := _valid_template()
	t.base_stats = null
	assert_false(t.is_valid(), "null base_stats is invalid")


func test_invalid_base_stats_fails() -> void:
	var t := _valid_template()
	t.base_stats.max_hp = 0  # StatBlock requires max_hp > 0
	assert_false(t.is_valid(), "an invalid StatBlock makes the template invalid")


func test_negative_age_fails() -> void:
	var t := _valid_template()
	t.age = -1
	assert_false(t.is_valid(), "negative age is invalid")


func test_out_of_range_enum_fails() -> void:
	var t := _valid_template()
	t.gender = 999  # hand-edited .tres could carry a bogus enum int
	assert_false(t.is_valid(), "out-of-range gender enum is rejected at the boundary")


## The SHIPPED player template must load and be valid — a broken content file would fail the
## real session start (`WorldRuntime._spawn_player`), so it is a high-value guard here.
func test_shipped_player_template_is_valid() -> void:
	assert_true(ResourceLoader.exists(PLAYER_TEMPLATE_PATH), "player template exists")
	var t: Resource = load(PLAYER_TEMPLATE_PATH)
	assert_not_null(t, "player template loads")
	assert_true(t.is_valid(), "shipped player template is valid: %s" % str(t.validation_errors()))
	assert_eq(String(t.id), "char_player_default", "stable player template id")
	assert_ne(String(t.name_key), "", "player has a name key")

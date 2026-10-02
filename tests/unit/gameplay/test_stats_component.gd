extends TestCase
## Unit tests for StatBlock (data) + StatsComponent (gameplay).
## Fresh instances; no autoloads. Verifies invariants and that authored .tres content is
## well-formed (content validation, `docs/TEST_PLAN.md` §7).

const StatBlockScript := preload("res://src/data/stats/stat_block.gd")
const StatsScript := preload("res://src/gameplay/components/stats_component.gd")
const PLAYER_STATS := "res://data/stats/player_stats.tres"
const DUMMY_STATS := "res://data/stats/training_dummy_stats.tres"


func _block(hp: int, atk: int, def: int, spd: float) -> Resource:
	var b: Resource = StatBlockScript.new()
	b.max_hp = hp
	b.attack = atk
	b.defense = def
	b.move_speed = spd
	return b


# --- StatBlock invariants ----------------------------------------------------

func test_valid_block_passes() -> void:
	var b := _block(100, 20, 5, 180.0)
	assert_true(b.is_valid(), "well-formed block is valid")
	assert_true(b.validation_errors().is_empty(), "no errors")


func test_zero_max_hp_is_invalid() -> void:
	var b := _block(0, 20, 5, 180.0)
	assert_false(b.is_valid(), "max_hp must be > 0")
	assert_false(b.validation_errors().is_empty(), "reports an error")


func test_negative_fields_invalid() -> void:
	assert_false(_block(100, -1, 5, 10.0).is_valid(), "negative attack invalid")
	assert_false(_block(100, 5, -1, 10.0).is_valid(), "negative defense invalid")
	assert_false(_block(100, 5, 5, -1.0).is_valid(), "negative move_speed invalid")


# --- StatsComponent reads + validation ---------------------------------------

func test_component_reads_block() -> void:
	var c: Node = StatsScript.new()
	c.stat_block = _block(80, 12, 3, 150.0)
	assert_true(c.validate(), "valid block validates")
	assert_eq(c.get_max_hp(), 80)
	assert_eq(c.get_attack(), 12)
	assert_eq(c.get_defense(), 3)
	assert_true(absf(c.get_move_speed() - 150.0) < 0.001)
	c.free()


func test_component_without_block_fails_validation() -> void:
	var c: Node = StatsScript.new()
	# No stat_block assigned. validate() must report false (loud), not silently pass.
	assert_false(c.validate(), "missing StatBlock fails validation")
	c.free()


# --- Authored content is well-formed -----------------------------------------

func test_player_stats_resource_valid() -> void:
	var b: Resource = load(PLAYER_STATS)
	assert_not_null(b, "player_stats.tres loads")
	if b != null:
		assert_true(b.is_valid(), "player stats content is valid: %s" % str(b.validation_errors()))


func test_dummy_stats_resource_valid() -> void:
	var b: Resource = load(DUMMY_STATS)
	assert_not_null(b, "training_dummy_stats.tres loads")
	if b != null:
		assert_true(b.is_valid(), "dummy stats content is valid: %s" % str(b.validation_errors()))

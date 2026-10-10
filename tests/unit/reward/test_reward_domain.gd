extends TestCase
## Unit tests for the Phase-19 reward ledger and delivery (D-070): `RewardData`,
## `RewardLedger`, `RewardService`. No scene tree. The bag is a REAL `InventoryState` and the
## regard part moves a REAL relationship graph; only progression is a counter, because the
## rule under test is the ORDER and the RECORD of payment, not the XP curve.

const CONFIG_PATH := "res://data/relationship/relationship_config.tres"
const PILL_PATH := "res://data/items/item_bo_huyet_dan.tres"
const STONE_PATH := "res://data/items/item_linh_thach.tres"
const SWORD_PATH := "res://data/items/item_kiem_thanh_thiet.tres"

const SOURCE := &"quest:quest_test"
const KEEPER := &"char_test_keeper"
const PLAYER := &"char_test_player"

var _ledger: RewardLedger = null
var _service: RewardService = null
var _bag: InventoryState = null
var _relationship: RelationshipService = null
var _config: RelationshipConfigData = null
var _items: Dictionary = {}
var _xp: int = 0
var _xp_accepts: bool = true
var _regard_accepts: bool = true
var _calls: Array[String] = []


func before_each() -> void:
	_ledger = RewardLedger.new()
	_service = RewardService.new(_ledger)
	_bag = InventoryState.new()
	_config = load(CONFIG_PATH) as RelationshipConfigData
	_relationship = RelationshipService.new(RelationshipStore.new(_config), _config)
	_items = {}
	for path: String in [PILL_PATH, STONE_PATH, SWORD_PATH]:
		var item := load(path) as ItemData
		_items[item.id] = item
	_xp = 0
	_xp_accepts = true
	_regard_accepts = true
	_calls = []


func after_each() -> void:
	_service = null
	_ledger = null
	_bag = null
	_relationship = null
	_config = null
	_items = {}


func _pill() -> ItemData:
	return _items[&"item_bo_huyet_dan"]


func _stone() -> ItemData:
	return _items[&"item_linh_thach"]


func _trade(take: Dictionary, give: Dictionary) -> bool:
	_calls.append("bag")
	var resolved: Dictionary = {}
	for item_id: StringName in give:
		resolved[_items[item_id]] = give[item_id]
	return _bag.exchange(take, resolved)


func _pay_xp(amount: int, _source: StringName) -> bool:
	_calls.append("xp")
	if _xp_accepts:
		_xp += amount
	return _xp_accepts


func _move_regard(character_id: StringName, dimension: StringName, delta: int,
		source: StringName) -> bool:
	_calls.append("regard")
	if not _regard_accepts:
		return false
	return bool(RegardRules.move(_relationship, _config, character_id, PLAYER, dimension,
		delta, source)["ok"])


func _payers() -> RewardPayers:
	var payers := RewardPayers.new()
	payers.trade = _trade
	payers.pay_xp = _pay_xp
	payers.move_regard = _move_regard
	return payers


func _entry(item: ItemData, count: int) -> RewardItemData:
	var entry := RewardItemData.new()
	entry.item = item
	entry.count = count
	return entry


## Two pills, 10 XP, the keeper's respect +10: every part there is.
func _reward() -> RewardData:
	var reward := RewardData.new()
	var items: Array[RewardItemData] = [_entry(_pill(), 2)]
	reward.items = items
	reward.xp = 10
	reward.regard_character_id = KEEPER
	reward.regard_dimension = &"respect"
	reward.regard_delta = 10
	return reward


func _respect() -> int:
	return RegardRules.read(_relationship, _config, KEEPER, PLAYER, &"respect")


## Fill every stack slot with swords (stack_max 1), so nothing else fits.
func _fill_bag() -> void:
	_bag.add(_items[&"item_kiem_thanh_thiet"], _bag.capacity)
	assert_eq(_bag.stack_count(), _bag.capacity, "the bag is full")


func _has_error(errors: Array[String], fragment: String) -> bool:
	for problem in errors:
		if problem.contains(fragment):
			return true
	return false


# === Data ==========================================================================

func test_a_reward_is_validated_part_by_part() -> void:
	assert_eq(_reward().validation_errors(), [] as Array[String], "the full reward is valid")
	var empty := RewardData.new()
	assert_true(_has_error(empty.validation_errors(), "pays nothing"), "a reward of nothing")
	var no_item := _reward()
	no_item.items[0].item = null
	assert_true(_has_error(no_item.validation_errors(), "names no item"), "an entry with no item")
	var zero := _reward()
	zero.items[0].count = 0
	assert_true(_has_error(zero.validation_errors(), "outside 1..99"), "a count of zero")
	var twice := _reward()
	twice.items.append(_entry(_pill(), 1))
	assert_true(_has_error(twice.validation_errors(), "listed twice"), "one item in two entries")
	var null_entry := _reward()
	null_entry.items.append(null)
	assert_true(_has_error(null_entry.validation_errors(), "is null"), "a null entry")
	var negative := _reward()
	negative.xp = -1
	assert_true(_has_error(negative.validation_errors(), "xp -1"), "negative XP")
	var huge := _reward()
	huge.xp = RewardData.MAX_XP + 1
	assert_true(_has_error(huge.validation_errors(), "outside 0..1000"), "XP over the ceiling")
	var unnamed := _reward()
	unnamed.regard_character_id = &""
	assert_true(_has_error(unnamed.validation_errors(), "without naming whose"),
		"a regard move with nobody named")
	var unmoved := _reward()
	unmoved.regard_delta = 0
	assert_true(_has_error(unmoved.validation_errors(), "moves it by 0"),
		"someone named and nothing moved")
	var leap := _reward()
	leap.regard_delta = RewardData.MAX_REGARD_DELTA + 1
	assert_true(_has_error(leap.validation_errors(), "exceeds the ceiling"), "a leap in regard")
	assert_eq(_reward().item_counts(), {&"item_bo_huyet_dan": 2}, "the shape the bag is given")


# === The ledger ====================================================================

func test_the_ledger_records_an_id_once_and_refuses_an_empty_one() -> void:
	assert_false(_ledger.has(SOURCE), "nothing is paid at first")
	assert_true(_ledger.claim(SOURCE), "the first claim may pay")
	assert_true(_ledger.has(SOURCE), "and is recorded")
	assert_false(_ledger.claim(SOURCE), "the second may not")
	assert_false(_ledger.claim(&""), "an empty id is refused")
	assert_false(_ledger.has(&""), "and records nothing")
	assert_eq(_ledger.count(), 1, "one id, once")


func test_the_ledger_round_trips_and_rejects_a_bad_payload_whole() -> void:
	_ledger.claim(&"enemy_mist_wolf_1#2")
	_ledger.claim(SOURCE)
	var saved := _ledger.to_dict()
	assert_eq(saved, {"schema": 1, "claimed": ["enemy_mist_wolf_1#2", "quest:quest_test"]},
		"plain data, sorted")
	var restored := RewardLedger.new()
	assert_true(restored.from_dict(saved), "accepted")
	assert_eq(restored.to_dict(), saved, "and identical")
	assert_false(restored.claim(SOURCE), "what was paid before the round trip stays paid")
	for bad: Dictionary in [{}, {"schema": 2, "claimed": []}, {"schema": 1, "claimed": "x"},
			{"schema": 1, "claimed": [1]}, {"schema": 1, "claimed": [""]},
			{"schema": 1, "claimed": ["a", "a"]}, {"schema": 1.0, "claimed": []}]:
		assert_false(restored.from_dict(bad), "rejected: %s" % str(bad))
		assert_eq(restored.to_dict(), saved, "and the ledger is unchanged")


# === Delivery ======================================================================

func test_a_reward_is_paid_bag_first_and_recorded_part_by_part() -> void:
	var outcome := _service.deliver(SOURCE, _reward(), {}, _payers())
	assert_eq(outcome.status, RewardOutcome.Status.PAID, "paid")
	assert_eq(_calls, ["bag", "xp", "regard"] as Array[String], "the bag is asked FIRST")
	assert_eq(outcome.paid_now, [&"bag", &"xp", &"regard"] as Array[StringName], "three parts")
	assert_eq(_bag.count_of(&"item_bo_huyet_dan"), 2, "the pills are in the bag")
	assert_eq(_xp, 10, "the XP is paid")
	assert_eq(_respect(), 10, "the keeper's respect is in the relationship graph")
	for id: StringName in [SOURCE, &"quest:quest_test/bag", &"quest:quest_test/xp",
			&"quest:quest_test/regard"]:
		assert_true(_ledger.has(id), "%s is recorded" % id)
	assert_true(_service.is_paid(SOURCE), "the source is paid")


func test_paying_again_pays_nothing() -> void:
	_service.deliver(SOURCE, _reward(), {}, _payers())
	_calls = []
	var again := _service.deliver(SOURCE, _reward(), {}, _payers())
	assert_eq(again.status, RewardOutcome.Status.ALREADY_PAID, "already paid")
	assert_eq(_calls, [] as Array[String], "no owner was even asked")
	assert_eq([_bag.count_of(&"item_bo_huyet_dan"), _xp, _respect()], [2, 10, 10], "nothing moved")
	# A different source paying the SAME authored reward is a different payment.
	var other := _service.deliver(&"quest:quest_other", _reward(), {}, _payers())
	assert_eq(other.status, RewardOutcome.Status.PAID, "another source is paid in its own right")
	assert_eq(_bag.count_of(&"item_bo_huyet_dan"), 4, "its own pills")


func test_a_full_bag_refuses_the_whole_reward_and_a_retry_pays_it_once() -> void:
	_fill_bag()
	var refused := _service.deliver(SOURCE, _reward(), {}, _payers())
	assert_eq(refused.status, RewardOutcome.Status.REFUSED, "refused")
	assert_eq(refused.reason, RewardService.REFUSE_NO_ROOM, "for want of room")
	assert_eq(_calls, ["bag"] as Array[String], "nothing after the bag was attempted")
	assert_eq([_xp, _respect(), _ledger.count()], [0, 0, 0],
		"no XP, no regard, nothing recorded: nothing is lost and nothing is half-paid")
	assert_eq(_bag.count_of(&"item_bo_huyet_dan"), 0, "and no pill squeezed in")
	# The player makes room and asks again.
	assert_true(_bag.remove(&"item_kiem_thanh_thiet", 1), "one slot freed")
	var paid := _service.deliver(SOURCE, _reward(), {}, _payers())
	assert_eq(paid.status, RewardOutcome.Status.PAID, "now it is paid")
	assert_eq([_bag.count_of(&"item_bo_huyet_dan"), _xp, _respect()], [2, 10, 10], "in full, once")
	assert_eq(_service.deliver(SOURCE, _reward(), {}, _payers()).status,
		RewardOutcome.Status.ALREADY_PAID, "and never again")


func test_what_the_source_takes_and_what_it_gives_are_one_exchange() -> void:
	_bag.add(_pill(), 2)
	var reward := RewardData.new()
	var items: Array[RewardItemData] = [_entry(_stone(), 3)]
	reward.items = items
	var outcome := _service.deliver(SOURCE, reward, {&"item_bo_huyet_dan": 2}, _payers())
	assert_eq(outcome.status, RewardOutcome.Status.PAID, "paid")
	assert_eq([_bag.count_of(&"item_bo_huyet_dan"), _bag.count_of(&"item_linh_thach")], [0, 3],
		"two pills out, three stones in")
	# Taking what is not held refuses everything — the stones are not handed over either.
	var short := _service.deliver(&"quest:quest_short", reward, {&"item_bo_huyet_dan": 2},
		_payers())
	assert_eq(short.status, RewardOutcome.Status.REFUSED, "a shortfall refuses the exchange")
	assert_eq(_bag.count_of(&"item_linh_thach"), 3, "nothing was given")
	assert_false(_ledger.has(&"quest:quest_short/bag"), "and nothing recorded")


func test_a_part_that_fails_after_the_bag_leaves_the_rest_owed_not_lost() -> void:
	_regard_accepts = false
	var first := _service.deliver(SOURCE, _reward(), {}, _payers())
	assert_eq(first.status, RewardOutcome.Status.OWED, "owed")
	assert_eq(first.paid_now, [&"bag", &"xp"] as Array[StringName], "the bag and the XP were paid")
	assert_false(_ledger.has(SOURCE), "the source is NOT recorded as paid")
	assert_false(_service.is_paid(SOURCE), "so nobody may treat it as settled")
	assert_true(_service.is_part_paid(SOURCE, RewardService.PART_BAG), "the bag part is")
	assert_eq([_bag.count_of(&"item_bo_huyet_dan"), _xp, _respect()], [2, 10, 0], "so far")
	# Asking again while it still fails pays nothing twice.
	_calls = []
	var still := _service.deliver(SOURCE, _reward(), {}, _payers())
	assert_eq(still.status, RewardOutcome.Status.OWED, "still owed")
	assert_eq(_calls, ["regard"] as Array[String], "only the unpaid part was attempted")
	assert_eq([_bag.count_of(&"item_bo_huyet_dan"), _xp], [2, 10], "no second pills, no second XP")
	# The owner recovers.
	_regard_accepts = true
	var last := _service.deliver(SOURCE, _reward(), {}, _payers())
	assert_eq(last.status, RewardOutcome.Status.PAID, "paid in full")
	assert_eq(last.paid_now, [&"regard"] as Array[StringName], "by paying only what was owed")
	assert_eq([_bag.count_of(&"item_bo_huyet_dan"), _xp, _respect()], [2, 10, 10], "each once")


func test_a_reward_with_no_bag_part_that_cannot_start_is_refused_not_owed() -> void:
	var reward := RewardData.new()
	reward.xp = 10
	_xp_accepts = false
	var outcome := _service.deliver(SOURCE, reward, {}, _payers())
	assert_eq(outcome.status, RewardOutcome.Status.REFUSED,
		"nothing was paid, so nothing is 'owed': it was refused")
	assert_eq(_ledger.count(), 0, "and nothing recorded")


func test_a_reward_this_session_cannot_finish_is_refused_before_it_starts() -> void:
	var no_regard := _payers()
	no_regard.move_regard = Callable()
	var outcome := _service.deliver(SOURCE, _reward(), {}, no_regard)
	assert_eq(outcome.status, RewardOutcome.Status.REFUSED, "refused whole")
	assert_eq(outcome.reason, RewardService.REFUSE_UNPAYABLE, "as unpayable")
	assert_eq(_calls, [] as Array[String], "the bag was never touched")
	assert_eq(_service.deliver(&"", _reward(), {}, _payers()).status,
		RewardOutcome.Status.REFUSED, "an unnamed source is refused")
	assert_eq(_service.deliver(SOURCE, RewardData.new(), {}, _payers()).status,
		RewardOutcome.Status.REFUSED, "an invalid reward is refused")
	assert_eq(_service.deliver(SOURCE, null, {}, _payers()).status,
		RewardOutcome.Status.REFUSED, "no reward is refused")
	assert_eq(_service.deliver(SOURCE, _reward(), {}, null).status,
		RewardOutcome.Status.REFUSED, "no payers is refused")
	assert_eq(RewardService.new(null).deliver(SOURCE, _reward(), {}, _payers()).status,
		RewardOutcome.Status.REFUSED, "no ledger is refused")
	assert_eq(_ledger.count(), 0, "none of it recorded anything")


func test_a_reward_cannot_be_paid_from_inside_its_own_payment() -> void:
	var inner: Array[RewardOutcome] = []
	var payers := _payers()
	payers.pay_xp = func(amount: int, _source: StringName) -> bool:
		# A listener of the XP change submits the same turn-in again.
		inner.append(_service.deliver(SOURCE, _reward(), {}, _payers()))
		_xp += amount
		return true
	var outer := _service.deliver(SOURCE, _reward(), {}, payers)
	assert_eq(outer.status, RewardOutcome.Status.PAID, "the outer payment completes")
	assert_eq(inner[0].status, RewardOutcome.Status.REFUSED, "the re-entrant one is refused")
	assert_eq(inner[0].reason, RewardService.REFUSE_BUSY, "as already under way")
	assert_eq([_bag.count_of(&"item_bo_huyet_dan"), _xp, _respect()], [2, 10, 10],
		"and everything was paid exactly once")

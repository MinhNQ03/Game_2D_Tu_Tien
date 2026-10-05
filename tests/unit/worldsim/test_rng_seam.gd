extends TestCase
## Unit tests for the deterministic RNG seam (Phase 08 / D-040 / C-010).
##
## The seam's whole value is three properties, so they are what this file asserts:
##   1. **Reproducible** — the same seed gives the same sequence, forever.
##   2. **Stream-isolated** — drawing from one subsystem's stream cannot change another's
##      future values. This is the property that makes "same seed → same world" survive a bug
##      fix in an unrelated subsystem, and it is the reason the seam has streams at all.
##   3. **Resumable** — a serialized stream continues exactly where it left off, not from the
##      beginning (`docs/SAVE_FORMAT.md` §3b).
##
## Pure domain `RefCounted` throughout, built with `.new()` — nothing to free (L-019 applies to
## Nodes). No `randomize()`, no engine RNG, no wall clock anywhere in here, which is also the
## point.

const StreamScript := preload("res://src/domain/worldsim/rng_stream.gd")
const ServiceScript := preload("res://src/domain/worldsim/rng_service.gd")

const SEED_A := 12345
const SEED_B := 999


# === 1-3. The mixer + raw draws =============================================

## Every value must stay inside the 32-bit window the algorithm is defined over. If it did
## not, the `>>` operations would be shifting a negative number and the sequence would become
## platform-dependent — the exact portability trap the hand-rolled-PRNG note warns about.
func test_01_raw_values_stay_in_the_32_bit_window() -> void:
	var stream: RngStream = StreamScript.new(&"probe", 0)
	for _i in 200:
		var value := stream.next_raw()
		assert_true(value >= 0, "a raw draw is never negative (got %d)" % value)
		assert_true(value < StreamScript.MOD_32,
			"a raw draw stays below 2^32 (got %d)" % value)
	assert_eq(stream.draw_count(), 200, "every draw is counted")


## The same seed must give the same sequence. Asserted as a sequence rather than a single
## value, because a mixer can agree on one draw and diverge on the next.
func test_02_the_same_seed_reproduces_the_sequence() -> void:
	var first: Array[int] = []
	var second: Array[int] = []
	var a: RngStream = StreamScript.new(&"s", 777)
	var b: RngStream = StreamScript.new(&"s", 777)
	for _i in 50:
		first.append(a.next_raw())
		second.append(b.next_raw())
	assert_eq(str(first), str(second), "two streams from one state produce one sequence")
	# And a DIFFERENT starting state must not produce the same sequence, or the seed would be
	# decorative.
	var c: RngStream = StreamScript.new(&"s", 778)
	assert_ne(c.next_raw(), first[0], "a different state produces a different sequence")


## The mixer is a pure function, so the same input must always map to the same output — this is
## what lets `RngService.derive_state` fold a stream id in without holding any state.
func test_03_the_mixer_is_pure() -> void:
	for value in [0, 1, 42, 65535, StreamScript.MASK_32]:
		var once := StreamScript.mix(int(value))
		var twice := StreamScript.mix(int(value))
		assert_eq(once, twice, "mix(%d) is stable" % int(value))
		assert_true(once >= 0 and once < StreamScript.MOD_32,
			"mix(%d) stays in the 32-bit window (got %d)" % [int(value), once])
	assert_ne(StreamScript.mix(0), StreamScript.mix(1),
		"adjacent inputs do not collide (the avalanche the finalizer exists for)")


# === 4-6. Bounded draws =====================================================

func test_04_next_below_respects_its_bound() -> void:
	var stream: RngStream = StreamScript.new(&"s", 1)
	for _i in 300:
		var value := stream.next_below(7)
		assert_true(value >= 0 and value < 7, "next_below(7) is in [0,7) (got %d)" % value)
	assert_eq(stream.next_below(1), 0, "a bound of 1 can only be 0")
	# A non-positive bound is an error that degrades to 0, not a crash or a negative index.
	assert_eq(stream.next_below(0), 0, "a zero bound reports and yields 0")


func test_05_next_range_is_inclusive_on_both_ends() -> void:
	var stream: RngStream = StreamScript.new(&"s", 99)
	var seen := {}
	for _i in 400:
		var value := stream.next_range(-2, 3)
		assert_true(value >= -2 and value <= 3,
			"next_range(-2,3) stays in range (got %d)" % value)
		seen[value] = true
	# Both ENDS must actually be reachable: an off-by-one in the multiply-shift would make the
	# top value impossible, which no range check would ever notice.
	assert_true(seen.has(-2), "the low end is reachable")
	assert_true(seen.has(3), "the high end is reachable")
	assert_eq(stream.next_range(5, 5), 5, "a degenerate range yields its single value")
	assert_eq(stream.next_range(9, 2), 9, "an inverted range reports and yields the low end")


## A probability of 0 or 100 must still CONSUME a draw. If it did not, editing a tuning value
## to 0 would shift every later draw in that stream — cross-contamination inside one stream,
## which is the same class of bug per-stream state exists to prevent.
func test_06_a_degenerate_chance_still_advances_the_stream() -> void:
	var never: RngStream = StreamScript.new(&"s", 5)
	assert_false(never.next_chance(0), "0% never fires")
	assert_eq(never.draw_count(), 1, "and it still consumed a draw")
	var always: RngStream = StreamScript.new(&"s", 5)
	assert_true(always.next_chance(100), "100% always fires")
	assert_eq(always.draw_count(), 1, "and it also consumed exactly one draw")
	# Both consumed one draw from the same start, so they must now be at the same position.
	assert_eq(never.state(), always.state(),
		"a tuning value cannot change how far the stream advanced")


# === 7-9. Stream isolation (the reason the seam has streams) ================

## THE ISOLATION GUARANTEE, stated as the regression it prevents: adding draws to one
## subsystem's stream must not change another subsystem's future values.
##
## Without it, a bug fix in combat that happens to roll one extra number would silently change
## every subsequent world-simulation outcome, and a seeded world would stop being reproducible
## across builds. That failure is invisible — nothing errors, the world is just different — so
## it has to be pinned by a test.
func test_07_draining_one_stream_cannot_move_another() -> void:
	var service: RngService = ServiceScript.new(SEED_A)
	var world := service.stream(ServiceScript.STREAM_WORLD_SIM)
	var other := service.stream(&"test_other_subsystem")
	assert_not_null(world, "the world-sim stream exists")
	assert_not_null(other, "a second stream can be created generically")

	# Baseline: what the second stream WOULD produce, from an independent service.
	var baseline_service: RngService = ServiceScript.new(SEED_A)
	var baseline: Array[int] = []
	for _i in 10:
		baseline.append(baseline_service.stream(&"test_other_subsystem").next_raw())

	# Hammer the first stream, then read the second.
	for _i in 1000:
		world.next_raw()
	var after: Array[int] = []
	for _i in 10:
		after.append(other.next_raw())

	assert_eq(str(after), str(baseline),
		("1000 draws on the world stream did not move the other stream by a single value; "
			+ "if this fails, one subsystem's randomness is leaking into another's"))
	assert_eq(other.draw_count(), 10, "and the other stream counted only its own draws")


## Two streams of DIFFERENT ids under the SAME seed must be unrelated sequences — not the same
## sequence read at two offsets, which is what a lazier derivation (seed + index) would give.
func test_08_different_stream_ids_start_far_apart() -> void:
	var service: RngService = ServiceScript.new(SEED_A)
	var a := service.stream(&"alpha")
	var b := service.stream(&"beta")
	assert_ne(a.state(), b.state(), "two ids derive different starting states")
	var a_values: Array[int] = []
	for _i in 8:
		a_values.append(a.next_raw())
	var b_values: Array[int] = []
	for _i in 8:
		b_values.append(b.next_raw())
	assert_ne(str(a_values), str(b_values), "and therefore different sequences")
	# The derivation is pure, so it must be reproducible without a service.
	assert_eq(ServiceScript.derive_state(SEED_A, &"alpha"),
		ServiceScript.derive_state(SEED_A, &"alpha"), "derive_state is pure")
	assert_ne(ServiceScript.derive_state(SEED_A, &"alpha"),
		ServiceScript.derive_state(SEED_B, &"alpha"),
		"and the WORLD SEED still matters for a given stream id")


## Asking for the same stream twice must return the SAME advancing object. If it returned a
## fresh one, every caller would silently restart the sequence and the world would repeat
## itself.
func test_09_a_stream_is_created_once_and_kept() -> void:
	var service: RngService = ServiceScript.new(SEED_A)
	assert_false(service.has_stream(ServiceScript.STREAM_WORLD_SIM),
		"no stream exists before it is asked for")
	var first := service.stream(ServiceScript.STREAM_WORLD_SIM)
	first.next_raw()
	first.next_raw()
	var again := service.stream(ServiceScript.STREAM_WORLD_SIM)
	assert_eq(again.get_instance_id(), first.get_instance_id(),
		"the SAME stream object comes back, not a fresh one at the start")
	assert_eq(again.draw_count(), 2, "so the sequence continues instead of restarting")
	assert_true(service.has_stream(ServiceScript.STREAM_WORLD_SIM), "and it is now known")


# === 10-11. Invalid seeds fail closed =======================================

## An invalid seed must be an explicit error that refuses to produce streams (B20), never a
## silent fallback: a world quietly built on a substituted seed is a world the player's save
## does not name.
func test_10_an_invalid_seed_refuses_to_produce_streams() -> void:
	var too_big: RngService = ServiceScript.new(ServiceScript.SEED_MAX + 1)
	assert_false(too_big.is_valid(), "a seed above the 32-bit window is invalid")
	assert_null(too_big.stream(ServiceScript.STREAM_WORLD_SIM),
		"and it hands out NO stream rather than an unseeded one")

	var negative: RngService = ServiceScript.new(-1)
	assert_false(negative.is_valid(), "a negative seed is invalid")
	assert_null(negative.stream(ServiceScript.STREAM_WORLD_SIM), "and produces no stream")

	var ok: RngService = ServiceScript.new(0)
	assert_true(ok.is_valid(), "seed 0 is a legitimate world")
	assert_not_null(ok.stream(ServiceScript.STREAM_WORLD_SIM), "and produces a stream")
	assert_null(ok.stream(&""), "an empty stream id is refused")


# === 12-14. Resume (the §3b requirement) ====================================

## THE RESUME CONTRACT: a stream restored from a snapshot continues where it left off.
##
## The failure this prevents is subtle and total: restoring only the SEED would put the stream
## back at the BEGINNING, so a save taken forty hours in would replay the first forty hours of
## world rolls. Nothing errors; the world is simply wrong.
func test_12_a_serialized_stream_resumes_where_it_stopped() -> void:
	var original: RngStream = StreamScript.new(&"world_sim", 4242)
	for _i in 37:
		original.next_raw()
	var expected: Array[int] = []
	var twin: RngStream = StreamScript.new(&"world_sim", 4242)
	for _i in 37:
		twin.next_raw()
	for _i in 5:
		expected.append(twin.next_raw())

	var restored: RngStream = StreamScript.new()
	assert_true(restored.from_dict(original.to_dict()), "the snapshot hydrates")
	assert_eq(restored.stream_id, &"world_sim", "the id survives")
	assert_eq(restored.state(), original.state(), "the position survives")
	assert_eq(restored.draw_count(), 37, "and so does the draw count")
	var actual: Array[int] = []
	for _i in 5:
		actual.append(restored.next_raw())
	assert_eq(str(actual), str(expected),
		"a restored stream produces the SAME next values as one that never stopped")


## The whole seam round-trips, and the snapshot is byte-stable (so two saves of one world
## compare equal).
func test_13_the_whole_seam_round_trips_byte_stably() -> void:
	var service: RngService = ServiceScript.new(SEED_A)
	service.stream(ServiceScript.STREAM_WORLD_SIM).next_raw()
	service.stream(&"zzz_last").next_raw()
	service.stream(&"aaa_first").next_raw()
	var snapshot := service.to_dict()

	var restored: RngService = ServiceScript.new(SEED_A)
	assert_true(restored.from_dict(snapshot), "the seam hydrates")
	assert_eq(restored.world_seed(), SEED_A, "the world seed survives")
	assert_eq(str(restored.stream_ids_sorted()), str(service.stream_ids_sorted()),
		"every stream survives, in sorted order")
	assert_eq(str(restored.to_dict()), str(snapshot), "and the round trip is byte-stable")
	# The restored streams must CONTINUE, which is the point of serializing their state.
	assert_eq(restored.stream(ServiceScript.STREAM_WORLD_SIM).draw_count(), 1,
		"a restored stream keeps its draw count")


## Malformed payloads are REJECTED, never coerced (L-024), and a rejection leaves the receiver
## untouched. Each case differs from a known-good payload in exactly one field and would
## otherwise be accepted.
func test_14_malformed_rng_payloads_fail_closed() -> void:
	var service: RngService = ServiceScript.new(SEED_A)
	service.stream(ServiceScript.STREAM_WORLD_SIM).next_raw()
	var good := service.to_dict()
	var before := str(good)

	var baseline: RngService = ServiceScript.new(SEED_A)
	assert_true(baseline.from_dict(good.duplicate(true)),
		"the baseline payload IS accepted, so every rejection below is about its one change")

	var cases := {
		"a non-dict payload": "nope",
		"a string seed": {"world_seed": "12345", "streams": {}},
		"a float seed": {"world_seed": 12345.0, "streams": {}},
		"an out-of-range seed": {"world_seed": ServiceScript.SEED_MAX + 1, "streams": {}},
		"a non-dict streams block": {"world_seed": SEED_A, "streams": []},
		"a malformed stream row": {"world_seed": SEED_A, "streams": {"s": 5}},
		"a string stream state": {
			"world_seed": SEED_A,
			"streams": {"s": {"stream_id": "s", "state": "7", "draws": 0}},
		},
		"an out-of-range stream state": {
			"world_seed": SEED_A,
			"streams": {"s": {"stream_id": "s", "state": StreamScript.MOD_32, "draws": 0}},
		},
		"a negative draw count": {
			"world_seed": SEED_A,
			"streams": {"s": {"stream_id": "s", "state": 1, "draws": -1}},
		},
		"a key that disagrees with its row": {
			"world_seed": SEED_A,
			"streams": {"s": {"stream_id": "other", "state": 1, "draws": 0}},
		},
	}
	var names: Array = cases.keys()
	names.sort()
	for name in names:
		var target: RngService = ServiceScript.new(SEED_A)
		target.stream(ServiceScript.STREAM_WORLD_SIM).next_raw()
		var snapshot_before := str(target.to_dict())
		assert_false(target.from_dict(cases[name]), "%s is REJECTED" % String(name))
		assert_eq(str(target.to_dict()), snapshot_before,
			"and the seam is byte-identical afterwards (%s)" % String(name))
	assert_eq(str(good), before, "the known-good payload was not mutated by the loop")

extends TestCase
## The ACTION LAYER of `CharacterVisualComponent` (D-056).
##
## What is under test is the SECOND semantic layer: locomotion (`IDLE`/`WALK`, looping, clocked
## by the component) versus action (`BASIC_ATTACK`, one-shot, driven from outside). The contract
## is `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` §2-§4, and the three properties that make it
## worth having are:
##
##   1. **ACTION OUT-RANKS LOCOMOTION** — a character mid-swing shows the swing while walking.
##   2. **GAMEPLAY TIMING OWNS THE TRUTH** — the frame is a pure function of a progress value
##      pushed in; the component keeps no clock an action could drift against, and it cannot
##      advance the lifecycle it depicts.
##   3. **ONE LAYER, MANY ACTORS** — the player (32x48, 8 frames) and the mist wolf (32x32,
##      6 frames) go through the same methods with no actor-specific branch.
##
## These drive the PUBLIC API only (`play_action` / `drive_action` / `end_action` /
## `is_action_playing`), never `_refresh_frame` or the private cursor, so the tests describe the
## contract rather than the implementation.
##
## Every `Node` built here is freed by the test that built it (L-019).

const ProfileScript := preload("res://src/data/characters/character_visual_profile_data.gd")
const VisualScript := preload("res://src/presentation/characters/character_visual_component.gd")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

## The TWO shipped actors the one action layer must serve. Different frame sizes, different
## frame counts, same contract — this pair IS the §31 second-use-case proof, so it is a
## constant rather than a value inlined in one test.
const ACTOR_PROFILES := [
	"res://data/characters/visual/player_visual.tres",
	"res://data/characters/visual/mist_wolf_visual.tres",
]


func _profile(path: String) -> CharacterVisualProfileData:
	return load(path) as CharacterVisualProfileData


## A component in the tree, bound to a shipped profile. No parent entity, so there is no attack
## lifecycle to bind — which is itself the "an entity that cannot attack is a correct scene"
## case, and it lets these tests drive the layer directly.
func _component(path: String) -> CharacterVisualComponent:
	var component: CharacterVisualComponent = VisualScript.new()
	add_to_tree(component)
	assert_true(component.setup(_profile(path)), "the shipped profile %s binds" % path)
	return component


# === The data carries an action sheet =======================================

## Every shipped profile authors the action sheet. An OPTIONAL field that no shipped data
## authors is a no-op with documentation — `walk_sheet` shipped null in all four profiles for a
## whole phase and the documented idle fallback was the only path that ever ran (L-029). This
## is the assertion that stops the action sheet repeating it.
func test_every_shipped_profile_authors_an_action_sheet() -> void:
	var paths := [
		"res://data/characters/visual/player_visual.tres",
		"res://data/characters/visual/cultivator_f_visual.tres",
		"res://data/characters/visual/elder_visual.tres",
		"res://data/characters/visual/merchant_visual.tres",
		"res://data/characters/visual/mist_wolf_visual.tres",
	]
	for path in paths:
		var profile := _profile(path)
		assert_not_null(profile, "%s loads" % path)
		if profile == null:
			continue
		assert_true(profile.is_valid(),
			"%s is valid with the action sheet wired: %s" % [path, str(
				profile.validation_errors())])
		assert_not_null(profile.attack_sheet,
			("%s authors attack_sheet — an optional field nothing authors is a no-op with "
				+ "documentation") % path)
		assert_true(profile.frame_count_of(profile.attack_sheet) > 1,
			("and its action sheet holds more than one frame, or there is no anticipation -> "
				+ "action -> recovery to show (got %d)")
				% profile.frame_count_of(profile.attack_sheet))


## A ragged action sheet is REJECTED at the boundary, like every other sheet. The validator was
## already sheet-agnostic; this proves the new field actually goes through it rather than
## bypassing validation.
func test_an_invalid_action_sheet_fails_cleanly() -> void:
	var profile: CharacterVisualProfileData = ProfileScript.new()
	profile.id = &"vis_broken_action"
	profile.frame_size = Vector2i(32, 48)
	profile.idle_sheet = _profile(ACTOR_PROFILES[0]).idle_sheet
	assert_true(profile.is_valid(), "the baseline fixture is accepted")

	# The WOLF's sheet on a 32x48 profile: 128 wide is a whole number of 32px frames, but 128
	# tall is not 4 rows of 48. Exactly one field differs from the accepted fixture.
	profile.attack_sheet = _profile(ACTOR_PROFILES[1]).attack_sheet
	assert_false(profile.is_valid(), "a mismatched action sheet is refused")
	var reasons := str(profile.validation_errors())
	assert_true("attack_sheet" in reasons,
		"and the error NAMES the field, not just 'invalid' (%s)" % reasons)


# === Layer separation and precedence ========================================

## The two layers are distinct, and the ACTION wins.
func test_action_out_ranks_locomotion() -> void:
	var component := _component(ACTOR_PROFILES[0])
	var profile := _profile(ACTOR_PROFILES[0])

	# Locomotion first: walking shows the walk sheet.
	component.update_facing(Vector2.RIGHT, true)
	assert_false(component.is_action_playing(), "no action is playing yet")
	assert_eq(component.get_sprite().texture, profile.walk_sheet,
		"walking shows the walk sheet")

	# An action begins WHILE walking: the action sheet takes over.
	assert_true(component.play_action(CharacterVisualComponent.ACTION_ATTACK),
		"the action starts")
	assert_true(component.is_action_playing(), "and is reported as playing")
	assert_eq(component.current_action(), CharacterVisualComponent.ACTION_ATTACK,
		"by name")
	assert_eq(component.get_sprite().texture, profile.attack_sheet,
		("the ACTION sheet shows even though the character is still walking — a character "
			+ "mid-swing shows the swing"))

	# And it hands back to locomotion, which is still walking.
	component.end_action()
	assert_false(component.is_action_playing(), "the action ended")
	assert_eq(component.get_sprite().texture, profile.walk_sheet,
		"and locomotion resumes where it was, still walking")
	free_node(component)


## A facing change mid-action TURNS the character without restarting or cancelling the action.
## Facing is shared by the layers; only the locomotion cursor is suppressed.
func test_turning_mid_action_does_not_cancel_or_restart_it() -> void:
	var component := _component(ACTOR_PROFILES[0])
	component.play_action(CharacterVisualComponent.ACTION_ATTACK)
	component.drive_action(0.5)
	var frame_before := component.get_sprite().frame
	var column_before := component.get_column()

	component.update_facing(Vector2.UP, true)
	assert_true(component.is_action_playing(), "the action survived the turn")
	assert_eq(component.get_column(), column_before,
		"and did not restart — the cursor is unchanged")
	assert_eq(component.get_direction(), CharacterVisualProfileData.Direction.UP,
		"but the character now faces UP")
	assert_ne(component.get_sprite().frame, frame_before,
		"so the rendered grid cell moved to the UP row")
	free_node(component)


## An action the profile cannot play is REFUSED, and locomotion carries on. Presentation
## degrades; gameplay is unaffected.
func test_an_unavailable_action_is_refused_and_locomotion_continues() -> void:
	var profile: CharacterVisualProfileData = ProfileScript.new()
	profile.id = &"vis_no_action"
	profile.frame_size = Vector2i(32, 48)
	profile.idle_sheet = _profile(ACTOR_PROFILES[0]).idle_sheet
	var component: CharacterVisualComponent = VisualScript.new()
	add_to_tree(component)
	assert_true(component.setup(profile), "a profile with no action sheet is still valid")

	assert_false(component.play_action(CharacterVisualComponent.ACTION_ATTACK),
		"an action with no sheet is refused rather than played blank")
	assert_false(component.is_action_playing(), "nothing is playing")
	assert_eq(component.get_sprite().texture, profile.idle_sheet,
		"and the character is still rendering locomotion")
	# Driving a refused action must be inert, not an error.
	component.drive_action(0.7)
	assert_false(component.is_action_playing(), "driving a refused action starts nothing")
	assert_eq(component.get_sprite().texture, profile.idle_sheet, "and renders nothing new")
	free_node(component)


## An unknown action name is refused. The vocabulary in the contract is RESERVED, not
## implemented, and a reserved name must not silently render the attack sheet.
func test_a_reserved_but_unimplemented_action_is_refused() -> void:
	var component := _component(ACTOR_PROFILES[0])
	for reserved in [&"hit", &"stun", &"death", &"emote"]:
		assert_false(component.play_action(reserved),
			("'%s' is reserved vocabulary with no sheet and no implementation — it must be "
				+ "refused, not quietly rendered as something else") % reserved)
		assert_false(component.is_action_playing(), "so nothing plays")
	free_node(component)


# === Driven, not clocked ====================================================

## THE frame is a pure function of the driven progress, CLAMPED at the end rather than wrapped.
## That clamp is what makes an action different in KIND from a locomotion cycle.
func test_the_action_frame_is_a_pure_function_of_driven_progress() -> void:
	var component := _component(ACTOR_PROFILES[0])
	var profile := _profile(ACTOR_PROFILES[0])
	var frames := profile.frame_count_of(profile.attack_sheet)
	component.update_facing(Vector2.DOWN, false)
	component.play_action(CharacterVisualComponent.ACTION_ATTACK)

	assert_eq(component.get_column(), 0, "progress 0 shows the first frame")
	component.drive_action(1.0)
	assert_eq(component.get_column(), frames - 1,
		"progress 1 shows the LAST frame, clamped — not wrapped back to 0")
	component.drive_action(2.0)
	assert_eq(component.get_column(), frames - 1,
		"and over-driving stays on the last frame rather than looping the swing")
	component.drive_action(-1.0)
	assert_eq(component.get_column(), 0, "under-driving clamps to the first")

	# The SAME progress always gives the same frame: there is no hidden clock.
	component.drive_action(0.5)
	var at_half := component.get_column()
	component.drive_action(0.9)
	component.drive_action(0.5)
	assert_eq(component.get_column(), at_half,
		"revisiting a progress value returns the same frame — the layer holds no clock")
	free_node(component)


## The action must traverse its frames: progress across [0,1] visits more than one column, and
## the first and last differ. A one-shot that renders frame 0 forever passes every
## single-sample assertion (L-029), so the traversal is what is asserted.
func test_driving_an_action_across_its_range_actually_traverses_frames() -> void:
	for path in ACTOR_PROFILES:
		var component := _component(path)
		var profile := _profile(path)
		var frames := profile.frame_count_of(profile.attack_sheet)
		component.play_action(CharacterVisualComponent.ACTION_ATTACK)
		var seen := {}
		for step in 20:
			component.drive_action(float(step) / 19.0)
			seen[component.get_column()] = true
		assert_eq(seen.size(), frames,
			("%s: driving 0 -> 1 visits every one of its %d frames (saw %d) — an action that "
				+ "renders one frame forever would pass a single-sample check")
				% [path.get_file(), frames, seen.size()])
		free_node(component)


## `advance()` must not step an action. The locomotion clock is the component's; the action's
## clock belongs to the authority that owns the lifecycle.
func test_advancing_time_does_not_move_a_driven_action() -> void:
	var component := _component(ACTOR_PROFILES[0])
	component.play_action(CharacterVisualComponent.ACTION_ATTACK)
	component.drive_action(0.4)
	var column := component.get_column()
	var progress := component.action_progress()

	for _i in 30:
		component.advance(0.1)
	assert_eq(component.get_column(), column,
		("30 ticks of 0.1s moved the action by nothing: it advances only when the gameplay "
			+ "authority says so (gameplay timing owns the truth)"))
	assert_true(is_equal_approx(component.action_progress(), progress),
		"and its progress is untouched")
	free_node(component)


# === Two actors, one layer ==================================================

## THE §31 proof: both shipped actors run the same action contract. Different frame SIZE
## (32x48 vs 32x32), different frame COUNT (8 vs 6), one code path, no actor branch.
func test_the_same_action_contract_serves_both_shipped_actors() -> void:
	var sizes := {}
	var counts := {}
	for path in ACTOR_PROFILES:
		var component := _component(path)
		var profile := _profile(path)
		sizes[str(profile.frame_size)] = true
		counts[profile.frame_count_of(profile.attack_sheet)] = true

		assert_true(component.play_action(CharacterVisualComponent.ACTION_ATTACK),
			"%s plays the action through the same method" % path.get_file())
		component.drive_action(0.5)
		assert_eq(component.get_sprite().texture, profile.attack_sheet,
			"%s renders its OWN action sheet" % path.get_file())
		assert_eq(component.get_sprite().hframes,
			profile.frame_count_of(profile.attack_sheet),
			"%s derives its column count from its own art" % path.get_file())
		component.end_action()
		assert_eq(component.get_sprite().texture, profile.idle_sheet,
			"%s returns to its own locomotion" % path.get_file())
		free_node(component)

	assert_eq(sizes.size(), 2,
		"the two actors genuinely differ in frame SIZE (%s)" % str(sizes.keys()))
	assert_eq(counts.size(), 2,
		"and in action frame COUNT (%s) — otherwise this proves one case twice"
			% str(counts.keys()))


## STRUCTURAL: there is exactly ONE animation controller. The failure this guards is four
## near-identical files (`player_cast.gd`, `enemy_cast.gd`, …) which is what the shared action
## model exists to prevent. The directory is WALKED, not listed (L-034).
func test_there_is_only_one_character_animation_controller() -> void:
	var drivers: Array[String] = []
	_collect_action_drivers("res://src", drivers)
	assert_eq(drivers.size(), 1,
		("exactly one file may own the character action layer; logic is shared and DATA "
			+ "differs per actor. Found: %s") % str(drivers))
	if drivers.size() == 1:
		assert_eq(drivers[0], "src/presentation/characters/character_visual_component.gd",
			"and it is the component that already owned the sprite")


func _collect_action_drivers(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_collect_action_drivers(full, out)
		elif entry.ends_with(".gd"):
			var file := FileAccess.open(full, FileAccess.READ)
			if file != null:
				var source := file.get_as_text()
				file.close()
				# A file that DECLARES the action API owns the layer. Calling it is fine (the
				# entity wiring does); declaring a second one is the duplication.
				if "func play_action(" in source and "func drive_action(" in source:
					out.append(full.trim_prefix("res://"))
		entry = dir.get_next()
	dir.list_dir_end()


# === Presentation owns nothing ==============================================

## Driving the whole action pipeline must not touch domain state. Deleting presentation changes
## no outcome; the inverse — presentation changing an outcome — is what this rules out.
func test_the_action_layer_mutates_no_domain_state() -> void:
	# The fixture is typed as the CONCRETE classes and uses the REAL field names. The first
	# version wrote `display_name_key`/`stat_block`, which do not exist — a non-existent
	# property on a typed `@export` is a VM error that ABORTS the method, and this project's
	# runner reports an aborted method as PASS because it only counts assertion failures
	# (L-026). It was caught by the suite's `SCRIPT ERROR:` check, which exists for exactly
	# this: a test that never ran is worse than a test that failed.
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 50
	stats.attack = 5
	stats.defense = 2
	stats.move_speed = 60.0
	var template: CharacterTemplateData = TemplateScript.new()
	template.id = &"tpl_action_probe"
	template.name_key = &"CHARACTER_PLAYER_NAME"
	template.title_key = &"CHARACTER_PLAYER_TITLE"
	template.base_stats = stats
	var state: CharacterState = StateScript.create_from_template(template, &"c_action_probe")
	assert_not_null(state, "the probe character was built")
	if state == null:
		return
	var before := str(state.to_dict())
	assert_ne(before, "{}", "and its snapshot is non-empty, so the comparison means something")

	var component := _component(ACTOR_PROFILES[0])
	component.update_facing(Vector2.LEFT, true)
	component.play_action(CharacterVisualComponent.ACTION_ATTACK)
	for step in 12:
		component.drive_action(float(step) / 11.0)
		component.advance(0.016)
	component.end_action()

	assert_eq(str(state.to_dict()), before,
		"a full action cycle left the character's authoritative state byte-identical")
	free_node(component)


# === Cost and cleanup =======================================================

## Repeating the action must not accumulate anything. Every creature carries one of these, so a
## node or timer leaked per swing is a leak per swing per creature.
func test_repeating_the_action_accumulates_no_nodes() -> void:
	var component := _component(ACTOR_PROFILES[0])
	var children_before := component.get_child_count()
	for _swing in 25:
		component.play_action(CharacterVisualComponent.ACTION_ATTACK)
		for step in 6:
			component.drive_action(float(step) / 5.0)
		component.end_action()
	assert_eq(component.get_child_count(), children_before,
		("25 action cycles created no extra nodes (one Sprite2D, before and after) — no "
			+ "AnimationPlayer per swing, no timer per effect"))
	assert_false(component.is_action_playing(), "and nothing is left playing")
	free_node(component)


## A STATIC character pays for no frames — unless an action is running, which must keep
## `_process` alive because the action still has to be ENDED. Both halves matter: this node
## exists on every creature in the world, so an always-on `_process` is N callbacks per frame;
## but an action that switched processing off could never finish and would freeze a pose.
func test_a_static_character_costs_no_frames_unless_an_action_is_running() -> void:
	var one_frame := ImageTexture.create_from_image(Image.create(
		32, 48 * CharacterVisualProfileData.DIRECTION_COUNT, false, Image.FORMAT_RGBA8))
	var two_frame := ImageTexture.create_from_image(Image.create(
		64, 48 * CharacterVisualProfileData.DIRECTION_COUNT, false, Image.FORMAT_RGBA8))
	var profile: CharacterVisualProfileData = ProfileScript.new()
	profile.id = &"vis_static_action"
	profile.frame_size = Vector2i(32, 48)
	profile.idle_sheet = one_frame
	profile.attack_sheet = two_frame
	assert_true(profile.is_valid(),
		"a static locomotion sheet with an animated action sheet is legal: %s"
			% str(profile.validation_errors()))

	var component: CharacterVisualComponent = VisualScript.new()
	add_to_tree(component)
	assert_true(component.setup(profile), "the component accepts it")
	assert_false(component.is_processing(),
		"a static character with no action running costs nothing per frame")

	assert_true(component.play_action(CharacterVisualComponent.ACTION_ATTACK),
		"the action starts")
	assert_true(component.is_processing(),
		("and _process is ON while it runs — an action that stopped being processed could "
			+ "never end, which would freeze the character in a pose"))

	component.end_action()
	assert_false(component.is_processing(),
		"when it ends, the static character stops paying again")
	free_node(component)

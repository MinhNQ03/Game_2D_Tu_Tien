extends TestCase
## Presentation tests for the Phase-11 progression UI: the level badge, the XP meter, and the
## one-shot level-up celebration.
##
## The two things this file exists to hold to account are the two the phase brief is strictest
## about:
##   1. **XP must not be confusable with HP.** They sit one above the other in the same plaque,
##      which is the hardest place to tell two bars apart, so the separation is asserted on
##      three independent channels (hue, weight, text) rather than trusted to look different.
##   2. **The celebration must be presentation-only and must always terminate.** It is driven
##      through its public clock, so the midpoint and the end state are both checked — an
##      effect that never finishes would leave the badge permanently lit and the banner
##      permanently on screen, and neither is visible to a test that only starts it.
##
## Every Node created here is freed (L-019).

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const FeedbackScript := preload("res://src/presentation/progression/level_up_feedback.gd")


func _hud() -> Node:
	var hud: Node = HUDScript.new()
	add_to_tree(hud)  # _ready() builds the labels + resolves autoloads
	return hud


func _view(level: int, into: int, cost: int, at_ceiling: bool = false) -> ProgressionView:
	var view := ProgressionView.new()
	view.available = true
	view.level = level
	view.xp_into_level = into
	view.xp_for_next = cost
	view.at_ceiling = at_ceiling
	view.progress = 1.0 if at_ceiling else (float(into) / float(maxi(1, cost)))
	return view


## Depth-first search for a node by name.
func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		# Explicitly typed: a RECURSIVE call's return type is not yet resolved, so `:=` here
		# infers Variant — which this project promotes to a compile error (L-020 / GD001).
		var found: Node = _find(child, wanted)
		if found != null:
			return found
	return null


## Every Label's text in the HUD, flattened — so a test can assert what the player can read.
func _all_text(node: Node) -> String:
	var out := ""
	var label := node as Label
	if label != null:
		out += label.text + "\n"
	for child in node.get_children():
		out += _all_text(child)
	return out


# --- Structure ---------------------------------------------------------------

func test_the_progression_row_exists_and_is_hidden_until_a_view_arrives() -> void:
	var hud := _hud()
	var badge := _find(hud, "LevelBadge") as Label
	var meter := _find(hud, "XpMeter") as ProgressBar
	assert_not_null(badge, "the HUD builds a named level badge")
	assert_not_null(meter, "and a named XP meter")
	if badge == null or meter == null:
		free_node(hud)
		return
	assert_false(badge.visible, "the badge is hidden before a progression session reports")
	assert_false(meter.visible, "and so is the meter")
	assert_false(hud.call("is_progression_visible"), "which the public contract reports")
	free_node(hud)


func test_the_level_badge_has_a_width_floor_so_levelling_does_not_resize_the_plaque() -> void:
	var hud := _hud()
	var badge := _find(hud, "LevelBadge") as Label
	assert_not_null(badge, "badge exists")
	if badge == null:
		free_node(hud)
		return
	assert_eq(int(badge.custom_minimum_size.x), UIPalette.LEVEL_BADGE_MIN_WIDTH,
		("the badge reserves a minimum width from a named token, so `Cấp 1` and `Cấp 20` do "
			+ "not make the identity plaque twitch on every level-up"))
	free_node(hud)


# --- XP must not be confusable with HP --------------------------------------

## The phase brief's hardest UI requirement, checked on three INDEPENDENT channels.
##
## Colour alone would fail a colour-blind player, and `docs/UI_UX_BIBLE.md` §4 forbids colour
## being the only carrier of meaning — so the weight difference and the written text are
## asserted as separate guarantees, not as nice-to-haves.
func test_the_xp_meter_is_distinguishable_from_the_health_gauge() -> void:
	var hud := _hud()
	hud.call("set_health", 42, 60)
	hud.call("set_progression_view", _view(3, 20, 45))

	var health := _find(hud, "VitalsGauge") as ProgressBar
	var xp := _find(hud, "XpMeter") as ProgressBar
	assert_not_null(health, "the health gauge is present")
	assert_not_null(xp, "and the XP meter")
	if health == null or xp == null:
		free_node(hud)
		return

	# 1. WEIGHT — the meter is thinner, so it reads as subordinate information.
	assert_true(xp.custom_minimum_size.y < health.custom_minimum_size.y,
		("the XP meter (%d px) is thinner than the vitals gauge (%d px)")
			% [int(xp.custom_minimum_size.y), int(health.custom_minimum_size.y)])

	# 2. HUE — gold for progression, jade for vitals. Read off the actual styleboxes, not off
	#    the palette, so pointing the meter at the wrong token fails here.
	var xp_fill := xp.get_theme_stylebox("fill") as StyleBoxFlat
	var hp_fill := health.get_theme_stylebox("fill") as StyleBoxFlat
	assert_not_null(xp_fill, "the meter has a flat fill")
	assert_not_null(hp_fill, "and so does the gauge")
	if xp_fill != null and hp_fill != null:
		assert_ne(str(xp_fill.bg_color), str(hp_fill.bg_color),
			"the two fills are different colours (xp=%s hp=%s)"
				% [str(xp_fill.bg_color), str(hp_fill.bg_color)])
		assert_eq(str(xp_fill.bg_color), str(UIPalette.XP_METER_FILL),
			"and the XP fill is the gold progression token, not the jade vitals one")

	# 3. TEXT — each writes its own numbers, so the distinction survives without colour.
	var text := _all_text(hud)
	assert_true("42 / 60" in text, "the health gauge writes its pair")
	assert_true("20 / 45" in text, "and the XP meter writes its own (got: %s)" % text)
	free_node(hud)


func test_the_meter_writes_a_localized_caption_so_the_numbers_are_not_bare() -> void:
	var hud := _hud()
	hud.call("set_progression_view", _view(2, 10, 45))
	var text := _all_text(hud)
	# The pair alone ("10 / 45") could be read as a second health pool. The caption is what
	# names it, and it must be localized rather than a hard-coded "XP".
	assert_true("10 / 45" in text, "the numbers are written")
	assert_false("UI_HUD_XP_PROGRESS" in text,
		"and the caption is RESOLVED, not a raw key leaking to the player (got: %s)" % text)
	assert_false("UI_HUD_LEVEL" in text, "nor the level key")
	free_node(hud)


func test_the_ceiling_reads_as_complete_rather_than_zero_of_zero() -> void:
	var hud := _hud()
	hud.call("set_progression_view", _view(21, 0, 0, true))
	var meter := _find(hud, "XpMeter") as ProgressBar
	assert_not_null(meter, "meter")
	if meter == null:
		free_node(hud)
		return
	assert_true(meter.value >= meter.max_value,
		"a maxed meter is FULL, not empty — the raw numbers at the ceiling are 0 and 0")
	assert_false("0 / 0" in _all_text(hud),
		"and it never writes `0 / 0`, which is what the raw pair would say")
	var fill := meter.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		assert_eq(str(fill.bg_color), str(UIPalette.XP_METER_FILL_COMPLETE),
			"the ceiling uses its own fill, so 'maxed' and 'nearly full' are not the same "
			+ "picture")
	free_node(hud)


# --- Localization ------------------------------------------------------------

func test_the_progression_strings_resolve_in_both_languages() -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	assert_not_null(loc, "the Localization autoload is live in the runner")
	if loc == null:
		return
	for key in ["UI_HUD_LEVEL", "UI_HUD_XP_PROGRESS", "UI_HUD_XP_COMPLETE",
			"UI_HUD_LEVEL_UP"]:
		assert_true(bool(loc.call("has_key", key)), "'%s' is authored" % key)

	# Both languages must have a real value, not a fallback to the key. The service returns
	# the KEY itself when a value is missing, so comparing against the key is the check.
	var original := String(loc.call("get_language"))
	for language in ["vi", "en"]:
		loc.call("set_language", language)
		for key in ["UI_HUD_LEVEL", "UI_HUD_XP_PROGRESS", "UI_HUD_XP_COMPLETE",
				"UI_HUD_LEVEL_UP"]:
			var text := String(loc.call("t", key))
			assert_ne(text, key, "'%s' has a real %s value (got '%s')" % [key, language, text])
	loc.call("set_language", original)


## The level/XP vocabulary must NOT borrow cultivation words.
##
## This is a design constraint, not a translation preference:
## `docs/PROGRESSION_CULTIVATION_DESIGN.md` §1 forbids collapsing level and cảnh giới into one
## idea, and the fastest way to break that in practice is for the UI to call level "tu vi" or
## a level-up "đột phá". Then the player is told they are the same thing in the only place
## they actually look. Phase 12 owns those words.
func test_the_level_vocabulary_does_not_borrow_cultivation_words() -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc == null:
		return
	var original := String(loc.call("get_language"))
	var reserved := ["tu vi", "đột phá", "cảnh giới", "tu luyện", "realm", "breakthrough",
		"cultivation"]
	for language in ["vi", "en"]:
		loc.call("set_language", language)
		for key in ["UI_HUD_LEVEL", "UI_HUD_XP_PROGRESS", "UI_HUD_XP_COMPLETE",
				"UI_HUD_LEVEL_UP"]:
			var text := String(loc.call("t", key)).to_lower()
			for word in reserved:
				assert_false(text.contains(word),
					("'%s' (%s) must not use the cultivation word '%s' — level is a "
						+ "different axis and Phase 12 owns that vocabulary (got '%s')")
						% [key, language, word, text])
	loc.call("set_language", original)


# --- The level-up celebration -----------------------------------------------

func test_the_celebration_runs_decays_and_terminates_exactly_at_rest() -> void:
	var hud := _hud()
	hud.call("set_progression_view", _view(2, 0, 45))
	var effect: LevelUpFeedback = hud.call("level_up_feedback")
	assert_not_null(effect, "the HUD owns a level-up effect")
	if effect == null:
		free_node(hud)
		return

	var resting := effect.resting_tint()
	assert_false(effect.is_celebrating(), "idle before anything happens")
	assert_false(effect.is_banner_visible(), "and no banner on screen")

	hud.call("celebrate_level_up", 2)
	assert_true(effect.is_celebrating(), "the celebration started")
	assert_true(effect.is_banner_visible(), "and the announcement is up")
	assert_ne(str(effect.current_tint()), str(resting), "the badge is lit")

	# Halfway: still running, and somewhere between the peak and rest.
	effect.advance(UIPalette.LEVEL_UP_SECONDS * 0.5)
	assert_true(effect.is_celebrating(), "still running at the midpoint")

	# Past the end: it must stop, hide the banner, and restore the resting colour EXACTLY —
	# a lerped endpoint would leave a few ten-millionths of tint behind on every level-up.
	effect.advance(UIPalette.LEVEL_UP_SECONDS)
	assert_false(effect.is_celebrating(), "the celebration terminated")
	assert_false(effect.is_banner_visible(), "the announcement came down")
	assert_eq(str(effect.current_tint()), str(resting),
		"and the badge is back at EXACTLY its resting colour")
	free_node(hud)


func test_the_celebration_costs_nothing_while_idle() -> void:
	var hud := _hud()
	var effect: LevelUpFeedback = hud.call("level_up_feedback")
	if effect == null:
		free_node(hud)
		return
	assert_false(effect.is_processing(),
		"_process is OFF before any level-up — a HUD that lives for the whole session must "
		+ "not pay for an effect that is not running")
	hud.call("set_progression_view", _view(2, 0, 45))
	hud.call("celebrate_level_up", 2)
	assert_true(effect.is_processing(), "on while celebrating")
	effect.advance(UIPalette.LEVEL_UP_SECONDS * 2.0)
	assert_false(effect.is_processing(), "and off again afterwards")
	free_node(hud)


func test_cancelling_mid_celebration_restores_the_badge_and_hides_the_banner() -> void:
	# A map transition or a return to the menu can land mid-effect. An effect that could be
	# interrupted and leave the badge lit forever would be a permanent visual defect caused by
	# ordinary play.
	var hud := _hud()
	hud.call("set_progression_view", _view(2, 0, 45))
	var effect: LevelUpFeedback = hud.call("level_up_feedback")
	if effect == null:
		free_node(hud)
		return
	var resting := effect.resting_tint()
	hud.call("celebrate_level_up", 2)
	effect.advance(UIPalette.LEVEL_UP_SECONDS * 0.25)
	effect.cancel()
	assert_false(effect.is_celebrating(), "cancelled")
	assert_false(effect.is_banner_visible(), "banner down")
	assert_eq(str(effect.current_tint()), str(resting), "badge restored immediately")
	free_node(hud)


func test_a_second_level_up_during_the_first_still_ends_at_rest() -> void:
	# A single big grant can cross several thresholds, and the player can immediately kill
	# something else — so two celebrations can overlap. The resting colour is captured ONCE at
	# bind time precisely so a restart cannot snapshot the previous flash as the new base and
	# leave the badge permanently brighter.
	var hud := _hud()
	hud.call("set_progression_view", _view(2, 0, 45))
	var effect: LevelUpFeedback = hud.call("level_up_feedback")
	if effect == null:
		free_node(hud)
		return
	var resting := effect.resting_tint()
	hud.call("celebrate_level_up", 2)
	effect.advance(UIPalette.LEVEL_UP_SECONDS * 0.4)
	hud.call("celebrate_level_up", 3)
	effect.advance(UIPalette.LEVEL_UP_SECONDS * 2.0)
	assert_false(effect.is_celebrating(), "the restarted celebration also terminated")
	assert_eq(str(effect.current_tint()), str(resting),
		"and the badge is back at the ORIGINAL resting colour, not a drifted one")
	assert_eq(effect.celebrated_level(), 3, "the latest level is the one recorded")
	free_node(hud)


## The announcement must live in a band the HUD RESERVES, not near the screen centre.
##
## A test cannot see the defect that produced this rule — the banner printing across the
## player's body — because the player is in the world and the banner is in screen space. What
## it CAN pin is the structural property that makes the collision impossible: the banner is
## bottom-anchored and sits clear of the strip the control prompts own. Two capture-found
## attempts preceded it (centred, then nudged up from centre), and the second failed because
## the camera is clamped by the map limits, so the player's screen position is not a fixed
## distance from the centre at all.
##
## Offsets are asserted, not anchors: `set_anchors_preset` preserves the current rect, so
## correct anchors prove nothing about where a control actually is (L-028).
func test_the_level_up_banner_sits_in_a_reserved_band_not_at_the_screen_centre() -> void:
	var hud := _hud()
	var banner := _find(hud, "LevelUpBanner") as Control
	assert_not_null(banner, "the HUD builds a named level-up banner")
	if banner == null:
		free_node(hud)
		return
	assert_eq(banner.anchor_top, 1.0,
		"the banner is anchored to the BOTTOM edge, not the centre — the centre is where the "
		+ "camera keeps the player")
	assert_eq(banner.anchor_bottom, 1.0, "both vertical anchors are on the bottom edge")
	# It must clear the prompt strip, by arithmetic from the same token the side panels use.
	assert_true(banner.offset_bottom <= -float(UIPalette.PROMPT_STRIP_RESERVE),
		("the banner clears the reserved prompt strip (offset_bottom=%.0f must be <= -%d), so "
			+ "it cannot bury the control prompts")
			% [banner.offset_bottom, UIPalette.PROMPT_STRIP_RESERVE])
	assert_true(banner.offset_bottom < 0.0,
		"and it is inset from the bottom edge rather than sitting on it")
	free_node(hud)


func test_the_effect_mutates_no_progression_state() -> void:
	# §27: animation must never mutate gameplay and animation state must never be
	# authoritative. The effect's only output is a colour and a visibility flag; the numbers
	# on screen come from the pushed view.
	var hud := _hud()
	hud.call("set_progression_view", _view(4, 12, 130))
	var before := _all_text(hud)
	hud.call("celebrate_level_up", 99)  # a level the view never reported
	var effect: LevelUpFeedback = hud.call("level_up_feedback")
	if effect != null:
		effect.advance(UIPalette.LEVEL_UP_SECONDS * 2.0)
	var badge := _find(hud, "LevelBadge") as Label
	assert_not_null(badge, "badge")
	if badge != null:
		assert_false("99" in badge.text,
			("the celebration cannot change the level the badge shows — the badge renders the "
				+ "pushed view, and the effect owns only a tint (got '%s')") % badge.text)
	assert_true("12 / 130" in before, "the meter rendered the pushed numbers")
	free_node(hud)

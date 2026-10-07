extends TestCase
## Structural tests for the GameplayHUD (Phase 04). The HUD must BUILD its labels, render a
## bound character's name key through Localization, and compose the control hint from the
## InputService display label (never a raw keycode). It reads /root autoloads (Localization,
## InputService) which are live in the runner (D-019) and are only READ here, so no shared
## state is mutated (the GameState isolation guard stays green).

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")
const SectPanelScript := preload("res://src/presentation/sect/sect_panel.gd")
const EventDataScript := preload("res://src/data/worldsim/world_sim_event_data.gd")
const LocalizationScript := preload("res://src/infrastructure/localization.gd")


func _hud() -> Node:
	var hud: Node = HUDScript.new()
	add_to_tree(hud)  # _ready() builds the labels + resolves autoloads
	return hud


func _player_state() -> RefCounted:
	var stats := StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var t := TemplateScript.new()
	t.id = &"char_x"
	t.name_key = &"CHARACTER_PLAYER_NAME"
	t.title_key = &"CHARACTER_PLAYER_TITLE"
	t.base_stats = stats
	return StateScript.create_from_template(t, &"inst_x")


func test_hud_builds_labels() -> void:
	var hud := _hud()
	# A FLOOR, not a count: name, title, map, plus the five prompt rows' badge+word pairs.
	# Deliberately left as ">= 4" rather than retuned every phase — the specific rows are
	# asserted by the tests that own them, and a brittle total here would only ever record
	# whatever the HUD happened to contain on the day it was edited.
	var labels: Array[Label] = []
	_collect_labels(hud, labels)
	assert_true(labels.size() >= 4, "HUD builds at least name/title/map/prompt labels")
	free_node(hud)


func test_hud_shows_character_name() -> void:
	var hud := _hud()
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "en")
	hud.set_character(_player_state())
	# The name label should resolve CHARACTER_PLAYER_NAME ("Wanderer" in en).
	var labels: Array[Label] = []
	_collect_labels(hud, labels)
	var found := false
	for label in labels:
		if label.text == "Wanderer":
			found = true
	assert_true(found, "HUD renders the character's localized name")
	free_node(hud)


func test_hud_prompts_use_graphic_badges_with_display_labels() -> void:
	var hud := _hud()
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "en")
	hud.set_interact_available(true)
	hud.set_cultivation_view(_cultivation_at_site())

	# Gather all label text + confirm the key badges exist as graphic chips (UIKeyBadge is a
	# PanelContainer wearing an asset-backed stylebox — not plain floating text).
	var all_text := _all_label_text(hud)
	assert_true("E" in all_text, "a key badge shows the 'E' glyph")
	assert_true("Esc" in all_text, "a key badge shows the 'Esc' glyph")
	assert_true("Interact" in all_text, "the interact prompt shows the localized action word")
	assert_true("Menu" in all_text, "the menu prompt shows the localized action word")
	# Never leak a raw keycode number or a raw action name.
	for t in all_text:
		assert_false(t.contains("69"), "no raw keycode in a prompt (%s)" % t)
		assert_false(t.contains("interact"), "no raw action name in a prompt (%s)" % t)
		assert_false(t.contains("open_menu"), "no raw action name in a prompt (%s)" % t)

	# The key glyphs sit inside graphic badge panels (PanelContainer holding a single Label),
	# proving a graphic treatment, not floating text. FIVE prompts are built (attack, interact,
	# sect, politics, menu) and interact is visible here, so all five carry a badge — the old
	# ">= 2 (interact + menu)" was written when the strip had two rows and had stopped
	# describing the HUD three prompts ago.
	assert_eq(_key_badge_count(hud), 6,
		("each of the six prompts (attack, interact, cultivate, sect, politics, menu) has a "
			+ "graphic "
			+ "key badge, got %d") % _key_badge_count(hud))
	free_node(hud)


# --- SectPanel resource rendering (§7 hardening) -----------------------------

## The sect resource summary is keyed by INTERNAL content ids (`spirit_stones`, `pills`, …).
## The panel used to print those tokens straight onto the screen, which is both a raw-id leak
## (§21) and hard-coded English-ish text in a Vietnamese-first game (`07-localization.md`).
## Every id must now render through its `SECT_RESOURCE_*` display key.
func test_sect_panel_renders_localized_resource_names_not_raw_ids() -> void:
	var panel: Node = SectPanelScript.new()
	add_to_tree(panel)  # _ready() resolves Localization + builds the labels
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "en")
	panel.call("set_view", _sect_view({
		"spirit_stones": 1200, "pills": 48, "manpower": 320,
	}))

	var all_text := _all_label_text(panel)
	for raw_id in ["spirit_stones", "pills", "manpower"]:
		for t in all_text:
			assert_false(String(t).contains(raw_id),
				"no raw resource id '%s' reaches the screen (saw '%s')" % [raw_id, t])
	# The localized names DO appear, with their quantities.
	var resources_line := _line_containing(all_text, "1200")
	assert_ne(resources_line, "", "the resource summary line is rendered")
	if loc != null:
		for key in [
			"SECT_RESOURCE_SPIRIT_STONES", "SECT_RESOURCE_PILLS", "SECT_RESOURCE_MANPOWER",
		]:
			var localized := String(loc.call("t", key))
			assert_true(resources_line.contains(localized),
				"the summary shows the localized name for '%s' ('%s')" % [key, localized])
	free_node(panel)


## An id with no authored display key must degrade to the LOCALIZED generic label, never to
## the internal token (a missing translation is a content gap, not a reason to leak data).
func test_sect_panel_falls_back_to_a_localized_label_for_an_unknown_resource() -> void:
	var panel: Node = SectPanelScript.new()
	add_to_tree(panel)
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", "vi")
	panel.call("set_view", _sect_view({"unobtainium_dust": 7}))

	var all_text := _all_label_text(panel)
	for t in all_text:
		assert_false(String(t).contains("unobtainium_dust"),
			"an unlocalized resource id never reaches the screen (saw '%s')" % t)
	var line := _line_containing(all_text, "7")
	assert_ne(line, "", "the summary line is still rendered for an unknown resource")
	if loc != null:
		var fallback := String(loc.call("t", "UI_SECT_PANEL_RESOURCE_UNKNOWN"))
		assert_true(line.contains(fallback),
			"it shows the localized generic label '%s' instead" % fallback)
	free_node(panel)


## The id → key convention itself (§7): `spirit_stones` -> `SECT_RESOURCE_SPIRIT_STONES`.
## A pure naming rule, so new content needs CSV rows only — no registry, no code change.
func test_sect_resource_key_convention() -> void:
	assert_eq(SectPanel.resource_name_key("spirit_stones"), "SECT_RESOURCE_SPIRIT_STONES",
		"resource id maps to its upper-cased prefixed key")
	assert_eq(SectPanel.resource_name_key("pills"), "SECT_RESOURCE_PILLS", "short id")
	assert_eq(SectPanel.resource_name_key("blood_crystals"), "SECT_RESOURCE_BLOOD_CRYSTALS",
		"multi-word id")


## A member view carrying `summary` as its resource dict; the other fields are real authored
## keys so the panel renders a complete, localizable row set.
func _sect_view(summary: Dictionary) -> SectMembershipView:
	var view := SectMembershipView.new()
	view.is_member = true
	view.sect_name_key = &"SECT_AZURE_CLOUD_NAME"
	view.doctrine_key = &"SECT_AZURE_CLOUD_DOCTRINE"
	view.rank_name_key = &"SECT_RANK_OUTER_DISCIPLE"
	view.tier = 3
	view.reputation = 45
	view.influence = 60
	view.territory_count = 2
	view.resource_summary = summary
	return view


## The first label text containing `needle`, or "" if none. Used to pick the resource summary
## line out of the panel without depending on label order.
func _line_containing(all_text: Array, needle: String) -> String:
	for t in all_text:
		if String(t).contains(needle):
			return String(t)
	return ""


## Collect every Label's text under a node (recursive).
func _all_label_text(node: Node) -> Array:
	var out: Array = []
	var labels: Array[Label] = []
	_collect_labels(node, labels)
	for label in labels:
		out.append(label.text)
	return out


## Count key-badge chips: PanelContainers whose only child is a Label (the UIKeyBadge shape).
func _key_badge_count(node: Node) -> int:
	var n := 0
	if node is PanelContainer and node.get_child_count() == 1 and node.get_child(0) is Label:
		n += 1
	for child in node.get_children():
		n += _key_badge_count(child)
	return n


## Walk the HUD subtree collecting every Label (the HUD builds them under a Control root).
func _collect_labels(node: Node, out: Array[Label]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child as Label)
		_collect_labels(child, out)


# --- D-041 visual pass (composition regression guards) -----------------------
#
# These assert the COMPOSITION the visual pass introduced, because the thing that broke in
# Phase 06 was never logic — it was layout and surface pairing, which no compile/lint gate
# can see (L-021). Each one names the specific reading failure it prevents.


## A9 — the identity plaque must read as ONE unit with TWO tiers.
##
## Before D-041 the sect chip was nested in the SAME column as the character's title: two
## muted hint-sized lines stacked under the name, so "Wanderer / Outer Disciple" and "Azure
## Cloud Sect / Rank" were typographically identical and the player could not tell personal
## identity from affiliation. The fix is structural: the portrait row and the sect chip are
## SIBLINGS inside one plaque, with an ornamental divider between them.
func test_identity_plaque_separates_personal_identity_from_affiliation() -> void:
	var hud := _hud()
	var panel := _identity_plaque(hud)
	assert_true(panel != null, "the HUD builds an identity plaque holding the portrait slot")
	if panel == null:
		free_node(hud)
		return

	var body := _single_container_child(panel)
	assert_true(body is VBoxContainer,
		"the plaque stacks its tiers vertically (got %s)" % _class_of(body))
	if not (body is VBoxContainer):
		free_node(hud)
		return

	# Tier 1 = the portrait row, tier 2 = the sect chip, with the divider BETWEEN them. The
	# order matters: a divider above both, or below both, separates nothing.
	var kinds: Array[String] = []
	for child in body.get_children():
		kinds.append(_class_of(child))
	assert_eq(kinds.size(), 3,
		"the plaque has exactly three tiers: identity row, divider, sect chip (got %s)"
			% str(kinds))
	if kinds.size() == 3:
		assert_eq(kinds[0], "HBoxContainer", "tier 1 is the portrait + name/title row")
		assert_eq(kinds[1], "TextureRect", "an ornamental rule divides the two tiers")
		assert_eq(kinds[2], "HBoxContainer", "tier 2 is the sect chip")

	# And the sect chip is NOT a descendant of the name/title column any more — that nesting
	# is exactly what made the two identities blur. Identified by NODE NAME: the old marker
	# ("the only TextureRect in the plaque") stopped being valid once tier 1 gained a painted
	# portrait, which is itself a TextureRect.
	var identity_row := body.get_child(0)
	assert_null(identity_row.find_child("SectEmblem", true, false),
		"the sect emblem no longer sits inside the character's own name column")
	assert_not_null(body.get_child(2).find_child("SectEmblem", true, false),
		"it lives in tier 2, the sect chip")
	free_node(hud)


## A10 — the map plaque must be a stable framed plate, not a shrink-wrapped chip.
##
## A PanelContainer with no width floor hugs its label, so the plaque visibly resized every
## time the player walked into a map with a shorter or longer name, and a two-word place name
## read as a stray fragment rather than an authored sign.
func test_map_plaque_is_a_stable_framed_plate_with_a_width_floor() -> void:
	var hud := _hud()
	_use_language("en")
	hud.set_map_name(&"UI_MAP_HUB_NAME")
	var expected := _localized("UI_MAP_HUB_NAME")
	assert_ne(expected, "", "the hub map name key is authored (fixture precondition)")

	var panel := _panel_containing_text(hud, expected)
	assert_true(panel != null, "the map name renders inside a framed plaque")
	if panel == null:
		free_node(hud)
		return

	assert_eq(int(panel.custom_minimum_size.x), UIPalette.HUD_MAP_PANEL_WIDTH,
		"the plaque has a width FLOOR so it stops resizing per map name")
	# A floor, not a cage: a longer localized name must still be able to widen the plaque
	# (the +40% vi/en string budget), so the height is left unconstrained and the label wraps
	# nothing — asserting the floor is only on the X axis keeps that property explicit.
	assert_eq(int(panel.custom_minimum_size.y), 0,
		"the plaque constrains only its width, so a taller localized name still fits")

	var label := _label_with_text(hud, expected)
	assert_true(label != null, "the map label exists")
	if label != null:
		assert_eq(int(label.horizontal_alignment), int(HORIZONTAL_ALIGNMENT_CENTER),
			"the place name is centred in its plaque, not left-ragged in a wide frame")
	free_node(hud)


## The dividers must stretch with their plaque. A fixed-width rule would either fall short of
## the frame or overflow it the moment a longer localized string widened the panel.
func test_hud_dividers_stretch_with_their_plaque() -> void:
	var hud := _hud()
	var strips := _divider_strips(hud)
	assert_true(strips.size() >= 2,
		"both the identity plaque and the map plaque carry an ornamental rule (got %d)"
			% strips.size())
	for strip in strips:
		assert_eq(int(strip.custom_minimum_size.x), 0,
			"a divider declares no fixed width, so it adopts the plaque's width")
		assert_true((int(strip.size_flags_horizontal) & int(Control.SIZE_EXPAND)) != 0,
			"a divider expands to fill the plaque")
		assert_eq(int(strip.stretch_mode), int(TextureRect.STRETCH_SCALE),
			"the rule scales along the plaque instead of tiling or cropping")
	free_node(hud)


## A15 — screen-edge spacing comes from ONE token, so the HUD is not authored around a single
## screenshot size. Every anchored plaque is inset by exactly `HUD_MARGIN` from the edges it
## hangs off (or 0 on an axis where it is centred).
##
## It asserts the authored OFFSETS, not `position`. `Control.position` is DERIVED — anchors ×
## parent size + offsets — so for a right- or bottom-anchored plaque it reads back as an
## absolute screen coordinate once the real viewport size propagates (the first version of
## this test read 914/1086/552 on a 1152x648 CI viewport and failed). Asserting `position`
## would mean asserting the viewport size, which is precisely what A15 forbids; the offset is
## the value the code writes and the only one that encodes "18px from the edge".
func test_hud_plaques_share_one_screen_edge_margin() -> void:
	var hud := _hud()
	var root := _hud_root(hud)
	assert_true(root != null, "the HUD builds a full-rect root Control")
	if root == null:
		free_node(hud)
		return
	var anchored := 0
	for child in root.get_children():
		var control := child as Control
		if control == null or not (control is PanelContainer):
			continue
		anchored += 1
		assert_true(_is_token_inset(control.offset_top),
			"a plaque's top inset is built from layout tokens, never a literal (got %s)"
				% str(control.offset_top))
		assert_true(_is_token_inset(control.offset_left),
			"a plaque's left inset is built from layout tokens, never a literal (got %s)"
				% str(control.offset_left))
	assert_true(anchored >= 3,
		"identity / map / prompt plaques are all anchored panels (got %d)" % anchored)
	free_node(hud)


## True when an authored inset is composed from the shared layout tokens (either sign, since a
## right/bottom-anchored plaque insets negatively) rather than being a hand-typed number.
##
## A side panel is inset by `HUD_MARGIN + SIDE_PANEL_WIDTH` on the axis it is bounded along,
## so the token set is wider than the plain margin — but it is still a CLOSED set, which is
## the property worth guarding: any value outside it means somebody typed a literal.
func _is_token_inset(inset: float) -> bool:
	var allowed := [
		0.0,
		float(UIPalette.HUD_MARGIN),
		float(UIPalette.HUD_MARGIN + UIPalette.SIDE_PANEL_WIDTH),
		float(UIPalette.HUD_MARGIN + UIPalette.PROMPT_STRIP_RESERVE),
		# D-050: a side panel clears the strip the top plaque owns. Listed as a TOKEN SUM
		# rather than as a number, which is the whole point of this helper — it accepts
		# insets that are composed of layout tokens and rejects hand-typed literals.
		float(UIPalette.HUD_MARGIN + UIPalette.TOP_PLAQUE_RESERVE),
	]
	return allowed.has(absf(inset))


## The layout contract that replaced the overflowing panel: a side panel is a BOUNDED BOX
## defined by screen anchors, not a content-sized control.
##
## The old version anchored from the vertical centre and took its content's minimum size, so
## three factions of detail grew past both the top and the bottom of the viewport — and since
## a 9-slice frame is drawn at the control's edges, those edges were off-screen and the panel
## rendered with no visible plate at all. Pinning all four sides makes that unreachable.
func test_side_panels_are_bounded_boxes_not_content_sized() -> void:
	var hud := _hud()
	var root := _hud_root(hud)
	if root == null:
		free_node(hud)
		return
	var side_panels := 0
	for child in root.get_children():
		var panel := child as Control
		if panel == null or not (panel is PanelContainer):
			continue
		# A bounded side panel is the one stretched between the top and bottom anchors.
		if panel.anchor_top != 0.0 or panel.anchor_bottom != 1.0:
			continue
		side_panels += 1
		# D-050 moved this boundary deliberately: a side panel now starts below the strip the
		# top-right map/world plaque owns, because at one screen margin it sat in the SAME
		# region and the sect panel covered the place name completely (visible the first time
		# the panel was captured open). The contract is still "pinned to a screen anchor by a
		# named token", which is what this test exists to protect — only the token changed.
		assert_eq(int(panel.offset_top),
			UIPalette.HUD_MARGIN + UIPalette.TOP_PLAQUE_RESERVE,
			("a side panel starts one margin below the top edge PLUS the reserved plaque "
				+ "strip, so it cannot cover the place name (D-050)"))
		# It must STOP SHORT of the bottom, leaving the reserved prompt strip clear.
		assert_eq(int(panel.offset_bottom),
			-(UIPalette.HUD_MARGIN + UIPalette.PROMPT_STRIP_RESERVE),
			"and stops short of the bottom so the control prompts are never covered")
		# Its width is fixed by the anchors, so content can never widen it either.
		assert_eq(int(absf(panel.offset_right - panel.offset_left)),
			UIPalette.SIDE_PANEL_WIDTH,
			"its width comes from SIDE_PANEL_WIDTH, not from its content")
	assert_eq(side_panels, 3,
		"all three side panels (sect, politics, satchel) are bounded boxes (got %d)"
			% side_panels)
	free_node(hud)


## The reserved top strip must be BIG ENOUGH for the plaques it reserves for.
##
## `TOP_PLAQUE_RESERVE` existed and was consumed correctly, and the panels still covered the
## plaques — because the only assertions on it were "> 0" and "the HUD mentions the token".
## A named reserve whose VALUE nobody checks is the same defect L-028 described, one level in:
## the arithmetic is there, but one of its inputs is a guess. The capture showed the sect
## panel's top corner sitting over the map plaque's bottom edge and the politics panel sitting
## over the identity plaque's affiliation tier.
##
## It measures a POPULATED HUD, which is the part that is easy to get wrong. A hidden child
## contributes nothing to a container's minimum size, and the map plaque hides its world-time
## lines until a world-sim view arrives — so a bare HUD measures a plaque ~50px shorter than
## the one on screen, and a reserve derived from it is wrong in exactly the direction that
## causes the overlap. Every plaque is therefore filled with real content first.
##
## `get_combined_minimum_size()` rather than `size`: a top-anchored content-sized plaque IS
## its minimum size, and the minimum comes from the content without needing a real viewport,
## so this does not depend on the runner's window the way `position`/`size` would (A15 above).
func test_the_reserved_top_strip_is_tall_enough_for_the_plaques_it_reserves_for() -> void:
	var hud := _hud()
	_populate_plaques(hud)
	await scene_tree.process_frame
	var root := _hud_root(hud)
	if root == null:
		free_node(hud)
		return
	var tallest := 0.0
	var measured: Array[String] = []
	for child in root.get_children():
		var plaque := child as PanelContainer
		# A TOP plaque: anchored to the top edge and sized by its content (anchor_bottom 0).
		# This excludes the bottom prompt row and the two stretched side panels.
		if plaque == null or plaque.anchor_top != 0.0 or plaque.anchor_bottom != 0.0:
			continue
		# ...and only the ones a SIDE panel can actually reach. The side panels hug the left
		# and right edges, so a CENTRE-anchored plaque (the Phase-10 combat target) can never
		# be covered by one and must not inflate the reserve. Checked by anchor rather than by
		# name so a new edge plaque is included automatically.
		if plaque.anchor_left != 0.0 and plaque.anchor_left != 1.0:
			continue
		var height := maxf(plaque.size.y, plaque.get_combined_minimum_size().y)
		measured.append("%s=%d" % [plaque.name, int(height)])
		tallest = maxf(tallest, height)
	assert_true(measured.size() >= 2,
		"both top plaques (identity + map) were found and measured, got %s" % str(measured))
	# The reserve is measured from the plaque's own top edge, which already sits at
	# HUD_MARGIN — so the reserve covers the plaque HEIGHT, plus one margin of breathing room
	# so a panel never butts directly against the plaque's frame.
	assert_true(float(UIPalette.TOP_PLAQUE_RESERVE) >= tallest + float(UIPalette.HUD_MARGIN),
		("TOP_PLAQUE_RESERVE (%d) must clear the tallest top plaque plus one margin "
			+ "(tallest=%d + margin=%d = %d). Measured: %s") % [
				UIPalette.TOP_PLAQUE_RESERVE, int(tallest), UIPalette.HUD_MARGIN,
				int(tallest) + UIPalette.HUD_MARGIN, str(measured)])
	free_node(hud)


## Fill every top plaque with real content, so a measurement reflects the screen the player
## sees rather than a bare HUD.
##
## Goes through the HUD's PUBLIC setters — the same ones the runtimes push through — so the
## test cannot drift from how the HUD is actually fed, and never touches its private fields.
func _populate_plaques(hud: Node) -> void:
	hud.call("set_character", _player_state())
	hud.call("set_map_name", &"UI_MAP_HUB_NAME")
	# The affiliation tier is HIDDEN until a membership view arrives, and a hidden child
	# contributes nothing to a container's minimum — so without this the identity plaque
	# measures a tier short of the one on screen.
	var sect := SectMembershipView.new()
	sect.is_member = true
	sect.sect_name_key = &"SECT_AZURE_CLOUD_NAME"
	sect.rank_name_key = &"SECT_RANK_OUTER_DISCIPLE"
	sect.reputation = 45
	hud.call("set_sect_view", sect)
	# The health gauge is hidden until a value arrives (Phase 09), and a hidden child
	# contributes nothing to a container's minimum size — the SAME trap that made the first
	# two reserve values too small. Pushing a value here is what makes the measured plaque the
	# plaque on screen.
	hud.call("set_health", 100, 100)
	# The level badge and XP meter (Phase 11) are hidden until a progression view arrives —
	# the SAME hidden-child trap, one phase later. This is the third time this fixture has had
	# to grow for it (the affiliation tier, then the health gauge, now the progression row),
	# which is the argument for populating EVERY plaque through the public setters rather than
	# only the ones a given test happens to care about.
	#
	# The widest realistic numbers are used deliberately: a two-digit level and a four-digit
	# cost are what the authored curve reaches, and they are what sets the plaque's width.
	var progression := ProgressionView.new()
	progression.available = true
	progression.level = 20
	progression.xp_into_level = 5431
	progression.xp_for_next = 5925
	progression.progress = 0.92
	hud.call("set_progression_view", progression)
	# A visible combat target too. It is CENTRE-anchored so it does not affect the reserve,
	# but populating it here keeps the fixture honest about what a live HUD contains — the
	# habit that L-035 exists to enforce.
	var target := CombatTargetView.new()
	target.has_target = true
	target.name_key = &"ENEMY_MIST_WOLF_NAME"
	target.threat_key = &"THREAT_FRONTIER_LOW"
	target.current_health = 20
	target.max_health = 34
	hud.call("set_target_view", target)
	var view := WorldSimView.new()
	view.available = true
	view.year = 1
	view.season = 1
	view.day = 1
	# An event is present in any live session after the first tick, and it is the one line in
	# a top plaque that can wrap — so the measured plaque must include it, at its LONGEST.
	view.last_event_kind_key = _longest_event_kind_key()
	view.last_event_magnitude = 1
	view.last_event_tick = 1
	hud.call("set_world_sim_view", view)


## The event-kind key whose text is longest across every supported language.
##
## DERIVED, not picked: the kinds are a closed authored set, so the worst case is knowable
## instead of guessable, and a new kind (or a longer translation of an existing one) is
## included automatically. Hard-coding one kind would measure whichever one somebody happened
## to type, and a later CSV edit could quietly make a different kind the tallest.
func _longest_event_kind_key() -> StringName:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	var keys: Array = EventDataScript.KIND_NAME_KEYS
	if loc == null or keys.is_empty():
		return StringName(keys[0]) if not keys.is_empty() else &""
	var original := String(loc.call("get_language"))
	var best: StringName = StringName(keys[0])
	var best_length := -1
	for language in LocalizationScript.SUPPORTED_LANGUAGES:
		loc.call("set_language", String(language))
		for key in keys:
			var length := String(loc.call("t", String(key))).length()
			if length > best_length:
				best_length = length
				best = StringName(key)
	loc.call("set_language", original)
	return best


## The world-event hint must be CAPPED, which is what gives the map plaque a maximum height
## and therefore makes `TOP_PLAQUE_RESERVE` knowable at all. Without a cap, a longer localized
## string wraps to a third line and walks the plaque down into the side panels again.
func test_world_event_hint_is_capped_so_the_plaque_has_a_maximum_height() -> void:
	var hud := _hud()
	var label := hud.find_child("WorldEvent", true, false) as Label
	assert_not_null(label, "the map plaque carries the world-event hint")
	if label == null:
		free_node(hud)
		return
	assert_eq(label.max_lines_visible, UIPalette.HUD_WORLD_EVENT_MAX_LINES,
		"the hint wraps to at most HUD_WORLD_EVENT_MAX_LINES lines")
	assert_eq(int(label.text_overrun_behavior), int(TextServer.OVERRUN_TRIM_ELLIPSIS),
		"and trims past the cap rather than pushing the plaque into the playfield")
	assert_true(label.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"it wraps rather than widening the plaque (the cap only means anything if it wraps)")
	free_node(hud)


## Content longer than the bounded box must SCROLL inside it. Without a scroll container the
## only two outcomes are a clipped panel the player cannot read or a frame pushed off-screen —
## which is the defect this replaced.
func test_side_panels_scroll_their_content() -> void:
	var hud := _hud()
	var root := _hud_root(hud)
	if root == null:
		free_node(hud)
		return
	var scrollers := 0
	for child in root.get_children():
		var panel := child as Control
		if panel == null or not (panel is PanelContainer):
			continue
		if panel.anchor_top != 0.0 or panel.anchor_bottom != 1.0:
			continue
		var scroll := _first_scroll(panel)
		assert_true(scroll != null, "a bounded side panel holds a ScrollContainer")
		if scroll == null:
			continue
		scrollers += 1
		assert_eq(int(scroll.horizontal_scroll_mode),
			int(ScrollContainer.SCROLL_MODE_DISABLED),
			"it scrolls vertically only — a horizontal bar on a fixed-width panel is a bug")
		assert_eq(int(scroll.mouse_filter), int(Control.MOUSE_FILTER_STOP),
			"and it accepts mouse input, or the wheel passes through and clipped content "
				+ "becomes unreachable (every other node in the panel is IGNORE)")
	assert_eq(scrollers, 3, "all three side panels scroll (got %d)" % scrollers)
	free_node(hud)


func _first_scroll(node: Node) -> ScrollContainer:
	for child in node.get_children():
		var found := child as ScrollContainer
		if found != null:
			return found
		var deeper := _first_scroll(child)
		if deeper != null:
			return deeper
	return null


## A8/A17 — the HUD must show a gauge for EXACTLY the stats a system owns, and no others.
##
## This rule has not been relaxed, it has been APPLIED, three times now: until Phase 09
## nothing in a running session owned health, so the correct number of gauges was zero; combat
## owning health made it one, and the combat target made it two; Phase 11 gives XP a real
## owner (`ProgressionRuntime` + the authoritative `CharacterState.xp`), so the correct number
## was THREE; Phase 12 gives realm progress a real owner (`CultivationRuntime` + the
## authoritative `CharacterState.cultivation_progress`), so it is now FOUR. Mana is still owned
## by nobody until P15 — which gives linh khí its owner (`SkillRuntime`), making it FIVE.
##
## The number is not the point — the pairing is. Each gauge is named, so swapping one for a
## mana bar fails even though the count would still be right.
func test_hud_shows_a_gauge_for_exactly_the_stats_a_system_owns() -> void:
	var hud := _hud()
	assert_eq(_count_class(hud, "ProgressBar"), 5,
		("exactly FIVE gauges — the player's health, the combat target's health, the "
			+ "player's XP meter, the tu vi meter and the linh khí bar (Phase 15, owned by "
			+ "SkillRuntime). A sixth means a bar was added for a stat no system backs yet"))
	assert_false(hud.call("is_cultivation_visible"),
		"the tu vi meter stays hidden until a cultivation view arrives")
	assert_eq(_count_class(hud, "TextureProgressBar"), 0,
		"and no textured gauge for an unbound stat")

	# All three are hidden until a value is pushed: a full bar for health nothing has reported
	# is the same lie as a bar for a system that does not exist.
	assert_false(hud.call("is_health_gauge_visible"),
		"the player gauge stays hidden until the session reports a health value")
	assert_false(hud.call("is_target_panel_visible"),
		"and the target plaque stays hidden until there is something to fight")
	assert_false(hud.call("is_progression_visible"),
		"and the level/XP row stays hidden until a progression session reports a view — "
		+ "`Cấp 0` for progression nothing owns is the same lie one phase later")

	hud.call("set_health", 42, 60)
	assert_true(hud.call("is_health_gauge_visible"), "pushing a value reveals the player gauge")

	# The NUMBER is written, not only drawn — colour is never the only carrier (UI bible §4),
	# and at low values the bar is too short to read at all.
	assert_true("42 / 60" in _all_label_text(hud),
		"the gauge writes its value as text, not only as a bar length")

	# A non-positive maximum is "nothing reported", not "dead at 0 HP": rendering those the
	# same way would make a wiring failure look like a death.
	hud.call("set_health", 0, 0)
	assert_false(hud.call("is_health_gauge_visible"),
		"a zero maximum hides the gauge rather than showing an empty one")

	# The XP meter obeys the same contract, through its own view's `available` flag.
	var progression := ProgressionView.new()
	progression.available = true
	progression.level = 3
	progression.xp_into_level = 20
	progression.xp_for_next = 45
	progression.progress = 0.44
	hud.call("set_progression_view", progression)
	assert_true(hud.call("is_progression_visible"), "pushing a view reveals the level/XP row")
	hud.call("set_progression_view", ProgressionView.make_empty())
	assert_false(hud.call("is_progression_visible"),
		"and an unavailable view hides it again rather than blanking it")
	free_node(hud)


## The target plaque RETIRES after a kill instead of advertising a corpse forever.
##
## Phase 10 shipped the plaque documented as showing a dead target "briefly" while nothing
## implemented a timeout at all, so it sat on "0 / 34" until the next fight — a comment
## contradicting its own code, which L-014 calls a bug. The retirement is asserted through the
## timer's OWN `timeout` signal rather than by waiting 2.5 real seconds: emitting the node's
## real signal runs the real handler, which is the documented substitution for an
## engine-internal clock in a headless test (L-016).
func test_the_target_plaque_retires_after_a_kill_instead_of_advertising_a_corpse() -> void:
	var hud := _hud()
	var linger := hud.find_child("TargetLinger", true, false) as Timer
	assert_not_null(linger, "the HUD owns a one-shot timer for retiring the plaque")
	assert_true(linger.one_shot,
		"one-shot: a repeating timer would keep hiding a plaque that is back on screen")

	# A LIVE target: shown, and nothing is counting down. A fight that drags on must not time
	# the plaque out from under the player.
	var live := CombatTargetView.new()
	live.has_target = true
	live.name_key = &"ENEMY_MIST_WOLF_NAME"
	live.threat_key = &"THREAT_FRONTIER_LOW"
	live.current_health = 20
	live.max_health = 34
	hud.call("set_target_view", live)
	assert_true(hud.call("is_target_panel_visible"), "a live target is shown")
	assert_true(linger.is_stopped(), "and nothing is counting down while it is alive")

	# DEAD: still shown — the name of what you just killed is wanted at exactly the moment it
	# would otherwise vanish — but now on a clock.
	var dead := CombatTargetView.new()
	dead.has_target = true
	dead.name_key = &"ENEMY_MIST_WOLF_NAME"
	dead.threat_key = &"THREAT_FRONTIER_LOW"
	dead.current_health = 0
	dead.max_health = 34
	dead.is_dead = true
	hud.call("set_target_view", dead)
	assert_true(hud.call("is_target_panel_visible"),
		"the kill is still on screen, so the player can read what they killed")
	assert_false(linger.is_stopped(), "and the retirement clock is running")
	assert_true(is_equal_approx(linger.wait_time, UIPalette.TARGET_PLAQUE_LINGER),
		"for the authored linger (%.2fs, expected %.2fs)"
			% [linger.wait_time, UIPalette.TARGET_PLAQUE_LINGER])

	linger.timeout.emit()
	assert_false(hud.call("is_target_panel_visible"),
		"once the linger elapses the plaque goes, rather than advertising a corpse forever")

	# A SECOND creature taking the player's attention cancels the retirement outright.
	hud.call("set_target_view", dead)
	hud.call("set_target_view", live)
	assert_true(hud.call("is_target_panel_visible"), "the new target is shown")
	assert_true(linger.is_stopped(),
		"and the dead one's countdown was cancelled, not left to hide a live target")
	free_node(hud)


## A meter that writes its value INSIDE itself must be tall enough to CONTAIN the glyphs.
##
## Found by opening a capture at 4x: the XP meter is `XP_METER_HEIGHT` (8px) tall and carries a
## `FONT_SIZE_HINT` (14px) label, so "KN 0 / 20" rendered with its descenders across the rail's
## bottom border — the number and the frame drawn on top of each other. The height was chosen
## to make the meter visibly subordinate to the health gauge, which is right, but nobody
## checked it against the label it has to hold (L-034: a named size nobody measured).
##
## Asserted for EVERY meter in the HUD, re-measured from the real label, so the next meter
## (mana, cultivation, a boss bar) cannot repeat it.
func test_every_meter_is_tall_enough_for_the_value_it_writes_inside_itself() -> void:
	var hud := _hud()
	hud.call("set_health", 100, 100)
	_populate_plaques(hud)
	_use_language("vi")
	await scene_tree.process_frame

	var meters: Array[ProgressBar] = []
	_collect_class(hud, "ProgressBar", meters)
	assert_true(meters.size() >= 2, "the HUD has meters to check (got %d)" % meters.size())
	for meter in meters:
		var value := meter.get_node_or_null("Value") as Label
		if value == null:
			continue
		var needed := value.get_combined_minimum_size().y
		assert_true(meter.custom_minimum_size.y >= needed,
			("meter '%s' is %dpx tall but the value it prints inside itself needs %dpx — the "
				+ "glyphs draw across its own frame") % [
					meter.name, int(meter.custom_minimum_size.y), int(needed)])
	free_node(hud)


func _collect_class(node: Node, class_label: String, out: Array[ProgressBar]) -> void:
	for child in node.get_children():
		if child.get_class() == class_label:
			out.append(child as ProgressBar)
		_collect_class(child, class_label, out)


## The visual pass must not have cost any behaviour: the character name, the map name, the
## prompts and the closed-by-default sect panel all still work (a pure presentation change).
func test_hud_behaviour_survived_the_visual_pass() -> void:
	var hud := _hud()
	_use_language("en")
	hud.set_character(_player_state())
	hud.set_map_name(&"UI_MAP_HUB_NAME")
	hud.set_interact_available(true)
	hud.set_cultivation_view(_cultivation_at_site())

	var all_text := _all_label_text(hud)
	assert_true("Wanderer" in all_text, "the character name still renders")
	assert_true(_localized("UI_MAP_HUB_NAME") in all_text, "the map name still renders")
	assert_true("E" in all_text, "the interact key badge still renders")
	assert_false(hud.call("is_sect_panel_open"),
		"the sect detail panel is still closed until the player opens it")
	free_node(hud)


# --- helpers for the composition guards --------------------------------------

func _use_language(code: String) -> void:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", code)


func _localized(key: String) -> String:
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if loc == null:
		return ""
	return String(loc.call("t", key))


func _class_of(node: Node) -> String:
	return "<null>" if node == null else node.get_class()


## The HUD's single full-rect root Control (it is a CanvasLayer, so the theme lives there).
func _hud_root(hud: Node) -> Control:
	for child in hud.get_children():
		if child is Control:
			return child as Control
	return null


## The identity plaque: the only HUD panel that holds the portrait NinePatchRect.
func _identity_plaque(hud: Node) -> PanelContainer:
	var root := _hud_root(hud)
	if root == null:
		return null
	# By NAME: the portrait slot's old marker (a NinePatch frame over a painted crop) went
	# away with the medallion (D-062), and a structural marker that changes with the art is
	# exactly the kind that silently stops finding anything.
	var panel := root.get_node_or_null("IdentityPlaque") as PanelContainer
	if panel != null and panel.find_child("Portrait", true, false) != null:
		return panel
	return null


## The top-level plaque whose subtree renders `text`.
func _panel_containing_text(hud: Node, text: String) -> PanelContainer:
	var root := _hud_root(hud)
	if root == null or text == "":
		return null
	for child in root.get_children():
		var panel := child as PanelContainer
		if panel != null and _contains_text(panel, text):
			return panel
	return null


func _contains_text(node: Node, text: String) -> bool:
	if text == "":
		return false
	for t in _all_label_text(node):
		if String(t) == text:
			return true
	return false


func _label_with_text(node: Node, text: String) -> Label:
	var labels: Array[Label] = []
	_collect_labels(node, labels)
	for label in labels:
		if label.text == text:
			return label
	return null


## A container's only child, or null when it has a different shape than expected.
func _single_container_child(node: Node) -> Node:
	return node.get_child(0) if node.get_child_count() == 1 else null


## Every ornamental divider strip: a TextureRect wearing the shared ornament rule.
##
## Matched by TEXTURE, not by node name: the name is cosmetic, the texture is the design
## decision. It tracks `UIPalette.TEX_ORNAMENT_DIVIDER` (the tintable mask the HUD moved to in
## D-050) rather than the retired jade `title_divider.png`, so this helper keeps measuring the
## rule the HUD actually builds instead of silently finding zero strips.
func _divider_strips(node: Node) -> Array[TextureRect]:
	var out: Array[TextureRect] = []
	_collect_divider_strips(node, out)
	return out


func _collect_divider_strips(node: Node, out: Array[TextureRect]) -> void:
	for child in node.get_children():
		var rect := child as TextureRect
		if rect != null and rect.texture != null \
				and rect.texture.resource_path == UIPalette.TEX_ORNAMENT_DIVIDER:
			out.append(rect)
		_collect_divider_strips(child, out)


func _count_class(node: Node, class_label: String) -> int:
	var n := 0
	for child in node.get_children():
		if child.get_class() == class_label:
			n += 1
		n += _count_class(child, class_label)
	return n


# === Attack discoverability (D-055-G) =======================================
#
# Phase 11 shipped a complete combat→XP→level loop in which the ATTACK was the one verb with
# no cue on screen. `T Sect`, `Y Politics` and `Esc Menu` were all advertised; the action that
# kills creatures and earns every point of XP was not. No test could see it, because every
# test and the whole playtest harness already KNOW the semantic action name and feed it
# directly — none of them ever asks "how would a player find out?". That is L-029's shape: a
# pipeline that is correct end to end and unreachable by the person it is for.


## The prompt exists, is named, and is built from the SHARED row component.
##
## The component matters as much as the presence: a hand-rolled badge+label inside the HUD
## would be the duplication `UIPromptRow` exists to prevent, and it would drift from the other
## four prompts the first time the badge style changed (the D-050 divider lesson).
func test_the_hud_advertises_the_basic_attack_through_the_shared_prompt_row() -> void:
	var hud := _hud()
	var row := hud.find_child("AttackPrompt", true, false)
	assert_not_null(row, "the HUD builds a named attack prompt")
	if row == null:
		free_node(hud)
		return
	assert_true(row is UIPromptRow,
		("the attack prompt IS a UIPromptRow, so it inherits the badge+label treatment "
			+ "instead of re-inventing it (got %s)") % _class_of(row))
	assert_true(row.visible,
		("the attack prompt is visible with no setup at all — the player is armed for the "
			+ "whole session, so there is no state in which this cue would be a lie, and a "
			+ "player who has never attacked cannot be taught the verb by a cue that only "
			+ "appears once an enemy is already on them"))
	free_node(hud)


## The glyph comes from the SEMANTIC action via InputService, not from a literal.
##
## Asserted by COMPARING against what the service reports for `attack` rather than against the
## letter "J": the point of the seam is that a rebind moves the prompt with it, and a test that
## hard-coded the current key would have to be edited by the same rebind — which is how a
## binding and its documentation drift apart (L-014).
##
## READ FROM INSIDE THE `AttackPrompt` SUBTREE. The first version asked whether the expected
## glyph appeared anywhere in `_all_label_text(hud)`, which is a weaker claim than it looks: the
## HUD renders five badges, so "the glyph is somewhere on screen" is satisfied by the MENU
## badge if the two actions ever share a letter, and it would stay green with the attack row's
## own badge blank. The row's own badge is the thing being claimed.
func test_the_attack_prompt_key_is_resolved_from_the_input_service() -> void:
	var hud := _hud()
	_use_language("en")
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	assert_not_null(input, "the InputService autoload is live in the runner")
	var row := hud.find_child("AttackPrompt", true, false) as UIPromptRow
	assert_not_null(row, "the attack prompt row is found by name")
	if input == null or row == null:
		free_node(hud)
		return
	var expected := String(input.call("get_action_display_label", &"attack"))
	assert_ne(expected, "", "the service resolves a display label for `attack`")
	assert_eq(_row_key_text(row), expected,
		("the badge INSIDE AttackPrompt carries the glyph InputService resolves for the "
			+ "`attack` action (expected '%s', row shows '%s')")
			% [expected, _row_key_text(row)])

	# Whole-HUD claim, which is genuinely about the whole HUD: no raw vocabulary anywhere.
	for t in _all_label_text(hud):
		assert_false(String(t).contains("attack"),
			"the raw semantic action name never reaches the screen (%s)" % t)
		assert_false(String(t).contains("74"),
			"nor the raw physical keycode (%s)" % t)
	free_node(hud)


## The action word is localized in BOTH languages, read from the attack row itself.
func test_the_attack_prompt_action_word_is_localized() -> void:
	var hud := _hud()
	var row := hud.find_child("AttackPrompt", true, false) as UIPromptRow
	assert_not_null(row, "the attack prompt row is found by name")
	if row == null:
		free_node(hud)
		return
	for language in ["vi", "en"]:
		_use_language(language)
		var expected := _localized("UI_HUD_ATTACK_ACTION")
		assert_ne(expected, "UI_HUD_ATTACK_ACTION",
			"the %s value is authored, not a fallback to the key" % language)
		assert_ne(expected, "", "and it is not empty in %s" % language)
		assert_eq(_row_action_text(row), expected,
			("the label INSIDE AttackPrompt is the localized attack word in %s (expected "
				+ "'%s', row shows '%s')") % [language, expected, _row_action_text(row)])
	_use_language("en")
	free_node(hud)


## NO OTHER ROW can satisfy the attack assertions.
##
## The reason the two tests above were weak is that four sibling rows render the same KIND of
## content, so any whole-HUD text search is ambiguous by construction. This pins the ambiguity
## shut from the other side: exactly ONE of the five rows carries the attack word, it is the one
## named `AttackPrompt`, and its badge is not simply whatever the neighbouring row shows.
func test_only_the_attack_row_carries_the_attack_prompt() -> void:
	var hud := _hud()
	_use_language("en")
	hud.call("set_interact_available", true)
	hud.call("set_cultivation_view", _cultivation_at_site())
	hud.call("set_skill_view", _skills_learned())
	var strip := hud.find_child("PromptStrip", true, false) as Control
	assert_not_null(strip, "the prompt strip is found")
	if strip == null:
		free_node(hud)
		return
	var rows := _prompt_rows(strip)
	assert_eq(rows.size(), 6, "all six prompts are present")

	var attack_word := _localized("UI_HUD_ATTACK_ACTION")
	var carriers: Array[String] = []
	for row in rows:
		if _row_action_text(row) == attack_word:
			carriers.append(row.name)
	assert_eq(carriers.size(), 1,
		("exactly one row advertises the attack (found %s) — otherwise a whole-HUD text "
			+ "search cannot tell which row it read") % str(carriers))
	if carriers.size() == 1:
		assert_eq(carriers[0], "AttackPrompt",
			"and it is the row named AttackPrompt, not a neighbour that happens to match")

	# Each row's action word is distinct, so none of the five can stand in for another. (The
	# BADGES are not required to differ — two actions could legitimately share a glyph — which
	# is exactly why the action word is the discriminator here.)
	var words := {}
	for row in rows:
		if not row.visible:
			continue  # a CONTEXTUAL prompt with nothing to offer here says nothing (Phase 12)
		var word := _row_action_text(row)
		assert_ne(word, "", "row '%s' renders an action word" % row.name)
		assert_false(words.has(word),
			"row '%s' duplicates the action word '%s'" % [row.name, word])
		words[word] = true
	free_node(hud)


## The key glyph rendered INSIDE a prompt row: the Label owned by the row's `UIKeyBadge`.
##
## Walks the row rather than indexing its children, so a layout tweak that reorders badge and
## label does not quietly make this read the wrong one.
func _row_key_text(row: Control) -> String:
	for child in row.get_children():
		var badge := child as UIKeyBadge
		if badge == null:
			continue
		for inner in badge.get_children():
			var label := inner as Label
			if label != null:
				return label.text
	return ""


## The action word rendered inside a prompt row: the row's OWN direct Label (the badge's label
## is nested one level deeper, so these two helpers cannot return the same node).
func _row_action_text(row: Control) -> String:
	for child in row.get_children():
		var label := child as Label
		if label != null:
			return label.text
	return ""


## STRUCTURAL: no presentation file may author a physical key for a prompt.
##
## WALKED, not listed (L-034). The rule being defended is the direction of the seam —
## `semantic action -> InputService display label -> HUD`, never `HUD -> physical key`. A
## literal is the cheap wrong thing to reach for when a prompt "just needs to say J", and it
## breaks silently on the first rebind rather than loudly.
##
## Comments are stripped, so a file may still explain the rule (this project documents its
## mistakes next to the code that made them).
func test_no_presentation_file_hard_codes_a_physical_key_for_a_prompt() -> void:
	var offenders: Array[String] = []
	_scan_for_literal_keys("res://src/presentation", offenders)
	assert_true(offenders.is_empty(),
		("a prompt's key glyph must come from InputService.get_action_display_label, so a "
			+ "rebind moves the prompt with it. These files author a literal instead: %s")
			% str(offenders))


func _scan_for_literal_keys(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_scan_for_literal_keys(full, offenders)
		elif entry.ends_with(".gd"):
			var file := FileAccess.open(full, FileAccess.READ)
			if file != null:
				var source := file.get_as_text()
				file.close()
				if _authors_a_literal_key(source):
					offenders.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()


## Does this source pass a hard-coded key glyph into a prompt row?
##
## Matches `set_prompt("<literal>"` — the one call that puts a glyph on screen. A literal
## there is the defect; a variable (`set_prompt(attack_key, ...)`) is the correct seam.
func _authors_a_literal_key(source: String) -> bool:
	var re := RegEx.new()
	re.compile("set_prompt\\(\\s*\"")
	for raw_line in source.split("\n"):
		var line: String = raw_line
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		if re.search(line) != null:
			return true
	return false


# === The reserved BOTTOM strip (D-055 §6) ===================================

## `PROMPT_STRIP_RESERVE` is re-measured against the POPULATED strip.
##
## L-034's rule is "a reserve constant must be derived from a MEASUREMENT of the thing it
## reserves for, and a test must re-measure it". That was applied to `TOP_PLAQUE_RESERVE` and
## never to this one — so the bottom reserve was a number nobody had checked for four phases,
## and D-055 adds a FIFTH prompt to the strip it protects. Two things are therefore asserted:
##
##   1. HEIGHT — the strip must fit inside the band the side panels and the level-up banner
##      both stop short of. The rows sit in an HBox, so a new prompt should not change the
##      height at all; "should not" is exactly the kind of claim that is worth measuring once
##      rather than assuming forever.
##   2. WIDTH — this is the NEW risk the attack prompt introduces. The strip is anchored
##      bottom-LEFT and grows RIGHT, while the level-up announcement is bottom-CENTRE. Enough
##      prompts and the two bottom-edge elements meet. Asserting the strip stays within the
##      left half means the collision is arithmetic rather than something to notice in a
##      screenshot later.
##
## Measured with `get_combined_minimum_size()` (A15): `size` would depend on the runner's
## window, and the minimum is what the content actually demands.
func test_the_reserved_bottom_strip_fits_the_prompts_it_reserves_for() -> void:
	var hud := _hud()
	# Every prompt visible at once: interact is contextual, so without this the strip measures
	# one row short of its widest real state — the hidden-child trap that made the TOP reserve
	# wrong three times (L-035).
	hud.call("set_interact_available", true)
	hud.call("set_cultivation_view", _cultivation_at_site())
	hud.call("set_skill_view", _skills_learned())
	# The LONGEST authored language, derived rather than guessed: vi is longer than en for
	# every one of these words, and a reserve measured on the shorter one is wrong by exactly
	# the amount that matters.
	_use_language("vi")
	await scene_tree.process_frame

	var strip := hud.find_child("PromptStrip", true, false) as Control
	assert_not_null(strip, "the prompt strip is found by name")
	if strip == null:
		free_node(hud)
		return

	var needed := strip.get_combined_minimum_size()
	assert_true(float(UIPalette.PROMPT_STRIP_RESERVE) >= needed.y,
		("PROMPT_STRIP_RESERVE (%d) must cover the populated strip's height (%d). The side "
			+ "panels and the level-up banner both inset by this token, so a strip taller "
			+ "than the reserve is covered by them.")
			% [UIPalette.PROMPT_STRIP_RESERVE, int(needed.y)])
	# ...and must not be far LARGER than it (D-057). A reserve that protects nothing is dead
	# playfield the side panels and the banner are kept out of: when the prompts left their
	# framed plaque the old 78 reserved 32px for nothing. Derived as the strip plus one margin,
	# like TOP_PLAQUE_RESERVE; SPACE_SM of slack absorbs a font metric, not a design decision.
	var ceiling := needed.y + float(UIPalette.HUD_MARGIN + UIPalette.SPACE_SM)
	assert_true(float(UIPalette.PROMPT_STRIP_RESERVE) <= ceiling,
		("PROMPT_STRIP_RESERVE (%d) is the strip (%d) plus one HUD_MARGIN (%d), not more — "
			+ "anything above %d reserves playfield for nothing")
			% [UIPalette.PROMPT_STRIP_RESERVE, int(needed.y), UIPalette.HUD_MARGIN,
				int(ceiling)])

	# The banner is centred, so the strip may occupy the left half and no more.
	#
	# The bound is the project's AUTHORED viewport width, read from ProjectSettings rather
	# than written here as a number. That is not "authoring around one screenshot size"
	# (A15): under `canvas_items` + `expand` the layout viewport never gets NARROWER than the
	# authored width — a wider window scales up, a taller one grows vertically — so the
	# authored width is the worst case for a horizontal overlap, and it is the one value that
	# cannot drift from the setting that actually governs it.
	var authored_width := float(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	assert_true(needed.x < authored_width * 0.5,
		("the populated prompt strip (%dpx wide) must stay inside the left half of the "
			+ "authored viewport (%d), because it is anchored bottom-LEFT and grows RIGHT "
			+ "while the level-up announcement is bottom-CENTRE — the two bottom-edge "
			+ "elements would otherwise meet once enough prompts exist")
			% [int(needed.x), int(authored_width)])

	# And the strip really does carry all five prompts, or the measurement above is of a
	# smaller thing than the player sees.
	assert_eq(_prompt_rows(strip).size(), 6,
		"all six prompts (attack, interact, cultivate, sect, politics, menu) were measured")
	free_node(hud)


func _prompt_rows(node: Node) -> Array[UIPromptRow]:
	var out: Array[UIPromptRow] = []
	_collect_prompt_rows(node, out)
	return out


func _collect_prompt_rows(node: Node, out: Array[UIPromptRow]) -> void:
	for child in node.get_children():
		var row := child as UIPromptRow
		if row != null:
			out.append(row)
		else:
			# A prompt row's own children are a badge + a label, never another row.
			_collect_prompt_rows(child, out)


# === D-057: HUD composition =================================================================


## A desktop HUD is never inset by the OS work area (D-057).
##
## `get_display_safe_area()` on a desktop is the WORK AREA — the screen minus docks, panels and
## taskbars, in SCREEN coordinates. Treated as a notch, it pushed the whole HUD by the size of
## the OS chrome wherever the window was. These are the MEASURED dev-machine numbers: a GNOME
## dock (66px) and top bar (32px), with the game window wholly inside the work area — which put
## the left plaques 85px from the window edge and the right ones 18px.
func test_the_desktop_hud_is_never_inset_by_the_os_work_area() -> void:
	var canvas := Vector2(1280, 720)
	var dev_machine_work_area := Rect2i(66, 32, 1854, 1048)
	var window_inside_it := Rect2i(353, 196, 1280, 720)
	assert_eq(GameplayHUD.safe_area_insets(false, window_inside_it, dev_machine_work_area,
			canvas), Vector4.ZERO,
		"a windowed desktop game is not inset by a dock and a top bar it does not overlap")
	# Full screen over a Windows taskbar: the taskbar is hidden, the work area still excludes
	# it, and the old arithmetic lifted the prompt strip by its 48px.
	assert_eq(GameplayHUD.safe_area_insets(false, Rect2i(0, 0, 1920, 1080),
			Rect2i(0, 0, 1920, 1032), canvas), Vector4.ZERO,
		"nor is a full-screen desktop game inset by a taskbar it covers")
	# And the HUD actually built in this (desktop) runner carries no inset at all.
	var hud := _hud()
	var root := _hud_root(hud)
	assert_not_null(root, "the HUD builds its root Control")
	if root != null:
		assert_eq(Vector4(root.offset_left, root.offset_top, root.offset_right,
				root.offset_bottom), Vector4.ZERO,
			"the live desktop HUD root is the full viewport, framed only by HUD_MARGIN")
	free_node(hud)


## On mobile the inset is the part of the WINDOW a notch covers, in CANVAS units (D-057).
func test_a_mobile_notch_insets_only_the_window_edge_it_covers() -> void:
	# Landscape phone: a 90px notch on the left of a 2400x1080 screen, the window full-screen,
	# a 1280x576 canvas — so one screen pixel is 1280/2400 of a canvas pixel.
	var screen := Rect2i(0, 0, 2400, 1080)
	var insets := GameplayHUD.safe_area_insets(true, screen, Rect2i(90, 0, 2310, 1080),
		Vector2(1280, 576))
	assert_true(is_equal_approx(insets.x, 90.0 * 1280.0 / 2400.0),
		"the notch edge is inset by the notch, converted to canvas units (got %.2f)" % insets.x)
	assert_eq(Vector3(insets.y, insets.z, insets.w), Vector3.ZERO,
		"and the three uncovered edges are not inset at all")
	# Split screen: the app owns the LOWER half of a portrait phone whose notch is at the top
	# of the screen. The notch is outside this window, so nothing is covered.
	assert_eq(GameplayHUD.safe_area_insets(true, Rect2i(0, 1200, 1080, 1200),
			Rect2i(0, 80, 1080, 2320), Vector2(1280, 1422)), Vector4.ZERO,
		"a notch outside the window covers nothing in it")
	# A display that reports nothing usable is not an excuse to inset by garbage.
	assert_eq(GameplayHUD.safe_area_insets(true, screen, Rect2i(), Vector2(1280, 576)),
		Vector4.ZERO, "an empty safe area produces no inset")


## The weight ladder (D-057): framed plaques for what the player TRACKS, a quiet band for hints.
##
## Ornament is how this UI says "this matters". The prompt strip used to wear the same
## gold-cornered plaque as the identity and the place name, which spent that signal on the least
## important text on screen and made the HUD read as four boxes rather than a frame around the
## game.
func test_the_prompt_strip_sits_on_a_quiet_band_and_the_tracked_plaques_stay_framed() -> void:
	var hud := _hud()
	var strip := hud.find_child("PromptStrip", true, false) as Control
	assert_not_null(strip, "the prompt strip is found by name")
	if strip != null:
		var band := strip.get_theme_stylebox("panel")
		var plaque := UITheme.panel_stylebox()
		if band is StyleBoxTexture and plaque is StyleBoxTexture:
			assert_ne((band as StyleBoxTexture).texture.resource_path,
				(plaque as StyleBoxTexture).texture.resource_path,
				"the prompts sit on the quiet band, never on the framed plaque")
			assert_eq((band as StyleBoxTexture).texture.resource_path, UIPalette.TEX_BAND_RIGHT,
				"the band that fades toward the playfield from the left edge")
		var probe := _band_probe()
		assert_true(probe.a < 1.0,
			"and the band is translucent, so the world shows through a passive hint")
	if UITheme.textures_present():
		for plaque_name in ["IdentityPlaque", "MapPlaque", "TargetPlaque"]:
			var plaque := hud.find_child(plaque_name, true, false) as Control
			assert_not_null(plaque, "%s is found by name" % plaque_name)
			if plaque != null:
				assert_true(plaque.get_theme_stylebox("panel") is StyleBoxTexture,
					"%s keeps the framed 9-slice plaque — it is what the player tracks"
						% plaque_name)
	free_node(hud)


## The hint band is a LEGAL text surface over ANY background (D-057, re-pinned D-062).
##
## The prompts are the light-only text palette, so what shows through the band must still
## measure as a dark surface. MEASURED on the kit's band where the text sits (the solid run),
## composited over pure white — the worst thing any floor, prop or sprite could put behind it —
## it must stay under the brightness limit the whole UI uses.
func test_the_hint_band_is_a_legal_text_surface_over_any_background() -> void:
	var fill := _band_probe()
	var over_white := fill.lerp(Color(1.0, 1.0, 1.0, 1.0), 1.0 - fill.a)
	var brightness: float = 255.0 * (0.299 * over_white.r + 0.587 * over_white.g
		+ 0.114 * over_white.b)
	assert_true(brightness < UIPalette.SURFACE_LIGHT_BRIGHTNESS_LIMIT,
		("the band over pure white measures %.0f, under the %d limit for a surface carrying "
			+ "light text — so the prompts are legible over anything the world can show")
			% [brightness, UIPalette.SURFACE_LIGHT_BRIGHTNESS_LIMIT])
	assert_true(fill.a < 1.0,
		"and it is still translucent: an opaque band is just a frameless box (alpha %.2f)"
			% fill.a)


## The band's colour where the prompts sit: the middle of its SOLID run (the fade is where it
## hands back to the world, and no text is placed there).
func _band_probe() -> Color:
	var texture := load(UIPalette.TEX_BAND_RIGHT) as Texture2D
	if texture == null:
		return Color(0, 0, 0, 1)
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image.get_pixel(UIPalette.BAND_SOLID_MARGIN + UIPalette.SPACE_MD,
		image.get_height() / 2)


## A defeated target's plaque states the outcome instead of keeping an empty row (D-057).
##
## The second row describes the target's CONDITION. It used to be blanked on a kill, leaving a
## gap between the name and the gauge for the whole linger — an empty row in every kill capture.
func test_a_defeated_target_says_so_instead_of_leaving_an_empty_row() -> void:
	var hud := _hud()
	var row := hud.find_child("TargetThreat", true, false) as Label
	assert_not_null(row, "the target's condition row is found by name")
	if row == null:
		free_node(hud)
		return
	var target := CombatTargetView.new()
	target.has_target = true
	target.name_key = &"ENEMY_MIST_WOLF_NAME"
	target.threat_key = &"THREAT_FRONTIER_LOW"
	target.current_health = 20
	target.max_health = 34
	hud.call("set_target_view", target)
	assert_eq(row.text, _localized("THREAT_FRONTIER_LOW"), "alive, the row is the threat rating")
	target.current_health = 0
	target.is_dead = true
	hud.call("set_target_view", target)
	assert_true(row.visible and row.text == _localized("UI_HUD_TARGET_DEFEATED"),
		"defeated, the row says so (got visible=%s text='%s')" % [row.visible, row.text])
	assert_ne(row.text, "", "and is never left as an empty row")
	# A live target with no authored rating has no condition to state: no row, not a blank one.
	var unrated := CombatTargetView.new()
	unrated.has_target = true
	unrated.name_key = &"ENEMY_MIST_WOLF_NAME"
	unrated.current_health = 5
	unrated.max_health = 34
	hud.call("set_target_view", unrated)
	assert_false(row.visible, "an unrated live target hides the row instead of blanking it")
	free_node(hud)


## Negative space, enforced (D-057): the HUD keeps the playfield centre clear, and the
## PERMANENT HUD stays inside its area budget, at both authored aspect ratios.
##
## Rects are computed from each element's anchors, offsets, minimum size and grow direction —
## the arithmetic Godot's layout uses — rather than read from the runner's window, so the
## assertion is about the HUD at a NAMED resolution (A15). Elements are found by WALKING the
## HUD root, never by a list of names (UI_UX_BIBLE §3b): a new plaque is measured automatically.
func test_the_hud_keeps_the_playfield_centre_clear_and_inside_its_area_budget() -> void:
	var hud := _hud()
	var original := String(scene_tree.root.get_node("Localization").call("get_language"))
	_use_language("vi")  # the longer language sizes every plaque
	_populate_plaques(hud)
	hud.call("set_interact_available", true)
	hud.call("set_cultivation_view", _cultivation_at_site())
	hud.call("set_skill_view", _skills_learned())
	hud.call("set_target_view", null)  # permanent HUD first: no fight in progress
	await scene_tree.process_frame
	var root := _hud_root(hud)
	if root == null:
		free_node(hud)
		_use_language(original)
		return
	for viewport: Vector2 in [Vector2(1280, 720), Vector2(1280, 800)]:
		var permanent := _visible_hud_rects(root, viewport)
		assert_true(permanent.size() >= 3,
			"the permanent identity, map and prompt elements were measured at %s (got %d)"
				% [str(viewport), permanent.size()])
		var area := 0.0
		for entry: Dictionary in permanent:
			var rect: Rect2 = entry["rect"]
			area += rect.get_area()
		var share := area / (viewport.x * viewport.y)
		assert_true(share <= UIPalette.HUD_PERMANENT_AREA_BUDGET,
			("at %s the permanent HUD covers %.1f%% of the screen, over its %.0f%% budget: "
				+ "%s") % [str(viewport), share * 100.0,
					UIPalette.HUD_PERMANENT_AREA_BUDGET * 100.0, _describe(permanent)])
	# Now the contextual surfaces too: a live target and a level-up announcement.
	var target := CombatTargetView.new()
	target.has_target = true
	target.name_key = &"ENEMY_MIST_WOLF_NAME"
	target.threat_key = &"THREAT_FRONTIER_LOW"
	target.current_health = 20
	target.max_health = 34
	hud.call("set_target_view", target)
	hud.call("celebrate_level_up", 20)
	await scene_tree.process_frame
	for viewport: Vector2 in [Vector2(1280, 720), Vector2(1280, 800)]:
		var everything := _visible_hud_rects(root, viewport)
		assert_true(everything.size() >= 5,
			"the target plaque and the level-up banner were measured too (got %d)"
				% everything.size())
		var zone := UIPalette.PLAYFIELD_CLEAR_ZONE
		var centre := Rect2(zone.position * viewport, zone.size * viewport)
		for entry: Dictionary in everything:
			var rect: Rect2 = entry["rect"]
			assert_false(rect.intersects(centre),
				("at %s, %s %s enters the playfield centre %s — the camera keeps the player "
					+ "there, so the HUD must not") % [str(viewport), entry["name"],
						str(rect), str(centre)])
	hud.call("level_up_feedback").call("cancel")
	free_node(hud)
	_use_language(original)


## Every VISIBLE direct child of the HUD root except an open side panel, with its rect in a
## viewport of the given size. Side panels are excluded by design: the player opens them on
## purpose, as a decision to read instead of play.
func _visible_hud_rects(root: Control, viewport: Vector2) -> Array:
	var out := []
	for child in root.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		if control.anchor_top == 0.0 and control.anchor_bottom == 1.0:
			continue  # a bounded side panel
		out.append({"name": String(control.name), "rect": _layout_rect(control, viewport)})
	return out


func _describe(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		parts.append("%s %dx%d" % [entry["name"], int(rect.size.x), int(rect.size.y)])
	return ", ".join(parts)


## Where `control` sits in a viewport of `viewport` size: anchors and offsets give the authored
## box, and a box smaller than the control's minimum grows the way the control says it grows.
func _layout_rect(control: Control, viewport: Vector2) -> Rect2:
	var minimum := control.get_combined_minimum_size()
	var h := _grow(control.anchor_left * viewport.x + control.offset_left,
		control.anchor_right * viewport.x + control.offset_right, minimum.x,
		control.grow_horizontal)
	var v := _grow(control.anchor_top * viewport.y + control.offset_top,
		control.anchor_bottom * viewport.y + control.offset_bottom, minimum.y,
		control.grow_vertical)
	return Rect2(h.x, v.x, h.y - h.x, v.y - v.x)


func _grow(start: float, end: float, minimum: float, direction: int) -> Vector2:
	if end - start >= minimum:
		return Vector2(start, end)
	match direction:
		Control.GROW_DIRECTION_BEGIN:
			return Vector2(end - minimum, end)
		Control.GROW_DIRECTION_BOTH:
			var middle := (start + end) * 0.5
			return Vector2(middle - minimum * 0.5, middle + minimum * 0.5)
		_:
			return Vector2(start, start + minimum)


## A settled HUD does no per-frame work (D-057 — no permanent processing for static things).
##
## Every feedback node switches itself off when idle, and each has its own test. This is the
## guard at the level that matters for the frame: the WHOLE populated HUD, walked, so a widget
## added later with an always-on `_process` is caught even if nobody wrote a test for it.
func test_a_settled_hud_does_no_per_frame_work() -> void:
	var hud := _hud()
	_populate_plaques(hud)
	hud.call("set_interact_available", true)
	hud.call("set_cultivation_view", _cultivation_at_site())
	hud.call("set_skill_view", _skills_learned())
	await scene_tree.process_frame
	await scene_tree.process_frame
	var busy: Array[String] = []
	var visited := _collect_processing(hud, busy)
	assert_true(visited >= 20,
		"the walk covered the HUD tree (%d nodes) — a broken walk would pass vacuously"
			% visited)
	assert_eq(busy, [],
		"no node in a settled HUD processes per frame; these do: %s" % str(busy))
	free_node(hud)


## The dock reads "press this key" without hiding anything it shows: each keycap sits on its
## slot's corner, never on the qi gauge under the slots (a key over the gauge hid the low end of
## the pool — the part the player needs before casting).
func test_the_dock_keys_never_cover_the_qi_gauge() -> void:
	var hud := _hud()
	hud.call("set_skill_view", _skills_learned())
	await scene_tree.process_frame
	await scene_tree.process_frame
	var dock := hud.find_child("SkillDock", true, false) as Control
	assert_true(dock != null and dock.visible, "the dock is up with techniques learned")
	if dock == null:
		free_node(hud)
		return
	var gauge: Control = null
	for node in dock.find_children("*", "ProgressBar", true, false):
		gauge = node as Control
	var caps := dock.find_children("KeyCap", "", true, false)
	assert_eq(caps.size(), 2, "one keycap per learned technique")
	assert_not_null(gauge, "the qi gauge is in the dock")
	if gauge != null:
		for cap in caps:
			var rect := (cap as Control).get_global_rect()
			assert_false(rect.intersects(gauge.get_global_rect()),
				"keycap %s stays off the qi gauge %s" % [rect, gauge.get_global_rect()])
			assert_true(rect.end.y > (cap.get_parent() as Control).get_global_rect().end.y,
				"the keycap still hangs off its slot's corner (read as a key, not a label)")
	free_node(hud)


func _collect_processing(node: Node, busy: Array[String]) -> int:
	if node.is_processing() or node.is_physics_processing():
		busy.append("%s (%s)" % [node.name, node.get_class()])
	var visited := 1
	for child in node.get_children():
		visited += _collect_processing(child, busy)
	return visited


func _class_of_resource(resource: Resource) -> String:
	return "<null>" if resource == null else resource.get_class()


## COMBAT TAKES THE SCREEN (D-057B). A side panel covers a third of the playfield; a fight that
## starts behind one is a fight the player cannot see. Engaging a LIVE target closes any open
## side panel — once, on the transition: a panel the player re-opens mid-fight stays open, and
## a health update or a kill does not close it again.
func test_engaging_a_live_target_closes_the_side_panels_once() -> void:
	var hud := _hud()
	var sect: Control = hud.get("_sect_panel")
	var faction: Control = hud.get("_faction_panel")
	sect.visible = true
	faction.visible = true
	var live := CombatTargetView.new()
	live.has_target = true
	live.name_key = &"ENEMY_MIST_WOLF_NAME"
	live.current_health = 30
	live.max_health = 34
	hud.call("set_target_view", live)
	assert_false(hud.call("is_sect_panel_open"), "engaging a live target closes the sect panel")
	assert_false(hud.call("is_faction_panel_open"), "and the politics panel")

	# The player re-opens one mid-fight: that is a choice, kept through health updates.
	sect.visible = true
	live.current_health = 20
	hud.call("set_target_view", live)
	assert_true(hud.call("is_sect_panel_open"),
		"a panel re-opened mid-fight stays open through a health update")
	var dead := CombatTargetView.new()
	dead.has_target = true
	dead.name_key = &"ENEMY_MIST_WOLF_NAME"
	dead.max_health = 34
	dead.is_dead = true
	hud.call("set_target_view", dead)
	assert_true(hud.call("is_sect_panel_open"), "and through the kill")

	# A NEW engagement after the fight closes it again.
	hud.call("set_target_view", live)
	assert_false(hud.call("is_sect_panel_open"), "a new engagement takes the screen back")
	free_node(hud)


## A cultivation view standing at a vein: the cultivate prompt is visible (the strip's worst case).
func _cultivation_at_site() -> CultivationView:
	var view := CultivationView.new()
	view.available = true
	view.realm_name_key = &"REALM_HAU_THIEN_NAME"
	view.layer = 9
	view.progress = 190
	view.step_cost = 240
	view.site_in_reach = true
	return view


## Two notices in a row are BOTH shown, in order (Phase 12, capture-found: reading the stele
## teaches two things, and the second notice used to erase the breathing method's).
func test_notices_queue_instead_of_overwriting() -> void:
	var hud := _hud()
	hud.call("announce", &"UI_KNOWLEDGE_NOTHING_NEW")
	var first: String = hud.call("notice_text")
	hud.call("announce", &"UI_CULTIVATE_NO_SITE")
	assert_eq(hud.call("notice_text"), first, "the first notice stays up for its full time")
	(hud.find_child("NoticeHold", true, false) as Timer).timeout.emit()
	assert_eq(hud.call("notice_text"), _localized("UI_CULTIVATE_NO_SITE"),
		"then the second takes its turn")
	free_node(hud)


## The satchel is MODAL: opening it hands input to the panel (the world stops reading the move
## keys), closing it gives input back — and closing the HUD never strands a modal context.
func test_the_satchel_takes_and_returns_input() -> void:
	var hud := _hud()
	var input := scene_tree.root.get_node_or_null("InputService")
	if input == null:
		free_node(hud)
		return
	input.call("set_gameplay_context")
	hud.call("open_inventory")
	assert_true(hud.call("is_inventory_open"), "open")
	assert_false(bool(input.call("is_gameplay_active")), "gameplay input is suspended")
	hud.call("close_inventory")
	assert_true(bool(input.call("is_gameplay_active")), "and handed back on close")
	hud.call("open_inventory")
	free_node(hud)
	assert_true(bool(input.call("is_gameplay_active")), "freeing the HUD never strands the modal")
	input.call("set_menu_context")


## Both techniques learned: the skill dock is up (the populated HUD's worst case, Phase 15).
func _skills_learned() -> SkillView:
	var view := SkillView.new()
	view.qi = 20.0
	view.qi_max = 40
	for slot in [1, 2]:
		view.slots.append({"slot": slot, "technique_id": StringName("tech_%d" % slot),
			"name_key": &"TECH_LOI_CHI_NAME",
			"icon": load("res://assets/sprites/items/skill_loi_chi.png"),
			"cooldown_left": 1.0, "cooldown_total": 4.0, "qi_cost": 16, "ready": false})
	return view


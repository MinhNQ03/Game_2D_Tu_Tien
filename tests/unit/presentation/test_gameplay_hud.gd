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
	# Four labels: name, title, map, hint. Find them by walking the single Control root.
	var labels: Array[Label] = []
	_collect_labels(hud, labels)
	assert_true(labels.size() >= 4, "HUD builds at least name/title/map/hint labels")
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
	# proving a graphic treatment, not floating text. Interact + menu => at least 2.
	assert_true(_key_badge_count(hud) >= 2, "interact + menu each have a graphic key badge")
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
	assert_eq(side_panels, 2,
		"both toggleable side panels (sect + politics) are bounded boxes (got %d)"
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
	assert_eq(scrollers, 2, "both side panels scroll (got %d)" % scrollers)
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
## is now THREE. Mana and realm progress are still owned by nobody, so a FOURTH gauge is still
## a lie, and the count is what catches one appearing.
##
## The number is not the point — the pairing is. Each gauge is named, so swapping one for a
## mana bar fails even though the count would still be right.
func test_hud_shows_a_gauge_for_exactly_the_stats_a_system_owns() -> void:
	var hud := _hud()
	assert_eq(_count_class(hud, "ProgressBar"), 3,
		("exactly THREE gauges — the player's health, the combat target's health, and the "
			+ "player's XP meter. A fourth means a bar was added for mana or realm progress, "
			+ "which no system backs yet"))
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


## The visual pass must not have cost any behaviour: the character name, the map name, the
## prompts and the closed-by-default sect panel all still work (a pure presentation change).
func test_hud_behaviour_survived_the_visual_pass() -> void:
	var hud := _hud()
	_use_language("en")
	hud.set_character(_player_state())
	hud.set_map_name(&"UI_MAP_HUB_NAME")
	hud.set_interact_available(true)

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
	for child in root.get_children():
		var panel := child as PanelContainer
		if panel != null and _count_class(panel, "NinePatchRect") > 0:
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

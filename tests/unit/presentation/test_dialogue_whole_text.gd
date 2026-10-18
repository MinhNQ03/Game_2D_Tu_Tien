extends TestCase
## UI-01: nothing anyone says is ever cut short. Every authored line, the speaker's name and
## title, and every answer that can be offered with it, in Vietnamese and in English, laid out
## in the real `DialoguePanel` with the real font and MEASURED: a label that clips or trims
## fails, a word wider than its column fails, a wrapped label shorter than its lines fails, a
## label drawn outside the box fails, and a line too long for the box must show every one of
## its wrapped lines across its pages. The box itself stays out of the playfield clear zone.

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const DIALOGUES := "res://data/dialogue/dialogue_catalog.tres"
## The stricter of the two shipped aspect ratios: 1280x800 only gives the box more room.
const VIEWPORT := Vector2(1280, 720)


func _hud() -> GameplayHUD:
	var hud: GameplayHUD = HUDScript.new()
	add_to_tree(hud)
	return hud


func _use_language(code: String) -> void:
	scene_tree.root.get_node("Localization").call("set_language", code)


func _settle() -> void:
	# A wrapped label's height is only known once it has been laid out at its real width.
	await scene_tree.process_frame
	await scene_tree.process_frame


func test_no_dialogue_label_clips_or_trims_its_text() -> void:
	_use_language("en")
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var dialogue := catalog.dialogue_of_speaker(&"actor_scout_ko")
	hud.set_dialogue_view(DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub")))
	await _settle()
	var labels := _labels(panel)
	assert_true(labels.size() >= 6, "the name, title, mood, line, keys and answers are labels")
	for label in labels:
		assert_false(label.clip_text, "'%s' (%s) clips its text" % [label.text, label.name])
		assert_eq(label.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING,
			"'%s' (%s) trims its text" % [label.text, label.name])
	_use_language("vi")
	free_node(hud)


func test_every_authored_line_speaker_and_answer_is_shown_whole_in_both_languages() -> void:
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var measured := 0
	var tallest := 0.0
	var tallest_at := ""
	var authored := 0
	var answers: Dictionary = {}  # "code dialogue/line/answer" -> true, for every answer laid out
	for code: String in ["vi", "en"]:
		_use_language(code)
		for dialogue in catalog.entries:
			assert_not_null(DialogueOffers.speaker_template(dialogue.speaker_id),
				"%s's speaker %s has a template to take a name from" % [dialogue.id,
					dialogue.speaker_id])
			for line in dialogue.nodes:
				authored += line.choices.size()
				# Every set of answers the line can show together, each laid out with the line:
				# no answer is left unmeasured, and the tallest box any of them makes is seen.
				var offers := DialogueOffers.sets(line)
				if offers.is_empty():
					offers = [[]]
				for offered: Array in offers:
					hud.set_dialogue_view(DialogueOffers.view_of(dialogue, line, measured + 1,
						offered))
					await _settle()
					var problems := await _cut_text(panel)
					assert_true(problems.is_empty(), "[%s] %s/%s %s: %s"
						% [code, dialogue.id, line.id, _ids(offered), "; ".join(problems)])
					if panel.size.y > tallest:
						tallest = panel.size.y
						tallest_at = "%s %s %s" % [code, line.id, _ids(offered)]
					for option: DialogueChoiceData in offered:
						answers["%s %s/%s/%s" % [code, dialogue.id, line.id, option.id]] = true
					measured += 1
	assert_true(measured >= 40, "every authored line was measured in both languages (%d)"
		% measured)
	assert_eq(answers.size(), authored,
		"every authored answer was laid out and measured, in both languages")
	print("[dialogue-whole-text] %d views, %d answers measured; tallest box %.0f px (%s) of %.0f"
		% [measured, answers.size(), tallest, tallest_at,
			VIEWPORT.y * 0.25 - UIPalette.HUD_MARGIN])
	_use_language("vi")
	free_node(hud)


## A line longer than the box can hold is not cut and does not push the box into the clear
## zone: it pages, the keys say so, and the answers wait for its last page.
func test_a_line_too_long_for_the_box_pages_with_a_cue_and_loses_nothing() -> void:
	_use_language("en")
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var dialogue := catalog.dialogue_of_speaker(&"actor_scout_ko")
	var view := DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"))
	# No shipped line is this long. Three lines' text said as one is: the panel is handed a
	# text it cannot fit, the way a translation that grew would hand it one.
	var said := " ".join([_t("DLG_LIN_RIVAL"), _t("DLG_LIN_NOTATION"), _t("DLG_LIN_SHEET_READ")])
	var loc := LongText.new(scene_tree.root.get_node("Localization"), {"DLG_KO_HUB": said})
	panel.set("_loc", loc)
	var asked: Array = []
	var on_choice := func(_node: StringName, id: StringName) -> void: asked.append(id)
	hud.dialogue_choice_requested.connect(on_choice)
	hud.set_dialogue_view(view)
	await _settle()
	assert_true(panel.page_count() >= 2, "the line pages (%d)" % panel.page_count())
	var line := panel.find_child("Line", true, false) as Label
	assert_eq(line.text, said, "the whole line is the label's text: nothing was dropped")
	assert_true(panel.keys_text().begins_with(UIPalette.DIALOGUE_MORE_CUE),
		"a page that is not the last says there is more ('%s')" % panel.keys_text())
	assert_true(panel.keys_text().contains(_continue_word()),
		"and how to read on ('%s')" % panel.keys_text())
	var keys_label := panel.find_child("Keys", true, false) as Label
	assert_not_null(keys_label, "the keys row is a label named Keys")
	if keys_label != null:
		assert_true(keys_label.get_theme_font("font").has_char(
			UIPalette.DIALOGUE_MORE_CUE.unicode_at(0)),
			"the more cue is a glyph of the keys row's own font, not a fallback's (or tofu)")
	var rows := panel.find_child("ChoiceRows", true, false) as Control
	assert_false(rows.visible, "the answers wait for the last page")
	panel.move_selection(1)
	assert_eq(panel.selected_index(), 0, "and the move keys do not choose one meanwhile")
	panel.confirm()
	assert_eq(panel.page_index(), 1, "confirm turns the page")
	assert_true(asked.is_empty(), "and says nothing")
	panel.reset_page()
	var problems := await _cut_text(panel)
	assert_true(problems.is_empty(), "every page shows its lines whole: %s" % "; ".join(problems))
	assert_eq(panel.page_index(), panel.page_count() - 1, "the walk ended on the last page")
	assert_false(panel.keys_text().begins_with(UIPalette.DIALOGUE_MORE_CUE),
		"the last page has no more cue")
	assert_true(rows.visible, "and offers the answers")
	panel.move_selection(1)
	assert_eq(panel.selected_index(), 1, "on the last page the answers are chosen again")
	panel.confirm()
	assert_eq(asked, [&"ko_ask_woods"], "and confirm says the chosen one")
	hud.set_dialogue_view(DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"), 2))
	assert_eq(panel.page_index(), 0, "a new line starts on its first page")
	hud.dialogue_choice_requested.disconnect(on_choice)
	panel.set("_loc", scene_tree.root.get_node("Localization"))
	free_node(loc)
	_use_language("vi")
	free_node(hud)


## A doubled press turns the first page while the box is still fading open: the turn must not
## leave the box half-transparent or the portrait mid-nod.
func test_a_page_turned_while_the_box_opens_leaves_it_whole_and_still() -> void:
	_use_language("en")
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var dialogue := catalog.dialogue_of_speaker(&"actor_scout_ko")
	var view := DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"))
	var said := " ".join([_t("DLG_LIN_RIVAL"), _t("DLG_LIN_NOTATION"), _t("DLG_LIN_SHEET_READ")])
	var loc := LongText.new(scene_tree.root.get_node("Localization"), {"DLG_KO_HUB": said})
	panel.set("_loc", loc)
	hud.set_dialogue_view(view)
	await _settle()
	# Laid out once, the box closes and the same line opens it again: its open fade and the
	# speaker's nod start now, and the press lands before a single frame of them has run.
	hud.set_dialogue_view(DialogueView.make_closed())
	var reopened := DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"), 2)
	reopened.gestures = true
	hud.set_dialogue_view(reopened)
	assert_true(panel.page_count() >= 2, "the line pages (%d)" % panel.page_count())
	assert_true(panel.modulate.a < 1.0, "the box is still fading open (%.2f)" % panel.modulate.a)
	panel.confirm()
	assert_eq(panel.page_index(), 1, "the doubled press turned the page")
	await scene_tree.create_timer(0.3).timeout
	assert_eq(panel.modulate.a, 1.0, "the box is fully shown after the turn")
	var portrait := panel.get("_portrait") as Control
	assert_eq(portrait.position, Vector2.ZERO, "and the portrait is back in its place")
	var line := panel.find_child("Line", true, false) as Label
	assert_eq(line.modulate.a, 1.0, "and the new page has settled in")
	panel.set("_loc", scene_tree.root.get_node("Localization"))
	free_node(loc)
	_use_language("vi")
	free_node(hud)


## An answer longer than its column wraps under its own first word — whole, never trimmed —
## and its column grows to hold it, the selection marker still on the answer's first line.
func test_a_long_answer_wraps_whole_and_its_column_grows_to_hold_it() -> void:
	_use_language("en")
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var dialogue := catalog.dialogue_of_speaker(&"actor_scout_ko")
	var view := DialogueOffers.view_of(dialogue, dialogue.node(&"ko_pills_offer"))
	hud.set_dialogue_view(view)
	await _settle()
	var column := panel.find_child("ChoiceRows", true, false) as Control
	var before := column.size.y
	var long_answer := "%s, and %s" % [_t("DLG_KO_CHOICE_PRICE"), _t("DLG_KO_CHOICE_WOODS")]
	var first_key := String(view.choices[0]["text_key"])
	var loc := LongText.new(scene_tree.root.get_node("Localization"), {first_key: long_answer})
	panel.set("_loc", loc)
	hud.set_dialogue_view(DialogueOffers.view_of(dialogue, dialogue.node(&"ko_pills_offer"), 2))
	await _settle()
	var answer := panel.find_child("Answer", true, false) as Label
	assert_eq(answer.text, long_answer, "the answer is the whole text")
	assert_true(answer.get_line_count() >= 2, "it wraps (%d lines)" % answer.get_line_count())
	assert_true(column.size.y > before, "the answers' column grew to hold it (%.0f -> %.0f)"
		% [before, column.size.y])
	var problems := await _cut_text(panel)
	assert_true(problems.is_empty(), "and nothing is cut: %s" % "; ".join(problems))
	var marker := answer.get_parent().find_child("Marker", false, false) as Label
	assert_true(marker.size.y < answer.size.y, "the marker sits on the first line only")
	panel.set("_loc", scene_tree.root.get_node("Localization"))
	free_node(loc)
	_use_language("vi")
	free_node(hud)


## The box keeps to its band at run time, not only for the text shipped today: an answer set
## too tall for it (five answers, the first saying all five as one, the way a translation that
## grew would) is shown as a window of WHOLE answers that follows the selection, a more-cue lit
## on the side that hides answers, and the box stays inside the band — 162 px at 1280x720, 182
## at 1280x800 — while the move keys walk every answer.
func test_an_answer_set_too_tall_for_the_band_is_windowed_and_the_box_stays_in_it() -> void:
	_use_language("vi")
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var window := scene_tree.root
	var was := window.size
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var dialogue := catalog.dialogue_of_speaker(&"actor_scout_ko")
	var view := DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"))
	assert_true(view.choices.size() >= 5, "the scout's hub offers five answers at once")
	var texts: PackedStringArray = []
	for option in view.choices:
		texts.append(_t(String(option["text_key"])))
	var loc := LongText.new(scene_tree.root.get_node("Localization"),
		{String(view.choices[0]["text_key"]): ", ".join(texts)})
	panel.set("_loc", loc)
	var above := panel.find_child("ChoicesAbove", true, false) as Label
	var below := panel.find_child("ChoicesBelow", true, false) as Label
	for screen: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		window.size = screen
		await _settle()
		hud.set_dialogue_view(DialogueView.make_closed())
		hud.set_dialogue_view(DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"),
			screen.y))
		await _settle()
		var allowed := screen.y * 0.25 - UIPalette.HUD_MARGIN
		assert_eq(panel.get_viewport_rect().size.y, float(screen.y), "laid out at %s" % screen)
		assert_eq(panel.max_height(), allowed, "%s: the panel holds itself to the %.0f px band"
			% [screen, allowed])
		var answer := panel.find_child("Answer", true, false) as Label
		# staging only: the long answer wraps (3 lines in the shipped font); that the whole set is
		# too tall for the band is proved below, where not every answer can be shown at once
		assert_true(answer.get_line_count() >= 2, "%s: the staged answer wraps (%d lines)"
			% [screen, answer.get_line_count()])
		var seen: Dictionary = {}
		for step in view.choices.size():
			var at := "%s step %d" % [screen, step]
			var shown := panel.shown_choice_indices()
			assert_true(shown.size() < view.choices.size(),
				"%s: not every answer fits, so a window is shown (%s)" % [at, shown])
			assert_true(shown.has(panel.selected_index()), "%s: the selected answer %d is shown"
				% [at, panel.selected_index()])
			assert_true(above.visible and below.visible, "%s: both cues hold their place" % at)
			assert_eq(above.modulate.a > 0.0, shown[0] > 0,
				"%s: the cue above is lit exactly when answers hide above" % at)
			assert_eq(below.modulate.a > 0.0, shown[-1] < view.choices.size() - 1,
				"%s: the cue below is lit exactly when answers hide below" % at)
			var problems := await _cut_text(panel, allowed)
			assert_true(problems.is_empty(), "%s: %s" % [at, "; ".join(problems)])
			assert_true(panel.size.y <= allowed, "%s: the box is %.0f px of %.0f"
				% [at, panel.size.y, allowed])
			for i in shown:
				seen[i] = true
			panel.move_selection(1)
			await _settle()
		assert_eq(seen.size(), view.choices.size(),
			"%s: walking the answers shows every one of them" % screen)
		assert_eq(panel.selected_index(), 0, "%s: and the selection wraps round to the first"
			% screen)
	window.size = was
	panel.set("_loc", scene_tree.root.get_node("Localization"))
	free_node(loc)
	free_node(hud)


## The speech column keeps to the band at run time too: a speaker title that wraps to more rows
## (four times the shipped one, the way a translation that grew would say it) on a line that
## already pages takes its rows out of the line's page — the page shows fewer wrapped lines, the
## line pages on, nothing is cut and the box stays inside the band at 1280x720 and 1280x800.
func test_a_title_that_wraps_takes_its_rows_from_the_page_and_the_box_stays_in_the_band() -> void:
	_use_language("en")
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var window := scene_tree.root
	var was := window.size
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var dialogue := catalog.dialogue_of_speaker(&"actor_scout_ko")
	var view := DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"))
	var title_key := String(view.speaker_title_key)
	assert_true(title_key != "", "the scout has a title to stage")
	var title := _t(title_key)
	var said := " ".join([_t("DLG_LIN_RIVAL"), _t("DLG_LIN_NOTATION"), _t("DLG_LIN_SHEET_READ")])
	var loc := LongText.new(scene_tree.root.get_node("Localization"),
		{"DLG_KO_HUB": said, title_key: " ".join([title, title, title, title])})
	panel.set("_loc", loc)
	var title_label := panel.find_child("SpeakerTitle", true, false) as Label
	for screen: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		window.size = screen
		await _settle()
		hud.set_dialogue_view(DialogueView.make_closed())
		hud.set_dialogue_view(DialogueOffers.view_of(dialogue, dialogue.node(&"ko_hub"),
			screen.y))
		await _settle()
		await _settle()
		var allowed := screen.y * 0.25 - UIPalette.HUD_MARGIN
		# staging only: the title really wraps, and the line really pages
		assert_true(title_label.get_line_count() >= 2, "%s: the staged title wraps (%d rows)"
			% [screen, title_label.get_line_count()])
		assert_true(panel.page_count() >= 2, "%s: the line pages (%d)"
			% [screen, panel.page_count()])
		assert_true(panel.size.y <= allowed, "%s: the box is %.0f px of %.0f"
			% [screen, panel.size.y, allowed])
		var problems := await _cut_text(panel, allowed)
		assert_true(problems.is_empty(), "%s: %s" % [screen, "; ".join(problems)])
	window.size = was
	panel.set("_loc", scene_tree.root.get_node("Localization"))
	free_node(loc)
	_use_language("vi")
	free_node(hud)


## The window is chosen from each answer's height worked out from its text and the font, before
## any layout pass: that height must be the one the row is then laid out at, for every authored
## answer in both languages, or the window could let the box grow past its band.
func test_the_answer_height_the_window_is_chosen_by_is_the_laid_out_height() -> void:
	var catalog := load(DIALOGUES) as DialogueCatalogData
	var hud := _hud()
	var panel := hud.dialogue_panel()
	var measured := 0
	var authored := 0
	var compared: Dictionary = {}
	for code: String in ["vi", "en"]:
		_use_language(code)
		for dialogue in catalog.entries:
			for line in dialogue.nodes:
				authored += line.choices.size()
				for offered: Array in DialogueOffers.sets(line):
					hud.set_dialogue_view(DialogueOffers.view_of(dialogue, line, measured + 1,
						offered))
					await _settle()
					measured += 1
					var rows: Array[Control] = []
					for row in panel.find_child("ChoiceRows", true, false).get_children():
						if not row.is_queued_for_deletion():
							rows.append(row as Control)
					assert_eq(rows.size(), offered.size(), "[%s] %s: a row per answer offered"
						% [code, line.id])
					for i in mini(rows.size(), offered.size()):
						var row := rows[i]
						if not row.visible:
							continue
						var label := row.find_child("Answer", true, false) as Label
						var worked_out: float = panel.call("_answer_height", label.text)
						assert_true(absf(worked_out - row.size.y) <= 0.5,
							"[%s] '%s': worked out %.1f px, laid out %.1f" % [code, label.text,
								worked_out, row.size.y])
						compared["%s %s/%s/%s" % [code, dialogue.id, line.id,
							(offered[i] as DialogueChoiceData).id]] = true
	assert_eq(compared.size(), authored, "every authored answer was compared, in both languages")
	_use_language("vi")
	free_node(hud)


## Every reason something in the open panel is cut, on every page of its line ([] = whole).
## Leaves the panel on its last page.
func _cut_text(panel: DialoguePanel,
		allowed: float = VIEWPORT.y * 0.25 - UIPalette.HUD_MARGIN) -> Array[String]:
	var problems: Array[String] = []
	var box := panel.get_global_rect().grow(0.5)
	if panel.size.x > VIEWPORT.x - 2.0 * UIPalette.HUD_MARGIN:
		problems.append("the box is %.0f px wide" % panel.size.x)
	var line := panel.find_child("Line", true, false) as Label
	var seen: Dictionary = {}
	var pages: int = panel.call("page_count") if panel.has_method("page_count") else 1
	for page in pages:
		if page > 0:
			panel.call("next_page")
			await _settle()
		# The middle half of the screen stays clear: the box, one margin above the bottom
		# edge, ends below three quarters of the height (UI_UX_BIBLE §3c).
		if panel.size.y > allowed:
			problems.append("page %d: the box is %.0f px tall and enters the clear zone"
				% [page + 1, panel.size.y])
		for label in _labels(panel):
			if not label.is_visible_in_tree() or label.text.strip_edges() == "":
				continue
			var why := _why_cut(label)
			if why != "":
				problems.append("page %d: '%s' %s" % [page + 1, label.text, why])
			if not box.encloses(label.get_global_rect()):
				problems.append("page %d: '%s' is drawn outside the box" % [page + 1, label.text])
		for i in line.get_visible_line_count():
			seen[line.lines_skipped + i] = true
	if line.text != "" and seen.size() < line.get_line_count():
		problems.append("the line has %d wrapped lines and its pages show %d"
			% [line.get_line_count(), seen.size()])
	return problems


## Why `label` does not show its whole text at the size it was laid out at ("" = it does).
func _why_cut(label: Label) -> String:
	if label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
		return "clips or trims"
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var width := label.size.x + 0.5
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		var needed := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x
		return "" if needed <= width else "needs %.0f px and has %.0f" % [needed, label.size.x]
	for word in label.text.split(" ", false):
		var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w > width:
			return "has the word '%s' (%.0f px) in a %.0f px column" % [word, w, label.size.x]
	if label.max_lines_visible < 0 and label.get_visible_line_count() < label.get_line_count():
		return "shows %d of its %d lines" % [label.get_visible_line_count(),
			label.get_line_count()]
	if label.size.y + 0.5 < label.get_minimum_size().y:
		return "is %.0f px tall and needs %.0f" % [label.size.y, label.get_minimum_size().y]
	return ""


func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Label:
			out.append(child as Label)
		out += _labels(child)
	return out


## The ids of a set of answers, for a failure message.
func _ids(offered: Array) -> String:
	var ids: PackedStringArray = []
	for option: DialogueChoiceData in offered:
		ids.append(String(option.id))
	return "[%s]" % ", ".join(ids)


func _t(key: String) -> String:
	return String(scene_tree.root.get_node("Localization").call("t", key))


## The continue prompt's own word ("Continue"), without the keys it names (they vary).
func _continue_word() -> String:
	var text := String(scene_tree.root.get_node("Localization").call("t_args",
		"UI_DIALOGUE_KEYS_CONTINUE", {"confirm": "", "close": ""}))
	return text.strip_edges().get_slice(" ", 0)


## Localization that says the given texts for the given keys and defers everything else.
class LongText extends Node:
	var _real: Node
	var _said: Dictionary

	func _init(real: Node, said: Dictionary) -> void:
		_real = real
		_said = said

	func t(key: String) -> String:
		return String(_said[key]) if _said.has(key) else String(_real.call("t", key))

	func t_args(key: String, args: Dictionary) -> String:
		return String(_real.call("t_args", key, args))

extends SceneTree
## playtest_flow — Aetheria real-application playtest harness (D-051).
##
## Boots the REAL game in a REAL window and PLAYS it with REAL semantic input, declaring
## expected-vs-observed for every step. It is the gate that proves the player-facing
## experience, which no other gate in this project covers: unit tests prove rules, integration
## tests prove boundaries, E2E proves the real flow — and all three were green while the
## Phase-09 attack lifecycle was completely invisible to the player (D-051 §10b).
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . -s res://tools/playtest_flow.gd
##     godot --path . -s res://tools/playtest_flow.gd -- vi user://playtest
##     godot --path . --resolution 1280x800 -s res://tools/playtest_flow.gd -- en /tmp/pt
##
## Arguments after `--`: [language] [output_dir]. Output defaults to `user://playtest`, which
## is EPHEMERAL EVIDENCE — screenshots and the report are produced, inspected, and NOT
## committed (`docs/PHASE_EXECUTION_PROTOCOL.md` §2).
##
## IT DRIVES THE REAL BOUNDARY, NOT A SHORTCUT. Movement, interaction, menus and attacks all
## go through `Input.parse_input_event` with a real `InputEventKey` built from the action's own
## binding, so the engine updates the InputMap state and dispatches it exactly as a key press
## does. It must NEVER call a domain mutator to fake player behaviour: that is L-017 — a test
## that bypasses the boundary it advertises stays green while the boundary is broken.
##
## The one sanctioned exception is DETERMINISTIC SETUP (placing the player for a reproducible
## encounter). Those steps say so in their name and in the report, so a reader can tell which
## steps are evidence about the input pipeline and which are staging.
##
## EXIT CODE IS THE GATE: 0 only when every step passed. A step that cannot even be attempted
## is a FAILURE, not a skip — "the harness could not find the HUD" must not read as success.

const MAIN_SCENE := "res://main.tscn"

## Frames to wait after a state change before sampling. UI builds in `_ready`, themes resolve
## on the next draw, and the map camera eases over several frames, so a single-frame wait
## samples a half-built screen.
const SETTLE_FRAMES := 12

## Bounded polling budget for an effect that takes an unknown number of frames (a transition,
## an attack landing). Polling the observable effect beats betting on one frame: synthetic
## `just_pressed` timing is fragile in a scripted run (L-016).
const POLL_FRAMES := 240

## D-063 §5: the answer to a key press is visible within 2 RENDERED frames and 100 ms.
const FEEDBACK_MAX_FRAMES := 2
const FEEDBACK_MAX_MSEC := 100.0
## A timing claim is only meaningful near 60 fps. A vsynced window in a LOCKED X session is
## presented at ~1 Hz (measured 931 ms/frame, D-063 A0): such a run is an INVALID environment
## and fails as one — it never produces a timing PASS. Run with `--disable-vsync --max-fps 60`
## when the session is locked.
const PACING_MAX_MEAN_MSEC := 20.0

var _out_dir := "user://playtest"
var _language := "vi"
## One entry per step: name, expected, observed, ok, msec, shot, map, ui.
var _steps: Array[Dictionary] = []
var _errors := 0
var _warnings := 0
var _shots: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_language = String(args[0])
	if args.size() >= 2:
		_out_dir = String(args[1])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _settle()

	# Language is applied AFTER boot and VERIFIED, because `Main._boot` applies the SAVED
	# language — setting it earlier is silently undone, which is how a whole capture run once
	# came out in the wrong language while every filename claimed otherwise (D-050).
	await _step_set_language()

	await _step_main_menu(main)
	await _step_new_game(main)
	var map := await _step_world_ready()
	await _step_hud_present(map)
	await _step_feedback(map)
	await _step_physical_truth(map)
	await _step_decor_solid(map)
	await _step_move(map)
	await _step_toggle_panel(map)
	await _step_attack(map)
	await _step_enter_field(map)
	await _step_encounter(main)
	await _step_natural_encounter(main)
	await _step_return_to_menu(main)

	_write_report()
	main.get_parent().remove_child(main)
	main.free()
	quit(1 if _failed_count() > 0 else 0)


# === Steps ==================================================================
#
# Every step records expected vs observed through `_record()`. A step that cannot run its check
# records a FAILURE with the reason, never a silent skip.

func _step_set_language() -> void:
	var started := Time.get_ticks_msec()
	var loc := root.get_node_or_null("Localization")
	if loc == null:
		_record("01_language", "/root/Localization present", "missing", false, started)
		return
	loc.call("set_language", _language)
	var active := String(loc.call("get_language"))
	_record("01_language", "language=%s" % _language, "language=%s" % active,
		active == _language, started)


func _step_main_menu(main: Node) -> void:
	var started := Time.get_ticks_msec()
	var menu := _menu_of(main)
	var buttons := _buttons_of(menu) if menu != null else [] as Array[Button]
	var ok := menu != null and buttons.size() >= 3
	if ok:
		buttons[0].grab_focus()
		await _settle()
	_record("02_main_menu", "menu with >= 3 actions",
		"menu=%s buttons=%d" % [menu != null, buttons.size()], ok, started,
		await _shot("02_main_menu"))


func _step_new_game(main: Node) -> void:
	var started := Time.get_ticks_msec()
	var menu := _menu_of(main)
	if menu == null or not menu.has_signal("new_game_pressed"):
		_record("03_new_game", "menu exposes new_game_pressed", "no menu signal", false, started)
		return
	# The menu's own intent signal, which is what its button emits — this is the real
	# navigation boundary, not a call into Main.
	menu.emit_signal("new_game_pressed")
	var gs := root.get_node_or_null("GameState")
	var running := false
	for _i in POLL_FRAMES:
		await process_frame
		if gs != null and bool(gs.call("is_session_active")):
			running = true
			break
	_record("03_new_game", "session_active=true", "session_active=%s" % running, running, started)


func _step_world_ready() -> Node:
	var started := Time.get_ticks_msec()
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = null
	for _i in POLL_FRAMES:
		await process_frame
		map = router.call("get_current_scene") if router != null else null
		if map != null:
			break
	await _settle()
	_record("04_world_ready", "a content scene is live",
		"map=%s" % _map_id(), map != null, started, await _shot("04_hub"))
	return map


func _step_hud_present(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var hud := map.get_node_or_null("GameplayHUD") if map != null else null
	_record("05_hud", "GameplayHUD exists in the active map",
		"hud=%s" % (hud != null), hud != null, started, await _shot("05_hud"))


## D-063 A1: the answer to the player's own key press is on screen within the threshold even
## with a PASSIVE notice up, and nothing that gives way is lost. Measured on RENDERED frames
## (`frame_post_draw`) in the real window. Placement onto pickups / beside the spring and the
## stele is deterministic SETUP; C and E are real keys.
func _step_feedback(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var hud := map.get_node_or_null("GameplayHUD") as GameplayHUD if map != null else null
	var player := _player_of(map)
	var spring := map.get_node_or_null("CultivationSites/LacHaSpring") as Node2D
	var stele := map.get_node_or_null("KnowledgeSources/LacHaStele") as Node2D
	if hud == null or player == null or spring == null or stele == null:
		_record("05b_answer_timing", "HUD, player, spring and stele in the hub",
			"hud=%s player=%s spring=%s stele=%s" % [hud != null, player != null,
				spring != null, stele != null], false, started)
		return
	var timing_ok := await _step_environment()
	# STATE (independent of timing): the setup pickups must REALLY collect via the live
	# InventoryRuntime — not merely become invisible. This runs even when the frame-pacing
	# environment is invalid, so a bad clock can never silently skip the collection proof.
	started = Time.get_ticks_msec()
	var inv_pre := _inventory()
	var pre_robe := inv_pre != null and bool(inv_pre.call("is_collected", &"pickup_hubrobe"))
	var pill := await _walk_onto(map, player, "Pickups/HubPill1", &"pickup_hubpill1")
	var manual := await _walk_onto(map, player, "Pickups/HubManualPhong",
		&"pickup_hubmanualphong")
	# The robe sits 12.8px from the manual (reach 14px): the manual placement collects it
	# too. Verify via the authority; the run proves collection iff it was uncollected
	# before this setup phase and is collected now, with the count matching the
	# authored WorldItem.
	var inv_post := _inventory()
	var robe_now := inv_post != null and bool(inv_post.call("is_collected", &"pickup_hubrobe"))
	var robe_node := map.get_node_or_null("Pickups/HubRobe")
	var robe_count_ok := false
	if robe_node != null and robe_node is WorldItem and inv_post != null:
		var rwi := robe_node as WorldItem
		if rwi.item != null and rwi.item.id != &"":
			var rc_after := int(inv_post.call("count_of", StringName(rwi.item.id)))
			# The robe was uncollected before setup (pre_robe false); its count must
			# have increased by exactly the authored count.
			robe_count_ok = rc_after == rwi.count
	var robe := {"ok": robe_now and not pre_robe and robe_count_ok,
		"reason": "pickup_hubrobe already collected before setup" if pre_robe
			else ("pickup_hubrobe count mismatch" if robe_now and not robe_count_ok
				else ("" if robe_now else "pickup_hubrobe not collected with the manual")),
		"pickup_id": &"pickup_hubrobe"}
	var state_ok: bool = pill["ok"] and manual["ok"] and robe["ok"]
	_record("05a_pickup_state",
		"pickup_hubpill1, pickup_hubmanualphong, pickup_hubrobe collected via the live "
			+ "InventoryRuntime (is_collected), not inferred from visibility",
		"pill=%s manual=%s robe=%s" % [_describe_setup(pill), _describe_setup(manual),
			_describe_setup(robe)],
		state_ok, started)
	if not state_ok:
		for step in ["05b_answer_timing", "05c_result_timing", "05d_notices_kept"]:
			_record(step, "setup pickups collected", "SETUP FAILED — gameplay not attempted",
				false, Time.get_ticks_msec())
		return
	var loc := root.get_node("Localization")
	# TIMING vs STATE/ORDER are separate evidence types. The 2-frame/100ms threshold is
	# only meaningful with a valid pacing environment; the gameplay interactions (C/E)
	# and the notice-order validation run regardless, so an invalid clock cannot hide
	# a broken sequence.
	var timing_label := "" if timing_ok else " [TIMING NOT MEASURED — invalid environment]"

	# 05b — C at the spring, no method yet, with a pickup notice on screen.
	# (The pill was collected in the setup above; its notice is the pending one.)
	started = Time.get_ticks_msec()
	var before := "kind=%s '%s'" % [hud.notice_kind(), hud.notice_text()]
	player.global_position = spring.global_position + Vector2(0, 26)  # SETUP
	for _i in 4:
		await physics_frame
	var refusal := String(loc.call("t", "UI_CULTIVATE_NO_METHOD"))
	var answer := await _time_feedback(&"cultivate", func() -> bool:
		return hud.notice_text() == refusal)
	var kept := hud.pending_notice_keys().has(&"UI_ITEM_GAINED")
	var timing_part := "frames=%d ms=%.1f" % [answer["frames"], answer["ms"]]
	if not timing_ok:
		timing_part = "NOT MEASURED (invalid pacing)"
	_record("05b_answer_timing",
		"refusal visible <= %d rendered frames and <= %.0f ms; the pickup notice kept%s"
			% [FEEDBACK_MAX_FRAMES, FEEDBACK_MAX_MSEC, timing_label],
		"%s kind=%s kept=%s (band before: %s)" % [timing_part, hud.notice_kind(), kept,
			before],
		(timing_ok and _within(answer) or not timing_ok)
			and hud.notice_kind() == GameplayHUD.NOTICE_ANSWER and kept, started,
		answer["shot"])

	# 05c — two pickups beside the stele (collected in the setup above), then E on the stele.
	# The setup already proved collection via is_collected; 05c fails explicitly if either
	# required pickup did not collect — it never passes on a missing pickup.
	started = Time.get_ticks_msec()
	var inv := _inventory()
	var manual_ok := inv != null and bool(inv.call("is_collected", &"pickup_hubmanualphong"))
	var robe_ok := inv != null and bool(inv.call("is_collected", &"pickup_hubrobe"))
	if not (manual_ok and robe_ok):
		_record("05c_result_timing",
			"pickup_hubmanualphong and pickup_hubrobe collected before the stele read",
			"manual=%s robe=%s — SETUP NOT PROVEN" % [manual_ok, robe_ok], false, started)
		# 05d cannot run meaningfully; record it as blocked by the failed setup.
		_record("05d_notices_kept", "pickup notices kept in order",
			"blocked: 05c setup failed", false, Time.get_ticks_msec())
		return
	player.global_position = stele.global_position + Vector2(0, 14)  # SETUP
	for _i in 4:
		await physics_frame
	# Explicit expectation: all three setup pickups (pill, manual, robe) each left one
	# passive UI_ITEM_GAINED notice waiting. Never derive the expected count from a dynamic
	# queue size — a missing pickup would shrink that count and let an incomplete run pass.
	var expected_passives := 3
	var lesson := String(loc.call("t", "KNOW_DAN_KHI_QUYET_NAME"))
	var result := await _time_feedback(&"interact", func() -> bool:
		return hud.notice_text().contains(lesson))
	var timing_part_c := "frames=%d ms=%.1f" % [result["frames"], result["ms"]]
	if not timing_ok:
		timing_part_c = "NOT MEASURED (invalid pacing)"
	_record("05c_result_timing",
		"lesson visible <= %d rendered frames and <= %.0f ms, ahead of %d waiting pickup notices%s"
			% [FEEDBACK_MAX_FRAMES, FEEDBACK_MAX_MSEC, expected_passives, timing_label],
		"%s kind=%s waiting=%s (expected %d passives)" % [timing_part_c,
			hud.notice_kind(), str(hud.pending_notice_keys()), expected_passives],
		(timing_ok and _within(result) or not timing_ok)
			and hud.notice_kind() == GameplayHUD.NOTICE_RESULT, started,
		result["shot"])

	# 05d — in real time: the second lesson, then every pickup notice, in order, none lost.
	# Expected: lesson 1, lesson 2, then exactly the 3 passive pickup notices from the
	# proven setup (pill, manual, robe — in emission order). Each notice is verified by
	# its authored identity, not just a count: a missing, duplicate, unexpected or
	# out-of-order notice fails.
	started = Time.get_ticks_msec()
	var sequence: Array[String] = []
	# EVERY id recorded so far, not just the last: the HUD resumes an interrupted notice with
	# its original id, and "different from the last one" recorded the resumed notice twice.
	var recorded_ids: Dictionary = {}
	var diagnostics: Array[String] = []
	var budget := int((expected_passives + 3) * UIPalette.HUD_NOTICE_SECONDS * 75.0)
	for _i in budget:
		await process_frame
		var text := hud.notice_text()
		var seq := hud.notice_seq()
		# Identity, not text: two distinct notice instances with identical kind and
		# text have different seq values and must both be recorded; a resumed instance
		# keeps its seq and is recorded once.
		var seen: Dictionary = NoticeSequenceValidator.record(sequence, recorded_ids,
			String(hud.notice_kind()), text, seq)
		var diagnostic := String(seen["diagnostic"])
		if diagnostic != "" and not diagnostics.has(diagnostic):
			diagnostics.append(diagnostic)
		if text == "" and hud.pending_notice_keys().is_empty():
			break
	var second := String(loc.call("t", "KNOW_LAC_HA_STELE_RECORD_NAME"))
	var pill_name := String(loc.call("t", "ITEM_BO_HUYET_DAN_NAME"))
	var manual_name := String(loc.call("t", "ITEM_MANUAL_PHONG_NAME"))
	var robe_name := String(loc.call("t", "ITEM_DAO_BAO_THANH_VAN_NAME"))
	var expected: Array = [
		{"kind": String(GameplayHUD.NOTICE_RESULT), "contains": lesson},
		{"kind": String(GameplayHUD.NOTICE_RESULT), "contains": second},
		{"kind": String(GameplayHUD.NOTICE_PASSIVE), "contains": pill_name},
		{"kind": String(GameplayHUD.NOTICE_PASSIVE), "contains": manual_name},
		{"kind": String(GameplayHUD.NOTICE_PASSIVE), "contains": robe_name},
	]
	var verdict: Dictionary = NoticeSequenceValidator.validate(sequence, expected)
	var ok: bool = (bool(verdict["ok"]) and not hud.notice_backlog_overflowed()
		and diagnostics.is_empty())
	var detail := String(verdict["reason"]) if not bool(verdict["ok"]) else "sequence exact"
	if not diagnostics.is_empty():
		detail += "; MALFORMED NOTICE: " + " / ".join(diagnostics)
	if hud.notice_backlog_overflowed():
		detail += "; BACKLOG OVERFLOWED"
	_record("05d_notices_kept",
		"lesson 1, lesson 2, then pill/manual/robe pickup notices in emission order, "
			+ "each exactly once; no overflow",
		"%s: %s" % [detail, " | ".join(sequence)],
		ok, started, await _shot("05d_band_drained"))


## D-063 A2: what is drawn with mass stops a walk. REAL held move keys walk the player into the
## Lạc Hà stele and spring from two sides each; the walk must stop OUTSIDE the body, the stop must
## still be inside the owner's reach (read / sit), pushing on must hold, walking away must be
## free. Placement at the start of each walk is SETUP.
func _step_physical_truth(map: Node) -> void:
	var player := _player_of(map)
	var stele := map.get_node_or_null("KnowledgeSources/LacHaStele") as KnowledgeSource
	var spring := map.get_node_or_null("CultivationSites/LacHaSpring") as CultivationSite
	if player == null or stele == null or spring == null:
		_record("05e_stele_solid", "player, stele and spring in the hub", "missing", false,
			Time.get_ticks_msec())
		return
	var hud := map.get_node_or_null("GameplayHUD") as GameplayHUD
	# The stele: from the south (its face) and from the east.
	var started := Time.get_ticks_msec()
	var south := await _walk_into(player, stele.global_position + Vector2(0, 48), &"move_up",
		&"move_down", "05e_stele_contact")
	var front_ok: bool = south["stopped"] and float(south["feet"].y) >= stele.global_position.y \
		+ 11.0 and stele.reaches(south["feet"])
	var nothing_new := String(root.get_node("Localization").call("t", "UI_KNOWLEDGE_NOTHING_NEW"))
	player.global_position = south["feet"]  # SETUP: back at the contact point to read
	await physics_frame
	var read := await _time_feedback(&"interact", func() -> bool:
		return hud != null and hud.notice_text() == nothing_new)
	var east := await _walk_into(player, stele.global_position + Vector2(56, -2), &"move_left",
		&"move_right")
	var side_ok: bool = east["stopped"] and float(east["feet"].x) >= stele.global_position.x \
		+ 23.0 and stele.reaches(east["feet"])
	_record("05e_stele_solid",
		"walks stop OUTSIDE the plinth (S, E), inside its reach; push holds; leaving is free; "
			+ "E answers <= %d frames" % FEEDBACK_MAX_FRAMES,
		"S: %s | E: %s | read: frames=%d ms=%.1f" % [_walk_note(south, stele.global_position),
			_walk_note(east, stele.global_position), read["frames"], read["ms"]],
		front_ok and side_ok and _held_and_free(south) and _held_and_free(east)
			and _within(read), started, south["shot"])
	# The spring: from the south (the bank the player sits on) and from the north.
	started = Time.get_ticks_msec()
	var bank := await _walk_into(player, spring.global_position + Vector2(0, 56), &"move_up",
		&"move_down", "05f_spring_contact")
	var far_bank := await _walk_into(player, spring.global_position + Vector2(0, -48),
		&"move_down", &"move_up", "05f_spring_far_bank")
	var bank_ok: bool = bank["stopped"] and float(bank["feet"].y) >= spring.global_position.y \
		+ 23.0 and spring.reaches(bank["feet"])
	var far_ok: bool = far_bank["stopped"] and float(far_bank["feet"].y) \
		<= spring.global_position.y - 11.0 and spring.reaches(far_bank["feet"])
	_record("05f_spring_solid",
		"walks stop OUTSIDE the ring of stones (S, N), inside the sitting radius; push holds; "
			+ "leaving is free",
		"S: %s | N: %s" % [_walk_note(bank, spring.global_position),
			_walk_note(far_bank, spring.global_position)],
		bank_ok and far_ok and _held_and_free(bank) and _held_and_free(far_bank), started,
		bank["shot"])


## D-063 A2b: the decor drawn with mass is solid too — a REAL held key walks the player into a
## banner pole, a lantern post, a planter and a rock in the hub. Where the walk must stop is read
## from each prop's OWN PropData (its footprint's edge plus the player's box), never typed here.
func _step_decor_solid(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var player := _player_of(map)
	if player == null:
		_record("05g_decor_solid", "a player in the hub", "missing", false, started)
		return
	# [decor node, approach side, the key toward it, the key back]
	var cases := [["Visual/Decor/BannerW", Vector2.DOWN, &"move_up", &"move_down"],
		["Visual/Decor/PlanterW", Vector2.DOWN, &"move_up", &"move_down"],
		["Visual/Decor/RockN", Vector2.DOWN, &"move_up", &"move_down"],
		["Visual/Decor/LanternN", Vector2.LEFT, &"move_right", &"move_left"]]
	var notes: Array[String] = []
	var ok := true
	var shot := ""
	for entry in cases:
		var decor := map.get_node_or_null(String(entry[0])) as Node2D
		var body := decor.get_node_or_null("Body") as PropBody if decor != null else null
		if body == null or body.prop == null:
			notes.append("%s: NO BODY" % entry[0])
			ok = false
			continue
		var side: Vector2 = entry[1]
		var foot := body.prop.footprint
		var walk := await _walk_into(player, decor.global_position + side * 48.0, entry[2],
			entry[3], "05g_%s_contact" % decor.name if shot == "" else "")
		if shot == "":
			shot = walk["shot"]
		var rel: Vector2 = walk["feet"] - decor.global_position
		# The nearest the feet may come: the footprint's edge plus the player's box (18 x 12, its
		# top 12 px above the feet), less the physics margin.
		var outside := rel.y >= foot.end.y + 12.0 - 0.5 if side == Vector2.DOWN \
			else rel.x <= foot.position.x - 9.0 + 0.5
		var good: bool = walk["stopped"] and outside and _held_and_free(walk)
		ok = ok and good
		notes.append("%s %s" % [decor.name, _walk_note(walk, decor.global_position)])
	_record("05g_decor_solid",
		"each decor walk stops OUTSIDE its footprint; push holds; leaving is free",
		" | ".join(notes), ok, started, shot)


## SETUP the start, then a REAL held key until the body stops (6 still physics frames); then
## push on for 20 frames and walk back for 30. Returns where it stopped and what each phase did.
func _walk_into(player: Node2D, start: Vector2, toward: StringName, back: StringName,
		shot_name: String = "") -> Dictionary:
	player.global_position = start
	for _i in 4:
		await physics_frame
	await RenderingServer.frame_post_draw
	_send_key(toward, true)
	var last := player.global_position
	var still := 0
	var stopped := false
	for _i in POLL_FRAMES:
		await physics_frame
		still = still + 1 if player.global_position.distance_to(last) < 0.05 else 0
		last = player.global_position
		if still >= 6:
			stopped = true
			break
	var feet := player.global_position
	# The CONTACT frame, taken while the key is still held against the body.
	var shot := await _shot(shot_name) if shot_name != "" else ""
	for _i in 20:
		await physics_frame
	var pushed := player.global_position.distance_to(feet)
	_send_key(toward, false)
	await RenderingServer.frame_post_draw
	_send_key(back, true)
	for _i in 30:
		await physics_frame
	_send_key(back, false)
	await physics_frame
	return {"stopped": stopped, "feet": feet, "pushed": pushed,
		"left": player.global_position.distance_to(feet), "shot": shot}


func _held_and_free(walk: Dictionary) -> bool:
	return float(walk["pushed"]) < 0.5 and float(walk["left"]) > 8.0


func _walk_note(walk: Dictionary, origin: Vector2) -> String:
	var rel: Vector2 = walk["feet"] - origin
	return "stopped=%s feet=(%+.1f,%+.1f) dist=%.1f pushed=%.2f left=%.1f" % [walk["stopped"],
		rel.x, rel.y, rel.length(), walk["pushed"], walk["left"]]


## Frame pacing of the real window, so a timing PASS can only come from a valid environment.
func _step_environment() -> bool:
	var started := Time.get_ticks_msec()
	var deltas: Array[float] = []
	var t := Time.get_ticks_usec()
	for _i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		deltas.append((now - t) / 1000.0)
		t = now
	deltas.sort()
	var mean := 0.0
	for d in deltas:
		mean += d
	mean /= deltas.size()
	var ok := mean <= PACING_MAX_MEAN_MSEC
	_record("05a_environment", "rendered frames near 60 fps (mean <= %.0f ms)"
			% PACING_MAX_MEAN_MSEC,
		"%s on %s, %s, vsync=%d max_fps=%d: mean=%.2f p95=%.2f max=%.2f ms%s" % [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_video_adapter_name(), str(root.get_visible_rect().size),
			DisplayServer.window_get_vsync_mode(), Engine.max_fps, mean,
			deltas[int(deltas.size() * 0.95)], deltas[-1],
			"" if ok else " — ENVIRONMENT INVALID (locked session? use --disable-vsync "
				+ "--max-fps 60)"],
		ok, started)
	return ok


## From a REAL key press to the first RENDERED frame on which `is_visible` holds: the frame
## count (`Engine.get_frames_drawn`), the wall-clock ms, and that frame as a screenshot.
func _time_feedback(action: StringName, is_visible: Callable) -> Dictionary:
	# Press at a FRAME BOUNDARY, where the OS delivers a real key (the start of a frame's input
	# phase). A synthetic key parsed from INSIDE a physics step is dispatched a frame later with
	# a stale "just pressed" stamp, and `_unhandled_input` never sees it — measured in D-063 A1:
	# the stele was never read. That is a harness artifact a real key cannot produce (L-016).
	await RenderingServer.frame_post_draw
	var drawn := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	_send_key(action, true)
	var frames := -1
	var ms := -1.0
	for _i in POLL_FRAMES:
		await RenderingServer.frame_post_draw
		if bool(is_visible.call()):
			frames = Engine.get_frames_drawn() - drawn
			ms = (Time.get_ticks_usec() - t0) / 1000.0
			break
	var shot := _shot_now("05_%s_visible" % action)
	_send_key(action, false)
	await process_frame
	return {"frames": frames, "ms": ms, "shot": shot}


func _within(timing: Dictionary) -> bool:
	return int(timing["frames"]) >= 0 and int(timing["frames"]) <= FEEDBACK_MAX_FRAMES \
		and float(timing["ms"]) <= FEEDBACK_MAX_MSEC


## SETUP: stand on a pickup until the live InventoryRuntime reports collection.
## Returns {"ok": bool, "reason": String, "pickup_id": StringName}.
## Fails loudly (ok=false) on: missing node, not a WorldItem, empty or unexpected
## pickup_id, already collected before setup, or no collection within 30 physics frames.
## Visibility going false is a secondary signal only — `is_collected()` is the proof.
## Never fakes collection and never writes inventory state directly.
func _walk_onto(map: Node, player: Node2D, path: String,
		expected_id: StringName) -> Dictionary:
	var pickup := map.get_node_or_null(path)
	if pickup == null:
		return {"ok": false, "reason": "missing pickup node at '%s'" % path,
			"pickup_id": &""}
	if not (pickup is WorldItem):
		return {"ok": false,
			"reason": "node at '%s' is %s, not a WorldItem" % [path, pickup.get_class()],
			"pickup_id": &""}
	var pid := StringName((pickup as WorldItem).pickup_id)
	if pid == &"":
		return {"ok": false, "reason": "WorldItem at '%s' has an empty pickup_id" % path,
			"pickup_id": &""}
	if pid != expected_id:
		return {"ok": false,
			"reason": "WorldItem at '%s' has pickup_id '%s', expected '%s'"
				% [path, pid, expected_id],
			"pickup_id": pid}
	var inv := _inventory()
	if inv == null:
		return {"ok": false, "reason": "no live InventoryRuntime", "pickup_id": pid}
	if bool(inv.call("is_collected", pid)):
		return {"ok": false,
			"reason": "pickup_id '%s' already collected before setup — this run cannot "
				% pid + "prove collection",
			"pickup_id": pid}
	var wi := pickup as WorldItem
	if wi.item == null or wi.item.id == &"":
		return {"ok": false,
			"reason": "WorldItem at '%s' has no usable item (id empty)" % path,
			"pickup_id": pid}
	if wi.count < 1:
		return {"ok": false,
			"reason": "WorldItem at '%s' has count %d < 1" % [path, wi.count],
			"pickup_id": pid}
	var item_id := StringName(wi.item.id)
	var expected_count := wi.count
	var count_before := int(inv.call("count_of", item_id))
	player.global_position = (pickup as Node2D).global_position
	for _i in 30:
		await physics_frame
		if bool(inv.call("is_collected", pid)):
			break
	if not bool(inv.call("is_collected", pid)):
		return {"ok": false,
			"reason": "pickup_id '%s' not collected within 30 physics frames" % pid,
			"pickup_id": pid}
	var count_after := int(inv.call("count_of", item_id))
	if count_after != count_before + expected_count:
		return {"ok": false,
			"reason": "pickup_id '%s' collected but count %d -> %d, expected +%d"
				% [pid, count_before, count_after, expected_count],
			"pickup_id": pid}
	return {"ok": true, "reason": "", "pickup_id": pid}


## One-line observed state for a `_walk_onto` result, for the playtest report.
func _describe_setup(result: Dictionary) -> String:
	if bool(result["ok"]):
		return "collected '%s'" % String(result["pickup_id"])
	return "FAILED: %s" % String(result["reason"])


## A REAL movement step: a held direction key, and the player's position must change.
func _step_move(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var player := _player_of(map)
	if player == null:
		_record("06_move", "player realized in the map", "no player", false, started)
		return
	var before := player.global_position
	var moved := await _hold_action(&"move_right", func() -> bool:
		return player.global_position.distance_to(before) > 1.0)
	_record("06_move", "position changes under a real move_right key",
		"moved=%.1fpx" % player.global_position.distance_to(before), moved, started)


## A REAL UI toggle: the sect panel key, and the HUD must report the panel open.
func _step_toggle_panel(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var hud := map.get_node_or_null("GameplayHUD") if map != null else null
	if hud == null or not hud.has_method("is_sect_panel_open"):
		_record("07_sect_panel", "HUD exposes is_sect_panel_open", "not available", false,
			started)
		return
	var opened := await _press_until(&"sect_panel", func() -> bool:
		return bool(hud.call("is_sect_panel_open")))
	var shot := await _shot("07_sect_panel")
	# Close it again so later steps see the normal playfield rather than a covered screen.
	if opened:
		await _press_until(&"sect_panel", func() -> bool:
			return not bool(hud.call("is_sect_panel_open")))
	_record("07_sect_panel", "a real sect_panel key opens the panel",
		"open=%s" % opened, opened, started, shot)


## A REAL attack: the attack key, and a registered target must lose health.
##
## The player is PLACED next to the target first. That step is deterministic setup, not a claim
## about the movement pipeline (step 06 already proved that with a real key), and it is named
## so in the report.
func _step_attack(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var player := _player_of(map)
	var targets: Array = map.call("get_combat_targets") if (
		map != null and map.has_method("get_combat_targets")) else []
	if player == null or targets.is_empty():
		_record("08_attack", "a combat target exists in the map",
			"player=%s targets=%d" % [player != null, targets.size()], false, started)
		return
	var target := targets[0] as Node2D
	if target == null or not target.has_method("get_current_health"):
		_record("08_attack", "the target exposes its health", "unusable target", false, started)
		return
	# --- deterministic setup (NOT an input-pipeline claim) ---
	player.global_position = target.global_position - Vector2(18, 0)
	var attack_component := player.get_node_or_null("AttackComponent")
	if attack_component != null:
		attack_component.call("set_facing", Vector2.RIGHT)
	await _settle()
	var before := int(target.call("get_current_health"))
	# --- the real boundary ---
	var hurt := await _press_until(&"attack", func() -> bool:
		return int(target.call("get_current_health")) < before)
	var after := int(target.call("get_current_health"))
	# The hit flash lasts `UIPalette.HIT_FLASH_SECONDS`, and `_shot()` captures one frame
	# later — so on a frame-starved machine the flash has already decayed and the screenshot
	# shows an untouched target. The shot is still taken, and the effect's STATE at the capture
	# boundary is reported rather than assumed, because a capture that silently lacks the thing
	# its name promises is worse than a missing one (L-034). It is not a PASS condition: a
	# real-time effect cannot be gated on frame pacing without becoming flaky.
	var shot := await _shot("08_attack")
	# Read AFTER the shot: `_shot()` awaits a frame and then grabs the image, so this is the
	# state at the capture boundary.
	#
	# WORDING IS DELIBERATE (D-055 §15). This says the effect was ACTIVE when the frame was
	# taken; it does NOT say the effect is visible in the pixels. Nothing here inspects an
	# image — that is the human reviewer's job, and a tool that claimed otherwise would make
	# the visual gate feel satisfied by a line of text.
	var flashing := _is_flashing(target)
	_record("08_attack", "target health drops after a real attack key",
		"hp %d -> %d, hit_flash_state_active_at_capture=%s [STATE EVIDENCE, not pixel]"
			% [before, after, flashing],
		hurt, started, shot)


## The live `ProgressionRuntime`, or null before a session exists.
func _progression() -> Node:
	var main := root.get_node_or_null("Main")
	if main == null:
		return null
	return main.get_node_or_null("Systems/ProgressionRuntime")


## The player's current level as the RUNTIME reports it, or -1 outside a session. Read through
## the view, which is the same thing the HUD reads — so a disagreement between the report and
## the screen is impossible by construction.
func _progression_level() -> int:
	var progression := _progression()
	if progression == null or not bool(progression.call("is_session_active")):
		return -1
	var view: ProgressionView = progression.call("build_view")
	return view.level if view.available else -1


## The live `InventoryRuntime`, or null before a session exists. The AUTHORITATIVE
## owner of pickup collection state — the harness observes it, never writes it.
func _inventory() -> Node:
	var main := root.get_node_or_null("Main")
	if main == null:
		return null
	return main.get_node_or_null("Systems/InventoryRuntime")


## The player's cumulative XP from the AUTHORITATIVE CharacterState, or -1 outside a session.
##
## Read from the authority rather than from the view on purpose: the view carries
## progress-within-a-level, and the thing worth recording in a playtest log is the total that
## actually persists.
func _progression_xp() -> int:
	var progression := _progression()
	if progression == null or not bool(progression.call("is_session_active")):
		return -1
	var character: CharacterState = progression.call("get_character")
	return character.xp if character != null else -1


## Is the HUD's level-up celebration running right now?
##
## Used the same way `_is_flashing` is: a screenshot named `level_up` that was taken after the
## effect decayed shows an ordinary HUD, and a capture that silently lacks the thing its name
## promises is worse than a missing one (L-034). So what the shot CAUGHT is reported rather
## than assumed, and it is not a pass condition — a real-time effect cannot be gated on frame
## pacing without becoming flaky.
func _is_celebrating() -> bool:
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = router.call("get_current_scene") if router != null else null
	var hud := _find_hud(map)
	if hud == null:
		return false
	var effect: Object = hud.call("level_up_feedback")
	if effect == null:
		return false
	return bool(effect.call("is_celebrating"))


## The `GameplayHUD` in a map's tree, or null.
func _find_hud(node: Node) -> Node:
	if node == null:
		return null
	if node is GameplayHUD:
		return node
	for child in node.get_children():
		# Explicitly typed: a recursive call's return type is not yet resolved, so `:=` would
		# infer Variant and fail the warning-as-error compile (GD001 / L-020).
		var found: Node = _find_hud(child)
		if found != null:
			return found
	return null


## Is this entity wearing a damage flash right now? False when it carries no `DamageFeedback`,
## which is a legitimate scene rather than an error.
func _is_flashing(entity: Node) -> bool:
	var feedback := entity.get_node_or_null("DamageFeedback")
	if feedback == null or not feedback.has_method("is_flashing"):
		return false
	return bool(feedback.call("is_flashing"))


## A REAL map transition: walk into the exit zone and interact.
func _step_enter_field(map: Node) -> void:
	var started := Time.get_ticks_msec()
	var player := _player_of(map)
	var zone := _first_exit_zone(map)
	if player == null or zone == null:
		_record("09_enter_field", "the map declares an exit zone",
			"player=%s zone=%s" % [player != null, zone != null], false, started)
		return
	var from_map := _map_id()
	# --- deterministic setup: stand in the exit zone ---
	player.global_position = zone.global_position
	await _settle()
	# The headless/scripted concession documented in L-016: the Area2D sensor's own signal is
	# emitted so the REAL handler runs. Everything after this is real input.
	zone.emit_signal("body_entered", player)
	await _settle()
	var changed := await _press_until(&"interact", func() -> bool:
		return _map_id() != from_map)
	_record("09_enter_field", "interact changes the active map (was %s)" % from_map,
		"map=%s" % _map_id(), changed, started, await _shot("09_field"))


## The Phase-10 encounter, as a player would meet it: the field is populated, a creature
## hunts, a real attack key kills it, and the corpse stops acting.
##
## Three steps rather than one, so a failure says WHICH part of an encounter broke — "the
## creature never hunted" and "the creature could not be killed" are different bugs with
## different causes, and a single `09_encounter FAILED` would hide that.
func _step_encounter(main: Node) -> void:
	var combat := main.get_node_or_null("Systems/CombatRuntime")
	var started := Time.get_ticks_msec()
	if combat == null:
		_record("10_enemies_spawned", "CombatRuntime exists", "missing", false, started)
		return
	var spawned := int(combat.call("enemy_count"))
	_record("10_enemies_spawned", "the field is populated from data",
		"enemies=%d living=%d" % [spawned, int(combat.call("living_enemy_count"))],
		spawned >= 1, started, await _shot("10_field_enemies"))
	if spawned < 1:
		return

	var enemies: Array = combat.call("enemies")
	var enemy := enemies[0] as Node2D
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = router.call("get_current_scene") if router != null else null
	var player := _player_of(map)
	if enemy == null or player == null:
		_record("11_enemy_hunts", "a creature and a player exist",
			"enemy=%s player=%s" % [enemy != null, player != null], false, started)
		return

	# --- it hunts (deterministic setup: stand where it can see you) ---
	started = Time.get_ticks_msec()
	player.global_position = enemy.global_position + Vector2(70, 0)
	var hunting := false
	var state := "IDLE"
	for _i in POLL_FRAMES:
		await process_frame
		state = String(enemy.call("ai_state_name"))
		if state in ["ALERT", "CHASE", "ATTACK", "RECOVER"]:
			hunting = true
			break
	var hunt_shot := await _shot("11_enemy_hunts")
	_record("11_enemy_hunts", "the creature notices the player and hunts",
		"state=%s" % state, hunting, started, hunt_shot)

	# --- the progression baseline, BEFORE the kill (Phase 11) ---
	# Captured as its own step so the report has an explicit "pre-combat" row to compare the
	# post-kill one against, and so a screenshot exists of the HUD before anything changed.
	started = Time.get_ticks_msec()
	var xp_before := _progression_xp()
	var level_before := _progression_level()
	_record("12_pre_combat_progression", "the HUD shows a level/XP row before the fight",
		"level=%d xp=%d" % [level_before, xp_before],
		level_before >= 1 and xp_before >= 0, started, await _shot("12_pre_combat"))

	# --- MODE A: the player kills it with REAL attack keys ---
	#
	# MODE A is MECHANICAL / DETERMINISTIC evidence (D-055 §13). The creature keeps moving, so
	# the player is re-placed inside reach each round; the SWING is always a real key event.
	# This exists to prove the combat→progression mechanic REPRODUCIBLY, and it is named Mode A
	# in the report so it is never mistaken for evidence about how the game plays. Mode B
	# (step 17) is the player-experience half and does no repositioning at all.
	started = Time.get_ticks_msec()
	var start_hp := int(enemy.call("get_current_health"))
	var attack_component := player.get_node_or_null("AttackComponent")
	for _round in 40:
		if bool(enemy.call("is_dead")):
			break
		player.global_position = enemy.global_position - Vector2(16, 0)
		if attack_component != null:
			attack_component.call("set_facing", Vector2.RIGHT)
		_send_key(&"attack", true)
		await process_frame
		_send_key(&"attack", false)
		for _i in 24:
			await process_frame
			if bool(enemy.call("is_dead")):
				break
	var dead := bool(enemy.call("is_dead"))
	# The level-up celebration is already running by the time the kill is confirmed, so this
	# shot is ALSO the level-up capture — taken while the banner is up rather than after it.
	var kill_shot := await _shot("13_enemy_killed_level_up")
	# STATE, NOT PIXELS (D-055 §15): this reports that the celebration was ACTIVE when the
	# frame was taken. It does not inspect the image and must not be read as "the banner is
	# visible in the PNG" — a human still has to open it.
	var celebrating := _is_celebrating()
	_record("13_enemy_killed", "[MODE A] real attack keys kill the creature",
		"hp %d -> %d dead=%s, celebration_state_active_at_capture=%s [STATE EVIDENCE]" % [
			start_hp, int(enemy.call("get_current_health")), dead, celebrating],
		dead, started, kill_shot)

	# --- THE REWARD: XP and level must have moved, through the real chain ---
	#
	# Polled over a bounded number of frames rather than read immediately: the grant happens
	# on the death signal, and the HUD is refreshed from the resulting event, so the observable
	# effect is a frame or two behind the kill (L-016 — poll the effect, do not bet on a frame).
	#
	# NOTHING here calls a progression mutator. The XP asserted was earned by the attack keys
	# fired above; faking it would make this step evidence of nothing (§29).
	started = Time.get_ticks_msec()
	var xp_after := xp_before
	for _i in POLL_FRAMES:
		await process_frame
		xp_after = _progression_xp()
		if xp_after > xp_before:
			break
	var level_after := _progression_level()
	_record("14_xp_updated", "the kill granted XP to the authoritative CharacterState",
		"xp %d -> %d (level %d -> %d)" % [xp_before, xp_after, level_before, level_after],
		xp_after > xp_before, started, await _shot("14_xp_updated"))
	_record("15_level_up", "the player levelled from the first authored kill",
		"level %d -> %d" % [level_before, level_after],
		level_after > level_before, started)

	# --- AFTER the celebration: the HUD must be clean again ---
	#
	# The one assertion that catches an effect which never terminates — a banner still on
	# screen, or a badge left permanently lit, after the event is over.
	started = Time.get_ticks_msec()
	for _i in POLL_FRAMES:
		await process_frame
		if not _is_celebrating():
			break
	var still_celebrating := _is_celebrating()
	_record("16_post_level", "the level-up effect terminated and the HUD is clean",
		"celebrating=%s level=%d xp=%d" % [
			still_celebrating, _progression_level(), _progression_xp()],
		not still_celebrating, started, await _shot("16_post_level"))

	# --- the corpse stops acting ---
	started = Time.get_ticks_msec()
	var resting := enemy.global_position
	for _i in 60:
		await process_frame
	var still := enemy.global_position.distance_to(resting) < 0.01
	var reset := String(enemy.call("ai_state_name")) == "IDLE"
	_record("17_corpse_inert", "a dead creature stops moving and thinking",
		"moved=%.2fpx state=%s" % [
			enemy.global_position.distance_to(resting), enemy.call("ai_state_name")],
		still and reset, started)


## MODE B — PLAYER EXPERIENCE (D-055 §13-14, §F).
##
## Mode A above proves the MECHANIC reproducibly, and it does so by teleporting the player into
## reach before every swing. That makes it worthless as evidence about how the game PLAYS: a
## build where the player moves at 2px/s, or where the attack has no reach, or where the HUD
## never tells you which key swings, would pass Mode A unchanged.
##
## So this step answers a different question — "could a person actually do this?" — and the
## rules are correspondingly stricter:
##   * the player is placed ONCE, at a distance, and never moved by code again;
##   * the approach is real `move_*` keys;
##   * the swing is the real `attack` key, read off the HUD prompt rather than hard-coded;
##   * the field authors TWO creatures, so this is a fresh one, not the Mode-A corpse.
##
## It also records the DISCOVERABILITY evidence (D-055-G): what the HUD is telling the player
## about how to attack. `attack_display_key` is whatever `InputService` resolves — never the
## literal "J" — so a rebind changes the evidence instead of invalidating it.
func _step_natural_encounter(main: Node) -> void:
	var started := Time.get_ticks_msec()
	var combat := main.get_node_or_null("Systems/CombatRuntime")
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = router.call("get_current_scene") if router != null else null
	var player := _player_of(map)

	# --- the discoverability half: what does the screen say? ---
	var hud := map.get_node_or_null("GameplayHUD") if map != null else null
	var prompt_row := hud.find_child("AttackPrompt", true, false) if hud != null else null
	var input := root.get_node_or_null("InputService")
	var display_key := String(input.call("get_action_display_label", &"attack")) \
		if input != null else ""
	var prompt_visible := prompt_row != null and bool(prompt_row.visible)
	_record("18_attack_is_discoverable",
		"the HUD advertises the basic attack before the player needs it",
		"attack_prompt=%s attack_action=attack attack_display_key=%s" % [
			"visible" if prompt_visible else "ABSENT", display_key],
		prompt_visible and display_key != "", started,
		await _shot("18_attack_prompt"))

	# --- find a LIVING creature for the natural encounter ---
	started = Time.get_ticks_msec()
	var living: Node2D = null
	if combat != null and combat.has_method("enemies"):
		for candidate in combat.call("enemies"):
			var node := candidate as Node2D
			if node == null or not is_instance_valid(node):
				continue
			if node.has_method("is_dead") and bool(node.call("is_dead")):
				continue
			living = node
			break
	if living == null or player == null:
		_record("19_natural_encounter",
			"a second living creature exists for an unassisted encounter",
			"living=%s player=%s (the field authors two; if this fails, one never spawned "
				+ "or Mode A killed both)" % [living != null, player != null],
			false, started)
		return

	# --- place ONCE, then never touch the position again ---
	#
	# This is the ONLY write to `player.global_position` in this step, and the single write is
	# the claim the step makes. `initial_gap_px` is measured HERE, after the placement has
	# settled, because that is the only moment at which "the gap the player started from" is a
	# fact — the creature hunts, so any later distance is a different quantity.
	# `placements` is a REAL count, incremented at the write. Starting it at a literal `1` was
	# the "fake counter" this step was told not to build: it would still have reported 1 after
	# someone added a second write, so the `placements == 1` pass condition could never fail —
	# evidence that cannot be wrong is not evidence.
	var placements := 0
	var approach_from := living.global_position + Vector2(96, 0)
	player.global_position = approach_from
	placements += 1
	await _settle()
	var initial_gap := player.global_position.distance_to(living.global_position)
	var xp_before := _progression_xp()
	var level_before := _progression_level()
	var start_hp := int(living.call("get_current_health"))

	# Walk in with real movement keys, then swing with real attack keys. Both are polled on
	# the observable effect rather than timed (L-016). The two are interleaved because the
	# creature is hunting back — it closes while the player closes, which is the actual
	# experience and the reason this cannot be a fixed script.
	# Deadline-based (not round-count-based): the wolf's real-time lifecycle needs a
	# wall-clock budget generous enough for approach + multiple swings. 45 seconds is
	# ample for the authored encounter at 60fps; the loop exits early on kill.
	var landed := false
	var deadline_msec := Time.get_ticks_msec() + 45000
	var rounds := 0
	while Time.get_ticks_msec() < deadline_msec:
		rounds += 1
		if bool(living.call("is_dead")):
			break
		var gap := player.global_position.distance_to(living.global_position)
		if gap > 20.0:
			# Approach: hold the direction that reduces the gap, for a few frames only, so
			# the loop keeps re-deciding as the creature moves.
			var towards := living.global_position - player.global_position
			var action := &"move_left" if towards.x < 0.0 else &"move_right"
			if absf(towards.y) > absf(towards.x):
				action = &"move_up" if towards.y < 0.0 else &"move_down"
			_send_key(action, true)
			for _i in 6:
				await process_frame
			_send_key(action, false)
			await process_frame
			continue
		_send_key(&"attack", true)
		await process_frame
		_send_key(&"attack", false)
		for _i in 20:
			await process_frame
			if int(living.call("get_current_health")) < start_hp:
				landed = true
			if bool(living.call("is_dead")):
				break
		if landed and bool(living.call("is_dead")):
			break
	var killed := bool(living.call("is_dead"))
	var timed_out := Time.get_ticks_msec() >= deadline_msec and not killed
	var final_gap := player.global_position.distance_to(living.global_position)
	var shot := await _shot("19_natural_encounter")
	# EVIDENCE, separated by what produced it. The previous version reported one number called
	# `placed_once_at`, computed as `approach_from.distance_to(living.global_position)` AFTER
	# the fight — the distance from the frozen placement POINT to where the creature had since
	# walked to. That is neither the initial gap nor the final one, and naming it after the
	# placement made a derived hybrid look like setup evidence (L-034: a report that quietly
	# mislabels its own measurement is worse than one that omits it).
	#
	#   setup     — placements: how many times the harness wrote a position (must be 1)
	#               initial_gap_px: the gap right after that single placement
	#   movement  — final_gap_px: the gap at capture, closed by REAL move_* keys and by the
	#               creature's own hunting; it differs from the initial gap precisely because
	#               neither side was teleported
	#   attack    — landed / killed, from REAL attack keys
	_record("19_natural_encounter",
		"[MODE B] the player closes the distance and kills with NO repositioning by code",
		("setup{placements=%d initial_gap_px=%.0f} movement{final_gap_px=%.0f} "
			+ "attack{hp %d -> %d landed=%s killed=%s rounds=%d timed_out=%s}") % [
			placements, initial_gap, final_gap, start_hp,
			int(living.call("get_current_health")), landed, killed, rounds, timed_out],
		landed and killed and placements == 1 and not timed_out, started, shot)

	# The reward must move again — a second payment, proving the ledger pays per SPAWN rather
	# than once per session.
	started = Time.get_ticks_msec()
	var xp_after := xp_before
	for _i in POLL_FRAMES:
		await process_frame
		xp_after = _progression_xp()
		if xp_after > xp_before:
			break
	_record("20_natural_reward",
		"the unassisted kill pays again (the ledger is per spawn, not per session)",
		"xp %d -> %d (level %d -> %d) killed=%s" % [
			xp_before, xp_after, level_before, _progression_level(), killed],
		xp_after > xp_before if killed else true, started,
		await _shot("20_natural_reward"))

	# And the player can keep playing: movement still works after the encounter.
	started = Time.get_ticks_msec()
	var before_move := player.global_position
	var moved := await _hold_action(&"move_right", func() -> bool:
		return player.global_position.distance_to(before_move) > 1.0)
	_record("21_play_continues", "the player can keep moving after the encounter",
		"moved=%.1fpx" % player.global_position.distance_to(before_move), moved, started)


func _step_return_to_menu(main: Node) -> void:
	var started := Time.get_ticks_msec()
	var gs := root.get_node_or_null("GameState")
	# Esc ASKS (D-068): the question must appear, and only the confirm key leaves.
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = router.call("get_current_scene") if router != null else null
	var hud := map.get_node_or_null("GameplayHUD") as GameplayHUD if map != null else null
	var asked := hud != null and await _press_until(&"open_menu", func() -> bool:
		return hud.session_prompt_kind() == GameplayHUD.PROMPT_LEAVE)
	var still_running := gs != null and bool(gs.call("is_session_active"))
	await _shot("22_leave_question")
	var back := asked and still_running and await _press_until(&"interact", func() -> bool:
		return gs != null and not bool(gs.call("is_session_active")))
	var teardown: Array = main.call("get_last_teardown_order") if main.has_method(
		"get_last_teardown_order") else []
	_record("22_return_to_menu", "Esc asks, the confirm key ends the session",
		"session_active=%s teardown=%s" % [
			gs != null and bool(gs.call("is_session_active")), str(teardown)],
		back, started, await _shot("22_menu"))


# === Real semantic input =====================================================

## Press `action` (a real key event for its binding) and poll `is_done` until it is true.
##
## Polls the OBSERVABLE EFFECT over a bounded number of frames instead of betting on a single
## frame: after a synthetic press, `is_action_just_pressed` timing is fragile in a scripted run
## (L-016), and an attack's effect lands a windup later anyway.
func _press_until(action: StringName, is_done: Callable) -> bool:
	if not InputMap.has_action(action):
		return false
	for _attempt in 8:
		_send_key(action, true)
		await process_frame
		_send_key(action, false)
		for _i in int(POLL_FRAMES / 8.0):
			await process_frame
			if bool(is_done.call()):
				return true
	return false


## Hold `action` down for up to `POLL_FRAMES`, releasing as soon as `is_done` is true.
## For continuous input (movement), where one press-release pair may move nothing visible.
func _hold_action(action: StringName, is_done: Callable) -> bool:
	if not InputMap.has_action(action):
		return false
	_send_key(action, true)
	var done := false
	for _i in POLL_FRAMES:
		await process_frame
		if bool(is_done.call()):
			done = true
			break
	_send_key(action, false)
	await process_frame
	return done


## Feed a real `InputEventKey` for the first physical key bound to `action`, through the engine,
## so the InputMap action state updates and `_input`/`_unhandled_input` dispatch exactly as a
## real key press does.
func _send_key(action: StringName, pressed: bool) -> void:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var synthetic := InputEventKey.new()
		synthetic.physical_keycode = key.physical_keycode
		synthetic.keycode = key.keycode
		synthetic.pressed = pressed
		Input.parse_input_event(synthetic)
		Input.flush_buffered_events()
		return


# === Observation helpers =====================================================

func _menu_of(main: Node) -> Node:
	var ui := main.get_node_or_null("UI")
	if ui == null or ui.get_child_count() == 0:
		return null
	return ui.get_child(0)


func _buttons_of(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node == null:
		return out
	if node is Button:
		out.append(node as Button)
	for child in node.get_children():
		out += _buttons_of(child)
	return out


func _player_of(map: Node) -> Node2D:
	if map == null:
		return null
	# Explicitly typed: `call()` returns Variant, and `:=` would infer Variant — which this
	# project promotes to a compile error (L-020).
	var host: Variant = map.call("get_player_host") if map.has_method(
		"get_player_host") else null
	if not (host is Node):
		return null
	for child in (host as Node).get_children():
		var body := child as Node2D
		if body != null and body.has_method("get_attack_power"):
			return body
	return null


func _first_exit_zone(map: Node) -> Node2D:
	var exits := map.get_node_or_null("Exits") if map != null else null
	if exits == null:
		return null
	for child in exits.get_children():
		var zone := child as Node2D
		if zone != null:
			return zone
	return null


## The id of the active map, as the ROUTER reports it (not as the scene is named), so the
## observed value is the one the game's own navigation state holds.
func _map_id() -> String:
	var router := root.get_node_or_null("SceneRouter")
	if router == null:
		return ""
	return String(router.call("get_current_key"))


## A compact description of what the UI is showing, for the report's `ui` column.
func _ui_state() -> String:
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = router.call("get_current_scene") if router != null else null
	if map == null:
		return "menu"
	var hud := map.get_node_or_null("GameplayHUD")
	if hud == null:
		return "map(no hud)"
	var parts: Array[String] = ["hud"]
	if hud.has_method("is_sect_panel_open") and bool(hud.call("is_sect_panel_open")):
		parts.append("sect_panel")
	if hud.has_method("is_health_gauge_visible") and bool(
			hud.call("is_health_gauge_visible")):
		parts.append("health")
	return "+".join(parts)


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


## The frame JUST drawn (call right after `frame_post_draw`), so the shot is the very frame the
## timing step measured — not one later.
func _shot_now(shot_name: String) -> String:
	var image := root.get_texture().get_image()
	if image == null:
		_errors += 1
		push_error("[playtest] viewport produced no image for '%s'" % shot_name)
		return ""
	var size := root.get_visible_rect().size
	var file := "%s_%dx%d_%s.png" % [_language, int(size.x), int(size.y), shot_name]
	if image.save_png("%s/%s" % [_out_dir, file]) != OK:
		_errors += 1
		push_error("[playtest] could not write %s" % file)
		return ""
	_shots.append(file)
	return file


## Write the current viewport and return the filename (empty on failure, which also counts as
## an error — a report that silently lacks its evidence is worse than a loud one).
func _shot(shot_name: String) -> String:
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		_errors += 1
		push_error("[playtest] viewport produced no image for '%s'" % shot_name)
		return ""
	var size := root.get_visible_rect().size
	var file := "%s_%dx%d_%s.png" % [
		_language, int(size.x), int(size.y), shot_name]
	if image.save_png("%s/%s" % [_out_dir, file]) != OK:
		_errors += 1
		push_error("[playtest] could not write %s" % file)
		return ""
	_shots.append(file)
	return file


func _record(
		step: String,
		expected: String,
		observed: String,
		ok: bool,
		started_msec: int,
		shot: String = "") -> void:
	if not ok:
		_errors += 1
	_steps.append({
		"step": step,
		"expected": expected,
		"observed": observed,
		"ok": ok,
		"msec": Time.get_ticks_msec() - started_msec,
		"shot": shot,
		"map": _map_id(),
		"ui": _ui_state(),
		# Progression state on EVERY step, not only the progression ones (Phase 11).
		# The brief asks for XP/level before and after; recording it on every step gives that
		# for free from any two adjacent rows, and it also answers the question that is
		# actually hard to debug afterwards — "when did this number change?" — without having
		# to guess which step to instrument.
		"level": _progression_level(),
		"xp": _progression_xp(),
	})


func _failed_count() -> int:
	var failed := 0
	for entry in _steps:
		if not bool(entry["ok"]):
			failed += 1
	return failed


# === Report ==================================================================

## Write both a human-readable report to stdout and a machine-readable JSON file.
##
## A failure must name the exact step, with expected and observed side by side. "PLAYTEST
## FAILED" is useless; "step=09_enter_field expected=map_field observed=map_hub" is actionable.
func _write_report() -> void:
	var failed := _failed_count()
	print("\n=== AETHERIA PLAYTEST REPORT ===")
	print("language=%s  viewport=%dx%d  steps=%d  failed=%d  errors=%d  warnings=%d" % [
		_language, int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y),
		_steps.size(), failed, _errors, _warnings])
	print("output=%s" % _out_dir)
	print("")
	for entry in _steps:
		print("[%s] %-28s %6dms  map=%-10s ui=%-20s lv=%-3s xp=%-6s" % [
			"PASS" if bool(entry["ok"]) else "FAIL", entry["step"], int(entry["msec"]),
			entry["map"], entry["ui"], str(entry.get("level", -1)),
			str(entry.get("xp", -1))])
		print("       expected: %s" % entry["expected"])
		print("       observed: %s" % entry["observed"])
		if String(entry["shot"]) != "":
			print("       shot:     %s" % entry["shot"])
	if failed > 0:
		print("\nPLAYTEST FAILED")
		for entry in _steps:
			if not bool(entry["ok"]):
				print("  step=%s expected=%s observed=%s" % [
					entry["step"], entry["expected"], entry["observed"]])
	else:
		print("\nPLAYTEST PASSED — %d step(s), %d screenshot(s)" % [
			_steps.size(), _shots.size()])

	_print_scorecard()

	var payload := {
		"language": _language,
		"viewport": [
			int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y)],
		"steps": _steps,
		"failed": failed,
		"errors": _errors,
		"warnings": _warnings,
		"shots": _shots,
	}
	var path := "%s/playtest_report.json" % _out_dir
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[playtest] could not write %s" % path)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("\nreport: %s" % path)


## The UX scorecard SECTION — deliberately a prompt, not a computed score.
##
## A number this tool invented would be worthless: nothing here can measure whether a screen is
## legible or whether an encounter is readable. What the tool CAN do is refuse to let the
## question go unasked, and name the artefacts the reviewer has to look at. The scores and the
## defect list belong in the phase report, written by whoever looked at the screenshots
## (`docs/PHASE_EXECUTION_PROTOCOL.md` §3) — and `B8`: a screenshot-producing tool is not a
## screenshot-reviewing tool.
func _print_scorecard() -> void:
	print("\n--- AI UX SCORECARD (fill in by LOOKING at the shots above, 1-5) ---")
	for dimension in [
		"CLARITY", "HIERARCHY", "RESPONSIVENESS", "PIXEL SHARPNESS", "LOCALIZATION",
		"VISUAL CONSISTENCY", "MOTION / FEEDBACK", "SPACING", "READABILITY",
		"PLAYER CONFIDENCE",
	]:
		print("  %-20s _/5" % dimension)
	print("  CONCRETE DEFECTS: list them; a score <= 3 REQUIRES at least one.")
	print("  %d screenshot(s) to inspect in %s" % [_shots.size(), _out_dir])

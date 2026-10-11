extends RefCounted
class_name RunKit
## RunKit — starting a run in a test or a tool whose SUBJECT is something else (Phase 20).
##
## Since D-072 New Game opens the identity screen, and a run opens on its Origin's vignette.
## Both have their own real-input E2E (`tests/e2e/story_flow_case.gd`). A flow about the shop,
## a quest or the pet has no business re-proving them, and must not be changed by them either
## — so this is the ONE sanctioned piece of non-player setup for getting past them, and it
## says what it does: the menu's own intent is emitted, the identity screen's own `confirmed`
## is emitted, and the scenes are stepped past through the story owner's own `skip_scene`.
##
## THE DEFAULT ORIGIN IS THE QUIET ONE. `origin_nghe_nhan` starts with one piece of knowledge
## and nothing else: no item in the bag, no first impression on anyone. Older flows count bag
## items and read shop prices, and an Origin that moved either would change what they measure.

const DEFAULT_ORIGIN := &"origin_nghe_nhan"


## New Game → identity (confirmed as `origin_id` and `appearance_id`; empty = the quiet
## default and the first look) → past the opening scenes. Returns false when the identity
## screen never appeared.
static func begin_run(main: Node, tree: SceneTree, origin_id: StringName = DEFAULT_ORIGIN,
		appearance_id: StringName = &"") -> bool:
	var menu := menu_of(main)
	if menu == null or not menu.has_signal("new_game_pressed"):
		return false
	menu.emit_signal("new_game_pressed")
	await tree.process_frame
	var identity := identity_of(main)
	if identity == null:
		return false
	var look: StringName = appearance_id if appearance_id != &"" \
		else StringName(identity.call("selected_appearance_id"))
	identity.emit_signal("confirmed", look, origin_id)
	await tree.process_frame
	skip_scenes(main)
	await tree.process_frame
	return true


static func menu_of(main: Node) -> Node:
	for child in main.get_node("UI").get_children():
		if not child.is_queued_for_deletion() and child.has_signal("new_game_pressed"):
			return child
	return null


## The identity screen while it is open, or null.
static func identity_of(main: Node) -> Node:
	for child in main.get_node("UI").get_children():
		if not child.is_queued_for_deletion() and child.has_signal("confirmed") \
				and child.has_method("selected_origin_id"):
			return child
	return null


static func story_of(main: Node) -> StoryRuntime:
	return main.get_node_or_null("Systems/StoryRuntime") as StoryRuntime


## SETUP, not proof: record that the elder has issued the outpost's blade, coat and primer,
## so a flow that is not about the story can walk onto them. The real path — asking him, with
## real keys — is proved once, in the Story E2E.
static func take_outpost_issue(main: Node) -> bool:
	var story := story_of(main)
	return story != null and story.set_flag(&"flag_outpost_issue", 1).ok


## SETUP, not proof: record that the vein has broken, so a flow that is not about the story
## finds what the rupture spilled in the woods (the thunder manual). The real path — walking
## into the Night — is the Story E2E's.
static func stage_the_rupture(main: Node) -> bool:
	var story := story_of(main)
	return story != null and story.set_flag(&"flag_vein_broke", 1).ok


## Step past every story scene now queued (a scene changes nothing; see `StoryRuntime`).
static func skip_scenes(main: Node) -> int:
	var story := story_of(main)
	var skipped := 0
	while story != null and story.is_session_active() and story.is_scene_playing() \
			and skipped < 16:
		story.skip_scene()
		skipped += 1
	return skipped

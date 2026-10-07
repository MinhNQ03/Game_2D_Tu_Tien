extends TestCase
## Unit tests for `DamageFeedback` — the Phase-10 review-pass component that makes TAKING a
## hit, and dying, visible (the review scored combat readability 4/5 because damage left no
## mark on the thing damaged, and the corpse look it later absorbed was a raw `Color(...)`
## literal inside a gameplay entity).
##
## These drive the REAL boundary the component advertises: damage is applied through a REAL
## `HurtboxComponent.apply_hit()`, so the `damaged` signal is emitted by the code that actually
## emits it in play. Nothing calls `_on_damaged` directly — that would prove the handler works
## while saying nothing about whether it is ever reached (L-017).
##
## The flash decays on an explicit clock rather than a `Tween` precisely so a headless test can
## step it; `advance()` is the public seam for that, exactly as
## `CharacterVisualComponent.advance()` is.
##
## Every `Node` built here is freed by the test that built it (L-019).

const FeedbackScript := preload("res://src/presentation/combat/damage_feedback.gd")
const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")

## The map floor a corpse lies on, and every sprite that can wear the corpse look. Listed
## because each is a DIFFERENT brightness — the wolf and the post sit near 0.49 and the player
## near 0.60, so a tint that works for one can erase another.
## The floors a body can actually fall on (D-062): every shipped map's PAINTED floor, measured
## per 16px cell — the old tile sheet is no longer under anyone's feet.
const FLOOR_LAYOUTS := [
	"res://data/maps/ground/lac_ha_ground.tres",
	"res://data/maps/ground/vo_mach_ground.tres",
]
const FLOOR_TILE_SIZE := 16
const CORPSE_WEARER_TEXTURES := [
	"res://assets/sprites/enemies/mist_wolf_idle.png",
	"res://assets/sprites/props/world/training_post.png",
	"res://assets/sprites/characters/player_proto.png",
]


## The minimum entity this component reacts to: it has health, it can die, it says so, and it
## is a `CanvasItem` so it has a `modulate` to drive. Deliberately NOT the real `Player` or
## `Enemy` — this file tests the component, and the real scenes' wiring is proved by the
## integration test that spawns `enemy.tscn` from the shipped spawn table.
class StubEntity extends Node2D:
	signal died()
	signal health_changed(current: int, maximum: int)

	var hp: int = 40

	func get_defense() -> int:
		return 0

	func is_dead() -> bool:
		return hp <= 0

	## Mirrors `HealthComponent`'s ORDER, which the component depends on: the new health is
	## reported first, then death. A stub that emitted them the other way round would let a
	## real ordering bug pass.
	func take_damage(amount: int) -> int:
		if hp <= 0 or amount <= 0:
			return 0
		var before := hp
		hp = maxi(0, hp - amount)
		health_changed.emit(hp, 40)
		if hp == 0:
			died.emit()
		return before - hp

	## Mirrors `TrainingDummy.reset_dummy()` — a new life, announced by `health_changed`.
	func revive() -> void:
		hp = 40
		health_changed.emit(hp, 40)


## An entity carrying a real hurtbox and a real feedback node, in the tree, ready to be hit.
func _entity() -> StubEntity:
	var entity := StubEntity.new()
	entity.name = "StubEntity"
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"stub"
	hurtbox.radius = 10.0
	entity.add_child(hurtbox)
	var feedback: DamageFeedback = FeedbackScript.new()
	feedback.name = "DamageFeedback"
	entity.add_child(feedback)
	add_to_tree(entity)
	return entity


func _feedback(entity: StubEntity) -> DamageFeedback:
	return entity.get_node("DamageFeedback") as DamageFeedback


func _hurtbox(entity: StubEntity) -> HurtboxComponent:
	return entity.get_node("HurtboxComponent") as HurtboxComponent


# === Being hit ==============================================================

## The point of the whole component: a hit CHANGES how the entity looks, immediately.
##
## Asserting "the tint differs from resting" rather than "the tint equals X" is deliberate — a
## palette change must not break this test, but a flash that renders nothing must.
func test_a_landed_hit_visibly_changes_the_entity_then_decays_back() -> void:
	var entity := _entity()
	var feedback := _feedback(entity)
	var resting := feedback.resting_tint()
	assert_eq(entity.modulate, resting, "it starts at its resting colour")
	assert_false(feedback.is_flashing(), "and nothing is flashing")

	_hurtbox(entity).apply_hit(6, false)
	assert_true(feedback.is_flashing(), "the hit started a flash")
	assert_ne(entity.modulate, resting,
		"and the entity LOOKS different the instant it is hit (%s vs resting %s)"
			% [str(entity.modulate), str(resting)])

	# Half way through: still tinted, but closer to resting than it was. A flash that holds one
	# colour and then snaps back reads as a glitch; the decay is the effect.
	feedback.advance(UIPalette.HIT_FLASH_SECONDS * 0.5)
	var midway := entity.modulate
	assert_ne(midway, resting, "it is still tinted half way through")
	assert_true(midway.r < UIPalette.HIT_FLASH_TINT.r,
		"and it has started decaying (%.3f < %.3f)" % [midway.r, UIPalette.HIT_FLASH_TINT.r])

	# Past the end: exactly resting, not merely near it, so repeated hits cannot accumulate a
	# residual tint over a fight.
	feedback.advance(UIPalette.HIT_FLASH_SECONDS)
	assert_eq(entity.modulate, resting,
		"it lands exactly on its resting colour (%s)" % str(entity.modulate))
	assert_false(feedback.is_flashing(), "and the flash is over")
	free_node(entity)


## A CRITICAL hit looks different from a normal one. `HurtboxComponent.damaged` carries
## `is_critical` for exactly this reason, and crits are reachable in shipped content (15% on
## the player's basic attack, 10% on the wolf's bite) — so this is a distinction real play
## produces, not a hypothetical configuration (L-029).
func test_a_critical_hit_is_distinguishable_from_a_normal_one() -> void:
	var normal := _entity()
	_hurtbox(normal).apply_hit(6, false)
	var normal_tint := normal.modulate

	var critical := _entity()
	_hurtbox(critical).apply_hit(9, true)
	var critical_tint := critical.modulate

	assert_ne(normal_tint, critical_tint,
		"a crit does not look like a normal hit (%s vs %s)"
			% [str(critical_tint), str(normal_tint)])
	assert_true(critical_tint.g > normal_tint.g,
		("the crit tint is the brighter, warmer one — the rarer event reads as the bigger "
			+ "one (%.2f > %.2f)") % [critical_tint.g, normal_tint.g])
	free_node(normal)
	free_node(critical)


## `modulate` is a MULTIPLY, so a tint built only from values <= 1 can only DARKEN. That is
## legible on the player's pale robe and nearly invisible on a dark creature, which is why both
## tints push a channel past 1.0. Pinning it here keeps a later palette tidy-up from quietly
## clamping the flash into invisibility on half the cast.
func test_the_flash_tints_brighten_rather_than_only_darken() -> void:
	var normal := UIPalette.HIT_FLASH_TINT
	var critical := UIPalette.HIT_FLASH_TINT_CRITICAL
	assert_true(maxf(normal.r, maxf(normal.g, normal.b)) > 1.0,
		"the normal flash brightens at least one channel (%s)" % str(normal))
	assert_true(maxf(critical.r, maxf(critical.g, critical.b)) > 1.0,
		"so does the critical flash (%s)" % str(critical))
	assert_true(normal.r > normal.g and normal.r > normal.b,
		"the normal flash keeps the crimson hue (%s)" % str(normal))


## A hit that applied NOTHING must not flash. An absorbed hit that still lights the entity up
## tells the player they were damaged when they were not, which is worse than no feedback.
func test_a_hit_that_applied_no_damage_does_not_flash() -> void:
	var entity := _entity()
	var feedback := _feedback(entity)
	var resting := feedback.resting_tint()
	# `apply_hit(0, …)` returns 0 applied, so `damaged` never fires at all; drive the signal
	# directly as well, so the component's own guard is exercised and not just the hurtbox's.
	assert_eq(_hurtbox(entity).apply_hit(0, false), 0, "nothing was applied")
	_hurtbox(entity).damaged.emit(0, false, Vector2.ZERO)
	assert_false(feedback.is_flashing(), "a zero-damage hit starts no flash")
	assert_eq(entity.modulate, resting, "and leaves the entity looking untouched")
	free_node(entity)


# === Dying ==================================================================

## A corpse must be MARKED, by this node and not by the entity. `Enemy._on_health_died()` used
## to set a literal colour on itself; the entity now only reports that it died.
func test_death_marks_the_entity_with_the_palette_corpse_look() -> void:
	var entity := _entity()
	var feedback := _feedback(entity)
	entity.take_damage(entity.hp)
	assert_true(entity.is_dead(), "it died")
	assert_true(feedback.is_corpse(), "and it is wearing its corpse look")
	assert_eq(entity.modulate, UIPalette.CORPSE_TINT,
		"which is the PALETTE token, so an art pass can change it (%s)" % str(entity.modulate))
	free_node(entity)


## The KILLING blow must not flash. `died` fires before the hurtbox reports the damage (health
## applied -> `died` -> `damaged`), so a flash here would paint over the corpse look and then
## "restore" a colour that is no longer the truth — the L-023 mistake in miniature.
func test_the_killing_blow_does_not_flash_over_the_death_look() -> void:
	var entity := _entity()
	var feedback := _feedback(entity)
	entity.hp = 3
	_hurtbox(entity).apply_hit(3, false)
	assert_true(entity.is_dead(), "the hit killed it")
	assert_false(feedback.is_flashing(),
		"the killing blow starts no flash — the death look owns the sprite now")
	assert_eq(entity.modulate, UIPalette.CORPSE_TINT, "and the corpse look is what shows")

	feedback.advance(UIPalette.HIT_FLASH_SECONDS * 4.0)
	assert_eq(entity.modulate, UIPalette.CORPSE_TINT,
		"nothing writes over it afterwards, however long the world runs (%s)"
			% str(entity.modulate))
	free_node(entity)


## A flash ALREADY RUNNING when the entity dies is abandoned, rather than finishing its decay
## and restoring the living colour over a corpse.
func test_a_flash_in_flight_is_abandoned_when_the_entity_dies() -> void:
	var entity := _entity()
	var feedback := _feedback(entity)
	entity.hp = 20
	_hurtbox(entity).apply_hit(5, false)
	assert_true(feedback.is_flashing(), "a flash is in flight")

	entity.take_damage(entity.hp)
	assert_false(feedback.is_flashing(), "the flash gave up when the entity died")
	feedback.advance(UIPalette.HIT_FLASH_SECONDS * 2.0)
	assert_eq(entity.modulate, UIPalette.CORPSE_TINT,
		"leaving the death look intact rather than restoring a living colour (%s)"
			% str(entity.modulate))
	free_node(entity)


## The corpse look is cleared ONLY by a revival — a new life, which is what
## `TrainingDummy.reset_dummy()` is. An ordinary hit also reports a new health value, and
## reacting to that would cut the flash short.
func test_only_a_revival_clears_the_corpse_look() -> void:
	var entity := _entity()
	var feedback := _feedback(entity)
	var resting := feedback.resting_tint()

	# An ordinary hit reports health too, and must not be mistaken for a revival.
	_hurtbox(entity).apply_hit(6, false)
	assert_true(feedback.is_flashing(),
		"a hit reports its new health and the flash still survives it")
	feedback.advance(UIPalette.HIT_FLASH_SECONDS)

	entity.take_damage(entity.hp)
	assert_true(feedback.is_corpse(), "it is a corpse")
	entity.revive()
	assert_false(feedback.is_corpse(), "a new life clears the corpse look")
	assert_eq(entity.modulate, resting,
		"and restores the living colour (%s)" % str(entity.modulate))
	free_node(entity)


## The corpse look is RE-MEASURED from the actual art, for every entity that wears it.
##
## Two previous values failed this, and the second one failed it while CITING the rule it
## broke. A corpse is composited as `sprite * tint.rgb * tint.a + floor * (1 - tint.a)`;
## `0.55, 0.55, 0.62 @ 0.75` landed 0.009 luminance from the floor and
## `0.62, 0.66, 0.80 @ 0.80` landed 0.014 — corpses a greyscale view cannot see at all. The
## second one looked better in a playtest capture purely because it was blue against green, so
## the entire signal rested on hue, which is exactly what "colour is never the only carrier"
## forbids.
##
## So this asserts the two luminance margins, derived from the PNGs rather than trusted from a
## comment, for each of the three entities that can die. A brighter floor or a darker creature
## then fails loudly instead of quietly erasing the body (L-034).
func test_the_corpse_look_clears_both_the_floor_and_the_living_sprite() -> void:
	# PER CELL, not the floor's mean: a corpse lands on one place, and averaging the floor is
	# averaging away the worst case. Every walkable cell of every painted floor is measured
	# (open water is excluded: nothing can lie there), deduplicated to distinct cell colours.
	var floor_tiles := _floor_fill_tiles()
	assert_true(floor_tiles.size() >= 20,
		"the painted floors' cells were measured (got %d distinct)" % floor_tiles.size())
	for path in CORPSE_WEARER_TEXTURES:
		var live := _mean_opaque_rgb(path)
		var live_lum := _luminance(live)
		var name := String(path).get_file()
		for index in floor_tiles.size():
			var tile: Color = floor_tiles[index]
			var tile_lum := _luminance(tile)
			var corpse_lum := _luminance(_composite_corpse(live, tile))
			assert_true(absf(corpse_lum - tile_lum) >= UIPalette.CORPSE_MIN_FLOOR_CONTRAST,
				("%s on floor tile %d: a corpse must stand clear of the FLOOR in luminance, "
					+ "so a body is visible without relying on hue — corpse %.3f vs floor "
					+ "%.3f is %.3f apart, needs %.2f") % [name, index, corpse_lum, tile_lum,
						absf(corpse_lum - tile_lum), UIPalette.CORPSE_MIN_FLOOR_CONTRAST])
			assert_true(absf(corpse_lum - live_lum) >= UIPalette.CORPSE_MIN_LIVE_CONTRAST,
				("%s on floor tile %d: and clear of the LIVING sprite, so dead is "
					+ "unmistakable — corpse %.3f vs live %.3f is %.3f apart, needs %.2f")
					% [name, index, corpse_lum, live_lum, absf(corpse_lum - live_lum),
						UIPalette.CORPSE_MIN_LIVE_CONTRAST])
	# The hue shift is the SECOND carrier, not the first. Kept as an assertion because a value
	# that passed on luminance alone would be a grey corpse, which reads as a shadow.
	var tint := UIPalette.CORPSE_TINT
	assert_true(tint.b - tint.r >= 0.10,
		("the corpse is also colour-shifted, so the mark carries twice (blue %.2f is %.2f "
			+ "above red)") % [tint.b, tint.b - tint.r])
	assert_true(tint.a < 1.0, "and slightly translucent, which reads as drained")


## The distinct mean colours of every walkable 16px cell of every painted floor (quantised to
## 1/64 so near-identical cells collapse), skipping open water.
func _floor_fill_tiles() -> Array[Color]:
	var out: Array[Color] = []
	var seen := {}
	for layout_path in FLOOR_LAYOUTS:
		var layout := load(layout_path) as GroundLayoutData
		if layout == null or layout.texture == null:
			continue
		var image := layout.texture.get_image()
		if image.is_compressed():
			image.decompress()
		var tile := FLOOR_TILE_SIZE
		for cy in layout.fill_rect.size.y:
			for cx in layout.fill_rect.size.x:
				# water and its bank: any cell a water BLOCKER touches is ground nothing can lie on
				var cell := layout.fill_rect.position + Vector2i(cx, cy)
				var wet := layout.is_water_cell(cell)
				for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
					var at: Vector2 = (Vector2(cell) + corner) * float(tile)
					for poly in layout.blockers:
						wet = wet or Geometry2D.is_point_in_polygon(at, poly)
				if wet:
					continue
				var total := Vector3.ZERO
				for y in range(cy * tile, (cy + 1) * tile, 2):
					for x in range(cx * tile, (cx + 1) * tile, 2):
						var pixel := image.get_pixel(x, y)
						total += Vector3(pixel.r, pixel.g, pixel.b)
				total /= float(tile * tile / 4)
				var key := Vector3i(int(total.x * 64.0), int(total.y * 64.0), int(total.z * 64.0))
				if seen.has(key):
					continue
				seen[key] = true
				out.append(Color(total.x, total.y, total.z))
	return out


## Mean colour of a texture's OPAQUE pixels. Transparent padding would drag every mean toward
## black and make a sprite look darker than it renders.
func _mean_opaque_rgb(path: String) -> Color:
	var texture := load(path) as Texture2D
	if texture == null:
		return Color.BLACK
	var image := texture.get_image()
	if image == null:
		return Color.BLACK
	var total := Vector3.ZERO
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5:
				continue
			total += Vector3(pixel.r, pixel.g, pixel.b)
			count += 1
	if count == 0:
		return Color.BLACK
	return Color(total.x / count, total.y / count, total.z / count)


## What a corpse actually renders as: the sprite multiplied by the tint, composited over the
## floor at the tint's alpha. This is the arithmetic the engine performs, not an approximation.
func _composite_corpse(sprite: Color, floor_rgb: Color) -> Color:
	var tint := UIPalette.CORPSE_TINT
	var a := tint.a
	return Color(
		sprite.r * tint.r * a + floor_rgb.r * (1.0 - a),
		sprite.g * tint.g * a + floor_rgb.g * (1.0 - a),
		sprite.b * tint.b * a + floor_rgb.b * (1.0 - a))


func _luminance(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


## A STRUCTURAL guard: no gameplay entity may author a colour. The corpse tint shipped as a
## `Color(...)` literal in `Enemy._on_health_died()`, which put a presentation decision in the
## gameplay layer and made a second writer of a property this node owns. The directory is
## WALKED rather than listed, because a hand-written inventory only protects the files somebody
## remembered (L-034).
func test_no_gameplay_entity_authors_a_colour() -> void:
	var offenders: Array[String] = []
	_scan_for_colour_literals("res://src/gameplay", offenders)
	assert_true(offenders.is_empty(),
		("colour is a presentation decision; these gameplay files author one: %s"
			% str(offenders)))


func _scan_for_colour_literals(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_scan_for_colour_literals(full, offenders)
		elif entry.ends_with(".gd"):
			var file := FileAccess.open(full, FileAccess.READ)
			if file != null:
				var source := file.get_as_text()
				file.close()
				if _authors_a_colour(source):
					offenders.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()


## Does this source author a colour in CODE?
##
## Comments are stripped first, deliberately: `enemy.gd` documents the literal it used to
## carry, and a guard that forbade naming the mistake would push the explanation out of the
## one file where it is most useful.
func _authors_a_colour(source: String) -> bool:
	for raw_line in source.split("\n"):
		var line: String = raw_line
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		if "Color(" in line or "UIPalette" in line:
			return true
	return false


# === Cost ===================================================================

## Every creature in the world carries one of these, so an always-on `_process` would be N
## callbacks per frame for an effect that runs for a sixth of a second per hit
## (`05-performance-testing.md`).
func test_it_costs_nothing_while_no_flash_is_running() -> void:
	var entity := _entity()
	var feedback := _feedback(entity)
	assert_false(feedback.is_processing(), "idle on arrival: no per-frame cost before any hit")

	_hurtbox(entity).apply_hit(6, false)
	assert_true(feedback.is_processing(), "it processes only while a flash is running")

	feedback.advance(UIPalette.HIT_FLASH_SECONDS * 1.5)
	assert_false(feedback.is_processing(), "and switches itself back off when the flash ends")
	free_node(entity)


## An entity with nothing to be hurt by legitimately has no hurtbox and no `died`. That is a
## correct scene, not a mis-wired one, so the node must stay silently inert rather than
## complain.
func test_an_entity_with_no_hurtbox_is_inert_not_an_error() -> void:
	var host := Node2D.new()
	host.name = "NoHurtbox"
	var feedback: DamageFeedback = FeedbackScript.new()
	feedback.name = "DamageFeedback"
	host.add_child(feedback)
	add_to_tree(host)
	assert_false(feedback.is_flashing(), "nothing is flashing")
	assert_false(feedback.is_corpse(), "nothing is a corpse")
	assert_false(feedback.is_processing(), "and nothing is being processed")
	feedback.advance(1.0)
	assert_eq(host.modulate, Color.WHITE, "advancing it changes nothing")
	free_node(host)

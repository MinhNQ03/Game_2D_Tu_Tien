extends TestCase
## The player's looks read at 1x (art-01, CHARACTER_ART_BIBLE §4c): the committed 32x48 sheets
## the game loads are measured pixel by pixel, the way `validate/readability.py` measures them
## when they are built. A rebuild that buries the hands in the sleeve again, flattens the face to
## one tone, or lets the woman's look collapse back into the man's fails here.

const CELL := Vector2i(32, 48)
const ROWS := 4
## The ground line inside the cell (designs/cultivator.yaml camera.gameplay.feet_row; the
## profiles' anchor_offset.y = 48 - 43): anchor points are stored relative to it.
const FEET_ROW := 43
## Rows from the crown that hold the head (style character.head_px max - 1).
const HEAD_BAND := 15
## Rows above the ground line the hem is measured over.
const HEM_ROWS := 8
const LOOKS: Array[String] = ["player_proto", "player_daobao", "player_f_proto",
	"player_f_daobao"]
## [his look, her look] in the same garment.
const PAIRS := [["player_proto", "player_f_proto"], ["player_daobao", "player_f_daobao"]]
## The shared ink: outline and sprite-LOD eye (designs/actors/player_*.yaml `eye` ramp).
const INK := "12121a"
## The skin ramps of the two bodies, [deep, shadow, base, light] (designs/actors/*.yaml).
const SKIN := {
	"player_proto": ["a5705e", "d09c82", "eec9ae", "f9e2ce"],
	"player_daobao": ["a5705e", "d09c82", "eec9ae", "f9e2ce"],
	"player_f_proto": ["a8705f", "d4a088", "f0cdb6", "fbe6d6"],
	"player_f_daobao": ["a8705f", "d4a088", "f0cdb6", "fbe6d6"],
}


func _sheet(look: String, anim: String) -> Image:
	var texture := load("res://assets/sprites/characters/%s_%s.png" % [look, anim]) as Texture2D
	assert_not_null(texture, "%s_%s sheet loads" % [look, anim])
	return texture.get_image() if texture != null else null


func _anchors(look: String) -> CharacterAnchorData:
	var data := load("res://data/characters/visual/anchors/%s_anchors.tres" % look) \
		as CharacterAnchorData
	assert_not_null(data, "%s anchors load" % look)
	return data


func _key(c: Color) -> String:
	return c.to_html(false)


## The skin tone index (0..3) of a pixel, or -1.
func _skin_tone(look: String, c: Color) -> int:
	if c.a < 1.0:
		return -1
	return (SKIN[look] as Array).find(_key(c))


func _crown(image: Image, col: int, row: int) -> int:
	for y in CELL.y:
		for x in CELL.x:
			if image.get_pixel(col * CELL.x + x, row * CELL.y + y).a >= 1.0:
				return y
	return -1


## The skin tones seen in the head band of one cell.
func _face_tones(look: String, image: Image, col: int, row: int) -> Dictionary:
	var top := _crown(image, col, row)
	var tones := {}
	for y in range(maxi(top, 0), mini(top + HEAD_BAND, CELL.y)):
		for x in CELL.x:
			var tone := _skin_tone(look, image.get_pixel(col * CELL.x + x, row * CELL.y + y))
			if tone >= 0:
				tones[tone] = true
	return tones


## True when a skin pixel lies within 1 px of one of the rig's hand anchors for this frame: the
## hand is where the rig holds it, so neck or chin skin (or a taller crown) cannot stand in.
func _hand_shows(look: String, image: Image, col: int, row: int,
		points: Array[Vector2]) -> bool:
	for p in points:
		var cx := floori(p.x - 0.5 + CELL.x / 2.0)
		var cy := floori(p.y - 0.5 + FEET_ROW)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= CELL.x or y >= CELL.y:
					continue
				if _skin_tone(look, image.get_pixel(col * CELL.x + x, row * CELL.y + y)) >= 0:
					return true
	return false


## The widest opaque row of the hem (the HEM_ROWS rows above the ground line, and that line).
func _hem_width(image: Image, col: int, row: int) -> int:
	var widest := 0
	for y in range(FEET_ROW - HEM_ROWS, FEET_ROW + 1):
		var lo := -1
		var hi := -1
		for x in CELL.x:
			if image.get_pixel(col * CELL.x + x, row * CELL.y + y).a >= 1.0:
				if lo < 0:
					lo = x
				hi = x
		if lo >= 0:
			widest = maxi(widest, hi - lo + 1)
	return widest


func test_the_sheets_keep_the_frozen_32x48_grid() -> void:
	for look in LOOKS:
		for anim in ["idle", "walk"]:
			var image := _sheet(look, anim)
			if image == null:
				continue
			assert_eq(image.get_height(), CELL.y * ROWS, "%s_%s: four facing rows" % [look, anim])
			assert_eq(image.get_width() % CELL.x, 0, "%s_%s: whole 32px columns" % [look, anim])


func test_the_front_face_is_modelled_in_two_tones_and_never_shaded_below_its_base() -> void:
	for look in LOOKS:
		var image := _sheet(look, "idle")
		if image == null:
			continue
		for col in image.get_width() / CELL.x:
			var tones := _face_tones(look, image, col, 0)
			assert_true(tones.size() >= 2,
				"%s idle DOWN %d: the face takes base AND light (a one-tone face is a ball): %s"
				% [look, col, tones.keys()])
			assert_false(tones.has(0) or tones.has(1),
				"%s idle DOWN %d: no face pixel darker than the skin's base (min_tone): %s"
				% [look, col, tones.keys()])


## The eye pixels of one cell's head band, by `validate/readability.py`'s rule: an ink pixel
## INSIDE the face — opaque on all four sides, skin on BOTH sides of it (the ink seam between
## the jaw and a lock has skin on one side and hair on the other; a 4 px slot between two
## curtain bangs puts each eye on a hair edge).
func _eyes(look: String, image: Image, col: int, row: int) -> Array[Vector2i]:
	var eyes: Array[Vector2i] = []
	var top := _crown(image, col, row)
	if top < 0:
		return eyes
	var ox := col * CELL.x
	var oy := row * CELL.y
	for y in range(maxi(top, 1), mini(top + HEAD_BAND, CELL.y - 1)):
		for x in range(1, CELL.x - 1):
			if _key(image.get_pixel(ox + x, oy + y)) != INK:
				continue
			var enclosed := true
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if image.get_pixel(ox + x + d.x, oy + y + d.y).a < 1.0:
					enclosed = false
			var left := image.get_pixel(ox + x - 1, oy + y)
			var right := image.get_pixel(ox + x + 1, oy + y)
			if enclosed and _skin_tone(look, left) >= 0 and _skin_tone(look, right) >= 0:
				eyes.append(Vector2i(x, y))
	return eyes


## Eye pixels gathered into eyes (8-connected: a taller eye is still one eye).
func _eye_groups(eyes: Array[Vector2i]) -> Array:
	var groups: Array = []
	var left := eyes.duplicate()
	while not left.is_empty():
		var group: Array[Vector2i] = [left.pop_back()]
		var i := 0
		while i < group.size():
			for j in range(left.size() - 1, -1, -1):
				var d: Vector2i = left[j] - group[i]
				if absi(d.x) <= 1 and absi(d.y) <= 1:
					group.append(left[j])
					left.remove_at(j)
			i += 1
		groups.append(group)
	return groups


## The open face (sprite-only bangs set further out, a larger sprite-LOD eye): facing the camera
## every idle frame shows exactly two eyes, each with skin on its outer side (the cheek a curtain
## bang used to cover), on a row whose skin spans at least 6 px. With the portrait's bangs in the
## sprite the face was a 4 px slot with an eye on each hair edge. Profiles are not held to this.
func test_the_front_face_opens_with_two_eyes() -> void:
	for look in LOOKS:
		var image := _sheet(look, "idle")
		if image == null:
			continue
		for col in image.get_width() / CELL.x:
			var groups := _eye_groups(_eyes(look, image, col, 0))
			assert_eq(groups.size(), 2, "%s idle DOWN %d: two eyes (%s)" % [look, col, groups])
			if groups.size() != 2:
				continue
			# The cheek beside each eye is guarded by the count above: _eyes() only takes an ink
			# pixel with skin on BOTH sides, so a bang over the cheek drops that eye. What is left
			# to check per eye is that the face around it is wide enough to read.
			for k in 2:
				var group: Array = groups[k]
				var eye_px: Vector2i = group[0]
				var y := eye_px.y
				var lo := -1
				var hi := -1
				for x in CELL.x:
					if _skin_tone(look, image.get_pixel(col * CELL.x + x, y)) >= 0:
						if lo < 0:
							lo = x
						hi = x
				assert_true(lo >= 0 and hi - lo + 1 >= 6,
					"%s idle DOWN %d: the face spans %d px on the eye row %d (>= 6)"
					% [look, col, hi - lo + 1 if lo >= 0 else 0, y])


## A hand pixel at the rig's own palm or rear palm, frame by frame. The base sheets showed it in
## 0 of 6 idle frames in every facing; at least 2 of 3 frames per facing must now. From behind
## (UP) the body hides the hands, as it should.
func test_the_hands_leave_the_sleeve_facing_the_camera_and_in_profile() -> void:
	for look in LOOKS:
		var anchors := _anchors(look)
		if anchors == null:
			continue
		for anim in ["idle", "walk"]:
			var image := _sheet(look, anim)
			if image == null:
				continue
			var columns := image.get_width() / CELL.x
			var palm: PackedVector2Array = anchors.points.get("%s/palm" % anim,
				PackedVector2Array())
			var rear: PackedVector2Array = anchors.points.get("%s/rear_palm" % anim,
				PackedVector2Array())
			assert_eq(palm.size(), columns * ROWS, "%s %s: a palm anchor per frame" % [look, anim])
			assert_eq(rear.size(), columns * ROWS, "%s %s: a rear palm per frame" % [look, anim])
			if palm.size() != columns * ROWS or rear.size() != columns * ROWS:
				continue
			for row in [0, 2, 3]:
				var shown := 0
				for col in columns:
					var i: int = row * columns + col
					var points: Array[Vector2] = [palm[i], rear[i]]
					if _hand_shows(look, image, col, row, points):
						shown += 1
				assert_true(shown * 3 >= columns * 2,
					"%s_%s row %d: skin at the rig's hand in %d of %d frames (>= 2/3)"
					% [look, anim, row, shown, columns])


## The woman's look must not be the man's recoloured, in either garment: her hem flares wider
## than his in every front and back idle frame (an A-line against his column — the base sheets
## had the same 16 px hem), and the silhouettes differ by a clear margin in every facing.
func test_her_hem_flares_wider_than_his_in_both_garments() -> void:
	for pair: Array in PAIRS:
		var a := _sheet(String(pair[0]), "idle")
		var b := _sheet(String(pair[1]), "idle")
		if a == null or b == null:
			continue
		for row in [0, 1]:
			for col in a.get_width() / CELL.x:
				var his := _hem_width(a, col, row)
				var hers := _hem_width(b, col, row)
				assert_true(hers >= his + 2, "%s vs %s idle row %d col %d: hem %d vs %d (>= +2)"
					% [pair[1], pair[0], row, col, hers, his])
		for row in ROWS:
			for col in a.get_width() / CELL.x:
				var diff := 0
				for y in CELL.y:
					for x in CELL.x:
						var px := Vector2i(col * CELL.x + x, row * CELL.y + y)
						if (a.get_pixelv(px).a >= 1.0) != (b.get_pixelv(px).a >= 1.0):
							diff += 1
				assert_true(diff >= 60,
					"%s vs %s facing %d col %d: silhouettes differ by %d px (>= 60)"
					% [pair[1], pair[0], row, col, diff])


## In the wanderer's clothes the upper body — the part carrying the face — also differs in
## value, not only in hue. (The Thanh Vân robe is the sect's uniform: both bodies wear the
## same ramp by design, D-062 CP9, so that pair is held apart by silhouette alone, above.)
func test_the_wanderer_looks_differ_in_upper_body_value() -> void:
	var a := _sheet("player_proto", "idle")
	var b := _sheet("player_f_proto", "idle")
	if a == null or b == null:
		return
	var gap := absf(_torso_luma(a) - _torso_luma(b))
	assert_true(gap >= 0.08, "front torso value gap %.3f (>= 0.08)" % gap)


## Mean luma of the front idle's torso band (below the head, above the sash line), skin and
## ink excluded: the garment the player reads under the face.
func _torso_luma(image: Image) -> float:
	var top := _crown(image, 0, 0)
	var total := 0.0
	var count := 0
	for y in range(top + HEAD_BAND, top + HEAD_BAND + 8):
		for x in CELL.x:
			var c := image.get_pixel(x, y)
			if c.a < 1.0 or _key(c) == INK or (c.r > c.g and c.g > c.b and c.r - c.b > 0.15):
				continue
			total += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			count += 1
	return total / maxf(1.0, float(count))

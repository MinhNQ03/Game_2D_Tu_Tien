extends "res://tests/framework/test_case.gd"
## The character card (the UI refresh after D-073): the body DRAWN, what it wears in two
## slots, the numbers combat reads — fed by views, owning nothing. And the two places that
## show it: the satchel and the Chronicle's body page.

const HudScript := preload("res://src/presentation/hud/gameplay_hud.gd")
const LOC_PATH := "/root/Localization"
const PLAIN := "res://data/characters/visual/player_visual.tres"
const ROBED := "res://data/characters/visual/player_daobao_visual.tres"
const ITEMS := "res://data/items/item_catalog.tres"
const WEAPON := EquipmentData.Slot.WEAPON
const BODY := EquipmentData.Slot.BODY


func _use_language(code: String) -> void:
	var loc := scene_tree.root.get_node_or_null(LOC_PATH)
	if loc != null:
		loc.call("set_language", code)


func _t(key: String) -> String:
	return String(scene_tree.root.get_node(LOC_PATH).call("t", key))


func _card() -> CharacterCard:
	var card := CharacterCard.new()
	add_to_tree(card)
	return card


## A satchel row for something worn, as `InventoryView.make` builds it.
func _worn_row(item_id: StringName) -> Dictionary:
	var item := (load(ITEMS) as ItemCatalogData).entry(item_id)
	return {"item_id": item.id, "name_key": item.name_key, "desc_key": item.desc_key,
		"icon": item.icon, "count": 1, "usable": true, "equipped": true,
		"slot": (item.equipment as EquipmentData).slot}


func _inventory_view(worn: Array[StringName], body: String) -> InventoryView:
	var view := InventoryView.new()
	view.body_profile = load(body) as CharacterVisualProfileData
	for item_id in worn:
		view.rows.append(_worn_row(item_id))
	var pill := (load(ITEMS) as ItemCatalogData).entry(&"item_bo_huyet_dan")
	view.rows.append({"item_id": pill.id, "name_key": pill.name_key, "desc_key": pill.desc_key,
		"icon": pill.icon, "count": 2, "usable": true, "equipped": false})
	return view


func test_an_empty_card_says_what_each_slot_is_for_and_shows_no_false_number() -> void:
	_use_language("vi")
	var card := _card()
	assert_eq(card.slot_text(WEAPON), _t("UI_SHEET_SLOT_WEAPON"), "an empty hand is named")
	assert_eq(card.slot_text(BODY), _t("UI_SHEET_SLOT_BODY"), "and travelling clothes")
	assert_false(card.slot_is_filled(WEAPON) or card.slot_is_filled(BODY), "nothing is worn")
	assert_eq(card.stat_texts(), ["—", "—", "—"] as Array[String],
		"with no numbers told, a dash — never a zero that reads as a stat")
	assert_null(card.body_profile(), "and nobody is drawn until a body is told")
	for key: String in CharacterCard.STAT_KEYS + ["UI_SHEET_SLOT_WEAPON", "UI_SHEET_SLOT_BODY"]:
		for code: String in ["vi", "en"]:
			_use_language(code)
			assert_ne(_t(key), key, "'%s' has words in %s" % [key, code])
	free_node(card)


func test_the_card_draws_the_body_it_is_told_and_names_what_is_worn() -> void:
	_use_language("vi")
	var card := _card()
	var worn: Array[StringName] = [&"item_kiem_thanh_thiet", &"item_dao_bao_thanh_van"]
	var view := _inventory_view(worn, ROBED)
	card.set_body(view.body_profile)
	card.set_worn(view.rows)
	card.set_stats(true, 23, 7, 180)
	assert_eq(card.body_profile(), view.body_profile, "the body told is the body held")
	var sprite := card.figure().get_sprite()
	assert_not_null(sprite, "the figure is the game's own sprite component")
	assert_eq(sprite.texture, view.body_profile.idle_sheet, "drawn from the robed look's sheet")
	assert_eq(card.figure().scale, Vector2(2, 2), "at an integer scale: never resampled")
	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "and nearest-filtered")
	assert_eq(card.slot_text(WEAPON), _t("ITEM_KIEM_THANH_THIET_NAME"), "the blade is named")
	assert_eq(card.slot_text(BODY), _t("ITEM_DAO_BAO_THANH_VAN_NAME"), "and the robe")
	assert_true(card.slot_is_filled(WEAPON) and card.slot_is_filled(BODY), "both slots filled")
	assert_eq(card.slot_icon(WEAPON), _worn_row(&"item_kiem_thanh_thiet")["icon"],
		"with the blade's own icon in its slot")
	assert_eq(card.stat_texts(), ["23", "7", "180"] as Array[String], "the numbers as told")
	# Taking the blade off empties ITS slot and no other.
	var only_robe: Array[StringName] = [&"item_dao_bao_thanh_van"]
	card.set_worn(_inventory_view(only_robe, ROBED).rows)
	assert_eq(card.slot_text(WEAPON), _t("UI_SHEET_SLOT_WEAPON"), "the hand is empty again")
	assert_true(card.slot_is_filled(BODY), "the robe is still on")
	_use_language("en")
	card.refresh_language()
	assert_eq(card.slot_text(BODY), _t("ITEM_DAO_BAO_THANH_VAN_NAME"), "and it speaks English")
	# A figure nobody can see does not animate.
	card.visible = false
	assert_false(card.figure().is_processing(), "hidden, the figure costs nothing")
	card.visible = true
	assert_true(card.figure().is_processing(), "shown, it breathes")
	free_node(card)


func test_the_satchel_and_the_book_show_the_same_person_from_the_same_feeds() -> void:
	_use_language("vi")
	var hud: GameplayHUD = HudScript.new()
	add_to_tree(hud)
	var worn: Array[StringName] = [&"item_dao_bao_thanh_van"]
	var bag := _inventory_view(worn, ROBED)
	var told := ChronicleView.new()
	told.available = true
	told.chapter_title_key = &"STORY_CHAPTER_PROLOGUE_TITLE"
	told.stats_available = true
	told.attack = 20
	told.defense = 9
	told.move_speed = 180
	hud.set_inventory_view(bag)
	hud.set_chronicle_view(told)
	var satchel := hud.inventory_panel().character_card()
	assert_not_null(satchel, "the satchel leads with the character")
	assert_eq(satchel.body_profile(), bag.body_profile, "in the body the bag's view names")
	assert_eq(satchel.slot_text(BODY), _t("ITEM_DAO_BAO_THANH_VAN_NAME"), "wearing the robe")
	assert_eq(satchel.stat_texts(), ["20", "9", "180"] as Array[String],
		"with the numbers the Chronicle's feed carries — one feed, two readers")
	var book := hud.chronicle_panel()
	book.visible = true
	book.reset_page()
	for _i in book.page_count():
		if book.page_id() == ChroniclePanel.PAGE_BODY:
			break
		book.advance_page()
	assert_eq(book.page_id(), ChroniclePanel.PAGE_BODY, "the book has its body page")
	var in_book := book.find_child("CharacterCard", true, false) as CharacterCard
	assert_not_null(in_book, "and that page is headed by the same card")
	if in_book != null:
		# The book feeds its card BEFORE the card enters the tree. The first real capture
		# showed the robe's name beside an EMPTY slot: the icon had been written to nothing.
		var robe_icon := (load(ITEMS) as ItemCatalogData).entry(&"item_dao_bao_thanh_van").icon
		assert_eq(in_book.slot_icon(BODY), robe_icon, "the robe's slot shows the robe")
		assert_null(in_book.slot_icon(WEAPON), "and the empty hand shows nothing")
		assert_eq([in_book.body_profile(), in_book.slot_text(BODY), in_book.stat_texts()],
			[bag.body_profile, satchel.slot_text(BODY), satchel.stat_texts()],
			"the same body, the same robe, the same numbers")
	assert_true(book.page_lines().has(String(scene_tree.root.get_node(LOC_PATH).call("t_args",
		"UI_CHRONICLE_STATS", {"attack": 20, "defense": 9, "speed": 180}))),
		"and the page still SAYS the numbers for whoever reads it as text")
	free_node(hud)

extends TestCase
## The satchel on the authored SHORT screen (D-062 capture review): more rows than fit must
## scroll, and the selected item's description and the keys must stay whole inside the frame. At
## 1280x720 the whole panel used to scroll, and the description — the one text the player opened
## the satchel to read — was cut mid-line by the frame's lower edge. Since UI-02 the satchel is
## the centred book, so the fixture is a 1280x720 screen and the frame is the book's.

const PanelScript := preload("res://src/presentation/inventory/inventory_panel.gd")

const SHORT_SCREEN := Vector2(1280, 720)
const ROWS := 12


func _panel() -> InventoryPanel:
	var screen := Control.new()
	screen.size = SHORT_SCREEN
	add_to_tree(screen)
	var panel: InventoryPanel = PanelScript.new()
	screen.add_child(panel)
	var view := InventoryView.new()
	var icon := load("res://assets/sprites/items/item_bo_huyet_dan.png") as Texture2D
	for i in ROWS:
		view.rows.append({"item_id": StringName("item_%d" % i),
			"name_key": &"ITEM_BO_HUYET_DAN_NAME", "desc_key": &"ITEM_BO_HUYET_DAN_DESC",
			"icon": icon, "count": 1, "usable": true, "equipped": false})
	panel.set_view(view)
	return panel


func _settle() -> void:
	for i in 3:
		await scene_tree.process_frame


func test_the_description_stays_whole_when_the_rows_overflow() -> void:
	var panel := _panel()
	await _settle()
	var frame := panel.frame().get_global_rect()
	var scroll := panel.find_child("ScrollBody", true, false) as ScrollContainer
	var desc := panel.find_child("Description", true, false) as Control
	var keys := panel.find_child("Keys", true, false) as Control
	assert_not_null(scroll, "the rows scroll")
	assert_not_null(desc, "the description is a pinned label")
	assert_not_null(keys, "the keys are a pinned label")
	if scroll == null or desc == null or keys == null:
		free_node(panel.get_parent())
		return
	assert_true(scroll.get_v_scroll_bar().max_value > scroll.size.y,
		"the fixture overflows (%d rows in %s) — or the test proves nothing"
			% [ROWS, SHORT_SCREEN])
	for label in [desc, keys]:
		var rect := (label as Control).get_global_rect()
		assert_true(frame.encloses(rect),
			"%s %s lies whole inside the frame %s" % [label.name, rect, frame])
		assert_true(rect.position.y >= scroll.get_global_rect().end.y,
			"%s sits below the scrolling rows, not inside them" % label.name)
	free_node(panel.get_parent())


func test_moving_past_the_fold_scrolls_the_selection_into_view() -> void:
	var panel := _panel()
	await _settle()
	var scroll := panel.find_child("ScrollBody", true, false) as ScrollContainer
	panel.move_selection(-1)  # wraps to the LAST row, below the fold
	await _settle()
	var rows := panel.find_child("ItemRows", true, false) as Control
	var last := rows.get_child(rows.get_child_count() - 1) as Control
	assert_true(scroll.scroll_vertical > 0, "the list scrolled to the selection")
	assert_true(scroll.get_global_rect().encloses(last.get_global_rect()),
		"the selected (last) row is fully visible: %s in %s"
			% [last.get_global_rect(), scroll.get_global_rect()])
	free_node(panel.get_parent())

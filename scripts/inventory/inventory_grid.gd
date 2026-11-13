extends Control

signal slot_selected(index: int)

const SLOT_TEXTURE: Texture2D = preload("res://ui/slot.png")
var inventory: RaidInventory
var drop_handler: Callable
var cell_size: float = RaidInventory.CELL_SIZE
var selected_index: int = -1
var plain_slots := false

func setup(value: RaidInventory, handler: Callable = Callable()) -> void:
	inventory = value
	drop_handler = handler
	custom_minimum_size = Vector2(inventory.width, inventory.height) * cell_size
	size = custom_minimum_size
	queue_redraw()
	if not inventory.changed.is_connected(queue_redraw):
		inventory.changed.connect(queue_redraw)

func _draw() -> void:
	if inventory == null:
		return
	for y in range(inventory.height):
		for x in range(inventory.width):
			var cell := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			if plain_slots:
				draw_rect(cell, Color("383838"))
				draw_rect(cell.grow(-1), Color("8b8b8b"))
				draw_rect(cell.grow(-3), Color("555555"))
			else:
				draw_texture_rect(SLOT_TEXTURE, cell, false)
	for index in range(inventory.slots.size()):
		var slot: Dictionary = inventory.slots[index]
		var item: ItemDef = inventory.items[slot.id]
		var rotated := bool(slot.get("rotated", false))
		var item_width := item.height if rotated else item.width
		var item_height := item.width if rotated else item.height
		var rect := Rect2(Vector2(int(slot.x), int(slot.y)) * cell_size + Vector2(2, 2), Vector2(item_width, item_height) * cell_size - Vector2(4, 4))
		draw_rect(rect, Color(0.24, 0.3, 0.32, 0.96), true)
		draw_rect(rect, Color(0.67, 0.58, 0.37), false, 2.0)
		if index == selected_index:
			draw_rect(rect, Color(1.0, 0.8, 0.28), false, 2.0)
		var label := item.display_name
		if rect.size.x < 72:
			label = label.substr(0, 1)
		elif rect.size.x < 130:
			label = label.substr(0, 4)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 16), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 12, Color.WHITE)
		if int(slot.quantity) > 1:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(3, rect.size.y - 3), "×%d" % int(slot.quantity), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 6, 10, Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected_index = _slot_at(event.position)
		slot_selected.emit(selected_index)
		queue_redraw()

func _get_tooltip(at_position: Vector2) -> String:
	var index := _slot_at(at_position)
	if index < 0:
		return ""
	var slot: Dictionary = inventory.slots[index]
	return "%s ×%d" % [inventory.items[slot.id].display_name, int(slot.quantity)]

func _get_drag_data(at_position: Vector2) -> Variant:
	var index := _slot_at(at_position)
	if index < 0:
		return null
	var preview := Label.new()
	preview.text = inventory.items[inventory.slots[index].id].display_name
	preview.add_theme_color_override("font_color", Color.WHITE)
	set_drag_preview(preview)
	return {"inventory": inventory, "index": index}

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.get("inventory") is RaidInventory or inventory == null:
		return false
	var source: RaidInventory = data.inventory
	var index: int = data.index
	if index < 0 or index >= source.slots.size():
		return false
	var slot: Dictionary = source.slots[index]
	var cell := _cell(at_position)
	if source == inventory:
		return inventory.can_place(slot.id, cell.x, cell.y, Input.is_key_pressed(KEY_R), index)
	var target_index := inventory._slot_at(cell.x, cell.y)
	if target_index >= 0 and inventory.slots[target_index].id == slot.id:
		return int(inventory.slots[target_index].quantity) + int(slot.quantity) <= inventory.items[slot.id].stack_limit
	return inventory.can_place(slot.id, cell.x, cell.y, Input.is_key_pressed(KEY_R), index if source == inventory else -1)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var cell := _cell(at_position)
	var rotated := Input.is_key_pressed(KEY_R)
	if drop_handler.is_valid():
		drop_handler.call(data, inventory, cell, rotated)
	elif data.inventory == inventory:
		inventory.move(int(data.index), cell.x, cell.y, rotated)
	else:
		data.inventory.transfer_to(int(data.index), inventory, cell.x, cell.y, rotated)

func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))

func _slot_at(position: Vector2) -> int:
	var cell := _cell(position)
	return inventory._slot_at(cell.x, cell.y)

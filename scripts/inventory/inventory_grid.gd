extends Control

signal slot_selected(index: int)
signal item_action(action: String, identity: String, at: Vector2)

var preview_handler: Callable
var filter_text := ""
var filter_category := ""
var highlight_caliber := ""
var highlight_magazine := ""
var header_button: Button
var header_title := ""
var keyboard_cell := Vector2i.ZERO

const SLOT_TEXTURE: Texture2D = preload("res://ui/slot.png")
var inventory: RaidInventory
var drop_handler: Callable
var cell_size: float = RaidInventory.CELL_SIZE
var selected_index: int = -1
var plain_slots := false

func setup(value: RaidInventory, handler: Callable = Callable()) -> void:
	inventory = value
	focus_mode = Control.FOCUS_ALL
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
		if not inventory.visible_item(index): continue
		var item: ItemDef = inventory.items[slot.id]
		if (not filter_text.is_empty() and not filter_text.to_lower() in item.display_name.to_lower()) or (not filter_category.is_empty() and item.kind != filter_category): continue
		var rotated := bool(slot.get("rotated", false))
		var item_width := item.height if rotated else item.width
		var item_height := item.width if rotated else item.height
		var rect := Rect2(Vector2(int(slot.x), int(slot.y)) * cell_size + Vector2(2, 2), Vector2(item_width, item_height) * cell_size - Vector2(4, 4))
		draw_rect(rect, Color(0.24, 0.3, 0.32, 0.96), true)
		draw_rect(rect, Color(0.67, 0.58, 0.37), false, 2.0)
		if (not highlight_magazine.is_empty() and slot.id == highlight_magazine) or (not highlight_caliber.is_empty() and Ammunition.caliber(slot.id, inventory.items) == highlight_caliber):
			draw_rect(rect.grow(-2), Color("81b5ad"), false, 2.0)
		if index == selected_index:
			draw_rect(rect, Color(1.0, 0.8, 0.28), false, 2.0)
		if item.icon != null:
			var icon_size := item.icon.get_size()
			var available := rect.size - Vector2(4, 4)
			if available.y > 0:
				var scale_factor := minf(available.x / icon_size.x, available.y / icon_size.y)
				var scaled := icon_size * scale_factor
				draw_set_transform(rect.get_center(), PI / 2 if rotated else 0.0)
				draw_texture_rect(item.icon, Rect2(-scaled / 2, scaled), false)
				draw_set_transform(Vector2.ZERO)
		var condition := float(slot.get("condition", 1.0))
		var state: Dictionary = slot.get("state", {})
		if state.has("wear") and item.definition is ArmorDef and item.definition.max_durability > 0:
			condition = 1.0 - float(state.wear) / item.definition.max_durability
		if condition < 1.0:
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 3), Vector2(rect.size.x * condition, 3)), Color("9dba80"))
		var label := item.display_name
		if rect.size.x < 72:
			label = label.substr(0, 1)
		elif rect.size.x < 130:
			label = label.substr(0, 4)
		if rect.size.y > 30 or rect.size.x > 80:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 13), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 11, Color.WHITE)
		if item.kind == "magazine":
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(3, rect.size.y - 3), str(slot.state.get("rounds", 0)), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 6, 11, Color("d1c49e"))
		if int(slot.quantity) > 1:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(3, rect.size.y - 3), "×%d" % int(slot.quantity), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 6, 10, Color.WHITE)

	if has_focus():
		draw_rect(Rect2(Vector2(keyboard_cell) * cell_size, Vector2.ONE * cell_size), Color("c7ba82"), false, 2.0)
	if get_viewport().gui_is_dragging() and get_global_rect().has_point(get_global_mouse_position()):
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("inventory") is RaidInventory:
			var source: RaidInventory = data.inventory
			var index := source.find_uid(str(data.get("uid", "")))
			if index >= 0:
				var cell := _cell(get_local_mouse_position())
				var footprint := source.dimensions(source.slots[index].id, bool(data.get("rotated", false)))
				var valid := _can_drop_data(get_local_mouse_position(), data)
				draw_rect(Rect2(Vector2(cell) * cell_size, Vector2(footprint) * cell_size), Color(0.2, 0.8, 0.3, 0.4) if valid else Color(0.9, 0.2, 0.2, 0.4))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		for action in {"ui_left": Vector2i.LEFT, "ui_right": Vector2i.RIGHT, "ui_up": Vector2i.UP, "ui_down": Vector2i.DOWN}:
			if event.is_action_pressed(action):
				keyboard_cell = (keyboard_cell + {"ui_left": Vector2i.LEFT, "ui_right": Vector2i.RIGHT, "ui_up": Vector2i.UP, "ui_down": Vector2i.DOWN}[action]).clamp(Vector2i.ZERO, Vector2i(inventory.width - 1, inventory.height - 1))
				selected_index = _slot_at(Vector2(keyboard_cell) * cell_size + Vector2.ONE)
				queue_redraw()
				accept_event()
		if event.is_action_pressed("ui_accept") and selected_index >= 0:
			item_action.emit("context", inventory.slots[selected_index].uid, global_position + Vector2(keyboard_cell) * cell_size)
			accept_event()
		return
	if not event is InputEventMouseButton or not event.pressed: return
	var index := _slot_at(event.position)
	if index < 0: return
	grab_focus()
	keyboard_cell = _cell(event.position)
	selected_index = index
	item_action.emit("select", inventory.slots[index].uid, get_global_mouse_position())
	slot_selected.emit(index)
	queue_redraw()
	if event.button_index == MOUSE_BUTTON_RIGHT:
		item_action.emit("context", inventory.slots[index].uid, get_global_mouse_position())
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			item_action.emit("inspect", inventory.slots[index].uid, get_global_mouse_position())
		elif Input.is_action_pressed("inventory_quick_transfer"):
			item_action.emit("transfer", inventory.slots[index].uid, get_global_mouse_position())
		elif Input.is_action_pressed("inventory_quick_equip"):
			item_action.emit("equip", inventory.slots[index].uid, get_global_mouse_position())

func _get_tooltip(at_position: Vector2) -> String:
	var index := _slot_at(at_position)
	if index < 0: return ""
	var entry: Dictionary = inventory.slots[index]
	var item: ItemDef = inventory.items[entry.id]
	return "%s x%d\n%s\n%.2f kg | %d x %d" % [item.display_name, entry.quantity, item.description, ItemInstance.weight(entry, inventory.items), item.width, item.height]

func drag_data(index: int, quantity := -1) -> Dictionary:
	var entry: Dictionary = inventory.slots[index]
	return {"inventory": inventory, "index": index, "uid": entry.uid, "revision": inventory.revision, "rotated": entry.rotated, "quantity": quantity}

func _get_drag_data(at_position: Vector2) -> Variant:
	var index := _slot_at(at_position)
	if index < 0 or not drop_handler.is_valid(): return null
	if Input.is_action_pressed("inventory_split") and inventory.slots[index].quantity > 1:
		item_action.emit("split_drag", inventory.slots[index].uid, get_global_mouse_position())
		return null
	var preview := Label.new()
	preview.text = inventory.items[inventory.slots[index].id].display_name
	set_drag_preview(preview)
	return drag_data(index)

func _input(event: InputEvent) -> void:
	if not get_viewport().gui_is_dragging(): return
	var data: Variant = get_viewport().gui_get_drag_data()
	if not data is Dictionary or not data.has("uid"): return
	if event.is_action_pressed("inventory_rotate") and not event.is_echo():
		data.rotated = not bool(data.rotated)
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		get_viewport().gui_cancel_drag()
		get_viewport().set_input_as_handled()
	queue_redraw()

func _process(_delta: float) -> void:
	if is_instance_valid(header_button) and inventory != null:
		var occupied := 0
		for entry in inventory.slots:
			var dimensions := inventory.dimensions(entry.id)
			occupied += dimensions.x * dimensions.y
		header_button.text = "%s | %.2f kg | %d/%d" % [header_title, inventory.total_weight(), occupied, inventory.width * inventory.height]
		if not inventory.searched:
			header_button.text = header_title + " | " + ("Searching %d%%" % int(inventory.search_elapsed / maxf(0.001, inventory.config.search_seconds) * 100) if inventory.searching else "Unsearched")
	if get_viewport().gui_is_dragging(): queue_redraw()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.get("inventory") is RaidInventory or inventory == null or not preview_handler.is_valid(): return false
	return preview_handler.call(data, inventory, _cell(at_position), bool(data.get("rotated", false)))

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if drop_handler.is_valid(): drop_handler.call(data, inventory, _cell(at_position), bool(data.get("rotated", false)))

func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))

func _slot_at(position: Vector2) -> int:
	var cell := _cell(position)
	if inventory == null: return -1
	var index := inventory._slot_at(cell.x, cell.y)
	if not inventory.visible_item(index): return -1
	var item: ItemDef = inventory.items[inventory.slots[index].id]
	if (not filter_text.is_empty() and not filter_text.to_lower() in item.display_name.to_lower()) or (not filter_category.is_empty() and filter_category != item.kind): return -1
	return index

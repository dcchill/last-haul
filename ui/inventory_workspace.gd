class_name InventoryWorkspace
extends Control

const Grid = preload("res://scripts/inventory/inventory_grid.gd")
const EquipButton = preload("res://ui/equipment_slot.gd")
var app: Node
var ui: PrototypeUI
var in_raid := false
var loot: RaidInventory
var gear: EquipmentComponent
var pack: RaidInventory
var pockets: RaidInventory
var grids: Dictionary = {}
var grid_views: Array[Control] = []
var windows: Array[Control] = []
var positions: Dictionary = {}
var context: PopupMenu
var menu_actions: Array[Callable] = []
var status: Label
var summary: Label
var body: HBoxContainer
var right_column: VBoxContainer
var drag_window: Control
var drag_offset := Vector2.ZERO

func setup(application: Node, owner_ui: PrototypeUI, raid_mode: bool, target: RaidInventory = null) -> void:
	app = application
	ui = owner_ui
	in_raid = raid_mode
	loot = target
	gear = ui.state().equipment if in_raid else app.loadout.gear
	pack = ui.state().inventory if in_raid else app.loadout.pack
	pockets = ui.state().pockets if in_raid else app.loadout.pockets
	positions = ui.container_positions
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	label(header, "LAST HAUL / " + ("LOOT" if loot != null else "CHARACTER" if in_raid else "STASH"), 24)
	summary = label(header, "", 14)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(header, "Character", func(): ui.show_inventory(in_raid))
	if not in_raid: button(header, "Stash", func(): right_column.visible = not right_column.visible)
	button(header, "Close [Esc]", close)
	body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	var equipment := scroll_column(body, 220)
	label(equipment, "EQUIPMENT", 18)
	for name in gear.slots:
		var slot: RaidInventory = gear.slots[name]
		var control: Button = EquipButton.new()
		control.custom_minimum_size = Vector2(210, 30)
		equipment.add_child(control)
		var update := func():
			control.text = name.replace("_", " ").capitalize() + ": " + (app.catalog.items[slot.slots[0].id].display_name if not slot.slots.is_empty() else "Empty")
		update.call()
		slot.changed.connect(update)
		control.accepts_drop = func(data): return preview(data, slot, Vector2i(0, 0), bool(data.get("rotated", false)))
		control.drop_item = func(data): move(data, slot, Vector2i(0, 0), bool(data.get("rotated", false)))
		control.pressed.connect(func():
			if not slot.slots.is_empty(): action("context", slot, slot.slots[0].uid, control.global_position + Vector2(0, 30)))
	var carried := scroll_column(body, 280)
	add_grid(carried, pockets, "POCKETS")
	add_grid(carried, pack, "BASE PACK")
	for storage in gear.storages(): add_grid(carried, storage, storage.display_name)
	gear.changed.connect(refresh_carried.bind(carried))
	right_column = scroll_column(body, 280)
	if loot != null:
		add_grid(right_column, loot, loot.display_name)
		button(right_column, "Take all", take_all)
	elif not in_raid:
		var search := LineEdit.new()
		search.placeholder_text = "Search stash..."
		right_column.add_child(search)
		var categories := OptionButton.new()
		categories.add_item("All")
		var kinds: Array[String] = []
		for definition: ItemDef in app.catalog.items.values():
			if definition.kind not in kinds: kinds.append(definition.kind)
		kinds.sort()
		for kind in kinds: categories.add_item(kind)
		right_column.add_child(categories)
		var stash_grid := add_grid(right_column, app.stash_view, "STASH")
		search.text_changed.connect(func(value): stash_grid.filter_text = value; stash_grid.queue_redraw())
		categories.item_selected.connect(func(index): stash_grid.filter_category = "" if index == 0 else categories.get_item_text(index); stash_grid.queue_redraw())
		if app.pending_save: button(right_column, "Retry pending extraction", func(): app.retry_save(); ui.show_inventory(false))
	else:
		label(right_column, "Inspect an item or open a container.")
	status = label(column, "Drag to move | R rotate | Ctrl transfer | Alt equip | Shift drag split | Right-click actions", 13)
	context = PopupMenu.new()
	context.id_pressed.connect(func(index): menu_actions[index].call())
	add_child(context)

func label(parent: Node, text: String, font_size := 15) -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size", font_size)
	parent.add_child(value)
	return value

func button(parent: Node, text: String, callback: Callable) -> Button:
	var value := Button.new()
	value.text = text
	value.pressed.connect(callback)
	parent.add_child(value)
	return value

func scroll_column(parent: Node, minimum: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = minimum
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

func add_grid(parent: Node, inventory: RaidInventory, title: String) -> Control:
	var panel := PanelContainer.new()
	panel.set_meta("inventory_grid", true)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("262c2d")
	style.border_color = Color("696652")
	style.set_border_width_all(1)
	style.set_content_margin_all(7)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var toggle := button(header, "- " + title, func():
		var content: Control = column.get_child(1)
		content.visible = not content.visible)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(header, "Sort", func(): submit(app.inventory_service().request("sort", inventory)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(inventory.width * 26, 480), minf(inventory.height * 26, 420))
	column.add_child(scroll)
	var grid: Control = Grid.new()
	grid.cell_size = 26
	grid.plain_slots = false
	scroll.add_child(grid)
	grid.setup(inventory, move)
	grid.header_button = toggle
	grid.header_title = title
	grid.preview_handler = preview
	grid.item_action.connect(func(kind, identity, at): action(kind, inventory, identity, at))
	grid_views.append(grid)
	if not grids.has(inventory.uid) or not is_instance_valid(grids[inventory.uid]): grids[inventory.uid] = grid
	return grid

func refresh_carried(column: VBoxContainer) -> void:
	for storage in gear.storages():
		if not grids.has(storage.uid) or not is_instance_valid(grids[storage.uid]): add_grid(column, storage, storage.display_name)
	for grid in grid_views:
		var key: String = grid.inventory.uid if is_instance_valid(grid) else ""
		if not is_instance_valid(grid): continue
		var available: Dictionary = app.inventory_service().grids()
		var frame: Control = grid.get_parent().get_parent().get_parent()
		if frame.get_parent() == column:
			frame.visible = available.has(key) and (grid.inventory in [pack, pockets] or grid.inventory in gear.storages())

func move_request(data: Dictionary, target: RaidInventory, at: Vector2i, rotated: bool) -> Dictionary:
	var source: RaidInventory = data.inventory
	var request: Dictionary = app.inventory_service().request("move", source, target, str(data.get("uid", "")), at, rotated, int(data.get("quantity", -1)))
	request.revisions[source.uid] = int(data.get("revision", -1))
	return request

func preview(data: Variant, target: RaidInventory, at: Vector2i, rotated: bool) -> bool:
	if not data is Dictionary or not data.get("inventory") is RaidInventory: return false
	return app.submit_inventory(move_request(data, target, at, rotated), true).ok

func move(data: Dictionary, target: RaidInventory, at: Vector2i, rotated: bool) -> void:
	submit(move_request(data, target, at, rotated))

func submit(request: Dictionary) -> bool:
	var result: Dictionary = app.submit_inventory(request)
	status.text = "Done" if result.ok else result.reason
	return result.ok

func destinations(source: RaidInventory) -> Array[RaidInventory]:
	var result: Array[RaidInventory] = []
	if loot != null and source not in loot.all_grids(): return [loot]
	if not in_raid:
		if source not in app.stash_view.all_grids(): return [app.stash_view]
	else:
		result.append_array(ui.state().reload_grids())
	if not in_raid: result.append(pockets)
	result.append(pack)
	result.append_array(gear.storages())
	result.erase(source)
	return result

func transfer(source: RaidInventory, identity: String, quantity := -1) -> void:
	for destination in destinations(source):
		var request: Dictionary = app.inventory_service().request("move", source, destination, identity, Vector2i(-1, -1), false, quantity)
		if app.submit_inventory(request, true).ok:
			submit(request)
			return
	status.text = "No compatible storage has enough space"

func equip(source: RaidInventory, identity: String) -> void:
	var index := source.find_uid(identity)
	if index < 0: return
	if not source.equipment_slot.is_empty():
		for destination in [pack, pockets] + gear.storages():
			if destination == source: continue
			var request: Dictionary = app.inventory_service().request("move", source, destination, identity)
			if app.submit_inventory(request, true).ok:
				submit(request)
				return
	else:
		var kind: String = app.catalog.items[source.slots[index].id].kind
		for name in app.catalog.items[source.slots[index].id].equipment_slots:
			if not gear.slots.has(name): continue
			var target: RaidInventory = gear.slots[name]
			var request: Dictionary = app.inventory_service().request("equip", source, target, identity, Vector2i(0, 0))
			if app.submit_inventory(request, true).ok:
				if submit(request) and in_raid and kind == "weapon":
					app.raid.request_assign(app.profile.profile.player_id, ui.state().selected, identity)
				return
	status.text = "Cannot equip: incompatible slot or no room for exchanged gear"

func action(kind: String, source: RaidInventory, identity: String, at: Vector2) -> void:
	var index := source.find_uid(identity)
	if index < 0: return
	var entry: Dictionary = source.slots[index]
	var item: ItemDef = app.catalog.items[entry.id]
	match kind:
		"select":
			var definition: Resource = app.catalog.definitions.get(entry.id)
			for grid in grid_views:
				if not is_instance_valid(grid): continue
				grid.highlight_caliber = definition.ammo.caliber if definition is WeaponDef else Ammunition.caliber(entry.id, app.catalog.items)
				grid.highlight_magazine = definition.magazine_id if definition is WeaponDef else ""
				grid.queue_redraw()
		"transfer": transfer(source, identity)
		"equip": equip(source, identity)
		"inspect": inspect(entry)
		"split_drag": split(source, identity, true)
		"context":
			context.clear()
			menu_actions.clear()
			menu("Inspect", func(): inspect(entry))
			menu("Quick transfer", func(): transfer(source, identity))
			if not item.equipment_slots.is_empty(): menu("Unequip" if not source.equipment_slot.is_empty() else "Equip", func(): equip(source, identity))
			if entry.has("storage"): menu("Open", func(): open_storage(entry.storage))
			if entry.quantity > 1: menu("Split", func(): split(source, identity))
			if item.width != item.height: menu("Rotate", func(): submit(app.inventory_service().request("rotate", source, source, identity, Vector2i(entry.x, entry.y), not bool(entry.rotated))))
			if not ArmoryContent.magazine_feed(entry.id).is_empty():
				for ammo in source.slots:
					if Ammunition.caliber(ammo.id, app.catalog.items) == Ammunition.caliber(str(ArmoryContent.magazine_feed(entry.id).ammo), app.catalog.items):
						var ammo_id: String = ammo.id
						menu("Load " + app.catalog.items[ammo_id].display_name, func():
							var request: Dictionary = app.inventory_service().request("load", source, null, identity)
							request.ammo_id = ammo_id
							submit(request))
				menu("Unload", func(): submit(app.inventory_service().request("unload", source, null, identity)))
			if in_raid:
				if item.kind in ["weapon", "grenade", "mount", "magazine"]: menu("Assign quick slot...", func(): assign_quick_slot(identity))
				if item.heal_amount > 0 or item.stamina_amount > 0: menu("Use", func(): submit(app.inventory_service().request("use", source, null, identity)))
				if item.kind == "weapon" and ui.state().weapon != null and ui.state().weapon.instance_id == identity:
					menu("Reload", func(): app.raid.request_reload(app.profile.profile.player_id))
					menu("Eject magazine", func(): app.raid.request_reload(app.profile.profile.player_id, "eject"))
				menu("Drop", func(): submit(app.inventory_service().request("drop", source, null, identity)))
			else:
				menu("Discard", func(): confirm_discard(source, identity))
			context.position = Vector2i(at)
			context.popup()

func menu(text: String, callback: Callable) -> void:
	context.add_item(text, menu_actions.size())
	menu_actions.append(callback)

func inspect(entry: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = app.catalog.items[entry.id].display_name
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.get_label().custom_minimum_size.x = 400
	dialog.dialog_text = app.catalog.items[entry.id].description + "\n" + ui._item_details(entry) + "\nWeight %.2f kg" % ItemInstance.weight(entry, app.catalog.items)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(440, 240))

func confirm_discard(source: RaidInventory, identity: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Permanently discard this item and all its contents?"
	add_child(dialog)
	dialog.confirmed.connect(func(): submit(app.inventory_service().request("discard", source, null, identity)); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func split(source: RaidInventory, identity: String, start_drag := false) -> void:
	var index := source.find_uid(identity)
	if index < 0 or source.slots[index].quantity < 2: return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Split stack"
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = int(source.slots[index].quantity) - 1
	spin.value = floorf(int(source.slots[index].quantity) / 2.0)
	dialog.add_child(spin)
	dialog.min_size = Vector2i(280, 120)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var current := source.find_uid(identity)
		if current >= 0:
			if start_drag and grids.has(source.uid) and is_instance_valid(grids[source.uid]):
				var grid: Control = grids[source.uid]
				var preview_label := Label.new()
				preview_label.text = "%s x%d" % [app.catalog.items[source.slots[current].id].display_name, int(spin.value)]
				grid.force_drag(grid.drag_data(current, int(spin.value)), preview_label)
			else: transfer(source, identity, int(spin.value))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func open_storage(storage: RaidInventory) -> void:
	for window in windows:
		if is_instance_valid(window) and window.get_meta("storage", "") == storage.uid:
			window.move_to_front()
			return
	var window := PanelContainer.new()
	window.set_meta("storage", storage.uid)
	window.position = positions.get(storage.uid, Vector2(300 + windows.size() * 24, 110 + windows.size() * 24))
	add_child(window)
	windows.append(window)
	var column := VBoxContainer.new()
	window.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var handle := label(header, "Move " + storage.display_name)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handle.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			drag_window = window if event.pressed else null
			drag_offset = get_global_mouse_position() - window.position)
	button(header, "X", func(): positions[storage.uid] = window.position; windows.erase(window); window.queue_free())
	add_grid(column, storage, storage.display_name)
	window.move_to_front()

func take_all() -> void:
	if loot == null: return
	var identities: Array[String] = []
	for entry in loot.slots: identities.append(entry.uid)
	for identity in identities: transfer(loot, identity)

func _process(_delta: float) -> void:
	if app == null: return
	if is_instance_valid(drag_window):
		drag_window.position = (get_global_mouse_position() - drag_offset).clamp(Vector2.ZERO, (size - drag_window.size).max(Vector2.ZERO))
		positions[drag_window.get_meta("storage")] = drag_window.position
	if summary != null:
		summary.text = "  %.2f kg%s" % [ui.state().total_weight() if in_raid else pack.total_weight() + pockets.total_weight() + gear.total_weight(), " | Stamina %d" % int(ui.state().stamina) if in_raid else ""]
	if loot != null and in_raid and ui.state().opened_container.is_empty(): close()
	for window in windows.duplicate():
		if is_instance_valid(window) and not app.inventory_service().grids().has(window.get_meta("storage")):
			windows.erase(window)
			window.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not windows.is_empty():
			var window: Control = windows.pop_back()
			if is_instance_valid(window): positions[window.get_meta("storage")] = window.position; window.queue_free()
		else: close()

func close() -> void:
	for window in windows:
		if is_instance_valid(window): positions[window.get_meta("storage")] = window.position
	if in_raid:
		ui.state().opened_container = ""
		ui.show_hud()
	else: ui.show_home()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		drag_window = null

func assign_quick_slot(identity: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Assign quick slot"
	var choice := OptionButton.new()
	for i in range(9): choice.add_item("Slot %d" % (i + 1))
	choice.select(ui.state().selected)
	dialog.add_child(choice)
	add_child(dialog)
	dialog.confirmed.connect(func():
		if not app.raid.request_assign(app.profile.profile.player_id, choice.selected, identity): status.text = "Cannot assign this item"
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(280, 120))

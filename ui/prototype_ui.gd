class_name PrototypeUI
extends CanvasLayer

var app: Node
var root: Control
var screen: Control
var panel: Container
var hud: Label
var notice_label: Label
var crosshair: Label
var mode := "home"
var message := ""
var notice_until := 0
var container_id := ""
var container_contents: RaidInventory
var selected_container_index := -1
var selected_loot_pack_index := -1
var inventory_from_raid := false
var selected_inventory_index := -1
var assign_slot := 0
var practice_filter := "weapon"
var transient: Array[Node] = []
var focus_scheduled := false
var inventory_flow: Container
var preview_box: VBoxContainer
var container_weight: Label
var loot_container_grid: Control
var loot_pack_grid: Control
var loot_transfer_button: Button
const InventoryGridScript = preload("res://scripts/inventory/inventory_grid.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 17
	root.theme = theme
	hud = Label.new()
	hud.position = Vector2(24, 18)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_outline_size", 5)
	root.add_child(hud)
	notice_label = Label.new()
	notice_label.position = Vector2(24, 676)
	notice_label.z_index = 1
	notice_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice_label.add_theme_constant_override("shadow_outline_size", 5)
	root.add_child(notice_label)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.position = Vector2(632, 345)
	root.add_child(crosshair)

func _clear(new_mode: String) -> void:
	mode = new_mode
	focus_scheduled = false
	if is_instance_valid(screen):
		if screen.get_parent() == root:
			root.remove_child(screen)
		screen.queue_free()
		screen = null
	for node in transient:
		if is_instance_valid(node):
			node.queue_free()
	transient.clear()
	panel = null
	inventory_flow = null
	preview_box = null
	container_weight = null
	var gameplay := new_mode == "hud"
	hud.visible = gameplay
	crosshair.visible = gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if gameplay else Input.MOUSE_MODE_VISIBLE
	if app.raid != null and app.raid.is_active():
		app.raid.request_input(app.profile.profile.player_id, false, false, new_mode == "customize")
	if gameplay:
		return
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.04, 0.055, 0.92)
	screen.add_child(shade)
	if new_mode in ["inventory", "raid_inventory", "container"]:
		_inventory_layout()
		return
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 24)
	scroll.size = Vector2(470, 630)
	screen.add_child(scroll)
	panel = VBoxContainer.new()
	panel.custom_minimum_size.x = 445
	panel.add_theme_constant_override("separation", 9)
	scroll.add_child(panel)

func _inventory_layout() -> void:
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_top = 24
	scroll.offset_right = -24
	scroll.offset_bottom = -24
	screen.add_child(scroll)
	if mode == "container":
		inventory_flow = VBoxContainer.new()
		inventory_flow.add_theme_constant_override("separation", 4)
	else:
		inventory_flow = HFlowContainer.new()
		inventory_flow.add_theme_constant_override("h_separation", 12)
		inventory_flow.add_theme_constant_override("v_separation", 12)
	inventory_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inventory_flow)
	if mode == "container":
		return
	var frame := _inventory_frame()
	frame.custom_minimum_size.x = 360
	inventory_flow.add_child(frame)
	var margins := MarginContainer.new()
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_theme_constant_override("margin_left", 12)
	margins.add_theme_constant_override("margin_top", 24)
	margins.add_theme_constant_override("margin_right", 12)
	margins.add_theme_constant_override("margin_bottom", 24)
	frame.add_child(margins)
	panel = VBoxContainer.new()
	panel.custom_minimum_size.x = 336
	panel.add_theme_constant_override("separation", 9)
	margins.add_child(panel)
	panel.minimum_size_changed.connect(func(): frame.custom_minimum_size.y = panel.get_combined_minimum_size().y + 48)

func _inventory_frame() -> Panel:
	var frame := Panel.new()
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close inventory"
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -20
	close.offset_top = 1
	close.offset_right = -1
	close.offset_bottom = 20
	close.pressed.connect(func():
		if mode == "container": _close_container()
		elif mode == "raid_inventory": _close_inventory()
		else: show_home())
	frame.add_child(close)
	return frame

func _inventory_grid(inventory: RaidInventory, title: String, handler: Callable = Callable()) -> Control:
	var frame := _inventory_frame()
	frame.name = "InventoryFrame"
	frame.set_meta("inventory_grid", true)
	frame.custom_minimum_size = Vector2(maxi(228, inventory.width * 18 + 18), inventory.height * 18 + 44)
	if mode == "container":
		frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inventory_flow.add_child(frame)
	var label := Label.new()
	label.text = title
	label.position = Vector2(9, 1)
	label.add_theme_font_size_override("font_size", 12)
	frame.add_child(label)
	var grid: Control = InventoryGridScript.new()
	grid.name = "Grid"
	grid.position = Vector2(9, 21)
	grid.cell_size = 18
	grid.plain_slots = true
	frame.add_child(grid)
	grid.setup(inventory, handler)
	return grid

func _text(value: String, size: int = 17) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 336 if inventory_flow != null else 420
	label.add_theme_font_size_override("font_size", size)
	panel.add_child(label)
	return label

func _button(value: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.disabled = disabled
	if inventory_flow != null and mode != "container":
		for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("292628") if state_name in ["hover", "focus"] else Color("161516")
			style.border_color = Color("706366") if state_name in ["hover", "focus"] else Color("51494b")
			style.set_border_width_all(1)
			button.add_theme_stylebox_override(state_name, style)
	button.custom_minimum_size.y = 24 if mode == "container" else 34
	if mode == "container":
		button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(callback)
	panel.add_child(button)
	if not disabled and not focus_scheduled:
		_focus.call_deferred(button)
		focus_scheduled = true
	return button

func _focus(button: Button) -> void:
	if is_instance_valid(button) and button.is_inside_tree() and not button.is_queued_for_deletion():
		button.grab_focus()

func _grid(inventory: RaidInventory, at: Vector2, handler: Callable = Callable(), cell_size: float = 28) -> Control:
	var grid: Control = InventoryGridScript.new()
	grid.position = at
	grid.cell_size = cell_size
	grid.plain_slots = true
	screen.add_child(grid)
	grid.setup(inventory, handler)
	return grid

func _root_text(value: String, at: Vector2) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	screen.add_child(label)

func show_home() -> void:
	_clear("home")
	_text("LAST HAUL", 40)
	_text("CREATE ARMORY  /  EXTRACTION", 21)
	_text("Stage gear in the raid pack. Surviving equipment returns on extraction; death loses it.")
	_button("Deploy to yard", app.deploy, not app.profile.writable or not app.loadout_ready())
	_button("Practice armory — all equipment", func(): app.deploy(true))
	_button("Inventory / stage loadout", show_inventory)
	_button("Save stash layout", app._save_stash_layout, not app.profile.writable)
	_button("Settings", func(): show_settings(false))
	_button("Quit", func(): get_tree().quit())
	if not app.profile.load_error.is_empty():
		_text(app.profile.load_error)
	_root_text("STASH", Vector2(530, 24))
	_grid(app.stash_view, Vector2(530, 52), Callable(), 28)
	_root_text("STAGED RAID PACK", Vector2(852, 24))
	_grid(app.loadout.pack, Vector2(852, 52), Callable(), 28)
	_root_text("Drag between grids. Hold R to rotate.\nOpen Inventory to inspect item state.", Vector2(852, 250))

func show_hud() -> void:
	_clear("hud")

func show_notice(value: String) -> void:
	message = value
	notice_until = Time.get_ticks_msec() + 5000

func state() -> RaidParticipant:
	return app.raid.participants[app.profile.profile.player_id]

func show_inventory(from_raid: bool = false, selected: int = -1) -> void:
	inventory_from_raid = from_raid
	selected_inventory_index = selected
	_clear("raid_inventory" if from_raid else "inventory")
	_text("FIELD INVENTORY" if from_raid else "STAGE LOADOUT", 30)
	var pack: RaidInventory = state().inventory if from_raid else app.loadout.pack
	var pack_grid := _inventory_grid(pack, "RAID PACK" if from_raid else "STAGED RAID PACK")
	pack_grid.slot_selected.connect(func(index): show_inventory(from_raid, index))
	if from_raid:
		if state().weapon != null and state().weapon.reload_end > 0:
			state().weapon.cancel_reload()
		_text("HP %d / 20  |  Armor %.0f + %.0f toughness" % [ceili(state().health), state().armor.points(), state().armor.toughness()])
		for slot in ["helmet", "chestplate", "leggings", "boots"]:
			var entry: Dictionary = state().armor.entries.get(slot, {})
			_text(slot.capitalize() + ": " + (app.catalog.items[entry.id].display_name if not entry.is_empty() else "None"))
			if not entry.is_empty():
				_button("Unequip " + slot, func():
					app.raid.request_unequip_armor(app.profile.profile.player_id, slot)
					show_inventory(true, selected))
		_text("Select an item in the pack for equipment controls.")
		var bar := OptionButton.new()
		for index in range(9):
			bar.add_item("Quick slot %d" % (index + 1))
		bar.select(assign_slot)
		bar.item_selected.connect(func(index): assign_slot = index)
		panel.add_child(bar)
	else:
		_inventory_grid(app.stash_view, "STASH")
		_text("Drag equipment and ammo into the raid pack. Hold R while dropping to rotate.")
	if selected >= 0 and selected < pack.slots.size():
		var entry: Dictionary = pack.slots[selected]
		_text(app.catalog.items[entry.id].display_name, 23)
		_text(_item_details(entry))
		var instance_id: String = entry.get("state", {}).get("instance_id", entry.get("uid", ""))
		var kind: String = app.catalog.items[entry.id].kind
		if from_raid and kind in ["weapon", "grenade", "mount", "magazine"]:
			_button("Assign to selected quick slot", func():
				app.raid.request_assign(app.profile.profile.player_id, assign_slot, instance_id)
				show_inventory(true, selected))
		if from_raid and kind == "armor":
			_button("Equip armor", func():
				app.raid.request_equip_armor(app.profile.profile.player_id, instance_id)
				show_inventory(true, selected))
		if from_raid and not ArmoryContent.magazine_feed(entry.id).is_empty():
			_button("Load magazine from loose ammunition", func():
				if not app.raid.request_magazine_load(app.profile.profile.player_id, instance_id): show_notice("No matching rounds or magazine full")
				show_inventory(true, pack.find_instance(instance_id)))
			_button("Unload magazine into pack", func():
				if not app.raid.request_magazine_load(app.profile.profile.player_id, instance_id, true): show_notice("Magazine empty or no pack space")
				show_inventory(true, pack.find_instance(instance_id)))
		_add_preview(entry.id, Vector2(535, 400))
	if from_raid and app.raid.practice:
		_button("Browse practice armory", show_practice)
		_button("Reset targets / replenish carried ammo", func(): app.raid.practice_reset(app.profile.profile.player_id); show_inventory(true))
	_button("Close [I / Esc]" if from_raid else "Back", _close_inventory if from_raid else show_home)

func _item_details(entry: Dictionary) -> String:
	var data: Dictionary = entry.get("state", {})
	var kind: String = app.catalog.items[entry.id].kind
	if kind == "weapon" and app.catalog.definitions[entry.id] is WeaponDef:
		var gun: WeaponDef = app.catalog.definitions[entry.id]
		var rounds: int = int(data.magazine.state.rounds) if not data.get("magazine", {}).is_empty() else int(data.get("rounds", 0))
		return "%d / %d rounds · %s\nDamage %.0f · %d pellets · %d ticks/shot\nReload %.2fs · %s\nAttachments: %s" % [rounds, gun.magazine_size, gun.feed, gun.damage, gun.pellets, gun.interval_ticks, gun.reload_seconds, "automatic" if gun.automatic else "semiautomatic", ", ".join(data.get("attachments", {}).keys())]
	if kind == "magazine":
		return "%d rounds loaded" % int(data.get("rounds", 0))
	if kind == "armor":
		var armor: ArmorDef = app.catalog.definitions[entry.id]
		return "%s · %.0f armor · %.0f toughness\nDurability %d / %d" % [armor.slot, armor.points, armor.toughness, maxi(0, armor.max_durability - int(data.get("wear", 0))), armor.max_durability]
	return "%d carried" % int(entry.quantity)

func _close_inventory() -> void:
	get_tree().paused = false
	show_hud()

func show_practice() -> void:
	_clear("armory")
	_text("PRACTICE ARMORY", 30)
	_text("All equipment is available here. Practice items never enter your stash.")
	var picker := OptionButton.new()
	var kinds := ["weapon", "ammo", "magazine", "attachment", "armor", "grenade", "mount", "unused models"]
	for kind in kinds:
		picker.add_item(kind.capitalize())
	picker.select(maxi(0, kinds.find(practice_filter)))
	picker.item_selected.connect(func(index): practice_filter = kinds[index]; show_practice())
	panel.add_child(picker)
	if practice_filter == "unused models":
		for model in ArmoryContent.DATA.data.previews:
			_button(str(model), func(): _preview_model(model))
	else:
		var ids: Array[String] = []
		for id in app.catalog.items:
			if app.catalog.items[id].kind == practice_filter and not id in ArmoryContent.MIGRATIONS and not str(app.catalog.items[id].display_name).begins_with("Legacy"):
				if practice_filter == "weapon" and (not app.catalog.definitions[id] is WeaponDef or not app.catalog.definitions[id].armory):
					continue
				ids.append(id)
		ids.sort()
		for id in ids:
			_button("Take " + app.catalog.items[id].display_name, func():
				if app.raid.practice_grant(app.profile.profile.player_id, id):
					show_notice("Added " + app.catalog.items[id].display_name)
				else:
					show_notice("Pack full — clear practice pack or start a fresh session")
				_add_preview(id, Vector2(570, 160)))
	_button("Clear practice pack", func():
		state().inventory.slots.clear()
		state().quickbar.fill("")
		state().armor_slots.clear()
		state().select(0, app.catalog)
		state().refresh_armor(app.catalog)
		app.raid.player.refresh_view()
		show_practice())
	_button("Reset targets / replenish", func(): app.raid.practice_reset(app.profile.profile.player_id); show_notice("Targets and carried ammunition reset"))
	_button("Back to field", show_hud)

func show_customization() -> void:
	if state().weapon == null:
		return
	_clear("customize")
	var gun := state().weapon
	gun.customizing = true
	_text("CUSTOMIZE  ·  HOLD T", 28)
	_text(gun.definition.display_name)
	for slot in ["optic", "muzzle", "grip"]:
		var installed: Dictionary = gun.data.attachments.get(slot, {})
		_text(slot.capitalize() + ": " + (app.catalog.items[installed.id].display_name if not installed.is_empty() else "None"))
		if not installed.is_empty():
			_button("Remove " + slot, func():
				if not app.raid.request_attachment(app.profile.profile.player_id, slot): show_notice("No room to remove attachment")
				show_customization())
		for entry in state().inventory.slots:
			var attachment: Resource = app.catalog.definitions.get(entry.id)
			if attachment is AttachmentDef and attachment.slot == slot and attachment.supports(gun.definition):
				var instance_id: String = entry.state.instance_id
				_button("Install " + attachment.display_name, func():
					if not app.raid.request_attachment(app.profile.profile.player_id, slot, instance_id): show_notice("Cannot exchange attachment now")
					show_customization())
	_text("Magazines")
	for entry in state().inventory.slots:
		if entry.id == gun.definition.magazine_id:
			var instance_id: String = entry.state.instance_id
			_button("Reload with %d-round magazine" % int(entry.state.rounds), func():
				app.raid.request_reload(app.profile.profile.player_id, instance_id))
	if not gun.definition.magazine_id.is_empty():
		_button("Eject loaded magazine", func(): app.raid.request_reload(app.profile.profile.player_id, "eject"))
	_text("Release T to return to the field.")

func open_container(_player_id: String, id: String) -> void:
	container_id = id
	selected_container_index = -1
	selected_loot_pack_index = -1
	_redraw_container()

func _redraw_container() -> void:
	_clear("container")
	container_contents = app.raid.containers[container_id]
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inventory_flow.add_child(box)
	var column := VBoxContainer.new()
	box.add_child(column)
	var title := Label.new()
	title.text = "CONTAINER"
	column.add_child(title)
	var container_row := HBoxContainer.new()
	column.add_child(container_row)
	var equipment_space := Control.new()
	container_row.add_child(equipment_space)
	loot_container_grid = _loot_grid(container_contents, container_row)
	loot_container_grid.selected_index = selected_container_index
	loot_container_grid.slot_selected.connect(func(index): _select_loot(true, index))
	var footer := HBoxContainer.new()
	footer.name = "ContainerActions"
	column.add_child(footer)
	panel = footer
	_button("Take all [F]", _take_all)
	loot_transfer_button = _button("Transfer [R]", _transfer_selected, selected_container_index < 0)
	_button("Sort [S]", _sort_pack)
	container_weight = Label.new()
	container_weight.add_theme_font_size_override("font_size", 11)
	footer.add_child(container_weight)
	_update_container_weight()
	var player_title := Label.new()
	player_title.text = "YOUR INVENTORY  •  Select an item or drag it to a slot"
	column.add_child(player_title)
	var player_row := HBoxContainer.new()
	column.add_child(player_row)
	var equipment := VBoxContainer.new()
	equipment.name = "Equipment"
	player_row.add_child(equipment)
	for slot in ["helmet", "chestplate", "leggings", "boots", "held"]:
		var button = preload("res://ui/equipment_slot.gd").new()
		button.name = slot.capitalize()
		var entry: Dictionary = state().held_entry() if slot == "held" else state().armor.entries.get(slot, {})
		button.text = slot.capitalize() + ": " + (str(app.catalog.items[entry.id].display_name) if not entry.is_empty() else "Empty")
		button.custom_minimum_size = Vector2(150, 28)
		button.accepts_drop = func(data): return _can_equip_loot(data, slot)
		button.drop_item = func(data): _equip_loot(data, slot)
		button.pressed.connect(func(): _equip_selected_loot(slot))
		equipment.add_child(button)
	equipment_space.custom_minimum_size.x = equipment.get_combined_minimum_size().x
	equipment.minimum_size_changed.connect(func(): equipment_space.custom_minimum_size.x = equipment.get_combined_minimum_size().x)
	loot_pack_grid = _loot_grid(state().inventory, player_row)
	loot_pack_grid.selected_index = selected_loot_pack_index
	loot_pack_grid.slot_selected.connect(func(index): _select_loot(false, index))
	panel = footer
	_button("Close [Esc]", _close_container)

func _loot_grid(inventory: RaidInventory, parent: Container) -> Control:
	var grid: Control = InventoryGridScript.new()
	grid.name = "Grid"
	grid.cell_size = 28
	grid.plain_slots = true
	parent.add_child(grid)
	grid.setup(inventory, _claim_drop)
	return grid

func _select_loot(from_container: bool, index: int) -> void:
	selected_container_index = index if from_container else -1
	selected_loot_pack_index = -1 if from_container else index
	loot_container_grid.selected_index = selected_container_index
	loot_pack_grid.selected_index = selected_loot_pack_index
	loot_container_grid.queue_redraw()
	loot_pack_grid.queue_redraw()
	loot_transfer_button.disabled = selected_container_index < 0

func _can_equip_loot(data: Variant, slot: String) -> bool:
	if not data is Dictionary or data.get("inventory") not in [container_contents, state().inventory]:
		return false
	var source: RaidInventory = data.inventory
	var index := int(data.get("index", -1))
	if index < 0 or index >= source.slots.size():
		return false
	var definition: Resource = app.catalog.definitions.get(source.slots[index].id)
	return definition is WeaponDef if slot == "held" else definition is ArmorDef and definition.slot == slot

func _equip_selected_loot(slot: String) -> void:
	var source := container_contents if selected_container_index >= 0 else state().inventory
	var index := selected_container_index if selected_container_index >= 0 else selected_loot_pack_index
	if index < 0 and slot != "held":
		app.raid.request_unequip_armor(app.profile.profile.player_id, slot)
		_redraw_container()
		return
	_equip_loot({"inventory": source, "index": index}, slot)

func _equip_loot(data: Dictionary, slot: String) -> void:
	if not _can_equip_loot(data, slot):
		show_notice("Select compatible equipment first")
		return
	var source: RaidInventory = data.inventory
	var index := int(data.index)
	var instance_id: String = source.slots[index].get("state", {}).get("instance_id", "")
	var player_id: String = app.profile.profile.player_id
	if source == container_contents and not app.raid.request_transfer(player_id, container_id, index):
		show_notice("Cannot transfer: pack full, out of reach, or item unavailable")
		return
	var equipped: bool = app.raid.request_assign(player_id, state().selected, instance_id) if slot == "held" else app.raid.request_equip_armor(player_id, instance_id)
	if not equipped:
		show_notice("Cannot equip item")
	selected_container_index = -1
	selected_loot_pack_index = -1
	_redraw_container()

func _update_container_weight() -> void:
	var limit := "--"
	if container_contents.config != null and container_contents.config.weight_limit > 0:
		limit = "%.2f" % container_contents.config.weight_limit
	container_weight.text = "%.2f / %s kg" % [container_contents.total_weight(), limit]

func _claim_drop(data: Dictionary, target: RaidInventory, _cell: Vector2i, _rotated: bool) -> void:
	if target == state().inventory and data.inventory == container_contents:
		if not app.raid.request_transfer(app.profile.profile.player_id, container_id, int(data.index)):
			show_notice("Cannot transfer: pack full, out of reach, or item unavailable")
	elif target == state().inventory and data.inventory == target:
		target.move(int(data.index), _cell.x, _cell.y, _rotated)
	selected_container_index = -1
	selected_loot_pack_index = -1
	_redraw_container()

func _transfer_selected() -> void:
	if not app.raid.request_transfer(app.profile.profile.player_id, container_id, selected_container_index):
		show_notice("Cannot transfer: pack full, out of reach, or item unavailable")
	selected_container_index = -1
	selected_loot_pack_index = -1
	_redraw_container()

func _take_all() -> void:
	for index in range(container_contents.slots.size() - 1, -1, -1):
		app.raid.request_transfer(app.profile.profile.player_id, container_id, index)
	selected_container_index = -1
	selected_loot_pack_index = -1
	_redraw_container()

func _sort_pack() -> void:
	state().inventory.sort()
	selected_loot_pack_index = -1
	_redraw_container()

func _close_container() -> void:
	state().opened_container = ""
	show_hud()

func show_result() -> void:
	get_tree().paused = false
	_clear("result")
	_text("PRACTICE ENDED" if app.raid.practice else "EXTRACTED" if app.raid.result.success else "RAID FAILED", 36)
	_text(app.raid.result.reason)
	if app.pending_save:
		_text("Result not saved. Retry before leaving.")
		_button("Retry save", func(): app.retry_save(); show_result())
		_button("Quit without saving", func(): get_tree().quit())
	else:
		_button("Return to stash", app.home)

func show_pause() -> void:
	get_tree().paused = true
	_clear("pause")
	_text("PAUSED", 36)
	_button("Resume [Esc]", _resume)
	if app.raid.practice:
		_button("Practice armory", func(): get_tree().paused = false; show_practice())
	_button("Settings", func(): show_settings(true))
	_button("End practice" if app.raid.practice else "Abandon raid — lose gear and loot", _abandon)

func _resume() -> void:
	get_tree().paused = false
	show_hud()

func _abandon() -> void:
	get_tree().paused = false
	app.raid.request_abandon(app.profile.profile.player_id)

func show_settings(from_raid: bool) -> void:
	_clear("settings")
	_text("SETTINGS", 36)
	_text("Mouse sensitivity")
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.0005
	sensitivity.max_value = 0.01
	sensitivity.step = 0.0001
	sensitivity.value = app.settings.sensitivity
	panel.add_child(sensitivity)
	_text("Volume")
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = app.settings.volume
	panel.add_child(volume)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = app.settings.fullscreen
	panel.add_child(fullscreen)
	_button("Apply and save", func():
		app.settings.sensitivity = sensitivity.value
		app.settings.volume = volume.value
		app.settings.fullscreen = fullscreen.button_pressed
		app.settings.apply()
		show_notice("Settings saved" if app.settings.save_settings() == OK else "Could not save settings"))
	_button("Back", show_pause if from_raid else show_home)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_I:
			if mode == "hud": show_inventory(true)
			elif mode == "raid_inventory": show_hud()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_T and mode == "hud" and state().weapon != null:
			show_customization()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_B and mode == "hud" and app.raid.practice:
			show_practice()
			return
		if mode == "container":
			match event.physical_keycode:
				KEY_F: _take_all()
				KEY_R: _transfer_selected()
				KEY_S: _sort_pack()
	if not event.is_action_pressed("ui_cancel"):
		return
	if app.raid != null and app.raid.is_active():
		if mode == "hud": show_pause()
		elif mode == "pause": _resume()
		elif mode == "container": _close_container()
		else: _resume()
	else:
		show_home()
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	notice_label.text = message if Time.get_ticks_msec() < notice_until else ""
	if mode == "container" and is_instance_valid(container_weight):
		_update_container_weight()
	if mode == "customize" and not Input.is_physical_key_pressed(KEY_T):
		if state().weapon != null:
			state().weapon.customizing = false
		show_hud()
	if mode != "hud" or app.raid == null or not app.raid.is_active():
		return
	var participant := state()
	var gun := participant.weapon
	var ammo := ""
	if gun != null:
		ammo = "%s  %d/%d  %s" % [gun.definition.display_name, gun.magazine, gun.definition.magazine_size, "RELOADING" if gun.reload_left > 0 else ""]
	var objective := "Practice · [B] all equipment / reset" if app.raid.practice else "Collect salvage → green extraction" if not app.raid.objective_complete(app.profile.profile.player_id) else "Extract at green zone"
	var prompt := "[E] Interact" if not app.raid.player.interaction_id().is_empty() else ""
	if participant.extracting:
		prompt = "EXTRACTING %.1fs" % participant.extraction_left
	var bar := ""
	for index in range(9):
		var item_index := participant.inventory.find_instance(participant.quickbar[index])
		var name: String = participant.inventory.slots[item_index].id if item_index >= 0 else "—"
		bar += "%s%d %s%s  " % ["[" if index == participant.selected else "", index + 1, name, "]" if index == participant.selected else ""]
	hud.text = "LAST HAUL / CREATE ARMORY\nHP %d/20 · ARMOR %.0f · %s\n%s\n%s\n\n%s\nWASD · Shift sprint · Ctrl crouch · Space jump · LMB fire · RMB aim/use\nR reload · Hold T customize · I inventory · G impact / Alt+G smoke · Esc pause" % [ceili(participant.health), participant.armor.points(), ammo, objective, prompt, bar]
	hud.add_theme_font_size_override("font_size", 15)
	crosshair.visible = app.raid.player.aim_blend < 0.7

func _add_preview(id: String, at: Vector2) -> void:
	var definition: Resource = app.catalog.definitions.get(id)
	if definition is WeaponDef and definition.armory:
		_preview(definition.model_path, definition.texture_path, definition.animation_path, at)
	elif id == "maska":
		_preview(ArmoryContent.ROOT + "geo/maska.geo.json", ArmoryContent.ROOT + "textures/item/maska.png", ArmoryContent.ROOT + "animations/maska.animation.json", at)
	elif definition is ArmorDef:
		var stage := _preview_stage(at)
		var visual := ArmorVisual.create(definition)
		visual.position.y = -0.6
		stage.add_child(visual)

func _preview_model(model: String) -> void:
	var texture := ""
	for source in ArmoryContent.DATA.data.guns:
		if source.model == model:
			texture = "item/" + str(source.texture)
	if texture.is_empty():
		var guesses := {"mountedminigun": "block/mountedmgun", "mountedrpg": "block/mountedrpgtexture", "gunmount": "block/mounttexture", "maska": "item/maska", "maskaopen": "item/maska", "smokenadegeo": "item/smoketexture", "impactnadegeo": "item/impactnade"}
		texture = guesses.get(model, "item/m4texture")
	_preview(ArmoryContent.ROOT + "geo/" + model + ".geo.json", ArmoryContent.ROOT + "textures/" + texture + ".png", ArmoryContent.ROOT + "animations/" + model + ".animation.json", Vector2(570, 160))

func _preview_stage(at: Vector2) -> Node3D:
	for child in screen.get_children():
		if child.name in ["Preview", "PreviewImage", "PreviewClips"]:
			screen.remove_child(child)
			child.queue_free()
	var viewport := SubViewport.new()
	viewport.name = "Preview"
	viewport.size = Vector2i(400, 250)
	viewport.transparent_bg = true
	viewport.world_3d = World3D.new()
	screen.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(1.8, 1.1, 2.1)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.3, 0))
	var image := TextureRect.new()
	image.name = "PreviewImage"
	image.texture = viewport.get_texture()
	image.custom_minimum_size = Vector2(400, 250)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if inventory_flow != null:
		if is_instance_valid(preview_box):
			preview_box.queue_free()
		preview_box = VBoxContainer.new()
		inventory_flow.add_child(preview_box)
		preview_box.add_child(image)
	else:
		image.position = at
		image.size = Vector2(400, 250)
		screen.add_child(image)
	return stage

func _preview(model: String, texture: String, animation: String, at: Vector2) -> void:
	if not ResourceLoader.exists(model) or not ResourceLoader.exists(texture) or not ResourceLoader.exists(animation):
		show_notice("Preview asset unavailable")
		return
	var stage := _preview_stage(at)
	var view = load("res://scripts/weapons/bedrock_weapon.gd").new()
	view.show_hands = false
	view.autoplay = true
	stage.add_child(view)
	view.configure(model, texture, animation)
	view.play_clip("idle" if view.clips.has("idle") else "0")
	var bounds := AABB()
	var first := true
	for part in view.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = part.global_transform * part.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first:
		view.position += Vector3(0, 0.3, 0) - bounds.get_center()
		stage.get_node("PreviewCamera").size = maxf(0.8, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 1.3)
	var clips := OptionButton.new()
	clips.name = "PreviewClips"
	clips.position = at + Vector2(0, 255)
	clips.custom_minimum_size.x = 300
	var names: Array = view.clips.keys()
	for name in names:
		clips.add_item("Play " + str(name))
	clips.item_selected.connect(func(index):
		if is_instance_valid(view):
			view.play_clip(names[index]))
	if inventory_flow != null:
		preview_box.add_child(clips)
	else:
		screen.add_child(clips)

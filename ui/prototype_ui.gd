class_name PrototypeUI
extends CanvasLayer

var app: Node
var root: Control
var panel: VBoxContainer
var hud: Label
var notice_label: Label
var crosshair: Label
var message: String = ""
var notice_until: int = 0
var mode: String = "home"
var container_id: String = ""
var focus_scheduled: bool = false
var inventory_from_raid: bool = false
var transient: Array[Node] = []
var container_contents: RaidInventory
var selected_container_index: int = -1
var pack_status: Label

const InventoryGridScript = preload("res://scripts/inventory/inventory_grid.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 20
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.12, 0.25, 0.31)
	focus.border_color = Color(0.4, 1, 0.8)
	focus.set_border_width_all(3)
	theme.set_stylebox("focus", "Button", focus)
	root.theme = theme
	hud = Label.new()
	hud.position = Vector2(24, 20)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_outline_size", 5)
	root.add_child(hud)
	notice_label = Label.new()
	notice_label.position = Vector2(24, 635)
	notice_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice_label.add_theme_constant_override("shadow_outline_size", 5)
	root.add_child(notice_label)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(7, 14)
	root.add_child(crosshair)

func _clear(new_mode: String) -> void:
	mode = new_mode
	focus_scheduled = false
	for node in transient:
		if is_instance_valid(node):
			node.queue_free()
	transient.clear()
	if panel != null:
		panel.get_parent().hide()
		panel.get_parent().queue_free()
		panel = null
	var is_hud := new_mode == "hud"
	hud.visible = is_hud
	crosshair.visible = is_hud
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if is_hud else Input.MOUSE_MODE_VISIBLE
	if is_hud:
		return
	if new_mode == "home":
		_add_frame("res://ui/player_inv.png", Vector2(18, 24), Vector2(228, 410))
	elif new_mode == "inventory":
		_add_frame("res://ui/player_inv.png", Vector2(18, 24), Vector2(228, 410))
		_add_frame("res://ui/container_large_no_slots.png", Vector2(600, 68), Vector2(228, 152))
	elif new_mode == "raid_inventory":
		_add_frame("res://ui/player_inv.png", Vector2(18, 24), Vector2(228, 410))
	elif new_mode == "container":
		_add_frame("res://ui/container_large_no_slots.png", Vector2(70, -20), Vector2(1140, 760))
	panel = null
	if new_mode != "container":
		var background := PanelContainer.new()
		background.position = Vector2(380, 35) if new_mode == "home" else Vector2(900, 215) if new_mode in ["inventory", "raid_inventory"] else Vector2(250, 55)
		background.custom_minimum_size = Vector2(850, 650) if new_mode == "home" else Vector2(340, 480) if new_mode in ["inventory", "raid_inventory"] else Vector2(780, 0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.055, 0.075, 0.78 if new_mode in ["inventory", "raid_inventory"] else 0.98)
		style.content_margin_left = 28
		style.content_margin_right = 28
		style.content_margin_top = 22
		style.content_margin_bottom = 22
		background.add_theme_stylebox_override("panel", style)
		root.add_child(background)
		panel = VBoxContainer.new()
		panel.add_theme_constant_override("separation", 4 if new_mode in ["inventory", "raid_inventory"] else 8)
		background.add_child(panel)

func _add_frame(path: String, at: Vector2, frame_size: Vector2) -> void:
	var frame := TextureRect.new()
	frame.texture = load(path)
	frame.position = at
	frame.size = frame_size
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	transient.append(frame)
	if mode in ["inventory", "raid_inventory", "container"]:
		var close := Button.new()
		close.position = at + Vector2(frame_size.x - 40, 3)
		if mode == "container":
			close.position = Vector2(1144, 4)
		close.size = Vector2(34, 34)
		close.flat = true
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(_close_menu)
		root.add_child(close)
		transient.append(close)

func _close_menu() -> void:
	if mode == "container":
		_close_container()
	elif mode == "raid_inventory":
		_close_inventory()
	elif mode == "inventory":
		show_home()

func _grid(inventory: RaidInventory, at: Vector2, handler: Callable = Callable(), cell_size: float = RaidInventory.CELL_SIZE) -> Control:
	var grid: Control = InventoryGridScript.new()
	grid.position = at
	grid.cell_size = cell_size
	root.add_child(grid)
	transient.append(grid)
	grid.setup(inventory, handler)
	return grid

func _action_button(key: String, title: String, icon_path: String, at: Vector2, callback: Callable) -> void:
	var button := Button.new()
	button.position = at
	button.size = Vector2(210, 48)
	button.text = "[%s]   %s" % [key, title]
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon = load(icon_path)
	button.expand_icon = true
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color(0.85, 0.86, 0.88))
	button.add_theme_stylebox_override("normal", _action_style(Color(0.055, 0.06, 0.065, 0.96)))
	button.add_theme_stylebox_override("hover", _action_style(Color(0.16, 0.13, 0.09, 0.98)))
	button.add_theme_stylebox_override("pressed", _action_style(Color(0.25, 0.18, 0.08, 0.98)))
	button.pressed.connect(callback)
	root.add_child(button)
	transient.append(button)

func _action_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.34, 0.36, 0.38)
	style.set_border_width_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func _root_text(value: String, at: Vector2, size: int = 20) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	root.add_child(label)
	transient.append(label)
	return label

func _text(value: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	panel.add_child(label)
	return label

func _button(value: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.disabled = disabled
	button.pressed.connect(callback)
	panel.add_child(button)
	if not disabled and not focus_scheduled:
		focus_scheduled = true
		button.grab_focus.call_deferred()
	return button

func show_home() -> void:
	_clear("home")
	_grid(app.stash_view, Vector2(27, 58))
	_root_text("PERSISTENT STASH", Vector2(28, 30), 16)
	_text("LAST HAUL", 42)
	_text("FIELD TEST  /  SALVAGE YARD", 22)
	_text("Secure salvage from the orange crate. Extract at green.")
	_text("Extraction returns surviving gear. Death or abandonment loses it.")
	_text("STAGED KIT  %s / %s / %d rounds" % [app.loadout.weapon, app.loadout.armor, app.loadout.pack.count("rifle_round")])
	_text("Attachments: " + ", ".join(app.loadout.attachments))
	_text("Attachment preset")
	var loadout_picker := OptionButton.new()
	for label in ["Standard", "Control - barrel, compensator + stock", "Mobile - reflex sight"]:
		loadout_picker.add_item(label)
	var loadout_names := ["standard", "control", "mobile"]
	loadout_picker.select(loadout_names.find(app.settings.starter_loadout))
	loadout_picker.item_selected.connect(func(index: int):
		app.set_starter_loadout(loadout_names[index])
		show_home()
	)
	panel.add_child(loadout_picker)
	if not app.profile.load_error.is_empty():
		_text(app.profile.load_error).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("Deploy to yard", app.deploy, not app.profile.writable or not app.loadout_ready())
	_button("Inventory / Loadout", show_inventory)
	_button("Save stash now", _save_stash, not app.profile.writable)
	_button("Settings", func(): show_settings(false))
	_button("Quit", func(): get_tree().quit())

func _save_stash() -> void:
	if app.profile.save_profile():
		show_notice("Stash saved")

func show_hud() -> void:
	_clear("hud")

func _gear_picker(kind: String, selected: String, omit_slot: String, callback: Callable) -> OptionButton:
	var picker := OptionButton.new()
	var ids: Array[String] = []
	for id in app.catalog.items:
		if app.catalog.items[id].kind == kind and (id == selected or app.available_for_loadout(id, omit_slot) > 0):
			ids.append(id)
			picker.add_item(app.catalog.items[id].display_name)
	if ids.is_empty():
		picker.add_item("None")
	else:
		picker.select(maxi(0, ids.find(selected)))
	picker.item_selected.connect(func(index: int):
		if not ids.is_empty():
			callback.call(ids[index])
	)
	return picker

func show_inventory(from_raid: bool = false) -> void:
	inventory_from_raid = from_raid
	_clear("raid_inventory" if from_raid else "inventory")
	if from_raid:
		var participant: RaidParticipant = app.raid.participants[app.profile.profile.player_id]
		_root_text("RAID PACK", Vector2(28, 30), 16)
		_grid(participant.inventory, Vector2(27, 58))
		_text("Equipped: %s / %s" % [participant.weapon.definition.display_name, participant.armor.definition.id])
		_text("Ammo: %d loaded + %d reserve" % [participant.weapon.magazine, participant.weapon.reserve])
		_button("Close [Esc]", _close_inventory)
		return
	_root_text("STASH - DRAG ITEMS TO PACK", Vector2(28, 30), 14)
	_root_text("RAID PACK  [R] ROTATE", Vector2(610, 72), 14)
	_grid(app.stash_view, Vector2(27, 58))
	_grid(app.loadout.pack, Vector2(609, 89))
	_text("EQUIPMENT", 22)
	_text("Weapon")
	panel.add_child(_gear_picker("weapon", app.loadout.weapon, "weapon", func(id: String):
		app.equip("weapon", id)
		show_inventory(false)
	))
	_text("Armor")
	panel.add_child(_gear_picker("armor", app.loadout.armor, "armor", func(id: String):
		app.equip("armor", id)
		show_inventory(false)
	))
	_text("Attachments")
	for id in app.catalog.items:
		if app.catalog.items[id].kind != "attachment":
			continue
		var attachment := CheckButton.new()
		attachment.text = app.catalog.items[id].display_name
		attachment.button_pressed = app.loadout.attachments.has(id)
		attachment.disabled = not attachment.button_pressed and app.available_for_loadout(id, "attachments") <= 0
		attachment.toggled.connect(func(enabled: bool, item_id: String = id):
			if not app.toggle_attachment(item_id, enabled):
				show_notice("Attachment slot is unavailable or incompatible")
			show_inventory(false)
		)
		panel.add_child(attachment)
	_button("Deploy to yard", app.deploy, not app.loadout_ready() or not app.profile.writable)
	_button("Back", show_home)

func _close_inventory() -> void:
	get_tree().paused = false
	show_hud()

func show_notice(value: String) -> void:
	message = value
	notice_until = Time.get_ticks_msec() + 5000

func open_container(_player_id: String, id: String) -> void:
	container_id = id
	selected_container_index = -1
	_clear("container")
	var container: RaidEntity = app.raid.entities[id]
	container_contents = RaidInventory.new(app.catalog.items, 10, 4)
	if container.remaining > 0:
		container_contents.add(container.loot.item.id, container.remaining)
	_root_text(container.loot.id.replace("_", " ").to_upper(), Vector2(54, 34), 24)
	var contents_grid := _grid(container_contents, Vector2(115, 85), Callable(), 90)
	contents_grid.slot_selected.connect(_select_container_item)
	_add_container_preview(container)
	_action_button("F", "TAKE ALL", "res://ui/take_all.png", Vector2(52, 636), _take_all)
	_action_button("R", "TRANSFER", "res://ui/transfer.png", Vector2(278, 636), _transfer_selected)
	_action_button("S", "SORT PACK", "res://ui/sort.png", Vector2(504, 636), _sort_pack)
	var status_icon := TextureRect.new()
	status_icon.texture = load("res://ui/weight.png")
	status_icon.position = Vector2(942, 647)
	status_icon.size = Vector2(28, 28)
	root.add_child(status_icon)
	transient.append(status_icon)
	pack_status = _root_text("", Vector2(980, 648), 16)
	_update_pack_status()

func _add_container_preview(container: RaidEntity) -> void:
	var card := Panel.new()
	card.position = Vector2(1024, 120)
	card.size = Vector2(220, 218)
	card.add_theme_stylebox_override("panel", _action_style(Color(0.035, 0.04, 0.045, 0.95)))
	root.add_child(card)
	transient.append(card)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 180)
	viewport.transparent_bg = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	transient.append(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var preview_mesh := MeshInstance3D.new()
	preview_mesh.mesh = _container_preview_mesh(container)
	preview_mesh.rotation_degrees.y = -24
	stage.add_child(preview_mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(2.4, 1.6, 2.8)
	camera.fov = 42.0
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var image := TextureRect.new()
	image.texture = viewport.get_texture()
	image.position = Vector2(1034, 128)
	image.size = Vector2(200, 180)
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(image)
	transient.append(image)
	_root_text(container.loot.id.replace("_", " ").to_upper(), Vector2(1034, 355), 18)
	_root_text("TYPE:  LOOT", Vector2(1034, 396), 15)
	_root_text("SIZE:  %d × %d" % [container_contents.width, container_contents.height], Vector2(1034, 428), 15)

func _container_preview_mesh(container: RaidEntity) -> Mesh:
	var model: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/props/container.bbmodel"))
	if not model is Dictionary or model.elements.is_empty():
		var source := container.get_node_or_null("MeshInstance3D") as MeshInstance3D
		return source.mesh if source != null else BoxMesh.new()
	var element: Dictionary = model.elements[0]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3(element.origin[0], element.origin[1], element.origin[2])
	for face in element.faces.values():
		for index in [0, 1, 2, 0, 2, 3]:
			var vertex_id: String = face.vertices[index]
			var point: Array = element.vertices[vertex_id]
			var uv: Array = face.uv[vertex_id]
			tool.set_uv(Vector2(float(uv[0]) / 128.0, float(uv[1]) / 128.0))
			tool.add_vertex((Vector3(point[0], point[1], point[2]) - origin) / 16.0)
	tool.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://resources/props/container.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := tool.commit()
	mesh.surface_set_material(0, material)
	return mesh

func _select_container_item(index: int) -> void:
	selected_container_index = index

func _take_all() -> void:
	var container: RaidEntity = app.raid.entities[container_id]
	if container.remaining <= 0:
		return
	if app.raid.request_claim(app.profile.profile.player_id, container_id, container.remaining):
		open_container(app.profile.profile.player_id, container_id)
	else:
		show_notice("Pack is full")

func _transfer_selected() -> void:
	if selected_container_index < 0 or selected_container_index >= container_contents.slots.size():
		show_notice("Select an item to transfer")
		return
	var slot: Dictionary = container_contents.slots[selected_container_index]
	if app.raid.request_claim(app.profile.profile.player_id, container_id, int(slot.quantity)):
		open_container(app.profile.profile.player_id, container_id)
	else:
		show_notice("Pack is full")

func _sort_pack() -> void:
	var pack: RaidInventory = app.raid.participants[app.profile.profile.player_id].inventory
	if not pack.sort():
		show_notice("Pack cannot be sorted")
		return
	_update_pack_status()

func _update_pack_status() -> void:
	if pack_status == null or not is_instance_valid(pack_status):
		return
	var pack: RaidInventory = app.raid.participants[app.profile.profile.player_id].inventory
	var used := 0
	for slot in pack.slots:
		var item: ItemDef = pack.items[slot.id]
		used += item.width * item.height
	pack_status.text = "PACK  %d / %d CELLS" % [used, pack.width * pack.height]

func _claim_drop(data: Dictionary, target: RaidInventory, cell: Vector2i, rotated: bool) -> void:
	if not data.inventory is RaidInventory or int(data.index) < 0 or int(data.index) >= data.inventory.slots.size():
		return
	var slot: Dictionary = data.inventory.slots[int(data.index)]
	if app.raid.request_claim_at(app.profile.profile.player_id, container_id, int(slot.quantity), cell.x, cell.y, rotated):
		open_container(app.profile.profile.player_id, container_id)
	else:
		show_notice("Loot claim rejected. Move closer or check pack capacity.")

func _close_container() -> void:
	app.raid.participants[app.profile.profile.player_id].opened_container = ""
	show_hud()

func show_result() -> void:
	get_tree().paused = false
	_clear("result")
	_text("EXTRACTED" if app.raid.result.success else "RAID FAILED", 40)
	_text(app.raid.result.reason)
	_text("Surviving kit and loot returned to stash." if app.raid.result.success and not app.pending_save else "")
	if app.pending_save:
		_text("Result not saved. Retry before leaving this screen.")
		_button("Retry save", func(): app.retry_save(); show_result())
		_button("Quit without saving", func(): get_tree().quit())
	else:
		_button("Return to stash", app.home)

func show_pause() -> void:
	get_tree().paused = true
	_clear("pause")
	_text("PAUSED", 36)
	_button("Resume [Esc]", _resume)
	_button("Settings", func(): show_settings(true))
	_button("Abandon raid - lose gear and loot", _abandon)

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
	_text("Master volume")
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
		show_notice("Settings saved" if app.settings.save_settings() == OK else "Could not save settings")
	)
	_button("Back", show_pause if from_raid else show_home)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I and mode == "hud":
		get_tree().paused = true
		show_inventory(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and mode == "container":
		if event.keycode == KEY_F:
			_take_all()
		elif event.keycode == KEY_R:
			_transfer_selected()
		elif event.keycode == KEY_S:
			_sort_pack()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if app.raid != null and app.raid.is_active():
		if mode == "hud":
			show_pause()
		elif mode == "pause":
			_resume()
		elif mode in ["container", "raid_inventory"]:
			_close_menu()
		elif mode == "settings":
			show_pause()
		elif mode == "inventory":
			show_home()
	elif mode == "inventory" or mode == "settings":
		show_home()
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	notice_label.text = message if Time.get_ticks_msec() < notice_until else ""
	if mode != "hud" or app.raid == null or not app.raid.is_active():
		return
	var raid: RaidAuthority = app.raid
	var state: RaidParticipant = raid.participants[app.profile.profile.player_id]
	var weapon: WeaponState = state.weapon
	var plates: Dictionary = state.armor.durability
	var objective := "Collect salvage - orange crate" if not raid.objective_complete(app.profile.profile.player_id) else "Reach green extraction zone"
	var prompt := "[E] Open salvage crate" if not raid.player.interaction_id().is_empty() else ""
	if state.extracting:
		prompt = "EXTRACTING - %.1f s - stay in zone" % state.extraction_left
	hud.text = "LAST HAUL  /  FIELD TEST\nHP %d   |   RIFLE %d / %d%s\nPLATES F/B/L/R  %d / %d / %d / %d\n%s\n%s\nWASD move - Shift sprint - Space jump - LMB fire - R reload - I inventory - Esc pause" % [ceili(state.health), weapon.magazine, weapon.reserve, "  RELOADING" if weapon.reload_left > 0 else "", ceili(plates.front), ceili(plates.rear), ceili(plates.left), ceili(plates.right), objective, prompt]

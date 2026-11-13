class_name PrototypeUI
extends CanvasLayer

var app: Node
var root: Control
var screen: Control
var panel: VBoxContainer
var hud: Label
var notice_label: Label
var crosshair: Label
var mode := "home"
var message := ""
var notice_until := 0
var container_id := ""
var container_contents: RaidInventory
var selected_container_index := -1
var inventory_from_raid := false
var selected_inventory_index := -1
var assign_slot := 0
var practice_filter := "weapon"
var transient: Array[Node] = []
var focus_scheduled := false
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
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 24)
	scroll.size = Vector2(470, 630)
	screen.add_child(scroll)
	panel = VBoxContainer.new()
	panel.custom_minimum_size.x = 445
	panel.add_theme_constant_override("separation", 9)
	scroll.add_child(panel)

func _text(value: String, size: int = 17) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420
	label.add_theme_font_size_override("font_size", size)
	panel.add_child(label)
	return label

func _button(value: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.disabled = disabled
	button.custom_minimum_size.y = 34
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
	_root_text("RAID PACK" if from_raid else "STAGED RAID PACK", Vector2(850, 24))
	var pack_grid := _grid(pack, Vector2(850, 54), Callable(), 28)
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
		_root_text("STASH", Vector2(530, 24))
		_grid(app.stash_view, Vector2(530, 54), Callable(), 28)
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
	_redraw_container()

func _redraw_container() -> void:
	_clear("container")
	container_contents = app.raid.containers[container_id]
	_text("FIELD CONTAINER", 30)
	_text("Select an item to transfer. The raid continues while looting.")
	_root_text("CONTENTS", Vector2(530, 24))
	var grid := _grid(container_contents, Vector2(530, 54), _claim_drop, 28)
	grid.slot_selected.connect(func(index): selected_container_index = index; _redraw_container())
	_root_text("YOUR PACK", Vector2(850, 24))
	_grid(state().inventory, Vector2(850, 54), _claim_drop, 28)
	if selected_container_index >= 0 and selected_container_index < container_contents.slots.size():
		var entry: Dictionary = container_contents.slots[selected_container_index]
		_text(app.catalog.items[entry.id].display_name, 22)
		_text(_item_details(entry))
		_add_preview(entry.id, Vector2(535, 410))
	_button("Transfer selected [R]", _transfer_selected, selected_container_index < 0)
	_button("Take all [F]", _take_all)
	_button("Sort pack [S]", _sort_pack)
	_button("Close [Esc]", _close_container)

func _claim_drop(data: Dictionary, target: RaidInventory, _cell: Vector2i, _rotated: bool) -> void:
	if target == state().inventory and data.inventory == container_contents:
		app.raid.request_transfer(app.profile.profile.player_id, container_id, int(data.index))
	_redraw_container()

func _transfer_selected() -> void:
	if not app.raid.request_transfer(app.profile.profile.player_id, container_id, selected_container_index):
		show_notice("Cannot transfer: pack full, out of reach, or item unavailable")
	selected_container_index = -1
	_redraw_container()

func _take_all() -> void:
	for index in range(container_contents.slots.size() - 1, -1, -1):
		app.raid.request_transfer(app.profile.profile.player_id, container_id, index)
	selected_container_index = -1
	_redraw_container()

func _sort_pack() -> void:
	state().inventory.sort()
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
	image.position = at
	image.size = Vector2(400, 250)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	screen.add_child(clips)

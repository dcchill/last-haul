extends Node3D

var registry := preload("res://scripts/data/environmental_props.gd").new()
var catalog := Catalog.new()
var stage: Node3D
var camera: Camera3D
var environment: Environment
var list: ItemList
var filter: LineEdit
var categories: OptionButton
var variants: OptionButton
var details: Label
var status: Label
var storage_grid: Control
var inventory_grid: Control
var current: Node3D
var current_id := ""
var current_variant := 0
var rows: Array[Dictionary] = []
var collision_display := false
var collision_root: Node3D
var zoom := 4.0
var yaw := -.6
var pitch := -.25
var target := Vector3.ZERO
var dragging := false
var pack: RaidInventory
var service := InventoryTransactions.new()
var selected_item := -1
var snapshots: Dictionary = {}

func _ready() -> void:
	var error := registry.load_catalog()
	if not error.is_empty(): push_error(error)
	error = catalog.load_all()
	if not error.is_empty(): push_error(error)
	pack = RaidInventory.new(catalog.items, 10, 5)
	service.actor_id = "prop-browser"
	service.authorize = func(grid): return grid == pack or (current is SearchableFurniture and not current.locked and grid == current.contents)
	build_ui()
	refresh_list()
	if not rows.is_empty(): select_id(rows[0].id)

func button(parent: Node, title: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = title
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(layout)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 345
	layout.add_child(panel)
	var sidebar := VBoxContainer.new()
	panel.add_child(sidebar)
	var title := Label.new()
	title.text = "LAST HAUL / ENVIRONMENT LIBRARY"
	title.add_theme_font_size_override("font_size", 18)
	sidebar.add_child(title)
	filter = LineEdit.new()
	filter.placeholder_text = "Search 001–200 or prop name"
	filter.text_changed.connect(func(_value): refresh_list())
	sidebar.add_child(filter)
	categories = OptionButton.new()
	categories.add_item("All categories")
	var seen := {}
	for entry: Dictionary in registry.entries.values():
		if not seen.has(entry.category): categories.add_item(entry.category); seen[entry.category] = true
	categories.item_selected.connect(func(_value): refresh_list())
	sidebar.add_child(categories)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 150
	list.item_selected.connect(func(index): select_id(rows[index].id))
	sidebar.add_child(list)
	variants = OptionButton.new()
	variants.item_selected.connect(func(index): show_variant(index))
	sidebar.add_child(variants)
	var controls := HBoxContainer.new()
	sidebar.add_child(controls)
	button(controls, "Rotate 90°", func(): yaw += PI / 2; update_camera())
	button(controls, "Reset view", frame_prop)
	var collision_toggle := CheckButton.new()
	collision_toggle.text = "Show collision"
	collision_toggle.toggled.connect(func(value): collision_display = value; update_collision())
	sidebar.add_child(collision_toggle)
	var light := OptionButton.new()
	for label in ["Overcast exterior", "Warehouse", "Medical interior"]: light.add_item(label)
	light.item_selected.connect(set_lighting)
	sidebar.add_child(light)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.x = 320
	details.add_theme_font_size_override("font_size", 13)
	sidebar.add_child(details)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(right)
	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.gui_input.connect(view_input)
	right.add_child(viewport_container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport_container.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("252e31")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a4b9bf")
	environment.ambient_light_energy = .65
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_color = Color("eadfc9")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(30, .1, 30)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -.052
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("555c59")
	floor_material.roughness = 1
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 45
	stage.add_child(camera)
	var hint := Label.new()
	hint.text = "Drag to orbit · Mouse wheel to zoom · Dimensions are in meters"
	right.add_child(hint)
	var search_controls := HBoxContainer.new()
	right.add_child(search_controls)
	button(search_controls, "Search / close", test_search)
	button(search_controls, "Grant keycard & unlock", unlock_preview)
	button(search_controls, "Take selected item", take_selected)
	button(search_controls, "Reset contents", reset_contents)
	status = Label.new()
	right.add_child(status)
	var grids := HBoxContainer.new()
	right.add_child(grids)
	storage_grid = preload("res://scripts/inventory/inventory_grid.gd").new()
	storage_grid.cell_size = 28
	storage_grid.slot_selected.connect(func(index): selected_item = index)
	grids.add_child(storage_grid)
	inventory_grid = preload("res://scripts/inventory/inventory_grid.gd").new()
	inventory_grid.cell_size = 28
	inventory_grid.setup(pack)
	grids.add_child(inventory_grid)

func refresh_list() -> void:
	rows = registry.find_props(filter.text, "" if categories.selected == 0 else categories.get_item_text(categories.selected))
	list.clear()
	for entry in rows:
		var missing := false
		for variant in entry.variants:
			if not ResourceLoader.exists(variant.scene): missing = true
		list.add_item(entry.id + "  " + entry.name + (" [MISSING]" if missing else ""))
		if missing: list.set_item_custom_fg_color(list.item_count - 1, Color.SALMON)

func select_id(id: String) -> void:
	current_id = id
	variants.clear()
	for variant: Dictionary in registry.entries[id].variants: variants.add_item("%d / %s" % [variant.index, variant.name])
	variants.select(0)
	show_variant(0)

func remember_current() -> void:
	if current is SearchableFurniture and current.contents != null:
		snapshots[current.entity_id] = current.storage_snapshot()

func show_variant(index: int) -> void:
	remember_current()
	if current != null: current.free()
	current_variant = index
	current = registry.instantiate_prop(current_id, index, 0, "browser-%s-%d" % [current_id, index])
	if current == null:
		details.text = "Missing scene for " + current_id
		return
	stage.add_child(current)
	if current is SearchableFurniture:
		var rng := RandomNumberGenerator.new()
		rng.seed = 928
		current.create_inventory(catalog.items, rng)
		if snapshots.has(current.entity_id): current.restore_storage(snapshots[current.entity_id], catalog.items)
		storage_grid.setup(current.contents)
		storage_grid.visible = true
		service.roots = [pack, current.contents]
	else:
		storage_grid.visible = false
	var entry: Dictionary = registry.entries[current_id]
	var box := registry.bounds(current_id, index)
	var scale_error := box.size.length() > 25 or box.size.x <= 0 or box.size.y <= 0 or box.size.z <= 0
	details.text = "%s / %s\n%.2f × %.2f × %.2f m%s\n%s\n%s · %s\nRooms: %s\nFront clearance: %.2f m" % [current_id, entry.name, box.size.x, box.size.y, box.size.z,
		"  [CHECK SCALE]" if scale_error else "", ", ".join(entry.classifications), "/".join(entry.placement.environments), entry.placement.attachment, ", ".join(entry.placement.rooms), entry.placement.service_clearance]
	details.modulate = Color.SALMON if scale_error else Color.WHITE
	selected_item = -1
	frame_prop()
	update_collision()

func frame_prop() -> void:
	if current == null: return
	var box := registry.bounds(current_id, current_variant)
	target = box.get_center()
	zoom = maxf(1.1, box.size.length() * 1.3)
	yaw = -.6
	pitch = -.25
	update_camera()

func update_camera() -> void:
	if camera == null: return
	camera.position = target + Vector3(sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch)) * zoom
	camera.look_at(target)

func view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), .3, 45)
			update_camera()
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * .008
		pitch = clampf(pitch + event.relative.y * .008, -1.35, .8)
		update_camera()

func update_collision() -> void:
	if collision_root != null: collision_root.free()
	collision_root = Node3D.new()
	stage.add_child(collision_root)
	if not collision_display or current == null: return
	for shape: CollisionShape3D in current.find_children("*", "CollisionShape3D", true, false):
		var visual := MeshInstance3D.new()
		visual.mesh = shape.shape.get_debug_mesh()
		collision_root.add_child(visual)
		visual.global_transform = shape.global_transform

func set_lighting(index: int) -> void:
	environment.ambient_light_energy = [.65, .22, .8][index]
	environment.ambient_light_color = [Color("a4b9bf"), Color("738b91"), Color("c4d4cf")][index]
	stage.get_node("KeyLight").light_energy = [1.5, .8, 1.2][index]
	stage.get_node("KeyLight").light_color = [Color("eadfc9"), Color("c5c8ad"), Color("e1eee8")][index]

func test_search() -> void:
	if not current is SearchableFurniture: return
	if current.locked:
		status.text = "Locked: grant the required keycard to test access."
		return
	if current.contents.is_open:
		current.contents.searching = false
		current.contents.is_open = false
		current.set_open(false)
	else:
		current.open_furniture()
		current.contents.begin_search()

func unlock_preview() -> void:
	if not current is SearchableFurniture or not current.locked: return
	if current.key_item.is_empty(): return
	if not pack.add(current.key_item, 1): return
	var identity := ""
	for item in pack.slots:
		if item.id == current.key_item: identity = item.uid
	if service.submit(service.request("consume", pack, null, identity, Vector2i(-1, -1), false, 1)).ok:
		current.locked = false

func take_selected() -> void:
	if not current is SearchableFurniture or selected_item < 0 or selected_item >= current.contents.slots.size(): return
	var result := service.submit(service.request("loot", current.contents, pack, current.contents.slots[selected_item].uid))
	status.text = "Transferred to test inventory" if result.ok else result.reason
	selected_item = -1

func reset_contents() -> void:
	if current is SearchableFurniture: snapshots.erase(current.entity_id)
	if current != null: current.free(); current = null
	show_variant(current_variant)

func _process(delta: float) -> void:
	if current is SearchableFurniture and current.contents != null:
		current.contents.tick_search(delta)
		status.text = ("Locked · " if current.locked else "") + current.contents.search_state() + " · %.1f / %.1f seconds · %d items" % [current.contents.search_elapsed, current.container_config.search_seconds, current.contents.slots.size()]
	else: status.text = "Select a searchable prop to test storage."
	if collision_display and current is SearchableFurniture and current.panel_tween != null and current.panel_tween.is_running(): update_collision()

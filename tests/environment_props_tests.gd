extends SceneTree

var checks := 0
var failures := 0
var props := preload("res://scripts/data/environmental_props.gd").new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func node_bounds(node: Node3D, transform := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var first := true
	for child in node.get_children():
		if not child is Node3D: continue
		var next: Transform3D = transform * child.transform
		var rect: AABB = next * child.mesh.get_aabb() if child is MeshInstance3D and child.mesh != null else node_bounds(child, next)
		if rect.size.is_zero_approx(): continue
		result = rect if first else result.merge(rect)
		first = false
	return result

func validate_entry(entry: Dictionary) -> void:
	check(entry.name.length() > 2 and not entry.category.is_empty(), entry.id + " named/category")
	check(entry.placement.rooms.size() > 0 and entry.placement.buildings.size() > 0 and entry.placement.rotations.size() > 0, entry.id + " placement tags")
	check(entry.variants.size() >= 1 and entry.variants.size() <= 4, entry.id + " variant limit")
	var seen := {}
	for variant: Dictionary in entry.variants:
		var label: String = entry.id + "/" + str(variant.index) + " " + variant.name
		var prop := props.instantiate_prop(entry.id, variant.index, 42, "test-" + entry.id)
		check(prop != null, label + " instantiates")
		if prop == null: continue
		var bounds := node_bounds(prop)
		var declared := props.bounds(entry.id, variant.index)
		check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.x > 0 and bounds.size.y > 0 and bounds.size.z > 0, label + " finite positive bounds")
		check(absf(bounds.position.y) < .025, label + " grounded")
		check(bounds.position.is_equal_approx(declared.position) and bounds.size.is_equal_approx(declared.size), label + " recorded scale/pose")
		check(bounds.size.max_axis_index() >= 0 and bounds.size.length() < 25, label + " meter scale")
		var triangles := 0
		var signature := ""
		for mesh: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
			var pose := mesh.transform
			var ancestor := mesh.get_parent()
			while ancestor != prop:
				if ancestor is Node3D: pose = ancestor.transform * pose
				ancestor = ancestor.get_parent()
			signature += str(pose)
			check(mesh.mesh is ArrayMesh and mesh.visibility_range_end > 0, label + " baked visible-range mesh")
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				triangles += indices.size() / 3
				var material := mesh.mesh.surface_get_material(surface)
				check(material != null and not material.resource_path.is_empty() and ResourceLoader.exists(material.resource_path), label + " external shared material")
				signature += str(hash(vertices)) + (material.resource_path if material != null else "missing")
				for vertex in vertices:
					if not vertex.is_finite(): check(false, label + " nonfinite vertex"); break
				for i in range(0, indices.size(), 3):
					var a := vertices[indices[i]]
					var b := vertices[indices[i + 1]]
					var c := vertices[indices[i + 2]]
					if (b-a).cross(c-a).length_squared() < .0000000001: check(false, label + " degenerate triangle"); break
		check(triangles > 0 and triangles <= 12000, label + " triangle budget")
		if seen.has(signature): check(false, label + " duplicates variant " + str(seen[signature]))
		seen[signature] = variant.index
		var colliders := prop.find_children("*", "CollisionShape3D", true, false)
		check(not colliders.is_empty() or not variant.collision_required, label + " required collision")
		for collider: CollisionShape3D in colliders:
			check(collider.shape != null and not collider.disabled and collider.position.is_finite(), label + " valid collision")
			if collider.shape is BoxShape3D: check(collider.shape.size.x > 0 and collider.shape.size.y > 0 and collider.shape.size.z > 0, label + " positive collision")
		if not entry.storage.is_empty():
			check(prop is SearchableFurniture and prop.container_config != null and prop.loot_table != null, label + " inventory integration")
			check(prop.has_node("MovingPanel") and prop.entity_id == "environment:test-" + entry.id, label + " moving panel/stable entity")
			check(prop.container_config.searchable and prop.container_config.search_seconds > 0, label + " timed search")
		prop.free()

func run() -> void:
	check(props.load_catalog().is_empty(), "catalog loads")
	var args := OS.get_cmdline_user_args()
	var category := 0
	if "--category" in args: category = int(args[args.find("--category") + 1])
	if category == 0:
		check(props.entries.size() == 200, "all 200 catalog IDs")
		for i in range(1, 201): check(props.entries.has("%03d" % i), "contiguous ID %03d" % i)
	for entry: Dictionary in props.entries.values():
		if category == 0 or int(entry.category_index) == category: validate_entry(entry)
	if category == 0:
		validate_placement()
		validate_storage()
		await validate_authority()
		await validate_browser()
	check(props.instantiate_prop("000") == null and props.instantiate_prop("001", 99) == null, "invalid requests rejected")
	var first := props.select_variant("001", 835, "barrier-a")
	props.select_variant("002", 91, "unrelated")
	check(props.select_variant("001", 835, "barrier-a") == first, "selection independent of call order")
	print("ENVIRONMENT PROP TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func validate_placement() -> void:
	var context := {"environment": "exterior", "room": "street", "attachment": "floor", "supported": true}
	var pose := Transform3D.IDENTITY
	check(props.placement_error("001", 0, pose, context).is_empty(), "appropriate street placement accepted")
	var bad: Dictionary = context.duplicate()
	bad.environment = "interior"
	check(not props.placement_error("001", 0, pose, bad).is_empty(), "interior/exterior rules enforced")
	bad = context.duplicate(); bad.supported = false
	check(not props.placement_error("001", 0, pose, bad).is_empty(), "unsupported placements rejected")
	bad = context.duplicate(); bad.room = "ward"
	check(not props.placement_error("001", 0, pose, bad).is_empty(), "inappropriate rooms rejected")
	var blocked: Array[AABB] = [AABB(Vector3(-2, 0, -1), Vector3(4, 3, 2))]
	check(not props.placement_error("001", 0, pose, context, [], blocked).is_empty(), "doorway keepout enforced")
	var access: Array[AABB] = [AABB(Vector3(-.25, 0, -1.1), Vector3(.5, 2, .5))]
	var office := {"attachment": "floor", "supported": true, "room": "office", "environment": "interior"}
	check(not props.placement_error("041", 0, pose, office, access).is_empty(), "front access clearance enforced")
	pose.basis = Basis(Vector3.UP, PI / 4)
	check(not props.placement_error("001", 0, pose, context).is_empty(), "unsupported rotations rejected")
	var parent := Node3D.new()
	var reserved: Array[AABB] = []
	var keepouts: Array[AABB] = []
	var first := props.place(parent, "171", 0, Transform3D.IDENTITY, {"attachment": "floor", "supported": true}, "crate-a", reserved, keepouts)
	check(first != null and reserved.size() == 1, "placement records occupied clearance")
	check(props.place(parent, "171", 0, Transform3D.IDENTITY, {"attachment": "floor", "supported": true}, "crate-b", reserved, keepouts) == null, "overlapping prop rejected")
	check(props.instantiate_prop("171", 0) == null, "storage requires a stable instance ID")
	parent.free()
	var poses: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0))]
	var batch := props.make_multimesh("144", 0, poses)
	check(batch != null and batch.instance_transforms.size() == 2, "static clutter can use existing MultiMesh implementation")
	if batch != null: batch.free()
	check(props.make_multimesh("001", 0, poses) == null and props.make_multimesh("171", 0, poses) == null, "batching preserves collision and interactions")

func validate_storage() -> void:
	var catalog := Catalog.new()
	check(catalog.load_all().is_empty(), "existing item catalog loads")
	var storage_ids := 0
	for entry: Dictionary in props.entries.values():
		if entry.storage.is_empty(): continue
		if int(entry.id) >= 171: storage_ids += 1
		for variant: Dictionary in entry.variants:
			var prop := props.instantiate_prop(entry.id, variant.index, 0, "storage-" + entry.id) as SearchableFurniture
			var rng := RandomNumberGenerator.new()
			rng.seed = 871
			var grid := prop.create_inventory(catalog.items, rng)
			check(grid.config == prop.container_config and not grid.searched, entry.id + " configured timed storage")
			check(grid.width == int(entry.storage.dimensions[0]) and grid.height == int(entry.storage.dimensions[1]), entry.id + " container-specific capacity")
			check(grid.slots.is_empty() if prop.starts_empty else not grid.slots.is_empty(), entry.id + " appropriate empty/loaded loot")
			for item in grid.slots: check(grid.accepts(item), entry.id + " generated items respect restrictions")
			prop.locked = false
			prop.open_furniture()
			grid.begin_search()
			grid.tick_search(prop.container_config.search_seconds * .45)
			check(not grid.searched and grid.search_elapsed > 0, entry.id + " timed search advances partially")
			var snapshot: Dictionary = JSON.parse_string(JSON.stringify(prop.storage_snapshot()))
			var second := props.instantiate_prop(entry.id, variant.index, 0, "storage-" + entry.id) as SearchableFurniture
			check(second.restore_storage(snapshot, catalog.items), entry.id + " restores existing inventory serialization")
			check(second.contents.snapshot() == grid.snapshot() and second.contents.search_elapsed == grid.search_elapsed and second.opened, entry.id + " identities/contents/search/open pose preserved")
			var original := second.contents
			var invalid := snapshot.duplicate(true)
			invalid.inventory.width = 128
			check(not second.restore_storage(invalid, catalog.items) and second.contents == original, entry.id + " invalid restore leaves live contents intact")
			grid.tick_search(prop.container_config.search_seconds)
			check(grid.searched, entry.id + " search completes")
			prop.set_open(false, false)
			check(not prop.opened and prop.get_node("MovingPanel").transform.is_equal_approx(prop.panel_rest), entry.id + " closes to authored rest pose")
			var marker := prop.get_node_or_null("LootContents") as Node3D
			if marker != null:
				grid.slots.clear(); grid.changed.emit()
				check(not marker.visible, entry.id + " emptied visual follows inventory")
			second.free(); prop.free()
	check(storage_ids == 30, "all 30 loot container IDs use existing storage")

func settle(frames := 3) -> void:
	for i in frames: await physics_frame

func face(raid: RaidAuthority, prop: RaidEntity) -> void:
	var actor := raid.player
	actor.global_position = prop.global_position + Vector3(0, -.8, 2)
	actor.previous_position = actor.global_position
	var direction := prop.global_position + prop.interaction_offset - actor.eye_position()
	actor.rotation.y = atan2(-direction.x, -direction.z)
	actor.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	actor.camera.rotation.x = actor.look_pitch
	await settle(6)

func validate_authority() -> void:
	var catalog := Catalog.new()
	catalog.load_all()
	var raid := load("res://scenes/raid/test_yard.tscn").instantiate() as RaidAuthority
	var secure := props.instantiate_prop("199", 0, 0, "authority-case") as SearchableFurniture
	secure.position = Vector3(0, 1, 9)
	raid.add_child(secure)
	root.add_child(raid)
	check(raid.deploy("prop-tester", catalog, SettingsStore.new(), {"practice": true}).is_empty(), "raid registers numbered container")
	raid.set_physics_process(false)
	raid.player.set_physics_process(false)
	for npc in raid.npcs: npc.set_physics_process(false); npc.state = RaidGuard.State.DEAD
	await face(raid, secure)
	check(raid.player.interaction_id() == secure.entity_id, "compound collision resolves searchable owner")
	check("Unlock" in raid.interaction_prompt(secure.entity_id), "locked contextual prompt")
	check(not raid.request_interact("prop-tester", secure.entity_id) and secure.locked, "authority rejects locked search without carried key")
	var state: RaidParticipant = raid.participants["prop-tester"]
	state.inventory.add("medtac_keycard", 1)
	check(raid.request_interact("prop-tester", secure.entity_id) and not secure.locked, "authority unlocks and searches with carried key")
	check(state.inventory.count("medtac_keycard") == 0 and secure.contents == raid.containers[secure.entity_id], "key consumed once and storage stays authority-owned")
	check(not raid.request_transfer("prop-tester", secure.entity_id, 0), "undiscovered loot cannot transfer")
	secure.contents.tick_search(secure.container_config.search_seconds)
	check(raid.request_transfer("prop-tester", secure.entity_id, 0), "searched item transfers through existing transactions")
	state.opened_container = ""
	raid.gameplay_step()
	check(not secure.opened, "closing search session closes configured furniture")
	await settle(24)
	check(secure.get_node("MovingPanel").transform.is_equal_approx(secure.panel_rest), "authority close restores panel and collider pose")
	# Movement/ray collision and intentional openings are checked in actual physics.
	var barrier := props.instantiate_prop("001", 0)
	barrier.position = Vector3(15, 0, 0)
	root.add_child(barrier)
	var detector := props.instantiate_prop("115", 0)
	detector.position = Vector3(20, 0, 0)
	root.add_child(detector)
	await settle()
	var space := root.world_3d.direct_space_state
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(15, .7, -2), Vector3(15, .7, 2))).is_empty(), "cover blocks firing ray")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20, 1, -2), Vector3(20, 1, 2))).is_empty(), "gate opening admits firing ray")
	var mover := CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3; capsule.height = 1.8
	collider.shape = capsule
	mover.add_child(collider)
	root.add_child(mover)
	mover.position = Vector3(15, .9, -2)
	check(mover.move_and_collide(Vector3(0, 0, 4), true) != null, "hard cover blocks player capsule")
	mover.position = Vector3(20, .9, -2)
	check(mover.move_and_collide(Vector3(0, 0, 4), true) == null, "detector preserves walk-through clearance")
	mover.free(); barrier.free(); detector.free(); raid.free()

func validate_browser() -> void:
	var browser: Node3D = load("res://scenes/environment_prop_browser.tscn").instantiate()
	root.add_child(browser)
	check(browser.rows.size() == 200, "browser lists all IDs")
	browser.filter.text = "hospital"
	browser.refresh_list()
	check(browser.rows.size() == 1 and browser.rows[0].id == "096", "browser text filter")
	browser.filter.text = ""
	browser.select_id("199")
	check(browser.current.locked and browser.current.contents != null, "browser creates real locked storage")
	browser.unlock_preview()
	check(not browser.current.locked, "browser exercises key consumption")
	browser.test_search()
	browser.current.contents.tick_search(5)
	check(browser.current.contents.searched, "browser uses existing timed search")
	browser.selected_item = 0
	browser.take_selected()
	check(not browser.pack.slots.is_empty(), "browser transfers with InventoryTransactions")
	browser.collision_display = true
	browser.update_collision()
	check(browser.collision_root.get_child_count() > 0, "browser visualizes actual collision shapes")
	var previous: Array = browser.current.contents.snapshot()
	browser.show_variant(1)
	browser.show_variant(0)
	check(browser.current.contents.snapshot() == previous, "browser retains looted state across variant selection")
	browser.free()

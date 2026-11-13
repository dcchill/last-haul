class_name RaidPlayer
extends CharacterBody3D

@export var entity_id := ""
@export var speed := 4.317
@export var sprint_speed := 5.612
@export var jump_speed := 8.4
@export var accepts_local_input := true
var authority: RaidAuthority
var settings: SettingsStore
@onready var camera: Camera3D = $Camera3D
@onready var rifle = $Camera3D/Rifle
var aim_blend := 0.0
var armor_plates: ArmorPlates
var movement := MinecraftMovement.new()
var weight_rules: WeightRules = preload("res://resources/weight_rules.tres")
var motion := WeaponMotion.new()
var grounded := false
var crouching := false
var sprinting := false
var move_input := Vector2.ZERO
var jump_input := false
var sprint_input := false
var crouch_input := false
var look_pitch := 0.0
var look_delta := Vector2.ZERO
var fall_distance := 0.0
var scope_viewport: SubViewport
var scope_camera: Camera3D
var scope_lens: MeshInstance3D
var armor_visuals: Node3D
var maska_open := false
var maska_view: Node3D
var requires_release := true
var previous_position := Vector3.ZERO
var hand_rig: WeaponHands

func _ready() -> void:
	$CollisionShape3D.shape = $CollisionShape3D.shape.duplicate()
	camera.cull_mask = 3
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	previous_position = global_position
	hand_rig = WeaponHands.new()
	hand_rig.name = "Hands"
	camera.add_child(hand_rig)
	hand_rig.visible = false

func eye_position() -> Vector3:
	return global_position + Vector3.UP * (1.27 if crouching else 1.62)

func aim_direction() -> Vector3:
	return global_basis * (Basis(Vector3.RIGHT, look_pitch) * Vector3.FORWARD)

func participant() -> RaidParticipant:
	return authority.participants.get(entity_id) if authority != null else null

func refresh_view() -> void:
	var state := participant()
	if state == null:
		return
	motion = WeaponMotion.new()
	requires_release = true
	var entry := state.held_entry()
	rifle.visible = not entry.is_empty()
	if state.weapon != null:
		var gun := state.weapon.definition
		rifle.visible = false
		rifle.configure(gun.model_path, gun.texture_path, gun.animation_path)
		rifle.show_attachments(state.weapon)
		hand_rig.bind(gun.hand_profile)
		hand_rig.visible = true
		rifle.play_clip("equip")
		# Rebuilds happen during authority requests. Fit the replacement before its
		# first rendered frame, keeping the existing hand meshes and evaluated pose.
		rifle.seek_visual(state.weapon, "equip", 0.0)
		WeaponPoseEvaluator.place(rifle, state.weapon, 0, state.weapon.magnification(authority.catalog.definitions))
		hand_rig.evaluate(rifle, state.weapon, "equip", 0, 0, false)
		rifle.visible = true
	elif entry.get("id", "") in ["smoke_nade", "impact_nade"]:
		hand_rig.visible = false
		var model := "smokenadegeo" if entry.id == "smoke_nade" else "impactnadegeo"
		var texture := "smoketexture" if entry.id == "smoke_nade" else "impactnade"
		rifle.configure(ArmoryContent.ROOT + "geo/" + model + ".geo.json", ArmoryContent.ROOT + "textures/item/" + texture + ".png", ArmoryContent.ROOT + "animations/" + model + ".animation.json")
	else:
		rifle.visible = false
		hand_rig.visible = false
	_setup_scope()

func _setup_scope() -> void:
	if is_instance_valid(scope_lens):
		scope_lens.queue_free()
	if scope_viewport == null:
		scope_viewport = SubViewport.new()
		scope_viewport.size = Vector2i(512, 512)
		scope_viewport.world_3d = get_world_3d()
		scope_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(scope_viewport)
		scope_camera = Camera3D.new()
		scope_camera.cull_mask = 1
		scope_camera.near = 0.05
		scope_viewport.add_child(scope_camera)
	var state := participant()
	if state == null or state.weapon == null or state.weapon.magnification(authority.catalog.definitions) <= 1 or not rifle.bones.has("optic_socket"):
		return
	scope_lens = MeshInstance3D.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(32):
		for point in [Vector2.ZERO, Vector2.from_angle(segment * TAU / 32), Vector2.from_angle((segment + 1) * TAU / 32)]:
			surface.set_uv(Vector2(0.5 + point.x * 0.5, 0.5 - point.y * 0.5))
			surface.add_vertex(Vector3(point.x, point.y, 0) * 0.17 * 0.25)
	surface.generate_normals()
	scope_lens.mesh = surface.commit()
	scope_lens.layers = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = scope_viewport.get_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	scope_lens.material_override = material
	rifle.bones.optic_socket.add_child(scope_lens)
	scope_lens.position = Vector3(0, 0.375, 0.39) * 0.25
	for vertical in [true, false]:
		var line := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.004, 0.16) * 0.25 if vertical else Vector2(0.16, 0.004) * 0.25
		line.mesh = quad
		line.layers = 2
		var ink := StandardMaterial3D.new()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ink.albedo_color = Color.BLACK
		ink.cull_mode = BaseMaterial3D.CULL_DISABLED
		line.material_override = ink
		scope_lens.add_child(line)
		line.position.z = 0.0005

func shot_fired(player_id: String, _at: Vector3) -> void:
	if player_id != entity_id:
		return
	var state := participant()
	if state == null or state.weapon == null:
		return
	var gun := state.weapon
	look_pitch = clampf(look_pitch + deg_to_rad(gun.recoil_strength()), -PI / 2, PI / 2)
	var weight: float = {"barret": 1.6, "bolt_action_sniper": 1.6, "double_barrel": 1.6, "rpg": 1.35, "pipe_pistol": 1.1, "junk_gun": 1.1, "mini_gun": 0.38, "upgraded_mini_gun": 0.38, "mac_ten": 0.65}.get(gun.definition.id, 0.8)
	motion.fire(weight * gun.recoil_strength() / gun.definition.recoil_degrees)
	rifle.fire()

func _process(delta: float) -> void:
	var state := participant()
	if state == null:
		return
	if previous_position.distance_to(global_position) > 1.5:
		previous_position = global_position
	var interpolated := previous_position.lerp(global_position, clampf(authority.accumulator / 0.05, 0, 1))
	camera.position = Vector3(0, 1.27 if crouching else 1.62, 0) + global_basis.inverse() * (interpolated - global_position)
	var gun := state.weapon
	if gun != null:
		animate_weapon(delta, gun.aiming, gun)
	else:
		rifle.position = Vector3(0.3, -0.45, -0.75)
		rifle.rotation = Vector3.ZERO
		rifle.animate_preview(delta)
		camera.rotation = Vector3(look_pitch, 0, 0)
		camera.fov = 70
		if scope_viewport != null:
			scope_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	look_delta = Vector2.ZERO

func animate_weapon(delta: float, aiming: bool, weapon: WeaponState) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var progress := 1 - weapon.reload_left / weapon.definition.reload_seconds if weapon.reload_left > 0 else -1.0
	motion.update(delta, aiming, 0.2, look_delta, planar / sprint_speed, sprinting, not weapon.definition.can_aim, progress)
	aim_blend = motion.aim
	rifle.render_fraction = clampf(authority.accumulator, 0, 0.04999)
	rifle.spin_angle = motion.barrel_angle
	rifle.animate(delta, weapon)
	WeaponPoseEvaluator.place(rifle, weapon, aim_blend, weapon.magnification(authority.catalog.definitions), motion.position, motion.angles)
	hand_rig.evaluate(rifle, weapon, rifle.action, rifle.action_time, delta, false)
	camera.rotation = Vector3(look_pitch, 0, 0) + motion.camera_angles * PI / 180.0
	camera.fov = 70 * (1 + 0.15 * motion.springs.get("sprint", Vector2.ZERO).x) * (1 - 0.08 * aim_blend)
	if scope_viewport != null:
		var active := weapon.magnification(authority.catalog.definitions) > 1 and aim_blend >= 0.7 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		scope_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		if active:
			scope_camera.global_transform = camera.global_transform
			scope_camera.fov = rad_to_deg(2 * atan((0.17 * 0.25 * 0.7 / weapon.definition.hand_profile.scope_distance) / weapon.magnification(authority.catalog.definitions)))

func _unhandled_input(event: InputEvent) -> void:
	if not accepts_local_input or authority == null or not authority.is_active() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var multiplier := 1.0
		var state := participant()
		if state.weapon != null:
			multiplier = lerpf(1, 0.65 / state.weapon.magnification(authority.catalog.definitions), aim_blend)
		rotate_y(-event.relative.x * settings.sensitivity * multiplier)
		look_pitch = clampf(look_pitch - event.relative.y * settings.sensitivity * multiplier, -PI / 2, PI / 2)
		look_delta += event.relative * 0.02
	if event.is_action_pressed("reload"):
		authority.request_reload(entity_id)
	if event.is_action_pressed("interact"):
		authority.request_interact(entity_id, interaction_id())
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			authority.request_select(entity_id, event.physical_keycode - KEY_1)
		elif event.physical_keycode == KEY_G:
			authority.request_grenade(entity_id, "smoke_nade" if Input.is_key_pressed(KEY_ALT) else "impact_nade")
		elif event.physical_keycode == KEY_F:
			authority.request_mount_refill(entity_id, interaction_id())
		elif event.physical_keycode == KEY_X:
			authority.request_mount_pickup(entity_id, interaction_id())
		elif event.physical_keycode == KEY_V:
			toggle_maska()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var entry := participant().held_entry()
		if not entry.is_empty() and authority.catalog.items[entry.id].kind == "grenade":
			authority.request_grenade(entity_id)
		elif not entry.is_empty() and authority.catalog.items[entry.id].kind == "mount":
			authority.request_place(entity_id)

func _physics_process(_delta: float) -> void:
	var active := accepts_local_input and authority != null and authority.is_active() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not active:
		requires_release = true
	elif not Input.is_action_pressed("fire") and not Input.is_action_pressed("aim"):
		requires_release = false
	move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active else Vector2.ZERO
	jump_input = active and Input.is_action_pressed("jump")
	sprint_input = active and Input.is_action_pressed("sprint")
	crouch_input = active and Input.is_action_pressed("crouch")
	if participant() != null:
		var customizing := participant().weapon != null and participant().weapon.customizing and not active
		authority.request_input(entity_id, active and not requires_release and Input.is_action_pressed("fire"), active and not requires_release and Input.is_action_pressed("aim"), customizing)

func authority_movement_tick() -> void:
	drive_movement(move_input, jump_input, sprint_input, 0.05)
	if global_position.y < -64:
		authority._apply_damage(self, 1000, null, true)

func drive_movement(input: Vector2, jump: bool, sprint: bool, _delta: float) -> void:
	grounded = test_move(global_transform, Vector3.DOWN * 0.03)
	_set_crouching(crouch_input)
	sprinting = sprint and not crouching and input.y < -0.5
	var burden := 0.0
	var state := participant()
	if state != null:
		burden = weight_rules.burden(state.total_weight())
		sprinting = sprinting and state.stamina > 0
		if sprinting:
			state.stamina = maxf(0, state.stamina - weight_rules.sprint_drain * lerpf(1, weight_rules.heavy_drain_multiplier, burden) * 0.05)
		else:
			state.stamina = minf(weight_rules.stamina_capacity, state.stamina + weight_rules.recovery * lerpf(1, weight_rules.heavy_recovery_multiplier, burden) * 0.05)
	var speed_scale := lerpf(1, weight_rules.sprint_multiplier if sprinting else weight_rules.walk_multiplier, burden)
	var displacement := movement.integrate(input, rotation.y, grounded, sprinting, jump, crouching, 0.6, speed_scale, lerpf(1, weight_rules.jump_multiplier, burden))
	var before_position := global_position
	previous_position = before_position
	var before_y := global_position.y
	var was_grounded := grounded
	var vertical := move_and_collide(Vector3(0, displacement.y, 0))
	if vertical != null:
		movement.velocity.y = 0
		if displacement.y < 0:
			grounded = true
	for axis in [0, 2] if absf(displacement.x) > absf(displacement.z) else [2, 0]:
		var travel := Vector3.ZERO
		travel[axis] = displacement[axis]
		if crouching and grounded:
			while absf(travel[axis]) > 0.0001 and not test_move(Transform3D(global_basis, global_position + travel), Vector3.DOWN * 0.6):
				travel[axis] = move_toward(travel[axis], 0, 0.05)
		var collision := move_and_collide(travel)
		if collision != null:
			var remainder: Vector3 = collision.get_remainder()
			if (grounded or was_grounded) and not test_move(global_transform, Vector3.UP * 0.6) and not test_move(Transform3D(global_basis, global_position + Vector3.UP * 0.6), remainder):
				move_and_collide(Vector3.UP * 0.6)
				move_and_collide(remainder)
				move_and_collide(Vector3.DOWN * 0.6)
			else:
				movement.velocity[axis] = 0
	grounded = test_move(global_transform, Vector3.DOWN * 0.03)
	if global_position.y < before_y:
		fall_distance += before_y - global_position.y
	if grounded:
		if not was_grounded and fall_distance > 0:
			motion.land(minf(1, fall_distance / 4.0))
			if fall_distance > 3 and authority != null:
				authority._apply_damage(self, ceilf(fall_distance - 3), null, true)
		fall_distance = 0
	velocity = (global_position - before_position) * 20

func _set_crouching(value: bool) -> void:
	if value == crouching:
		return
	var shape: BoxShape3D = $CollisionShape3D.shape
	if not value:
		var query := PhysicsShapeQueryParameters3D.new()
		var standing := BoxShape3D.new()
		standing.size = Vector3(0.6, 1.8, 0.6)
		query.shape = standing
		query.transform = Transform3D(global_basis, global_position + Vector3.UP * 0.901)
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query).is_empty():
			return
	crouching = value
	shape.size.y = 1.5 if value else 1.8
	$CollisionShape3D.position.y = shape.size.y * 0.5
	camera.position.y = 1.27 if value else 1.62

func interaction_id() -> String:
	var hit := Ballistics.new().trace(get_world_3d(), eye_position(), aim_direction(), 3.5, [get_rid()])
	if not hit.is_empty() and (hit.collider is RaidEntity or hit.collider is MountedArmory):
		return hit.collider.entity_id
	return ""

func refresh_armor_visuals() -> void:
	if is_instance_valid(armor_visuals):
		armor_visuals.queue_free()
	armor_visuals = Node3D.new()
	add_child(armor_visuals)
	var state := participant()
	if state == null:
		return
	for slot in state.armor.entries:
		var entry: Dictionary = state.armor.entries[slot]
		var definition: ArmorDef = authority.catalog.definitions[entry.id]
		if entry.id == "maska":
			maska_view = load("res://scripts/weapons/bedrock_weapon.gd").new()
			maska_view.show_hands = false
			armor_visuals.add_child(maska_view)
			maska_view.configure(ArmoryContent.ROOT + "geo/maska.geo.json", ArmoryContent.ROOT + "textures/item/maska.png", ArmoryContent.ROOT + "animations/maska.animation.json")
			maska_view.visible = false # First-person camera is inside the helmet; preview shows it.
			continue
		var visual := ArmorVisual.create(definition)
		for mesh in visual.get_children():
			mesh.layers = 4
		armor_visuals.add_child(visual)

func toggle_maska() -> void:
	if not is_instance_valid(maska_view):
		return
	maska_open = not maska_open
	var model := "maska" if maska_open else "maskaopen"
	maska_view.configure(ArmoryContent.ROOT + "geo/" + model + ".geo.json", ArmoryContent.ROOT + "textures/item/maska.png", ArmoryContent.ROOT + "animations/" + model + ".animation.json")
	maska_view.play_clip("open" if maska_open else "close")
	maska_view.autoplay = true
	var expected := maska_open
	var duration: float = maska_view.clips.get("open" if maska_open else "close", {}).get("length", 0.5)
	get_tree().create_timer(maxf(0.01, duration)).timeout.connect(func():
		if not is_instance_valid(maska_view) or maska_open != expected:
			return
		var resting := "maskaopen" if expected else "maska"
		maska_view.configure(ArmoryContent.ROOT + "geo/" + resting + ".geo.json", ArmoryContent.ROOT + "textures/item/maska.png", ArmoryContent.ROOT + "animations/" + resting + ".animation.json"))

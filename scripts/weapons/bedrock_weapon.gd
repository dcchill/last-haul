extends Node3D

# Bedrock/GeckoLib geometry and source animation data, in block units.
@export var model: JSON = preload("res://resources/weapons/kalashnikov.json")
@export var texture: Texture2D = preload("res://resources/weapons/kalashnikov_texture.png")
@export var animations: JSON = preload("res://resources/weapons/kalashnikov.animation.json")
const UNIT := 1.0 / 16.0

var bones: Dictionary = {}
var clips: Dictionary = {}
var action := "equip"
var action_time := 0.0
var reloading := false
var solid_parts: Array[MeshInstance3D] = []
var show_hands := true
var serial := -1
var attachment_views: Array[Node3D] = []
var current_weapon: WeaponState
var spin_angle := 0.0
var autoplay := false
var render_fraction := 0.0

func _process(delta: float) -> void:
	if autoplay:
		animate_preview(delta)

func _ready() -> void:
	_rebuild()

func configure(model_path: String, texture_path: String, animation_path: String) -> void:
	model = load(model_path)
	texture = load(texture_path)
	animations = load(animation_path)
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	bones.clear()
	solid_parts.clear()
	clips.clear()
	attachment_views.clear()
	if model == null or texture == null or animations == null:
		return
	var geometry: Dictionary = model.data["minecraft:geometry"][0].duplicate(true)
	# The source mounted minigun contains two identically named cosmetic bones.
	# Preserve both meshes; animation/parent references resolve to the first bone.
	var seen_names: Dictionary = {}
	for bone in geometry.bones:
		var original: String = bone.name
		var count: int = seen_names.get(original, 0)
		seen_names[original] = count + 1
		if count > 0:
			bone.name = original + "__" + str(count)
	var texture_size := Vector2(geometry.description.texture_width, geometry.description.texture_height)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for bone in geometry.bones:
		var node := Node3D.new()
		node.name = bone.name
		node.set_meta("pivot", _vector(bone.get("pivot", [0, 0, 0])))
		bones[bone.name] = node
	for bone in geometry.bones:
		var node: Node3D = bones[bone.name]
		var parent: Node3D = bones.get(bone.get("parent", ""), self)
		parent.add_child(node)
		var pivot: Vector3 = node.get_meta("pivot")
		var parent_pivot: Vector3 = parent.get_meta("pivot", Vector3.ZERO)
		node.position = (pivot - parent_pivot) * UNIT
		node.rotation_degrees = _vector(bone.get("rotation", [0, 0, 0])) * Vector3(-1, 1, 1)
		node.set_meta("rest_position", node.position)
		node.set_meta("rest_rotation", node.rotation_degrees)
		for cube in bone.get("cubes", []):
			var part := MeshInstance3D.new()
			part.mesh = _cube_mesh(cube, pivot, texture_size)
			part.material_override = material
			part.layers = 2 if show_hands else 1
			_register_solid(part, cube, pivot, str(bone.name))
			node.add_child(part)
	_compile_animations()
	action = "idle"
	action_time = 0
	serial = -1

func play_if_changed(clip_name: String) -> void:
	if action != clip_name:
		play_clip(clip_name)

func animate_preview(delta: float) -> void:
	action_time += delta
	var clip: Dictionary = clips.get(action, {})
	var duration: float = clip.get("length", 0.0)
	if duration > 0 and clip.get("loop", false):
		action_time = fmod(action_time, duration)
	apply_clip(action, action_time)

func _compile_animations() -> void:
	clips.clear()
	for clip_name in animations.data.animations:
		var source: Dictionary = animations.data.animations[clip_name]
		var loop_mode: Variant = source.get("loop", false)
		var clip := {"length": float(source.get("animation_length", 0.0)), "loop": loop_mode is bool and loop_mode, "hold": loop_mode is String and loop_mode == "hold_on_last_frame", "bones": {}}
		for bone_name in source.get("bones", {}):
			if show_hands and str(bone_name).ends_with("hand_socket"):
				continue
			if not bones.has(bone_name):
				continue
			var tracks := {}
			for property in source.bones[bone_name]:
				if property not in ["position", "rotation", "scale"]:
					continue
				var raw: Variant = source.bones[bone_name][property]
				if raw is Array:
					raw = {"vector": raw}
				var keys: Dictionary = raw
				if keys.has("vector"):
					tracks[property] = [{"time": 0.0, "value": _vector(keys.vector), "easing": "linear", "steps": 1.0}]
					continue
				var times := keys.keys()
				times.sort_custom(func(a, b): return float(a) < float(b))
				var frames := []
				for time in times:
					var key: Variant = keys[time]
					var values: Array = key.get("vector", []) if key is Dictionary else key
					if values.size() == 3:
						frames.append({"time": float(time), "value": _vector(values), "easing": key.get("easing", "linear") if key is Dictionary else "linear", "steps": float(key.get("easingArgs", [1])[0]) if key is Dictionary and not key.get("easingArgs", []).is_empty() else 1.0})
				tracks[property] = frames
			clip.bones[bone_name] = tracks
		clips[clip_name] = clip

func play_clip(clip_name: String) -> bool:
	if not clips.has(clip_name):
		return false
	action = clip_name
	action_time = 0.0
	return true

func fire() -> void:
	play_clip("fire")

func animate(delta: float, weapon: WeaponState) -> void:
	current_weapon = weapon
	if serial != weapon.action_serial:
		serial = weapon.action_serial
		play_clip(weapon.last_action)
	if weapon.reload_left > 0:
		action = weapon.reload_action
		action_time = weapon.definition.reload_seconds - weapon.reload_left + render_fraction
	else:
		action_time += delta
	var clip: Dictionary = clips.get(action, {})
	var length: float = clip.get("length", 0.0)
	if length > 0 and action_time >= length:
		if clip.get("loop", false):
			action_time = fmod(action_time, length)
		elif not clip.get("hold", false):
			action = "idle"
			action_time = 0
	apply_clip(action, action_time)
	_update_parts(weapon)

func seek_visual(weapon: WeaponState, clip_name: String, seconds: float) -> void:
	action = clip_name
	action_time = seconds
	apply_clip(action, action_time)
	var reload := action.begins_with("reload") or action == "unload"
	_update_parts(weapon, clampf(seconds / weapon.definition.reload_seconds, 0, 1) if reload else -1.0)

func _update_parts(weapon: WeaponState, override_progress: float = -2.0) -> void:
	var progress := override_progress if override_progress > -2.0 else 1.0 - weapon.reload_left / weapon.definition.reload_seconds if weapon.reload_left > 0 else -1.0
	var magazine_reload := not weapon.definition.magazine_id.is_empty() and progress >= 0
	var had_magazine: bool = not weapon.data.magazine.is_empty()
	var visible_magazine: bool = (progress < 0.36 and had_magazine or progress >= 0.46 and weapon.reload_action != "unload") if magazine_reload else had_magazine
	for name in ["mag", "cogwheel"]:
		if bones.has(name) and not weapon.definition.magazine_id.is_empty():
			bones[name].visible = visible_magazine
	if bones.has("scope"):
		bones.scope.visible = false
	if bones.has("rocket"):
		bones.rocket.visible = weapon.magazine > 0 or progress >= 0.28
	for name in ["fx", "firefx", "muzzleflash"]:
		if bones.has(name):
			bones[name].visible = action == "fire" and action_time < 0.1 and not weapon.suppressed()
	if not weapon.definition.can_aim:
		if bones.has("barrel"):
			bones.barrel.rotation_degrees.z = spin_angle
		if bones.has("cogwheel") and progress < 0:
			bones.cogwheel.rotation_degrees.z = -spin_angle * 0.25

func show_attachments(weapon: WeaponState) -> void:
	for slot in weapon.data.attachments:
		var socket: Node3D = bones.get(slot + "_socket")
		if socket == null:
			continue
		var entry: Dictionary = weapon.data.attachments[slot]
		var path := ArmoryContent.ROOT + "models/item/" + str(entry.id) + ".json"
		if not ResourceLoader.exists(path):
			continue
		var data: Dictionary = load(path).data
		var mount := Node3D.new()
		socket.add_child(mount)
		attachment_views.append(mount)
		mount.scale = Vector3.ONE * (0.18 if slot == "grip" else 0.22 if slot == "muzzle" else 0.25)
		mount.position = Vector3(0, -0.25, 0) * 0.18 if slot == "grip" else Vector3(0, 0, -0.5) * 0.22 if slot == "muzzle" else Vector3(0, 0.375 if entry.id != "reflex_sight" else 0.25, 0) * 0.25
		for element in data.get("elements", []):
			var faces := {}
			for face in element.get("faces", {}):
				var uv: Array = element.faces[face].get("uv", [0, 0, 16, 16])
				faces[face] = {"uv": [uv[0], uv[1]], "uv_size": [uv[2] - uv[0], uv[3] - uv[1]]}
			var cube := {"origin": element.from, "size": [_vector(element.to).x - _vector(element.from).x, _vector(element.to).y - _vector(element.from).y, _vector(element.to).z - _vector(element.from).z], "uv": faces}
			if element.has("rotation"):
				var angles := Vector3.ZERO
				angles[{"x": 0, "y": 1, "z": 2}[element.rotation.axis]] = element.rotation.angle
				cube.rotation = [angles.x, angles.y, angles.z]
				cube.pivot = element.rotation.origin
			var part := MeshInstance3D.new()
			part.mesh = _cube_mesh(cube, Vector3(8, 8, 8), Vector2(16, 16))
			part.layers = 2
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.12, 0.14, 0.15)
			var ref: String = element.faces.values()[0].get("texture", "#metal") if not element.get("faces", {}).is_empty() else "#metal"
			var texture_ref: String = data.get("textures", {}).get(ref.trim_prefix("#"), "")
			var texture_path := ArmoryContent.ROOT + "textures/" + texture_ref.trim_prefix("createarmory:") + ".png"
			if ResourceLoader.exists(texture_path):
				material.albedo_texture = load(texture_path)
				material.albedo_color = Color.WHITE
			if "glass" in ref:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color = Color(0.2, 0.7, 0.8, 0.12)
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			part.material_override = material
			if not "glass" in ref:
				_register_solid(part, cube, Vector3(8, 8, 8), "attachment:" + str(entry.id))
			mount.add_child(part)

func apply_clip(clip_name: String, time: float) -> void:
	for node in bones.values():
		node.position = node.get_meta("rest_position")
		node.rotation_degrees = node.get_meta("rest_rotation")
		node.scale = Vector3.ONE
	if not clips.has(clip_name):
		return
	for bone_name in clips[clip_name].bones:
		var node: Node3D = bones[bone_name]
		var tracks: Dictionary = clips[clip_name].bones[bone_name]
		if tracks.has("position"):
			node.position += _sample(tracks.position, time) * UNIT
		if tracks.has("rotation"):
			var angles := _sample(tracks.rotation, time)
			angles.x = -angles.x
			node.rotation_degrees += angles
		if tracks.has("scale"):
			node.scale = _sample(tracks.scale, time)

func _sample(frames: Array, time: float) -> Vector3:
	if frames.is_empty():
		return Vector3.ZERO
	var previous: Dictionary = frames[0]
	for frame in frames:
		if time < frame.time:
			var weight := clampf((time - previous.time) / (frame.time - previous.time), 0.0, 1.0)
			return previous.value.lerp(frame.value, _ease(weight, frame.easing, frame.steps))
		previous = frame
	return previous.value

func _ease(weight: float, easing: String, steps: float) -> float:
	if easing == "step":
		return floor(weight * maxf(steps, 1.0)) / maxf(steps, 1.0)
	if easing == "linear":
		return weight
	var transition := Tween.TRANS_LINEAR
	if easing.ends_with("Sine"):
		transition = Tween.TRANS_SINE
	elif easing.ends_with("Quad"):
		transition = Tween.TRANS_QUAD
	elif easing.ends_with("Cubic"):
		transition = Tween.TRANS_CUBIC
	elif easing.ends_with("Quart"):
		transition = Tween.TRANS_QUART
	elif easing.ends_with("Quint"):
		transition = Tween.TRANS_QUINT
	elif easing.ends_with("Expo"):
		transition = Tween.TRANS_EXPO
	elif easing.ends_with("Back"):
		transition = Tween.TRANS_BACK
	var direction := Tween.EASE_IN_OUT if easing.begins_with("easeInOut") else (Tween.EASE_OUT if easing.begins_with("easeOut") else Tween.EASE_IN)
	return Tween.interpolate_value(0.0, 1.0, weight, 1.0, transition, direction)

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _cube_mesh(cube: Dictionary, bone_pivot: Vector3, texture_size: Vector2) -> ArrayMesh:
	var origin := _vector(cube.origin)
	var size := _vector(cube.size)
	var inflate: float = cube.get("inflate", 0.0)
	var low := origin - Vector3.ONE * inflate
	var high := origin + size + Vector3.ONE * inflate
	var pivot := _vector(cube.get("pivot", cube.origin))
	var angles := _vector(cube.get("rotation", [0, 0, 0]))
	angles.x = -angles.x
	var rotation := Basis.from_euler(angles * PI / 180.0)
	var vertices := [
		Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z),
		Vector3(high.x, high.y, low.z), Vector3(low.x, high.y, low.z),
		Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z),
		Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z)]
	var faces := {"north": [2, 3, 0, 1], "south": [7, 6, 5, 4],
		"east": [6, 2, 1, 5], "west": [3, 7, 4, 0],
		"up": [6, 7, 3, 2], "down": [1, 0, 4, 5]}
	var uv_faces: Dictionary = {}
	if cube.get("uv") is Array:
		var u := float(cube.uv[0])
		var v := float(cube.uv[1])
		var w := size.x
		var h := size.y
		var d := size.z
		uv_faces = {"west": {"uv": [u, v + d], "uv_size": [d, h]}, "north": {"uv": [u + d, v + d], "uv_size": [w, h]},
			"east": {"uv": [u + d + w, v + d], "uv_size": [d, h]}, "south": {"uv": [u + d * 2 + w, v + d], "uv_size": [w, h]},
			"up": {"uv": [u + d, v], "uv_size": [w, d]}, "down": {"uv": [u + d + w, v + d], "uv_size": [w, -d]}}
	else:
		uv_faces = cube.get("uv", {})
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		if not uv_faces.has(face):
			continue
		var uv_data: Dictionary = uv_faces[face]
		var uv := Vector2(uv_data.uv[0], uv_data.uv[1])
		var span := Vector2(uv_data.uv_size[0], uv_data.uv_size[1])
		var uvs := [uv, uv + Vector2(span.x, 0), uv + span, uv + Vector2(0, span.y)]
		for index in [0, 1, 2, 0, 2, 3]:
			surface.set_uv(uvs[(3 - index) if cube.get("mirror", false) else index] / texture_size)
			surface.add_vertex((pivot + rotation * (vertices[faces[face][index]] - pivot) - bone_pivot) * UNIT)
	surface.generate_normals()
	return surface.commit()

func _register_solid(part: MeshInstance3D, cube: Dictionary, bone_pivot: Vector3, tag: String) -> void:
	if tag in ["fx", "firefx", "muzzleflash"]:
		return
	var size := _vector(cube.size) + Vector3.ONE * float(cube.get("inflate", 0.0)) * 2
	if minf(size.x, minf(size.y, size.z)) <= 0.00001:
		return
	var pivot := _vector(cube.get("pivot", cube.origin))
	var angles := _vector(cube.get("rotation", [0, 0, 0])) * Vector3(-1, 1, 1)
	var basis := Basis.from_euler(angles * PI / 180.0)
	var center := (pivot + basis * (_vector(cube.origin) + _vector(cube.size) * 0.5 - pivot) - bone_pivot) * UNIT
	part.set_meta("solid_pose", Transform3D(basis, center))
	part.set_meta("solid_half", size * UNIT * 0.5)
	part.set_meta("solid_tag", tag)
	solid_parts.append(part)

func solid_shapes(space: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var inverse := space.global_transform.affine_inverse()
	for part in solid_parts:
		if not is_instance_valid(part) or not part.is_visible_in_tree():
			continue
		var pose: Transform3D = inverse * part.global_transform * part.get_meta("solid_pose")
		if absf(pose.basis.determinant()) < 0.00000001:
			continue
		var shape := HandClearance.box(pose, part.get_meta("solid_half"))
		shape.tag = part.get_meta("solid_tag")
		result.append(shape)
	return result

func contact_transform(bone_name: String, model_point: Vector3) -> Transform3D:
	var bone: Node3D = bones.get(bone_name)
	if bone == null:
		return global_transform
	var point := (model_point - Vector3(bone.get_meta("pivot"))) * UNIT
	return Transform3D(bone.global_basis.orthonormalized(), bone.to_global(point))

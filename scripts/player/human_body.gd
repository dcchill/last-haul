extends "res://scripts/characters/block_character.gd"

@export var first_person := true
var torso: Node3D
var head: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var veins: Array[MeshInstance3D] = []
var clock := 0.0
var phase := 0.0
var boot_left := 0.0
var damage_left := 0.0
var landing := 0.0
var previous_health := RaidParticipant.MAX_HEALTH
var was_grounded := false
var symptom_stage := 0
var breath: AudioStreamPlayer3D
var symptom_clock := 0.0

func _ready() -> void:
	torso = pivot(self, "Torso", Vector3.ZERO)
	part(torso, Vector3(0.44, 0.48, 0.25), Vector3(0, 1.08, 0.18), "515b4b")
	part(torso, Vector3(0.025, 0.42, 0.018), Vector3(0, 1.09, 0.046), "a49b7d")
	for side in [-1, 1]:
		part(torso, Vector3(0.13, 0.10, 0.025), Vector3(side * 0.12, 1.07, 0.038), "424a3e")
	part(torso, Vector3(0.37, 0.07, 0.27), Vector3(0, 0.82, 0.16), "302e29")
	part(torso, Vector3(0.13, 0.12, 0.13), Vector3(0, 1.38, 0.10), "b6b59d")
	head = pivot(torso, "HumanHead", Vector3(0, 1.59, 0.07))
	part(head, Vector3(0.29, 0.35, 0.28), Vector3.ZERO, "b6b59d")
	part(head, Vector3(0.31, 0.10, 0.29), Vector3(0, 0.16, 0), "3f3c34")
	part(head, Vector3(0.06, 0.07, 0.04), Vector3(0, -0.015, -0.15), "a6a58e")
	for side in [-1, 1]:
		part(head, Vector3(0.045, 0.025, 0.012), Vector3(side * 0.075, 0.045, -0.146), "353d36")
		veins.append(part(head, Vector3(0.012, 0.11, 0.012), Vector3(side * 0.12, -0.04, -0.145), "635d66"))
		var leg := pivot(torso, "LeftLeg" if side < 0 else "RightLeg", Vector3(side * 0.135, 0.77, 0.10))
		part(leg, Vector3(0.19, 0.35, 0.21), Vector3(0, -0.18, 0), "57534b")
		part(leg, Vector3(0.17, 0.27, 0.19), Vector3(0, -0.47, 0), "4a473f")
		part(leg, Vector3(0.22, 0.15, 0.31), Vector3(0, -0.68, -0.045), "302f2a")
		part(leg, Vector3(0.23, 0.035, 0.32), Vector3(0, -0.745, -0.045), "222823")
		legs.append(leg)
		var arm := pivot(torso, "LeftArm" if side < 0 else "RightArm", Vector3(side * 0.32, 1.28, 0.10))
		part(arm, Vector3(0.18, 0.30, 0.21), Vector3(0, -0.14, 0), "515b4b")
		part(arm, Vector3(0.16, 0.22, 0.19), Vector3(0, -0.40, 0), "424a3e")
		part(arm, Vector3(0.17, 0.065, 0.20), Vector3(0, -0.51, 0), "b8b19a" if side < 0 else "b6b59d")
		part(arm, Vector3(0.06, 0.035, 0.012), Vector3(0.02, -0.51, -0.106), "704b42")
		part(arm, Vector3(0.16, 0.10, 0.18), Vector3(0, -0.59, 0), "373e35")
		arms.append(arm)
	set_first_person(first_person)
	breath = AudioStreamPlayer3D.new()
	breath.max_distance = 2
	breath.volume_db = -34
	add_child(breath)

func set_first_person(enabled: bool) -> void:
	first_person = enabled
	shadow_only(head, enabled)
	for arm in arms: shadow_only(arm, enabled)

func pose(delta: float, speed := 0.0, crouching := false, advancing := false, terminal := false) -> void:
	clock += delta
	phase += delta * (9.0 if speed > 0.2 else 1.5)
	damage_left = maxf(0, damage_left - delta)
	landing = move_toward(landing, 0, delta * 0.4)
	torso.position.y = sin(clock * (3 if advancing else 1.8)) * 0.006 - landing - (0.22 if crouching else 0.0)
	torso.rotation.x = move_toward(torso.rotation.x, 1.15 if terminal else 0.035 if advancing else 0.0, delta * 1.5)
	for i in range(2):
		legs[i].rotation.x = sin(phase + i * PI) * minf(speed * 0.1, 0.5)
		arms[i].rotation.x = -legs[i].rotation.x
	head.rotation.z = sin(clock * 1.3) * (0.035 if terminal else 0.008)
	for vein in veins: vein.visible = symptom_stage > 0

func _process(delta: float) -> void:
	if not get_parent() is RaidPlayer: return
	var actor: RaidPlayer = get_parent()
	var state := actor.participant()
	if state == null: return
	if state.health < previous_health: damage_left = 0.25
	previous_health = state.health
	if actor.grounded and not was_grounded: landing = 0.08
	was_grounded = actor.grounded
	symptom_stage = 2 if state.infection_remaining <= 60 else 1 if state.infection_remaining <= 120 else 0
	pose(delta, Vector2(actor.velocity.x, actor.velocity.z).length() if actor.authority.is_active() else 0.0, actor.crouching, symptom_stage > 0, state.infection_remaining <= 0 or state.health <= 0)
	symptom_clock += delta
	if symptom_stage > 0 and actor.authority.is_active() and symptom_clock > (9.0 if symptom_stage == 2 else 5.0):
		symptom_clock = 0
		breath.stream = symptom_sound(symptom_stage == 2)
		breath.play()

static func symptom_sound(cough: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var samples := PackedByteArray()
	var count := 15000 if cough else 24000
	samples.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 47
	var filtered := 0.0
	for i in range(count):
		var t := float(i) / count
		filtered = lerpf(filtered, noise.randf_range(-1, 1), 0.22)
		var envelope := sin(PI * t) * (maxf(0, sin(t * PI * 7)) if cough else 1.0)
		samples.encode_s16(i * 2, int(filtered * envelope * 10000))
	wav.data = samples
	return wav

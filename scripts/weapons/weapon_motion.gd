class_name WeaponMotion
extends RefCounted

var springs: Dictionary = {}
var aim_progress := 0.0
var aim := 0.0
var phase := 0.0
var shot_age := 10.0
var spin_speed := 0.0
var barrel_angle := 0.0
var position := Vector3.ZERO
var angles := Vector3.ZERO
var camera_angles := Vector3.ZERO

func spring(name: String, target: float, frequency: float, dt: float) -> float:
	var state: Vector2 = springs.get(name, Vector2.ZERO)
	var offset := state.x - target
	var decay := exp(-frequency * dt)
	var travel := (state.y + frequency * offset) * dt
	state = Vector2(target + (offset + travel) * decay, (state.y - frequency * travel) * decay)
	springs[name] = state
	return state.x

func impulse(name: String, strength: float, limit: float) -> void:
	var state: Vector2 = springs.get(name, Vector2.ZERO)
	state.y = minf(limit, state.y + strength)
	springs[name] = state

func fire(strength: float) -> void:
	impulse("kick", strength * 18, 32)
	shot_age = 0

func land(speed: float) -> void:
	impulse("landing", minf(1, speed) * 10, 12)

func update(dt: float, aiming: bool, ads_seconds: float, look: Vector2, speed: float, sprinting: bool, minigun: bool, progress: float) -> void:
	if dt <= 0:
		return
	aim_progress = clampf(aim_progress + (dt if aiming else -dt) / ads_seconds, 0, 1)
	aim = aim_progress * aim_progress * (3 - 2 * aim_progress)
	var kick := minf(0.7, spring("kick", 0, 22, dt))
	if springs.kick.x > 0.7:
		springs.kick = Vector2(0.7, minf(0, springs.kick.y))
	var sway_x := spring("sway_x", clampf(look.x, -1, 1), 14, dt)
	var sway_y := spring("sway_y", clampf(look.y, -1, 1), 14, dt)
	var landing := spring("landing", 0, 18, dt)
	var movement := spring("movement", clampf(speed, 0, 1), 12, dt)
	var sprint := spring("sprint", 1 if sprinting else 0, 14, dt)
	phase = fmod(phase + dt * (9 + sprint * 5), 100 * PI)
	var present := 0.0 if progress < 0 else smoothstep(0, 1, progress / 0.16) * (1 - smoothstep(0, 1, (progress - 0.8) / 0.2))
	var tilt := spring("handling", present, 18, dt)
	var decorate := 1 - aim
	var walk := movement * decorate * (0.25 if progress >= 0 else 1.0)
	var breath := sin(phase * 0.22) * 0.0015 * decorate
	position = Vector3(decorate * (-sway_x * 0.025 - tilt * 0.14) + sin(phase) * walk * 0.012,
		breath + decorate * (tilt * 0.30 - landing * 0.035 - sprint * 0.045) + cos(phase * 2) * walk * 0.008,
		kick * 0.09 + tilt * 0.035 * decorate)
	angles = Vector3(-kick * (2.8 - aim * 2.4) + decorate * (sway_y * 2 + landing * 3 + tilt * 7),
		decorate * (-sway_x * 2 + tilt * 4), decorate * (-sway_x * 2.5 - tilt * 17 + sin(phase) * walk * 1.5))
	camera_angles = Vector3(clampf(-kick * 0.65 + landing * 0.4 + tilt * 0.12, -0.75, 0.75) * decorate, 0,
		clampf(-kick * 0.18 - tilt * 0.18, -0.35, 0.35) * decorate)
	var spinning := clampf(0.16 - shot_age, 0, dt) if minigun and progress < 0 else 0.0
	_spin(spinning, 1440)
	_spin(dt - spinning, 0)
	shot_age += dt

func _spin(dt: float, target: float) -> void:
	var rate := 5.0 if target == 0 else 18.0
	var decay := exp(-dt * rate)
	barrel_angle = fmod(barrel_angle + target * dt + (spin_speed - target) * (1 - decay) / rate, 1440)
	spin_speed = target + (spin_speed - target) * decay

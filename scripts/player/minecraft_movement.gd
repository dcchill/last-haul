class_name MinecraftMovement
extends RefCounted

const TICK := 0.05
var velocity := Vector3.ZERO # blocks per gameplay tick
var jump_delay := 0

func integrate(input: Vector2, yaw: float, grounded: bool, sprint: bool, jump: bool, crouch: bool, slipperiness: float = 0.6) -> Vector3:
	if jump_delay > 0:
		jump_delay -= 1
	if not jump:
		jump_delay = 0
	var intent := input.limit_length(1.0) * 0.98 * (0.3 if crouch else 1.0)
	var friction := slipperiness * 0.91 if grounded else 0.91
	var acceleration := (0.1 * (1.3 if sprint else 1.0) * 0.21600002 / pow(slipperiness, 3)) if grounded else (0.026 if sprint else 0.02)
	if grounded and jump and jump_delay == 0:
		velocity.y = 0.42
		if sprint:
			velocity += Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.2)
		jump_delay = 10
	velocity += Basis(Vector3.UP, yaw) * Vector3(intent.x * acceleration, 0, intent.y * acceleration)
	var displacement := velocity
	velocity.x *= friction
	velocity.z *= friction
	velocity.y = (velocity.y - 0.08) * 0.98
	for axis in range(3):
		if absf(velocity[axis]) < 0.003:
			velocity[axis] = 0
	return displacement

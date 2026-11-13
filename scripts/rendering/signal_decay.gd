class_name SignalDecay
extends CanvasLayer

@export var environment_path: NodePath = ^"../WorldEnvironment"
@export var enabled := true:
	set(value):
		enabled = value
		refresh()
@export_range(0.0, 1.0) var strength := 0.85:
	set(value):
		strength = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		refresh()
@export_range(1.0, 8.0) var dither_scale := 2.0
@export_enum("Off:1", "2x:2", "3x:3", "4x:4") var pixel_size: int = 2:
	set(value):
		pixel_size = clampi(value, 1, 4)
		refresh()
@export_range(0.0, 1.0) var dither_amplitude := 0.65
@export_range(8, 256) var color_levels := 32
@export_range(0.0, 1.0) var saturation := 0.75
@export var tint := Color(0.92, 1.0, 0.94)
@export_range(0.0, 200.0) var haze_start := 12.0
@export_range(0.1, 500.0) var haze_end := 45.0
@export var haze_color := Color("687368")
@export_range(0.0, 1.0) var haze_density := 0.45
@export_range(0.0, 0.05) var grain := 0.006
@export var flicker_enabled := true:
	set(value):
		flicker_enabled = value
		pulse_left = 0.0
		refresh()
@export_range(0.0, 0.02) var flicker_intensity := 0.02
@export var flicker_interval := Vector2(12.0, 25.0)
@export var flicker_duration := Vector2(0.06, 0.12)

var bypassed := false
var sensor_stress := 0.0
var pulse_left := 0.0
var pulse_intensity := 0.0
var flicker_left := 0.0
var elapsed := 0.0
var random := RandomNumberGenerator.new()
var world_environment: WorldEnvironment
var original_environment: Environment
var sensor_environment: Environment
@onready var screen: ColorRect = $Screen
var shader: ShaderMaterial

func _ready() -> void:
	shader = screen.material.duplicate()
	screen.material = shader
	world_environment = get_node_or_null(environment_path) as WorldEnvironment
	if world_environment != null and world_environment.environment != null:
		original_environment = world_environment.environment
		sensor_environment = original_environment.duplicate()
	random.randomize()
	flicker_left = random.randf_range(flicker_interval.x, flicker_interval.y)
	refresh()

func configure(settings: SettingsStore) -> void:
	enabled = settings.sensor_enabled
	strength = settings.sensor_strength
	flicker_enabled = settings.sensor_flicker
	pixel_size = settings.sensor_pixel_size

func is_active() -> bool:
	return enabled and not bypassed and strength > 0.0

func toggle_comparison() -> bool:
	bypassed = not bypassed
	refresh()
	return is_active()

func set_sensor_stress(amount: float) -> void:
	sensor_stress = clampf(amount, 0.0, 1.0) if is_finite(amount) else 0.0
	refresh()

func trigger_glitch(intensity: float, duration: float) -> void:
	if not flicker_enabled or not is_active():
		return
	pulse_intensity = clampf(intensity, 0.0, 1.0) if is_finite(intensity) else 0.0
	pulse_left = clampf(duration, 0.0, 1.0) if is_finite(duration) else 0.0

func refresh() -> void:
	if not is_node_ready() or shader == null:
		return
	screen.visible = is_active()
	var effective_strength := strength * 2.0
	if world_environment != null and sensor_environment != null:
		world_environment.environment = sensor_environment if is_active() else original_environment
		sensor_environment.fog_enabled = true
		sensor_environment.fog_mode = Environment.FOG_MODE_DEPTH
		sensor_environment.fog_depth_begin = maxf(haze_start, 0.0)
		sensor_environment.fog_depth_end = maxf(haze_end, haze_start + 0.1)
		sensor_environment.fog_density = minf(clampf(haze_density, 0.0, 1.0) * effective_strength, 1.0)
		sensor_environment.fog_light_color = haze_color
		sensor_environment.fog_light_energy = 1.0
		sensor_environment.fog_sun_scatter = 0.0
		# Keep the yard's dark background under the distant haze.
		sensor_environment.fog_sky_affect = 0.35
	shader.set_shader_parameter("strength", effective_strength)
	shader.set_shader_parameter("pixel_size", float(pixel_size))
	shader.set_shader_parameter("dither_scale", maxf(dither_scale, 1.0))
	shader.set_shader_parameter("dither_amplitude", clampf(dither_amplitude, 0.0, 1.0))
	shader.set_shader_parameter("color_levels", maxf(8.0, color_levels * (1.0 - sensor_stress * 0.5)))
	shader.set_shader_parameter("saturation", saturation)
	shader.set_shader_parameter("tint", tint)
	shader.set_shader_parameter("grain", grain * (1.0 + sensor_stress * 2.0))
	if not is_active() or not flicker_enabled:
		pulse_left = 0.0
		shader.set_shader_parameter("disturbance", 0.0)
		shader.set_shader_parameter("grain_tick", 0.0)

func _process(delta: float) -> void:
	if not is_active() or not flicker_enabled:
		return
	elapsed += delta
	flicker_left -= delta
	if flicker_left <= 0.0:
		trigger_glitch(clampf(flicker_intensity, 0.0, 0.02) / 0.08,
			random.randf_range(maxf(0.01, flicker_duration.x), maxf(0.01, flicker_duration.y)))
		flicker_left = random.randf_range(maxf(1.0, flicker_interval.x), maxf(1.0, flicker_interval.y))
	pulse_left = maxf(0.0, pulse_left - delta)
	shader.set_shader_parameter("grain_tick", floor(elapsed * 12.0))
	shader.set_shader_parameter("disturbance", pulse_intensity * 0.08 if pulse_left > 0.0 else 0.0)

func _exit_tree() -> void:
	if is_instance_valid(world_environment) and world_environment.environment == sensor_environment:
		world_environment.environment = original_environment

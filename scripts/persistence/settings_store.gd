class_name SettingsStore
extends RefCounted

var path: String
var sensitivity: float = 0.0025
var volume: float = 0.7
var fullscreen: bool = false
var starter_loadout: String = "standard"
var sensor_enabled := true
var sensor_strength := 0.85
var sensor_flicker := true
var sensor_pixel_size := 2

func _init(settings_path: String = "user://settings.cfg") -> void:
	path = settings_path

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var mouse: Variant = config.get_value("settings", "sensitivity", sensitivity)
	var sound: Variant = config.get_value("settings", "volume", volume)
	var screen: Variant = config.get_value("settings", "fullscreen", fullscreen)
	var kit: Variant = config.get_value("settings", "starter_loadout", starter_loadout)
	var sensor: Variant = config.get_value("settings", "sensor_enabled", sensor_enabled)
	var strength: Variant = config.get_value("settings", "sensor_strength", sensor_strength)
	var flicker: Variant = config.get_value("settings", "sensor_flicker", sensor_flicker)
	var pixels: Variant = config.get_value("settings", "sensor_pixel_size", sensor_pixel_size)
	if pixels is int and pixels >= 1 and pixels <= 4:
		sensor_pixel_size = pixels
	if sensor is bool:
		sensor_enabled = sensor
	if (strength is float or strength is int) and is_finite(float(strength)):
		sensor_strength = clampf(float(strength), 0.0, 1.0)
	if flicker is bool:
		sensor_flicker = flicker
	if (mouse is float or mouse is int) and is_finite(float(mouse)):
		sensitivity = clampf(float(mouse), 0.0005, 0.01)
	if (sound is float or sound is int) and is_finite(float(sound)):
		volume = clampf(float(sound), 0.0, 1.0)
	if screen is bool:
		fullscreen = screen
	if kit is String and WeaponState.LOADOUTS.has(kit):
		starter_loadout = kit

func apply() -> void:
	AudioServer.set_bus_volume_linear(0, volume)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("settings", "sensitivity", sensitivity)
	config.set_value("settings", "volume", volume)
	config.set_value("settings", "fullscreen", fullscreen)
	config.set_value("settings", "starter_loadout", starter_loadout)
	config.set_value("settings", "sensor_enabled", sensor_enabled)
	config.set_value("settings", "sensor_strength", sensor_strength)
	config.set_value("settings", "sensor_flicker", sensor_flicker)
	config.set_value("settings", "sensor_pixel_size", sensor_pixel_size)
	return config.save(path)

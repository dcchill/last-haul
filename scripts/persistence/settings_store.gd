class_name SettingsStore
extends RefCounted

var path: String
var sensitivity: float = 0.0025
var volume: float = 0.7
var fullscreen: bool = false
var starter_loadout: String = "standard"

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
	return config.save(path)

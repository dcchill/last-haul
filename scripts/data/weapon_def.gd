class_name WeaponDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var armory: bool = false
@export var model_path: String = ""
@export var texture_path: String = ""
@export var animation_path: String = ""
@export var hand_profile: WeaponHandProfile
@export var feed: String = "DIRECT"
@export var magazine_id: String = ""
@export var interval_ticks: int = 4
@export var reload_ticks: int = 40
@export var automatic: bool = false
@export var pellets: int = 1
@export var damage: float = 4.0
@export var projectile_speed: float = 9.0
@export var spread: float = 1.0
@export var recoil_degrees: float = 0.45
@export var head_multiplier: float = 1.5
@export var can_aim: bool = true
@export var attachment_slots: int = 0
@export var ammo: AmmoDef
@export_range(1, 100) var magazine_size: int = 12
@export_range(0, 500) var starter_reserve: int = 48
@export_range(0.05, 5.0) var fire_interval: float = 0.2
@export_range(0.1, 10.0) var reload_seconds: float = 1.5
@export_range(1.0, 500.0) var range_meters: float = 100.0
@export_range(1.0, 2000.0) var muzzle_velocity: float = 715.0
@export_range(0.0, 2.0) var vertical_recoil: float = 0.12
@export_range(0.0, 2.0) var horizontal_recoil: float = 0.04
@export_range(0.05, 5.0) var ads_time: float = 1.0
@export_range(0.0, 2.0) var sway: float = 0.02
@export_range(0.0, 1.0) var hipfire_spread: float = 0.025

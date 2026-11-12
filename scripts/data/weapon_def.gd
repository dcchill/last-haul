class_name WeaponDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var ammo: AmmoDef
@export_range(1, 100) var magazine_size: int = 12
@export_range(0, 500) var starter_reserve: int = 48
@export_range(0.05, 5.0) var fire_interval: float = 0.2
@export_range(0.1, 10.0) var reload_seconds: float = 1.5
@export_range(1.0, 500.0) var range_meters: float = 100.0

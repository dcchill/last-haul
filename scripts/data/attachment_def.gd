class_name AttachmentDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var slot: String = ""
@export var compatible_weapons: PackedStringArray = []
@export_range(0.1, 3.0) var vertical_recoil: float = 1.0
@export_range(0.1, 3.0) var horizontal_recoil: float = 1.0
@export_range(0.1, 3.0) var ads_time: float = 1.0
@export_range(0.1, 3.0) var sway: float = 1.0
@export_range(0.1, 3.0) var hipfire: float = 1.0
@export_range(0.1, 3.0) var muzzle_velocity: float = 1.0
@export_range(0.1, 3.0) var damage: float = 1.0

func supports(weapon: WeaponDef) -> bool:
	return weapon != null and compatible_weapons.has(weapon.id)

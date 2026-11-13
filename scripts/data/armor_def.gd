class_name ArmorDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var slot: String = "chestplate"
@export var points: float = 0.0
@export var toughness: float = 0.0
@export var max_durability: int = 80
@export var knockback_resistance: float = 0.0
@export var color: Color = Color.GRAY
@export_range(0.0, 100.0) var resistance: float = 20.0
@export_range(0.0, 1.0) var ricochet: float = 0.19
@export_range(1.0, 1000.0) var plate_durability: float = 90.0
@export_range(0.0, 20.0) var plate_weight: float = 1.5
@export_range(0.0, 10.0) var carrier_weight: float = 0.5
@export_range(0.1, 3.0) var durability_loss: float = 1.0
@export var side_plates: bool = true

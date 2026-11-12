class_name AmmoDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_range(0.0, 200.0) var damage: float = 25.0
@export_range(0.0001, 1.0) var mass_kg: float = 0.008
@export_range(0.0, 1.0) var drag: float = 0.0002
@export_range(0.0, 3.0) var gravity: float = 1.0
@export_range(0.0, 200.0) var penetration: float = 45.0
@export_range(0.0, 10.0) var armor_damage: float = 1.0
@export_range(0.0, 1.0) var bypass: float = 0.0
@export_range(0.0, 1.0) var stopped_damage: float = 0.05

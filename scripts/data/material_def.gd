class_name MaterialDef
extends Resource

@export var id: String = ""
@export var impact_color: Color = Color.ORANGE
@export_range(0.0, 2.0) var damage_multiplier: float = 1.0
@export_range(0.0, 100000.0) var resistance: float = 1200.0
@export_range(0.0, 5.0) var thickness_meters: float = 0.25
@export_range(0.0, 1.0) var ricochet: float = 0.0

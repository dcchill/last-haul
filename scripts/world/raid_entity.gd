class_name RaidEntity
extends StaticBody3D

@export var entity_id: String = ""
@export_enum("target", "container") var kind: String = "target"
@export var material: MaterialDef
@export var loot: LootDef
@export var interaction_offset := Vector3(0, 0.4, 0)
@export var max_health: float = 100.0
var health: float
var remaining: int = 0

func _ready() -> void:
	health = max_health
	if loot != null:
		remaining = loot.quantity

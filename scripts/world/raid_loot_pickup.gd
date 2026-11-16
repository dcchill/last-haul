class_name RaidLootPickup
extends RaidEntity

@export var item_id := "salvage"
@export var amount := 1
var available := true

func collect_visual() -> void:
	available = false
	visible = false
	for child in get_children():
		if child is CollisionShape3D: child.set_deferred("disabled", true)


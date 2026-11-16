class_name MedTacVariantSlot
extends Node3D

@export var slot_id := ""
@export var variants: Array[PackedScene] = []
var selected := -1
var active: Node3D

func configure(seed_value: int) -> void:
	if variants.size()!=3:
		push_error("Cover slot must have three imported arrangements: "+slot_id)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + ":cover:" + slot_id)
	var choice := rng.randi_range(0, variants.size()-1)
	if selected == choice and is_instance_valid(active): return
	if is_instance_valid(active):
		remove_child(active)
		active.free()
	selected = choice
	active = variants[choice].instantiate()
	add_child(active)
	for anchor in active.find_children("Cover*", "Marker3D", true, false):
		anchor.add_to_group("medtac_cover")


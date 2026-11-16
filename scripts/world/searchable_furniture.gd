class_name SearchableFurniture
extends RaidEntity

@export var display_name := "Storage"
@export var opening := "hinge"
@export var loot_profile := "technical"
var opened := false

func open_furniture() -> void:
	if opened: return
	opened = true
	var panel := get_node_or_null("MovingPanel") as Node3D
	if panel == null: return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if opening == "drawer":
		tween.tween_property(panel, "position:z", panel.position.z + 0.4, 0.3)
	elif opening == "lid":
		tween.tween_property(panel, "rotation:x", -1.35, 0.35)
	else:
		tween.tween_property(panel, "rotation:y", -1.4, 0.35)


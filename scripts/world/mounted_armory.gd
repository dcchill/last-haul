class_name MountedArmory
extends StaticBody3D

var entity_id := ""
var item_id := "mounted_minigun"
var heading := 0
var powered := false
var ammo := 0
var next_shot := 0
var view: Node3D

func _ready() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.0, 0.9)
	collision.shape = shape
	collision.position.y = 0.5
	add_child(collision)
	view = load("res://scripts/weapons/bedrock_weapon.gd").new()
	view.show_hands = false
	add_child(view)
	var model: String = {"mounted_minigun": "mountedminigun", "mounted_rpg": "mountedrpg", "gun_mount": "gunmount"}[item_id]
	var texture: String = {"mounted_minigun": "mountedmgun", "mounted_rpg": "mountedrpgtexture", "gun_mount": "mounttexture"}[item_id]
	view.configure(ArmoryContent.ROOT + "geo/" + model + ".geo.json", ArmoryContent.ROOT + "textures/block/" + texture + ".png", ArmoryContent.ROOT + "animations/" + model + ".animation.json")
	view.rotation.y = 0
	view.play_clip("0")

func ammo_id() -> String:
	return "rpg_rocket" if item_id == "mounted_rpg" else "nine_mm"

func refill(pack: RaidInventory) -> bool:
	var amount := mini(64 - ammo, pack.count(ammo_id()))
	if amount <= 0 or not pack.remove(ammo_id(), amount):
		return false
	ammo += amount
	return true

func authority_tick(authority: RaidAuthority) -> void:
	if not powered or ammo <= 0 or item_id == "gun_mount":
		view.play_if_changed("0")
		return
	view.play_if_changed("1")
	if authority.gameplay_tick < next_shot or (item_id == "mounted_minigun" and authority.gameplay_tick % 2 != 0):
		return
	ammo -= 1
	next_shot = authority.gameplay_tick + (20 if item_id == "mounted_rpg" else 2)
	var direction := -global_basis.z
	var origin := global_position + Vector3.UP * 0.65 + direction * (2.0 if item_id == "mounted_rpg" else 1.1)
	authority._spawn_projectile(origin, direction + Vector3.UP * 0.01, 4 if item_id == "mounted_rpg" else 8, 2, 3 if item_id == "mounted_rpg" else 4, 1.5, get_rid(), "rocket" if item_id == "mounted_rpg" else "bullet")
	authority._play_tone(global_position, "explosion")
	if item_id == "mounted_minigun":
		authority._drop_item("nine_mm_casing", global_position)

func _process(delta: float) -> void:
	if view != null:
		view.animate_preview(delta)

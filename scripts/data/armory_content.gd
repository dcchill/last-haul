class_name ArmoryContent
extends RefCounted

const ROOT := "res://resources/create_armory/"
const INVENTORY_DATA = preload("res://resources/inventory_content.json")
const DATA = preload("res://resources/create_armory/content.json")
const MIGRATIONS := {"rifle": "m_four", "rifle_round": "five_five_six", "pistol": "pipe_pistol", "magazine": "stanag_magazine"}
const ARMOR_IDS := ["patrol", "vest", "sentinel", "bastion", "juggernaut"]
# Save compatibility only: these IDs are never added to the playable catalog.
const REMOVED_ARMOR_TIERS := {"leather": "patrol", "chainmail": "vest", "iron": "sentinel", "gold": "vest", "diamond": "bastion", "netherite": "juggernaut"}

static func removed_armor_replacement(id: String) -> String:
	for tier in REMOVED_ARMOR_TIERS:
		for slot in ["helmet", "chestplate", "leggings", "boots"]:
			if id == tier + "_" + slot:
				return REMOVED_ARMOR_TIERS[tier]
	return ""


static func install(catalog: Catalog) -> void:
	for id in ["nine_mm", "five_five_six", "fifty_cal", "shotgun_shell", "rpg_rocket"]:
		var ammo := AmmoDef.new()
		ammo.id = id
		ammo.caliber = id
		ammo.display_name = id.replace("_", " ").capitalize()
		catalog.definitions[id] = ammo
		catalog.items[id] = catalog._inventory_item(ammo, 64, 1, 1, "ammo")
	var variant: AmmoDef = catalog.definitions.five_five_six.duplicate()
	variant.id = "five_five_six_ap"
	variant.display_name = "5.56 armor piercing"
	variant.damage_multiplier = 0.9
	variant.bypass = 0.2
	variant.penetration = 65.0
	catalog.definitions[variant.id] = variant
	catalog.items[variant.id] = catalog._inventory_item(variant, 64, 1, 1, "ammo")
	for data in DATA.data.guns:
		var gun := WeaponDef.new()
		gun.id = data.id
		var inventory_data: Dictionary = INVENTORY_DATA.data.get(gun.id, {})
		var dimensions: Array = inventory_data.get("dimensions", [2, 5])
		gun.inventory_dimensions = Vector2i(int(dimensions[0]), int(dimensions[1]))
		gun.inventory_weight = float(inventory_data.get("weight", 3.0))
		gun.equipment_slots = PackedStringArray(inventory_data.get("equipment_slots", ["primary", "secondary"]))
		gun.display_name = data.name
		gun.armory = true
		gun.model_path = ROOT + "geo/" + data.model + ".geo.json"
		gun.texture_path = ROOT + "textures/item/" + data.texture + ".png"
		gun.animation_path = ROOT + "animations/" + data.model + ".animation.json"
		gun.hand_profile = load("res://resources/hand_poses/" + str(data.id) + ".tres")
		gun.ammo = catalog.definitions[data.ammo]
		gun.feed = data.feed
		gun.magazine_id = data.magazine
		gun.magazine_size = int(data.capacity)
		gun.interval_ticks = int(data.interval)
		gun.reload_ticks = int(data.reload_ticks)
		gun.fire_interval = gun.interval_ticks / 20.0
		gun.reload_seconds = gun.reload_ticks / 20.0
		gun.automatic = data.automatic
		gun.pellets = int(data.pellets)
		gun.damage = data.damage
		gun.projectile_speed = data.speed
		gun.muzzle_velocity = data.speed * 20.0
		gun.spread = data.spread
		gun.recoil_degrees = data.recoil
		gun.head_multiplier = data.head_multiplier
		gun.can_aim = data.can_aim
		gun.attachment_slots = int(data.slots)
		gun.ads_time = 0.2
		gun.range_meters = 2000.0
		catalog.definitions[gun.id] = gun
		catalog.items[gun.id] = catalog._inventory_item(gun, 1, 2, 5, "weapon")
	for feed in DATA.data.feeds.values():
		if not str(feed.magazine).is_empty():
			add_item(catalog, feed.magazine, "magazine", 1, 1, 2)
	for data in DATA.data.attachments:
		var attachment := AttachmentDef.new()
		attachment.id = data.id
		attachment.display_name = str(data.id).replace("_", " ").capitalize()
		attachment.slot = data.slot
		attachment.magnification = int(data.magnification)
		var bit: int = {"optic": 1, "muzzle": 2, "grip": 4}[data.slot]
		for gun in DATA.data.guns:
			if int(gun.slots) & bit:
				attachment.compatible_weapons.append(gun.id)
		catalog.definitions[attachment.id] = attachment
		catalog.items[attachment.id] = catalog._inventory_item(attachment, 1, 1, 1, "attachment")
	for data in DATA.data.armor:
		var armor := ArmorDef.new()
		armor.id = data.id
		armor.display_name = str(data.id).replace("_", " ").capitalize()
		armor.slot = data.slot
		armor.points = data.points
		armor.toughness = data.toughness
		armor.max_durability = int(data.durability)
		armor.knockback_resistance = data.knockback
		armor.color = Color.from_string(data.color, Color.GRAY)
		catalog.definitions[armor.id] = armor
		catalog.items[armor.id] = catalog._inventory_item(armor, 1, 2, 3 if armor.slot == "chestplate" else 2, "armor")
	var maska := ArmorDef.new()
	maska.id = "maska"
	maska.display_name = "Maska (cosmetic)"
	maska.slot = "helmet"
	maska.max_durability = 0
	catalog.definitions.maska = maska
	catalog.items.maska = catalog._inventory_item(maska, 1, 2, 2, "armor")
	for id in ["impact_nade", "smoke_nade"]:
		add_item(catalog, id, "grenade", 16, 1, 1)
	for id in ["gun_mount", "mounted_minigun", "mounted_rpg"]:
		add_item(catalog, id, "mount", 1, 2, 2)
	for id in ["nine_mm_casing", "five_five_six_casing", "fifty_cal_casing"]:
		add_item(catalog, id, "item", 64, 1, 1)
	for id in ["balanced_compensator", "precision_stock", "heavy_barrel"]:
		catalog.items[id].display_name = "Legacy " + catalog.items[id].display_name
		var legacy: AttachmentDef = catalog.definitions[id].duplicate()
		legacy.compatible_weapons = []
		catalog.definitions[id] = legacy
		catalog.items[id].definition = legacy

static func add_item(catalog: Catalog, id: String, kind: String, limit: int, width: int, height: int) -> void:
	var item := ItemDef.new()
	item.id = id
	item.display_name = id.replace("_", " ").capitalize()
	item.kind = kind
	item.stack_limit = limit
	item.width = width
	item.height = height
	catalog.items[id] = item
	catalog.definitions[id] = item

static func magazine_feed(id: String) -> Dictionary:
	for feed in DATA.data.feeds.values():
		if feed.magazine == id:
			return feed
	return {}

class_name WeaponState
extends RefCounted

var definition: WeaponDef
var magazine: int
var reserve: int
var cooldown: float = 0.0
var reload_left: float = 0.0
var attachments: Array[AttachmentDef] = []
var vertical_recoil: float
var horizontal_recoil: float
var ads_time: float
var sway: float
var hipfire_spread: float
var muzzle_velocity: float
var damage_multiplier: float

const LOADOUTS := {
	"standard": [],
	"control": ["heavy_barrel", "balanced_compensator", "precision_stock"],
	"mobile": ["reflex_sight"]
}

func _init(data: WeaponDef, loadout: String = "standard", definitions: Dictionary = {}) -> void:
	definition = data
	magazine = data.magazine_size
	reserve = data.starter_reserve
	vertical_recoil = data.vertical_recoil
	horizontal_recoil = data.horizontal_recoil
	ads_time = data.ads_time
	sway = data.sway
	hipfire_spread = data.hipfire_spread
	muzzle_velocity = data.muzzle_velocity
	damage_multiplier = 1.0
	set_loadout(loadout, definitions)

func set_loadout(loadout: String, definitions: Dictionary) -> bool:
	if not LOADOUTS.has(loadout):
		return false
	return set_attachments(LOADOUTS[loadout], definitions)

func set_attachments(ids: Array, definitions: Dictionary) -> bool:
	var selected: Array[AttachmentDef] = []
	var slots: Dictionary = {}
	for id in ids:
		var attachment = definitions.get(id)
		if not attachment is AttachmentDef or not attachment.supports(definition) or slots.has(attachment.slot):
			return false
		slots[attachment.slot] = true
		selected.append(attachment)
	attachments = selected
	vertical_recoil = definition.vertical_recoil
	horizontal_recoil = definition.horizontal_recoil
	ads_time = definition.ads_time
	sway = definition.sway
	hipfire_spread = definition.hipfire_spread
	muzzle_velocity = definition.muzzle_velocity
	damage_multiplier = 1.0
	for attachment in attachments:
		vertical_recoil *= attachment.vertical_recoil
		horizontal_recoil *= attachment.horizontal_recoil
		ads_time *= attachment.ads_time
		sway *= attachment.sway
		hipfire_spread *= attachment.hipfire
		muzzle_velocity *= attachment.muzzle_velocity
		damage_multiplier *= attachment.damage
	return true

func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		if reload_left == 0.0:
			var amount := mini(definition.magazine_size - magazine, reserve)
			magazine += amount
			reserve -= amount

func fire() -> bool:
	if cooldown > 0.0 or reload_left > 0.0 or magazine <= 0:
		return false
	magazine -= 1
	cooldown = definition.fire_interval
	return true

func reload() -> bool:
	if reload_left > 0.0 or magazine == definition.magazine_size or reserve == 0:
		return false
	reload_left = definition.reload_seconds
	return true

func cancel_reload() -> void:
	reload_left = 0.0

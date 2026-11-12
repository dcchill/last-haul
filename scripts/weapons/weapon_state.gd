class_name WeaponState
extends RefCounted

var definition: WeaponDef
var magazine: int
var reserve: int
var cooldown: float = 0.0
var reload_left: float = 0.0

func _init(data: WeaponDef) -> void:
	definition = data
	magazine = data.magazine_size
	reserve = data.starter_reserve

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

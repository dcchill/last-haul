class_name LootTable
extends Resource

@export var rolls: Vector2i = Vector2i(2, 5)
# Entries: {id: String, weight: float, min: int, max: int}.
@export var entries: Array[Dictionary] = []

func generate(grid: RaidInventory, rng: RandomNumberGenerator) -> bool:
	if grid.loot_generated:
		return true
	var total := 0.0
	for entry in entries:
		if not grid.items.has(entry.get("id", "")) or float(entry.get("weight", 0)) <= 0:
			return false
		if int(entry.get("min", 1)) < 1 or int(entry.get("max", 1)) < int(entry.get("min", 1)):
			return false
		total += float(entry.weight)
	if total <= 0 or rolls.x < 0 or rolls.y < rolls.x:
		return false
	for _roll in range(rng.randi_range(rolls.x, rolls.y)):
		var pick := rng.randf() * total
		for entry in entries:
			pick -= float(entry.weight)
			if pick <= 0:
				grid.add(entry.id, rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1))))
				break
	grid.loot_generated = true
	return true

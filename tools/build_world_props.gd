extends SceneTree

## Authoring-only recipes. Run headless; the game loads the baked meshes/scenes.
const OUT := "res://resources/world_props/"
const SCENES := "res://scenes/props/"
const PALETTE := {
	"paint": Color("52645b"), "blue": Color("526871"), "cream": Color("b3aa88"),
	"rust": Color("805039"), "rust_light": Color("a16b48"), "steel": Color("68716b"),
	"dark": Color("303b38"), "rubber": Color("262d2b"), "glass": Color("283e42"),
	"wood": Color("877353"), "wood_dark": Color("5e513d"), "yellow": Color("b9994c"),
	"concrete": Color("85877b"), "red": Color("805049"), "white": Color("c4c2ad")}
const CATEGORIES := ["Vehicles", "Cargo", "Scrap", "Workshop", "Utilities", "Roadside", "Industrial storage", "Depot fixtures"]
const NAMES := [
	["Sedan", "Hatchback", "Station wagon", "Pickup", "Panel van", "Flatbed truck", "Burned sedan", "Stripped car chassis"],
	["Short shipping container", "Long shipping container", "Open shipping container", "Wooden crate", "Reinforced crate", "Cargo case", "Pallet", "Loaded pallet"],
	["Loose tire", "Tire stack", "Detached car door", "Detached hood", "Engine block", "Sheet metal heap", "Broken pipe heap", "Rubble heap"],
	["Workbench", "Tool cabinet", "Tool chest", "Shelving unit", "Parts bin", "Welding cart", "Hand trolley", "Hydraulic jack"],
	["Generator", "Air compressor", "Electrical cabinet", "Transformer", "Ventilation unit", "Radiator", "Cable reel", "Portable work light"],
	["Concrete barrier", "Plastic barricade", "Traffic cone", "Bollard", "Guardrail segment", "Road sign", "Fence panel", "Damaged gate"],
	["Oil drum", "Dented drum", "Drum cluster", "Fuel tank", "Water tote", "Dumpster", "Scrap skip", "Pipe rack"],
	["Guard booth", "Loading ramp", "Metal stairs", "Awning", "Bench", "Locker bank", "Industrial sink", "Overturned shelving"]]

var parts: Array[Dictionary] = []
var solids: Array[Dictionary] = []
var baked: Array[Dictionary] = []
var shared: StandardMaterial3D
var failed := false

func _initialize() -> void:
	call_deferred("build")

# All boxes use a bottom Y, centered X/Z, in meters. Coordinates snap to 1/8 m.
func b(x: float, y: float, z: float, w: float, h: float, d: float, color: String) -> void:
	parts.append({"at": Vector3(x, y + h / 2.0, z), "size": Vector3(w, h, d), "color": PALETTE[color]})

func c(x: float, y: float, z: float, w: float, h: float, d: float) -> void:
	solids.append({"at": Vector3(x, y + h / 2.0, z), "size": Vector3(w, h, d)})

func bc(x: float, y: float, z: float, w: float, h: float, d: float, color: String) -> void:
	b(x, y, z, w, h, d, color)
	c(x, y, z, w, h, d)

func legs(w: float, d: float, h: float, color: String = "dark") -> void:
	for x in [-w / 2.0 + 0.125, w / 2.0 - 0.125]:
		for z in [-d / 2.0 + 0.125, d / 2.0 - 0.125]:
			bc(x, 0, z, 0.25, h, 0.25, color)

func ring(x: float, y: float, z: float, radius: float, width: float, vertical := false, color := "rubber") -> void:
	# Stepped, hollow square-octagonal profile; no smooth cylinders.
	for side in [-1, 1]:
		if vertical:
			b(x, y + radius + side * (radius - 0.125) - 0.125, z, width, 0.25, radius, color)
			b(x, y + radius - radius / 2.0, z + side * (radius - 0.125), width, radius, 0.25, color)
		else:
			b(x + side * (radius - 0.125), y, z, 0.25, width, radius, color)
			b(x, y, z + side * (radius - 0.125), radius, width, 0.25, color)

func wheel(x: float, z: float) -> void:
	ring(x, 0, z, 0.5, 0.375, true)
	b(x, 0.25, z, 0.5, 0.5, 0.5, "steel")
	b(x + signf(x) * 0.25, 0.375, z, 0.125, 0.25, 0.25, "rust")

func vehicle(kind: int) -> void:
	var length: float = [4.5, 3.5, 4.75, 5.0, 5.0, 6.0, 4.5, 4.0][kind]
	var paint: String = ["paint", "red", "cream", "blue", "cream", "paint", "rust", "rust"][kind]
	bc(0, 0.5, 0, 1.75, 0.5, length, "rust" if kind == 7 else paint)
	b(0, 0.375, 0, 1.5, 0.125, length - 0.25, "dark")
	for x in [-0.875, 0.875]:
		for z in [-length / 2.0 + 0.875, length / 2.0 - 0.875]:
			if kind == 7 and x > 0: continue
			wheel(x, z)
	if kind == 7:
		for x in [-0.625, 0.625]: b(x, 1, 0, 0.25, 0.125, 3.0, "steel")
		b(0, 1, -1.25, 1.0, 0.375, 0.75, "dark")
		b(0, 1, 0.25, 0.25, 0.25, 1.75, "rust")
		return
	var cabin_z := -0.875 if kind in [3, 5] else 0.125
	var cabin_d := 1.5 if kind in [3, 5] else 2.25 if kind != 1 else 1.75
	var cabin_h := 1.25 if kind in [4, 5] else 0.875
	if kind == 2: cabin_d = 3.0
	if kind == 4: cabin_d = 3.5; cabin_z = 0.375
	bc(0, 1, cabin_z, 1.5, cabin_h, cabin_d, paint)
	if kind != 6:
		b(0, 1.125, cabin_z - cabin_d / 2.0, 1.25, 0.5, 0.125, "glass")
		b(0, 1.125, cabin_z + cabin_d / 2.0, 1.25, 0.5, 0.125, "glass")
	for x in [-0.75, 0.75]:
		b(x, 1.125, cabin_z - 0.25, 0.125, 0.5, 0.75, "dark" if kind == 6 else "glass")
		if kind in [0, 1, 2, 4]: b(x, 1.125, cabin_z + 0.625, 0.125, 0.5, 0.625, "glass" if kind != 6 else "rust")
		b(x, 1, cabin_z, 0.125, 0.125, 0.25, "steel")
		b(x, 0.625, -1.375, 0.25, 0.25, 0.5, "rust")
	b(0, 0.5, -length / 2.0, 1.875, 0.25, 0.125, "dark")
	b(0, 0.5, length / 2.0, 1.875, 0.25, 0.125, "steel")
	for x in [-0.625, 0.625]:
		b(x, 0.75, -length / 2.0 - 0.125, 0.375, 0.125, 0.125, "cream")
		b(x, 0.75, length / 2.0 + 0.125, 0.25, 0.125, 0.125, "red")
	if kind in [3, 5]:
		var bed_z := 1.125 if kind == 3 else 1.0
		var bed_d := 1.75 if kind == 3 else 3.0
		for x in [-0.875, 0.875]: bc(x, 1, bed_z, 0.125, 0.5, bed_d, paint)
		bc(0, 1, bed_z + bed_d / 2.0, 1.75, 0.5, 0.125, paint)
		b(0, 1, bed_z, 1.5, 0.125, bed_d, "wood_dark")
	if kind == 6:
		b(0.25, 1.875, 0.125, 0.75, 0.125, 1.5, "dark")
		b(-0.625, 1, -1.375, 0.5, 0.25, 0.75, "dark")

func container(length: float, opened: bool) -> void:
	bc(0, 0, 0, 2.5, 0.25, length, "dark")
	bc(0, 2.5, 0, 2.5, 0.125, length, "paint")
	for x in [-1.125, 1.125]:
		bc(x, 0.25, 0, 0.25, 2.25, length, "paint")
		for i in range(int(length / 0.5)):
			b(x + signf(x) * 0.125, 0.25, -length / 2 + 0.25 + i * 0.5, 0.125, 2.25, 0.125, "steel")
		b(x + signf(x) * 0.125, 0.375, 0.75, 0.125, 0.375, 0.75, "rust")
	bc(0, 0.25, length / 2 - 0.125, 2, 2.25, 0.25, "paint")
	if opened:
		for x in [-1.75, 1.75]:
			bc(x, 0.25, -length / 2 - 0.125, 1.0, 2.25, 0.25, "paint")
			b(x, 0.375, -length / 2 - 0.375, 0.125, 1.75, 0.125, "steel")
	else:
		bc(0, 0.25, -length / 2 + 0.125, 2, 2.25, 0.25, "paint")
		for x in [-0.625, 0.625]: b(x, 0.375, -length / 2 - 0.125, 0.125, 1.875, 0.125, "steel")
		b(0.625, 1.375, -length / 2 - 0.25, 0.375, 0.125, 0.125, "cream")

func pallet(y: float = 0.0) -> void:
	for x in [-0.5, 0.0, 0.5]: bc(x, y, 0, 0.25, 0.25, 1.25, "wood_dark")
	for z in [-0.5, -0.25, 0.0, 0.25, 0.5]: b(0, y + 0.25, z, 1.5, 0.125, 0.125, "wood")

func crate(x: float, y: float, z: float, size: float = 1.0, reinforced := false) -> void:
	bc(x, y, z, size, size, size, "paint" if reinforced else "wood")
	for side in [-1, 1]:
		b(x + side * (size / 2 - 0.125), y, z, 0.125, size, size + 0.25, "steel" if reinforced else "wood_dark")
		b(x, y + size - 0.125, z + side * size / 2, size, 0.125, 0.125, "rust" if reinforced else "wood_dark")
	if reinforced:
		for sx in [-1, 1]:
			for sz in [-1, 1]: b(x + sx * (size / 2 - 0.125), y, z + sz * (size / 2 - 0.125), 0.375, 0.25, 0.375, "steel")

func cargo(kind: int) -> void:
	if kind < 3: container(12.0 if kind == 1 else 6.0, kind == 2); return
	match kind:
		3, 4: crate(0, 0, 0, 1.25, kind == 4)
		5:
			bc(0, 0, 0, 1.25, 0.625, 0.75, "blue")
			b(0, 0.625, 0, 1.375, 0.125, 0.875, "dark")
			for x in [-0.5, 0.5]: b(x, 0.25, -0.5, 0.125, 0.25, 0.125, "steel")
		6: pallet()
		7:
			pallet()
			crate(0, 0.375, 0, 1)
			crate(0, 1.375, 0, 0.75)

func scrap(kind: int) -> void:
	match kind:
		0: ring(0, 0, 0, 0.5, 0.375)
		1:
			for i in range(4): ring(0.125 if i % 2 else 0, i * 0.375, 0, 0.5, 0.375)
			c(0, 0, 0, 0.75, 1.5, 0.75)
		2:
			b(0, 0, 0, 1.25, 0.125, 0.875, "blue")
			for x in [-0.5, 0.5]: b(x, 0, 0.625, 0.25, 0.125, 0.5, "rust")
			b(0, 0, 0.875, 1.25, 0.125, 0.125, "blue")
			b(0.375, 0.125, -0.25, 0.25, 0.125, 0.125, "steel")
		3:
			b(0, 0, 0, 1.5, 0.125, 1.25, "cream")
			b(0, 0.125, 0, 0.75, 0.125, 1, "rust")
		4:
			b(0, 0, 0, 0.75, 0.375, 1.0, "dark")
			for x in [-0.375, 0.375]:
				b(x, 0.375, 0, 0.25, 0.25, 1, "steel")
				for z in [-0.25, 0, 0.25]: b(x, 0.625, z, 0.25, 0.125, 0.125, "rust")
		5:
			for i in range(5): b((i % 3 - 1) * 0.375, i * 0.125, (i % 2) * 0.25, 1.25 - (i % 2) * 0.5, 0.125, 0.75, "rust" if i % 2 else "steel")
		6:
			for i in range(6): b((i % 3 - 1) * 0.375, (i / 3) * 0.25, (i % 2) * 0.25, 0.25, 0.25, 1.5 - (i % 3) * 0.25, "rust" if i % 2 else "steel")
		7:
			for i in range(12): b((i % 4 - 1.5) * 0.375, (i / 8) * 0.25, ((i / 4) % 2 - 0.5) * 0.5, 0.375, 0.25, 0.375, "concrete" if i % 3 else "rust")

func shelf(w: float = 2.0, h: float = 2.0, d: float = 0.75) -> void:
	legs(w, d, h, "steel")
	for y in [0.125, h / 2, h - 0.125]: bc(0, y, 0, w, 0.125, d, "paint")

func cabinet(w: float, h: float, d: float, color: String, drawers := false) -> void:
	bc(0, 0, 0, w, h, d, color)
	b(0, 0, 0, w + 0.125, 0.125, d + 0.125, "dark")
	b(0, h, 0, w + 0.125, 0.125, d + 0.125, "steel")
	if drawers:
		for i in range(int(h / 0.25)):
			b(0, 0.125 + i * 0.25, -d / 2 - 0.125, w - 0.25, 0.125, 0.125, "dark")
			b(0, 0.125 + i * 0.25, -d / 2 - 0.25, 0.5, 0.125, 0.125, "steel")
	else:
		b(0, 0.125, -d / 2 - 0.125, 0.125, h - 0.25, 0.125, "dark")
		b(0.25, h / 2, -d / 2 - 0.25, 0.125, 0.25, 0.125, "steel")

func workshop(kind: int) -> void:
	match kind:
		0:
			legs(2, 0.875, 0.875)
			bc(0, 0.875, 0, 2.25, 0.25, 1, "wood")
			b(0.75, 1.125, 0, 0.375, 0.25, 0.375, "dark")
			b(0, 1.125, -0.125, 0.5, 0.125, 0.25, "rust")
		1: cabinet(1.25, 1.75, 0.75, "red")
		2: cabinet(1.0, 0.75, 0.625, "red", true)
		3:
			shelf()
			b(-0.5, 0.25, 0, 0.5, 0.375, 0.5, "wood")
			b(0.5, 1.125, 0, 0.5, 0.25, 0.5, "rust")
		4:
			b(0, 0, 0, 0.75, 0.125, 0.75, "blue")
			for x in [-0.375, 0.375]: b(x, 0.125, 0, 0.125, 0.375, 0.75, "blue")
			b(0, 0.125, 0.375, 0.75, 0.375, 0.125, "blue")
			for i in range(3): b((i - 1) * 0.25, 0.125, 0, 0.125, 0.125, 0.375, "rust")
		5:
			bc(0, 0.25, 0, 0.875, 0.125, 1.25, "dark")
			bc(0, 0.375, 0.125, 0.625, 0.625, 0.75, "paint")
			bc(0, 0.375, 0.5, 0.375, 1.125, 0.375, "rust")
			for x in [-0.5, 0.5]: ring(x, 0, 0.375, 0.25, 0.25, true)
			b(0, 1.5, 0.5, 0.125, 0.25, 0.125, "steel")
		6:
			for x in [-0.375, 0.375]: bc(x, 0.125, 0.25, 0.125, 1.375, 0.125, "rust")
			bc(0, 1.375, 0.25, 0.875, 0.125, 0.125, "dark")
			bc(0, 0, -0.125, 0.875, 0.125, 0.75, "steel")
			for x in [-0.5, 0.5]: ring(x, 0, 0.25, 0.25, 0.25, true)
		7:
			b(0, 0, 0, 0.5, 0.125, 1.0, "red")
			b(0, 0.125, -0.125, 0.25, 0.25, 0.5, "dark")
			b(0, 0.375, -0.25, 0.5, 0.125, 0.25, "steel")
			b(0, 0.125, 0.625, 0.125, 0.125, 0.75, "dark")

func utilities(kind: int) -> void:
	match kind:
		0:
			bc(0, 0, 0, 1.5, 0.25, 1, "dark")
			bc(0, 0.25, 0, 1.25, 0.75, 0.75, "yellow")
			b(0, 1, 0, 0.75, 0.125, 0.5, "dark")
			for i in range(4): b(-0.375 + i * 0.25, 0.375, -0.5, 0.125, 0.375, 0.125, "dark")
			b(0.625, 0.75, 0.25, 0.125, 0.75, 0.125, "rust")
		1:
			legs(1.5, 0.75, 0.25)
			bc(0, 0.25, 0, 1.5, 0.625, 0.75, "red")
			bc(0, 0.875, 0, 0.75, 0.375, 0.5, "dark")
			b(0.5, 0.875, 0, 0.125, 0.25, 0.125, "steel")
		2:
			cabinet(1.25, 2, 0.625, "paint")
			b(-0.375, 1.25, -0.5, 0.25, 0.25, 0.125, "yellow")
			for i in range(3): b(-0.375 + i * 0.375, 0.25, -0.375, 0.125, 0.375, 0.125, "dark")
		3:
			bc(0, 0, 0, 1.75, 0.25, 1.25, "concrete")
			bc(0, 0.25, 0, 1.25, 1.25, 0.875, "paint")
			for x in [-0.375, 0.0, 0.375]:
				b(x, 1.5, 0, 0.25, 0.375, 0.25, "cream")
				b(x, 1.625, 0, 0.375, 0.125, 0.375, "steel")
			for z in [-0.375, -0.125, 0.125, 0.375]: b(0.75, 0.375, z, 0.125, 0.875, 0.125, "dark")
		4:
			bc(0, 0, 0, 1.5, 1.0, 1.25, "steel")
			for i in range(5): b(0, 0.125 + i * 0.125, -0.75, 1.125, 0.125, 0.125, "dark")
			b(0, 1, 0, 0.875, 0.25, 0.875, "dark")
			b(0, 1.25, 0, 1.0, 0.125, 1, "steel")
		5:
			for x in [-0.625, 0.625]: bc(x, 0, 0, 0.25, 0.25, 0.375, "rust")
			for i in range(7): bc(-0.75 + i * 0.25, 0.125, 0, 0.125, 1.0, 0.375, "cream")
			for y in [0.25, 0.875]: b(0, y, 0, 1.75, 0.125, 0.25, "rust")
		6:
			for z in [-0.5, 0.5]: bc(0, 0, z, 1.25, 0.125, 0.25, "wood_dark")
			bc(0, 0.125, 0, 1, 0.875, 0.75, "rubber")
			for z in [-0.5, 0.5]:
				bc(0, 0.125, z, 1.25, 0.875, 0.125, "wood")
				b(0, 0.375, z + signf(z) * 0.125, 0.375, 0.375, 0.125, "dark")
		7:
			bc(0, 0, 0, 1, 0.125, 0.75, "dark")
			bc(0, 0.125, 0, 0.125, 1.75, 0.125, "yellow")
			bc(0, 1.875, 0, 0.875, 0.5, 0.25, "dark")
			b(0, 2, -0.25, 0.625, 0.25, 0.125, "cream")

func roadside(kind: int) -> void:
	match kind:
		0:
			bc(0, 0, 0, 2.5, 0.25, 0.875, "concrete")
			bc(0, 0.25, 0, 2.5, 0.375, 0.625, "concrete")
			bc(0, 0.625, 0, 2.5, 0.5, 0.375, "concrete")
			for x in [-0.875, 0, 0.875]: b(x, 0.75, -0.25, 0.375, 0.25, 0.125, "yellow")
		1:
			for x in [-0.75, 0.75]: bc(x, 0, 0, 0.375, 0.125, 0.875, "dark")
			bc(0, 0.125, 0, 2, 0.875, 0.375, "yellow")
			for x in [-0.75, 0, 0.75]: b(x, 0.375, -0.25, 0.375, 0.375, 0.125, "white")
		2:
			b(0, 0, 0, 0.625, 0.125, 0.625, "dark")
			b(0, 0.125, 0, 0.375, 0.25, 0.375, "rust_light")
			b(0, 0.375, 0, 0.25, 0.25, 0.25, "white")
			b(0, 0.625, 0, 0.125, 0.25, 0.125, "rust_light")
		3:
			bc(0, 0, 0, 0.5, 0.125, 0.5, "dark")
			bc(0, 0.125, 0, 0.25, 0.875, 0.25, "yellow")
			b(0, 0.625, 0, 0.375, 0.125, 0.375, "dark")
		4:
			for x in [-1.25, 1.25]: bc(x, 0, 0.125, 0.25, 1, 0.25, "rust")
			bc(0, 0.5, 0, 3, 0.25, 0.125, "steel")
			bc(0, 0.875, 0, 3, 0.125, 0.125, "steel")
		5:
			bc(0, 0, 0, 0.25, 2, 0.25, "steel")
			bc(0, 1.75, 0, 1.25, 0.875, 0.125, "paint")
			b(0, 2, -0.125, 0.75, 0.125, 0.125, "cream")
			b(-0.375, 1.875, -0.125, 0.125, 0.375, 0.125, "cream")
		6:
			for x in [-1.5, 1.5]: bc(x, 0, 0, 0.125, 2, 0.125, "rust")
			for y in [0.25, 1.875]: bc(0, y, 0, 3, 0.125, 0.125, "steel")
			for i in range(11): bc(-1.25 + i * 0.25, 0.375, 0, 0.125, 1.5, 0.125, "dark")
		7:
			for x in [-1.5, 1.5]: bc(x, 0, 0, 0.25, 2.25, 0.25, "rust")
			bc(-0.5, 0.375, 0, 2, 0.125, 0.125, "paint")
			bc(-0.5, 1.875, 0, 2, 0.125, 0.125, "paint")
			for i in range(6): bc(-1.25 + i * 0.25, 0.5, 0, 0.125, 1.375 - (i % 3) * 0.25, 0.125, "steel")

func drum(x: float = 0, z: float = 0, dented := false) -> void:
	bc(x, 0, z, 0.625, 0.875, 0.625, "rust" if dented else "blue")
	for y in [0, 0.375, 0.875]: b(x, y, z, 0.75, 0.125, 0.75, "dark")
	if dented: b(x + 0.25, 0.5, z - 0.375, 0.25, 0.25, 0.125, "dark")
	b(x - 0.125, 1, z, 0.125, 0.125, 0.125, "steel")

func bin_body(w: float, h: float, d: float, color: String) -> void:
	bc(0, 0, 0, w, 0.125, d, "dark")
	for x in [-w / 2, w / 2]: bc(x, 0.125, 0, 0.125, h, d, color)
	for z in [-d / 2, d / 2]: bc(0, 0.125, z, w, h, 0.125, color)

func storage(kind: int) -> void:
	match kind:
		0, 1: drum(0, 0, kind == 1)
		2:
			drum(-0.375, 0.375); drum(0.375, 0.375, true); drum(0, -0.375)
		3:
			legs(2.5, 1.25, 0.375)
			bc(0, 0.375, 0, 2.5, 1.125, 1.25, "cream")
			bc(0, 1.5, 0, 2.25, 0.25, 1, "cream")
			b(0.75, 1.75, 0, 0.25, 0.125, 0.25, "rust")
			b(-1.375, 0.625, 0, 0.375, 0.25, 0.25, "rust")
		4:
			pallet()
			bc(0, 0.375, 0, 1.25, 1.125, 1, "cream")
			for x in [-0.625, 0, 0.625]: b(x, 0.375, 0, 0.125, 1.125, 1.25, "steel")
			for y in [0.5, 1.25]: b(0, y, 0, 1.375, 0.125, 1.125, "steel")
			b(0, 1.5, 0, 0.25, 0.125, 0.25, "dark")
		5:
			bin_body(2, 1.25, 1.25, "paint")
			bc(0, 1.375, 0, 2.25, 0.125, 1.5, "dark")
			for x in [-0.875, 0.875]: b(x, 0.5, -0.75, 0.125, 0.375, 0.125, "rust")
		6:
			bin_body(2.5, 1.125, 1.75, "yellow")
			for i in range(6): b((i % 3 - 1) * 0.625, 0.25 + (i / 3) * 0.375, (i % 2 - 0.5) * 0.75, 0.75, 0.375, 0.5, "rust" if i % 2 else "steel")
		7:
			shelf(2.5, 1.75, 1.25)
			for i in range(5): b((i - 2) * 0.375, 0.25, 0, 0.25, 0.25, 1.75, "rust")
			for i in range(3): b((i - 1) * 0.5, 1, 0, 0.375, 0.375, 1.75, "steel")

func fixtures(kind: int) -> void:
	match kind:
		0:
			bc(0, 0, 0, 2, 0.125, 2, "dark")
			bc(0, 0.125, 0.875, 2, 2.375, 0.25, "paint")
			for x in [-0.875, 0.875]:
				bc(x, 0.125, 0, 0.25, 1, 2, "paint")
				bc(x, 1.125, 0, 0.125, 1, 2, "glass")
			bc(-0.625, 0.125, -0.875, 0.75, 2.375, 0.25, "paint")
			bc(0.625, 0.125, -0.875, 0.25, 2.375, 0.25, "paint")
			bc(0, 2.125, -0.875, 2, 0.375, 0.25, "paint")
			bc(0, 2.5, 0, 2.5, 0.25, 2.5, "dark")
		1:
			for i in range(6): bc(0, 0, -1.25 + i * 0.5, 2, (i + 1) * 0.125, 0.5, "steel")
			for x in [-1, 1]: bc(x, 0, 0, 0.125, 0.25, 3, "rust")
		2:
			for i in range(6): bc(0, 0, -1.25 + i * 0.5, 1.5, (i + 1) * 0.25, 0.5, "steel")
			for x in [-0.875, 0.875]:
				for i in range(3): bc(x, (i * 2 + 1) * 0.25, -1.25 + i, 0.125, 1, 0.125, "rust")
				for i in range(6): bc(x, (i + 1) * 0.25 + 0.875, -1.25 + i * 0.5, 0.125, 0.125, 0.5, "yellow")
		3:
			for x in [-1.5, 1.5]: bc(x, 0, 0.75, 0.25, 2.75, 0.25, "rust")
			bc(0, 2.75, 0, 3.5, 0.25, 2, "paint")
			for i in range(7): b(-1.5 + i * 0.5, 3, 0, 0.125, 0.125, 2, "steel")
		4:
			legs(2, 0.75, 0.5)
			for z in [-0.25, 0, 0.25]: bc(0, 0.5, z, 2, 0.125, 0.125, "wood")
			for x in [-0.75, 0.75]: bc(x, 0.5, 0.375, 0.125, 0.75, 0.125, "dark")
			bc(0, 0.875, 0.375, 2, 0.25, 0.125, "wood")
		5:
			bc(0, 0, 0, 1.875, 2, 0.625, "paint")
			for i in range(3):
				b(-0.625 + i * 0.625, 0.125, -0.375, 0.5, 1.75, 0.125, "steel")
				b(-0.5 + i * 0.625, 0.875, -0.5, 0.125, 0.25, 0.125, "dark")
				for y in [0.25, 1.625]: b(-0.625 + i * 0.625, y, -0.5, 0.25, 0.125, 0.125, "dark")
		6:
			legs(1.5, 0.875, 0.75, "steel")
			bc(0, 0.75, 0, 1.5, 0.125, 0.875, "steel")
			for x in [-0.75, 0.75]: bc(x, 0.875, 0, 0.125, 0.25, 0.875, "steel")
			for z in [-0.375, 0.375]: bc(0, 0.875, z, 1.5, 0.25, 0.125, "steel")
			bc(0, 1.125, 0.375, 0.125, 0.375, 0.125, "rust")
			b(0, 1.5, 0.25, 0.125, 0.125, 0.375, "steel")
		7:
			for z in [-0.875, 0.875]:
				for x in [-0.875, 0.875]: bc(x, 0, z, 0.25, 0.75, 0.25, "rust")
			for x in [-1, 0, 1]: bc(x, 0, 0, 0.125, 0.75, 2, "steel")
			b(0, 0, 0, 1.875, 0.125, 1.75, "paint")

func save_resource(resource: Resource, path: String) -> void:
	var error := ResourceSaver.save(resource, path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		push_error("Could not save " + path + ": " + error_string(error))
		failed = true
	else:
		resource.take_over_path(path)

func mesh_from_parts() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	const CORNERS := [[1, 3, 7, 5], [4, 6, 2, 0], [2, 6, 7, 3], [4, 0, 1, 5], [5, 7, 6, 4], [0, 2, 3, 1]]
	for part in parts:
		var half: Vector3 = part.size / 2
		var vertices: Array[Vector3] = []
		for i in range(8): vertices.append(part.at + Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z))
		for face in range(6):
			for index in [0, 2, 1, 0, 3, 2]:
				st.set_normal(NORMALS[face])
				st.set_color(part.color)
				st.add_vertex(vertices[CORNERS[face][index]])
	st.index()
	st.set_material(shared)
	return WorldMeshKit.remove_coplanar_overdraw(st.commit())

func own(root_node: Node, child: Node, parent: Node = null) -> void:
	(root_node if parent == null else parent).add_child(child)
	child.owner = root_node

func pack_save(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	if packed.pack(node) != OK: failed = true
	save_resource(packed, path)
	node.free()

func bake_prop(category: int, kind: int) -> void:
	parts.clear()
	solids.clear()
	match category:
		0: vehicle(kind)
		1: cargo(kind)
		2: scrap(kind)
		3: workshop(kind)
		4: utilities(kind)
		5: roadside(kind)
		6: storage(kind)
		7: fixtures(kind)
	var title: String = NAMES[category][kind]
	var id := title.to_snake_case().replace(" ", "_")
	var mesh := mesh_from_parts()
	save_resource(mesh, OUT + id + ".res")
	var node := Node3D.new()
	node.name = title.to_pascal_case().replace(" ", "")
	node.set_meta("prop_id", id)
	node.set_meta("category", CATEGORIES[category])
	node.set_meta("collision_mode", "static" if not solids.is_empty() else "none")
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	own(node, visual)
	if not solids.is_empty():
		var body := DecorativeProp.new()
		body.name = "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		body.material = load("res://resources/materials/concrete.tres" if category == 5 and kind == 0 else "res://resources/materials/steel.tres")
		own(node, body)
		for solid in solids:
			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = solid.size
			collision.shape = box
			collision.position = solid.at
			own(node, collision, body)
	pack_save(node, SCENES + id + ".tscn")
	var bounds := mesh.get_aabb()
	baked.append({"id": id, "name": title, "category": CATEGORIES[category], "scene": SCENES + id + ".tscn",
		"bounds": {"position": [bounds.position.x, bounds.position.y, bounds.position.z], "size": [bounds.size.x, bounds.size.y, bounds.size.z]},
		"collision_mode": "static" if not solids.is_empty() else "none"})

func label_at(node: Node, title: String, at: Vector3, size: int) -> void:
	var label := Label3D.new()
	label.text = title
	label.position = at
	label.font_size = size
	label.pixel_size = 0.015
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("d0c7a5")
	own(node, label)

func gallery() -> void:
	var node := Node3D.new()
	node.name = "WorldPropGallery"
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202e30")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a8bdc1")
	environment.environment.ambient_light_energy = 0.65
	own(node, environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("ffe7c4")
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	own(node, sun)
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(132, 0.25, 140)
	ground.mesh = ground_mesh
	ground.position.y = -0.125
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("39433d")
	ground.material_override = mat
	own(node, ground)
	for i in range(baked.size()):
		var at := Vector3((i % 8) * 16 - 56, 0, (i / 8) * 16 - 56)
		var prop: Node3D = load(baked[i].scene).instantiate()
		prop.position = at
		own(node, prop)
		label_at(node, "%02d / %s" % [i + 1, baked[i].name], at + Vector3(0, 0.5, 5.5), 24)
		if i % 8 == 0: label_at(node, CATEGORIES[i / 8].to_upper(), at + Vector3(0, 3, -7), 36)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(82, 104, 110)
	camera.basis = Basis.looking_at(-camera.position, Vector3.UP)
	camera.far = 400
	camera.current = true
	camera.set_script(load("res://scripts/world/prop_preview_camera.gd"))
	own(node, camera)
	pack_save(node, "res://scenes/props_preview.tscn")

func build() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(SCENES)
	shared = StandardMaterial3D.new()
	shared.vertex_color_use_as_albedo = true
	shared.roughness = 0.95
	save_resource(shared, OUT + "palette.tres")
	for category in range(8):
		for kind in range(8): bake_prop(category, kind)
	var file := FileAccess.open(OUT + "catalog.json", FileAccess.WRITE)
	if file == null:
		failed = true
	else:
		file.store_string(JSON.stringify(baked, "\t") + "\n")
		file.close()
	gallery()
	print("WORLD PROPS: baked ", baked.size(), " assets and preview; errors=", failed)
	quit(1 if failed else 0)

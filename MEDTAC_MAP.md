# MedTac Labs

This is the preserved Labs regression fixture. Normal deployment now selects
[Medtac Quarantine District](docs/world-generation.md). Labs-specific tests select
this map explicitly; its original layout, 20-minute timer and gameplay rules remain.

MedTac created the outbreak pathogen to sell an exclusive cure. The cure worked;
domestic containment failed. The remaining cure stock left this facility before
its evacuation collapsed. Suppressants delay turning and are not a cure.

## Playing the map

When deploying the Labs fixture, a raid randomly chooses
one of seven perimeter insertions and assigns the two extracts farthest away by
baked walking-route distance. The compass lists their names and bearings.
Stay inside an assigned extract for 15 continuous seconds. Leaving or changing
extract resets progress. No research objective is required.

Start with **20:00 until turning**. Inventory, looting, combat, and extraction
continue the countdown. Sprinting uses stamina without accelerating infection;
pause freezes simulation. A suppressant buys three minutes, up to 20:00 remaining.
Practice is exempt. Death, turning, or abandonment loses everything carried.
Turning takes priority if extraction completes on the same simulation tick.

The ground floor has a complete loot loop independent of basement access. There
are 128 searchable furnishings and 64 authored loose-loot sockets, with exactly
32 sockets active each raid. There are 22 enemies: 16 infected and six scavengers.
The two factions fight each other as well as the player. There are no respawn waves.

## Departments and routes

The approximately 640-meter-square site follows the supplied sketch: southern
entrance/reception, western laboratories, a central connector, eastern loading
bay, surrounding roads and woodland. Yellow markings are road paint. The seven
insertions and four extracts retain their sketch positions. The longest authored
insertion-to-extract route is approximately 900 meters (3:28 at unloaded walk speed).

- **Reception and clinical:** screening, consultation and examination suites,
  sample collection, procedures, nursing, monitored recovery, observation,
  clinical stores, consent, security, staff facilities and records.
- **Laboratories:** receiving and sorting, preparation, analysis, microscopy,
  instrumentation, wash/sterilization, reagent stores, cold/freezer banks,
  offices, records, support rooms and a damaged service shortcut.
- **Warehouse:** receiving inspection, cold-chain staging, tall loaded pallet
  racks, marked vehicle aisles, packing/conveyors, dispatch and maintenance.
- **Basement:** trial control, human trials, observation, failed containment,
  isolation, cure-transfer archives, medical stores, security and utilities.
- **Grounds:** abandoned parking, truck apron, checkpoint, utilities, fences, and trees.

Main, side, and service entrances connect the ground-floor circuit. Two enclosed
stairwells connect to a basement loop. Their gates are independently controlled.

Exactly one rare keycard may appear in a raid: a **10% total chance**, choosing
one of the security cabinet, staff locker, records supply, or dispatch safe.
An extracted card can be staged for a later raid. Unlocking consumes one carried
card and authorizes only that entrance for that raid. Inside emergency egress
works without a card and closes again without granting outside authorization.
Restricted structure cannot be destroyed or bypassed through weak partitions.

Basement containers guarantee at least two suppressants and two research drives,
with additional medical, electronic, and equipment rolls. Covered bodies, trial
records, empty shipping stock, and damaged containment tell the story. Spills
are scenery; respiratory gear and contamination damage are not required.

## Loot and interaction

Each searchable furnishing has an explicit profile selected by its physical
container model. Nearby room categories do not broaden that profile.

| Container | Contents |
| --- | --- |
| Medical bag, medical cabinet, medicine fridge | Medkits and infection suppressants |
| Specimen cooler, laboratory fridge/freezer | Sealed specimens and sterile laboratory supplies |
| Filing cabinet, desk drawers | Research notes and research drives |
| Personal bag, staff locker | Food, personal effects, face covering and glasses |
| Tool drawers, general shipping storage | Tools, salvage and laboratory electronics |
| Security equipment locker | Armor, protective accessories and bags |
| Weapon box or weapon crate (8 total) | Weapons and attachments |
| Ammunition box (12 total) | Ammunition and magazines |

Weapons, attachments and ammunition never roll in general storage or authored
loose-loot sockets. NPC equipment, corpses and player-dropped items keep their
normal inventories. The rare keycard is the single deliberate profile exception
at its four designated candidate sources. Basement guaranteed suppressants are
in the medical store; guaranteed drives are in records/control storage.

Aim within 3.5 meters and press **E**. Furniture opens a drawer, lid or door
and remains open for that raid. Loose items transfer directly to carried storage
without a search window; a successful transfer removes the world item. A blocked
interaction or full inventory leaves it in place. HUD prompts provide interaction
text; all map lettering is printed on physical signs or equipment labels.

## Dressing, lighting and variation

The facility contains 79 named rooms/suites with equipment tied to their function.
Original textured block models include clinical furniture, instruments, cold
storage, records, utilities, handling equipment and item-specific pickups. Service
conduits, suspended fixtures, packing debris, covered bodies and abandonment
details supplement the work areas. The existing retro shader and settings remain.

Twenty-four cover slots each select one of three curated arrangements. Fifteen
shared variant scenes cover five department themes. The layouts preserve central
walking lanes, while changing sightlines and nearby NPC cover. Six extra service
passages can vary; no more than two start barricaded. Main doors, core routes,
spawns, extracts and basement security remain fixed.

Layout, secondary-route, fixture-failure, loot and keycard rolls use independent
seed streams. A seed reproduces its layout. Some ordinary fixtures start failed;
protected emergency lights keep core routes readable. Ordinary observation glass,
selected fixtures and service barricades can be shot or damaged by explosions.
Breakage supplies bounded shards and impact sound. Protected security structure
and emergency fixtures cannot be destroyed.

## Authoring

`scenes/raid/medtac_labs.tscn` is the playable scene. Departments are editable scene
instances under `scenes/raid/medtac/`. `resources/maps/medtac_labs.tres` defines map
identity and starting infection time. The 75 original textured models live in
`scenes/props/medtac/detail/`, with shared materials, UVs, baked meshes and compound
collision. Recipes are in `resources/medtac/prop_recipes.json`. The existing
64-prop library remains independently authored.

`tools/build_medtac.gd` and `tools/medtac_detail.gd` contain layout/dressing recipes.
`tools/build_medtac_textures.py` authors the atlas, printed signs and model recipes
with the Python standard library. `tools/build_medtac_props.gd` bakes the models.
Run the complete pipeline in this order:

```powershell
python tools/build_medtac_textures.py
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tools/build_medtac_props.gd
godot --headless --path . --script res://tools/build_medtac.gd
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/medtac_tests.gd
godot --headless --path . --script res://tests/medtac_detail_tests.gd
godot --path . --resolution 1280x720 --script res://tests/medtac_tests.gd -- --capture
```

Regeneration overwrites MedTac scenes, variants and models. Put changes into
the recipes if they must survive regeneration. It opens ordinary doors during
navigation baking, keeps restricted gates closed, supplies controlled traversal
links, and calculates far-side assignments from the resulting ground-floor routes.
The runtime loads saved scenes and selects saved cover variants; it does not
generate or bake geometry. The fixed navigation reserves cover-slot footprints;
selected variants supply their own baked region and four portal links. Navigation
regions update synchronously so deployment starts with a complete map. Long route
queries use a 65,536-polygon search budget. Wall occluders and local prop/light
distance culling reduce rendering work; occlusion culling is enabled for MedTac.

Generated captures are `.godot/medtac-{entrance,clinical,laboratory,warehouse,containment,human,encounter,overhead}.png`.
The overhead image is a review cutaway; playable buildings retain their ceilings.
The capture check prints frame times with VSync disabled. These are rendering
samples with encounters frozen, followed by a three-second encounter with all 22
AI active, movement, gunfire, ballistics and effects. It prints mean and p95 frame
times. These samples are not a minimum hardware specification.

## Compatibility and verification

Version 6 profiles convert historical `battery_cell` items to suppressants with
an original-file backup. The conversion preserves nested storage, staged layouts,
item identities, stash contents, and pending extraction rewards. Older equipment
migrations remain supported. The legacy item definition is retained only so old
profiles can be validated before conversion.

The dedicated MedTac integration test covers geometry/navigation, seven spawn
assignments, four extracts, actual stair walking, card ownership and consumption,
emergency egress, faction targeting, treatment rules, seeded loot rarity,
profile migration, and terminal extraction ordering. The full test runner includes
MedTac and PCK export validation. The detail test also checks all 15 variants,
physical signs, container-specific loot, pickup identity/space handling, opening
animations, breakage, 200 layout seeds and extraction reachability. The depot
remains a compact regression fixture.

The completed detail pass passed 56,745 detail checks across 200 layout seeds,
946 checks in the rendered MedTac integration run, and 139 rendered application
smoke checks. The complete regression runner passed, including 1,188,462 hand-pose
checks, persistence restart and loading the exported PCK. Logs and captures are
under `.godot/medtac-*`.

A 1280x720 Compatibility-renderer sample on an i7-14700K / RTX 4090, with the
existing visual treatment and VSync disabled, measured 191-409 FPS across the
static views. The three-second active encounter averaged 11.03 ms (90.7 FPS),
with 12.23 ms p95, all 22 AI active, 18 actors moving and 12 live shots. These are
short local measurements; lower-end hardware and long-session performance have
not been characterized.

The game remains single-player. Spawns are laid out for future multiplayer;
networking, character customization, playable turning, and a usable cure are not
part of this release.

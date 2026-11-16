The district reference library and review pipeline are documented in
[Decaying Voxel Realism](../docs/art-direction.md). Its original shaped-profile
models live under `scenes/props/district/`, shared materials/asset definitions under
`resources/district/`, and physical sign textures under `assets/district/`.
`tools/build_district.ps1 -Capture -ReviewOnly` renders the eight references and
four-part showcase. Artist GLB/glTF assets can use the same wrapper and review tools.

The preserved decoration library includes **64 voxel props**: eight each of vehicles, cargo, scrap, workshop equipment, utilities, roadside objects, industrial storage, and depot fixtures. No third-party assets or licenses are required.

Open `res://scenes/props_preview.tscn` and press **F6** to browse all 64 labeled props. Hold **right mouse + WASD** to fly, **Q/E** to descend/ascend, **Shift** to move faster, and **Home** to return to the overview. Release right mouse or press **Escape** to release the cursor.

Drag individual scenes from `scenes/props/` into a map. Each uses meters, a ground-centered origin, and forward **-Z**. Models use a 0.125-meter authoring grid, opaque vertex colors, one shared rough material, and one baked mesh each. Compound boxes approximate substantial forms while preserving container entrances, gate gaps, and shelving openings. Small scrap has no collision. Props are static scenery; cargo does not supply loot, and vehicles cannot be driven or destroyed.

`resources/world_props/catalog.json` lists all stable IDs, categories, scene paths, local bounds (`position` and `size` in meters), and `collision_mode` (`static` or `none`). The recipe names map to snake_case IDs, such as `open_shipping_container` and `stripped_car_chassis`. All scenes and meshes are checked into source control; the game does not generate them at runtime. Collision bodies expose `MaterialDef` for the existing impact/footstep system, using the prototype's steel surface or concrete for concrete barriers.

Veyra Depot instances **24 different props** through `scenes/raid/depot_decoration.tscn`, beneath its navigation region. Keep at least **1.25 meters** clear on intended walking routes and leave spawn, extraction, NPC routes, and loot access unobstructed. Place floor props at Y=0 outdoors or Y=0.25 on the medical floor; tabletop parts sit on their support surface. Decorative props do not join `raid_entities` or change the five loot/power containers.

Author shapes, wear, and collision proxies in `tools/build_world_props.gd`, then regenerate the library and preview with:

```powershell
godot --headless --path . --script res://tools/build_world_props.gd
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/world_props_tests.gd
```

Regeneration replaces the 64 library scenes, baked meshes, palette, catalog, and preview. Edit recipes to retain shape changes; depot placements are authored separately and survive regeneration. Existing `resources/props/container.bbmodel` and its texture remain separate source art.

After editing depot placements or collision, rebake and verify routes:

```powershell
godot --headless --path . --script res://tests/bake_navigation.gd -- res://scenes/raid/veyra_depot.tscn
godot --headless --path . --script res://tests/depot_tests.gd
godot --path . --resolution 1280x720 --script res://tests/world_props_tests.gd -- --capture --benchmark
```

The last command saves a gallery overview, a labeled 8×8 contact sheet, and sensor-filtered depot views under `.godot/props-*.png`. It compares bare/dressed rendering using three interleaved samples per view, with the same camera, sensor settings, collision, and VSync disabled. `tests/run.ps1` includes asset checks; `-Capture` also runs the preview capture/benchmark. The export smoke check loads all 64 scenes from the PCK.

Other placeholder meshes use Godot primitives serialized in scenes.

The player is an original infected-human block model in `scripts/player/human_body.gd`, with civilian clothing, pale skin, visible infection, a bandaged wrist, and restrained breathing/coughs. First-person sleeves and gloves match the body while preserving existing weapon contacts and animation. Head and body arms retain shadow-only first-person rendering. Equipped armor follows the body.

MedTac adds 75 original textured block models under `scenes/props/medtac/detail/`: clinical furniture, laboratory instruments, medical/specimen/records storage, tall pallet racks, warehouse handling equipment, utilities and item-specific loose pickups. A shared original pixel atlas provides UV materials; physical signs use generated lettering textures. Substantial model parts have compound collision so shelves and tabletop access remain open. Fifteen saved cover arrangements supply five department themes with three layouts each. All assets are authored locally; no third-party assets or Python packages are needed. See [the map guide](../MEDTAC_MAP.md) for the texture/model/layout generation sequence, container loot rules and review captures. The MedTac pipeline does not overwrite the existing 64-prop catalog.

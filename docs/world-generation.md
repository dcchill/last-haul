# District authoring and gameplay

The default raid is **Medtac Quarantine District**, a 350 × 350 m district with
seven POIs, seven insertions, four extracts, sixteen enterable buildings, upper
storeys/mezzanines, and three baked layouts. Labs remains a regression fixture.
No inventory IDs, profile schema, weapon authority, or player controller were
replaced by this work.

## Playing and inspecting

Choose **Enter raid - Medtac Quarantine District**. Infection starts at 25:00;
each suppressant adds 3:00 up to 25:00. Your two assigned extracts are the farthest
by baked walking distance. Hold an assigned extract for 15 continuous seconds.
There are 18 infected and 10 scavengers, with no respawn waves. Death, turning,
and abandonment retain their existing equipment-loss rules.

The main loot budget is 96 searchable furnishings and 48 active items selected
from 96 loose-loot sockets. Physical container profiles restrict the item types.
An accessible medical records cabinet and checkpoint storage are the two rare
keycard candidates; there is a 10% total chance of exactly one card. The optional
research room contains guaranteed suppressants and research drives. Its ordinary
raid loop does not require entry. Upper-floor access cannot bypass its sealed
ground-floor structure.

Developer controls, in a district raid:

| Key | Action |
| --- | --- |
| F7 | Inspector: graph, POI boundaries, exposure, cover, actors, paths, spawn/extract markers, rendering statistics |
| F9 | Cycle Overcast Day, Contaminated Dusk, Foggy Morning, Emergency Night |
| F6 | Toggle rain and wet surfaces |
| F10 | Cycle contamination off / Dormant / Spreading / Consumed |
| F8 | Existing screen-treatment comparison; world atmosphere remains active |

Settings exposes Low / Medium / High world quality, independently of the retained
pixelation, grading, and flicker settings. Quality changes affect lights, shadows,
volumetric fog, effect distance, and particle counts. They do not change cover,
loot, collision, enemies, or routes.

To reproduce a district layout and its raid rolls:

```powershell
godot --path . -- --layout-seed 19381 --raid-seed 94731
```

The layout seed must identify an approved scene (19381, 43721, or 90217 by default).
An unapproved layout is rejected before loadout debit. Without flags the game
selects an approved layout and new raid randomness. Results record both seeds.

## Authoring pipeline

The dependency order is:

1. Shared art/material definitions and physical sign textures.
2. Eight reference assets and technical asset review.
3. Four-part art showcase and rendered review.
4. Seeded traversal graph and reserved building/door/stair footprints.
5. Terrain, routes, architecture, tactical cover, contextual dressing, gameplay sockets.
6. Navigation bake, physical validation, tactical ray tests, publication.

Use the standard Godot 4.7.2 executable and Python 3. There are no external voxel
plugins or Python packages required.

```powershell
# Render assets/showcase for inspection without rebuilding the district:
./tools/build_district.ps1 -Godot 'C:/path/to/godot_console.exe' -Capture -ReviewOnly
# Rebuild and validate all approved layouts; also render district captures:
./tools/build_district.ps1 -Godot 'C:/path/to/godot_console.exe' -Capture
# Complete regression suite and PCK export:
./tests/run.ps1 -Godot 'C:/path/to/godot_console.exe'
```

Review the reference assets and showcase before extending the asset family. The
pipeline's technical success does not constitute artistic approval. Edit recipes,
not generated scenes, when a change must survive regeneration.

`DistrictLayout` creates the graph before geometry. Its stable, versioned seed
derivation separates layout/vegetation domains. Raid loot, keycard, dressing and
fixture rolls retain independent streams in the existing authority. This is
reproducibility for the pinned generator/engine version, not a promise that future
engine or recipe changes will reproduce identical content.

The graph has seven loops, no articulation point in its mandatory network, and
at least three approaches per POI. The build rejects disconnected or insufficient
graphs. Publication occurs only after all curated candidates have passed. Failed
validation leaves the approved scene files intact; build diagnostics remain in
`.godot/district-build/`. Generation does not retry forever or silently substitute
a different seed.

## Resources and extension points

| Interface | Responsibility |
| --- | --- |
| `RaidMapDefinition` | Identity, scene/approved layouts, timers, spawn/extract counts, assigned exits, loose-item and encounter budgets |
| `DistrictGenerationConfig` | Generator version, extent, graph/coverage requirements, curated seeds |
| `DistrictPOIDefinition` | Authorable POI identity, purpose, footprint, risk, loot profiles and modular building scenes |
| `WorldArtDirection` / `WorldAssetDefinition` | Art standards, palettes, asset bounds, provenance, required components, collision and triangle budgets |
| `WorldEnvironmentPreset` / `WorldQualitySettings` | Reusable visual parameters, separate from layout and gameplay |

The shipped POI recipes in `DistrictSceneAuthor` deliberately reserve authored
footprints and entrances; they are not arbitrary building scatter. Add a new POI
by defining its graph node, footprint reservation, appropriate building recipe,
encounter anchors, loot/storytelling profiles, then validating actual traversal.
`DistrictPOIDefinition` is an extension resource; the current seven-POI recipe is
explicit code rather than a fully generic module editor.

Terrain consists of 25 m sections with 5 m sampled height geometry. Foundations,
roads, insertion areas and extracts flatten before meshing. Shared boundary
samples avoid section seams. The extent parameter supports authoring experiments
from 280–500 m; **350 m is the size physically validated and visually reviewed**.
Other sizes must pass a complete bake, capture and gameplay review before shipping.

Navigation is static and baked from final collision. Ordinary doors bake open;
the restricted research gate uses a disabled access link and emergency egress.
Six voxel cover sections reuse the existing destruction/debris implementation.
Their destruction adds physical clearance, but does not perform runtime navmesh
rebaking. Required routes never depend on destroying them. Furniture, windows,
stairs and doors have collision independently of visual detail.

Tactical analysis checks reachable crouch-cover anchors with real physics rays,
samples eight sight directions around POIs, and measures distance from the
mandatory walking routes to useful cover. It rejects distances beyond the
configured 25 m default. This distance metric is not a claim that every route is
safe from every firing angle. Long-range lanes deliberately remain possible.

The runtime loads approved scenes, uploads saved foliage transforms once, selects
safe dressing, and controls local visual effects. It does not generate terrain,
rebuild architectural meshes, or bake navigation during play.

## Performance and failure investigation

Use `.godot/district-build.log` and the per-layout JSON reports for generation
failures. Reports record graph nodes/edges, loops, counts, reachability, navigation
polygons, valid/rejected cover anchors, exposure samples and sampled sightlines.
The inspector consumes these reports rather than recomputing them every frame.

The renderer uses shared external materials, merged architectural meshes, wall
occluders, section culling, instanced foliage, asset distance limits, capped debris,
and a nearest-light budget updated at 5 Hz. Medium permits 16 nearby local lights
and two local shadow casters, plus the sun. Foliage transforms are serialized
explicitly because the headless Dummy renderer does not retain GPU instance data.

```powershell
godot --path . --resolution 1920x1080 --script res://tests/district_benchmark.gd
# Short harness check (not acceptance evidence):
godot --path . --resolution 1920x1080 --script res://tests/district_benchmark.gd -- --seconds 8
```

The default benchmark runs ten minutes with all 28 AI, movement and live
ballistics. Protected actor health and ammo replenishment maintain the workload.
Player/NPC collision exceptions prevent immortal actors from pinning the camera
route; normal geometry and NPC/NPC collision remain active. The report labels
these harness conditions. It reports frame percentiles, memory,
draw calls, route distance, moving actors and projectile count. Do not present a
short static view or RTX 4090 result as verification on the reference GPU.

## Surface and placement constraints

Ground patches are clipped into disjoint polygons before triangulation. Road paint
takes precedence over asphalt, asphalt over courtyard concrete, and building
footprints cut through every patch. Contamination stages also use disjoint residue
polygons. This avoids relying on tiny height offsets between overlapping faces.

`WorldMeshKit.remove_coplanar_overdraw` clips redundant triangles on each oriented
plane, preserving material assignments, UVs and vertex colors. District references,
Medtac details and the legacy world-prop baker use this shared cleanup. Regenerate
their resources when changing the cleanup implementation.

Authored POI yards reserve 33 meters around their centers against roadside prop
placement. Tree placement also reserves infill buildings. Interior shelving is sized
for the room, machinery clears ceilings and worktops, and loose loot is placed
beside its container toward the room center using the container collision bounds.

`tests/district_surface_tests.gd` checks polygon subtraction, interior/exterior prop
overlap and tree clearance on all three baked seeds. `tests/asset_surface_tests.gd`
checks the 147 generated prop meshes for positive-area coplanar overlap. Both are
part of `tests/run.ps1`; rendered review remains necessary for visual acceptance.


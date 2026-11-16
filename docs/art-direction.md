# Decaying Voxel Realism

## Standards

The world uses meter scale, Y up, and -Z forward. Architectural modules generally
follow a 0.25 m grid, prop forms 0.125 m, and selected small details 0.03125–0.0625 m.
These are hierarchical design standards, not an instruction to voxelize every
object at one universal resolution. Existing destructible cells remain 0.25 m.

Architecture needs readable massing and functional openings before trim.
Reference doors are 1.6–2 m wide and 2.4 m high, storeys 3.5 m, and walls about
0.3 m thick. Clearance must account for the real 0.6 × 1.8 m player collider and
NPC navigation radius. Upper floors need an actual walkable approach, not merely
a navigation marker. Roofs/mezzanines, parapets, window bays and utility housings
distinguish departments.

The restrained palette centers on gray concrete, dark asphalt, desaturated painted
steel, brown rust, dark rubber/glass, muted wood, and pale medical equipment.
Warning yellow, red and medical light are selective functional accents. Shared
material resources define roughness, metalness, subtle pixel surface variation
and wetness eligibility. Screen treatment remains optional and uses the existing
defaults; asset review also includes clear views so pixelation cannot hide defects.

## Modeling rules

`WorldMeshKit` surfaces authored profiles, extrusions and functional components,
merging them by material. It rejects degenerate triangles and writes correct
surface normals/UV projection. Avoid adding disconnected cubes merely to raise
the polygon count. Prefer external artist assets whenever they meet the standard.

The eight reference models establish these requirements:

| Asset | Readable structure |
| --- | --- |
| Damaged car | Continuous shaped body, wheel arches, correct axles, recessed glass, roof, pillars, lamps, bumpers and exposed damage |
| Industrial truck | Cab-over-engine profile, windshield, wheels, open bed, structural rails and grille |
| Industrial press | Load-bearing frame, bed, ram, guide rods, hydraulics, power unit and controls |
| Medical station | Wheeled base, pedestal, treatment surface, monitor and IV equipment |
| Concrete barricade | Tapered profile, lifting slots and functional warning markings |
| Shipping container | Corrugated walls, corner castings, roof/floor, opening and folded door with locking rods |
| Residential facade | Proportioned openings, recessed glazing, piers, sills, cornice and damage |
| Warehouse facade | Structural bays, loading opening, shutter, seams and exposed metal |

Reference budgets default to 12,000 triangles per complex prop and 20,000 per
facade. The current reference set uses roughly 112–1,342 triangles per asset.
These low counts are a performance fact, not proof of artistic quality. Additional
geometry is justified when it improves silhouette or functional detail.

Collision is independent of decoration. Shipping-container openings remain open;
walls and cover block actors and projectiles; nonfunctional small trim should not
create movement obstacles. Use compound boxes or appropriate static mesh collision
and existing `MaterialDef` resources. Preserve intentional holes and access routes.

Damage follows plausible component failure: missing lights, oxidized exposed
steel, broken panel edges, bent bumpers, damaged masonry and failed fixtures.
Avoid arbitrary holes through protected research access. Wear belongs near edges,
water paths, mechanisms and abandoned equipment rather than uniform visual noise.

## Imported assets

Keep the original source and provenance alongside the exported asset. Blockbench
can supply GLB/glTF. Export MagicaVoxel meshes through a compatible interchange
workflow and convert to GLB/glTF; do not rename `.vox` to another extension.
The project does not implement native `.vox` or `.bbmodel` parsing and does not
require every asset to be authored in code.

Export in meters with -Z forward, apply transforms, then wrap a static source:

```powershell
godot --headless --path . --script res://tools/import_district_asset.gd -- res://assets/artist/machine.glb artist_machine
godot --path . --resolution 768x768 --script res://tools/review_district_assets.gd -- --definition res://resources/district/assets/artist_machine.tres
```

The wrapper grounds/recenters the source, preserves materials and geometry, adds
static collision and writes an asset definition. It refuses to overwrite an
existing asset and rejects excessive triangle counts. Review/material adjustment
is still required before placing an imported asset. Set its author/license and
expected components in the definition; automatic wrapping cannot determine those.

## Review and atmosphere

The review renderer saves front, side, top, three-quarter, neutral and gameplay
lighting views under `.godot/asset-review/<id>/`, plus a contact sheet and technical
JSON. Bounds, scale, orientation, missing meshes/materials, triangle integrity,
welded geometry islands, component declarations, collision and complexity are checked separately from
rendered silhouette/proportion/readability review. Intentional separated details
and damage require visual inspection; geometry checks do not establish realism.

The four-part showcase is `scenes/review/art_direction_showcase.tscn`. Its 40
captures cover street, medical, industrial, contamination and overview cameras
under four presets, with screen treatment enabled/disabled. Full district captures
live under `.godot/district-review/`. Regeneration replaces these captures.

World atmosphere owns fog and lighting; `SignalDecay.manages_environment=false`
keeps F8 from removing district weather. Legacy fixtures keep their prior sensor
haze behavior. Atmosphere presets share geometry. Medium/High use localized
volumetric effects; Low retains ordinary fog and reduced particle/light budgets.

High quality additionally enables shallow local fog volumes at contamination
sources; Medium uses the global atmospheric volume and source particles to limit
fog/shadow cost. Low retains conventional fog.

Dust, steam, smoke, debris, rain and contamination use small faceted particles at
believable sources, with distance and global particle budgets. Rain modifies only
wettable materials. Contamination layers are visual: Dormant residue, Spreading
airborne material/local deposits, Consumed denser deposits and degraded silhouettes.
They introduce no supernatural colors or automatic environmental damage. Existing
lore remains: Medtac engineered the pathogen, its cure stock left, and suppressants
delay turning rather than cure it.

## Review status

Rendered reference assets, showcase spaces and district views were inspected during
implementation. Revisions addressed vehicle proportions, excessive surface pattern,
night readability, missing props, opening animation and foliage persistence.
This is an engineering visual review. Human art-direction approval, encounter
balance, and sustained playtesting on reference hardware remain separate work.

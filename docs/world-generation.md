# MedTac campus authoring and gameplay

The normal Medtac Quarantine District raid uses one fixed **350 ? 350 m campus**, layout **19381**. There are four principal enterable buildings and 63 named rooms. Architecture and major cover do not change between raids. The old Labs map remains an isolated regression fixture; the two retired district scenes are not approved deployment layouts.

## Buildings and circulation

North is negative Z. Central Labs occupies approximately 110 ? 100 m, with research to the north/west, research-participant clinical suites to the south, an eastern connector, and separated west/east enclosed basement stairs. The restricted basement is 4.2 m below ground. Outpatient/administration sits south, bulk logistics east, and facilities/security west. There are no enclosed inter-building links.

Public consultations stay separate from research-participant procedures. Labs receives specimens and working stocks; logistics receives bulk freight. Parking is south-west, the loading apron east, and the separated fuel/waste yard west. An inner pedestrian circuit and outer service circuit let players bypass Labs.

Administration has two stairs and a full upper floor. Logistics has two stairs to a dispatch mezzanine. Stairs have 24 visible 175 mm risers, 500 mm treads, smooth collision, and rails. Basement floor openings are physically cut out of the foundation; enclosed side walls and two credential gates protect access.

The [area audit](../resources/district/reports/campus-area-audit.json) records every room and exterior review area: purpose, floor, nearby rooms, entrance coordinates, equipment, loot sockets, service access, encounter role, roof failures, and corrections. The machine-readable layout report additionally records room-clearance and navigation validation.

## Raid rules

- Infection starts at 25:00; suppressants add 3:00 up to that cap. Extraction requires 15 continuous seconds in one of two assigned farthest exits.
- Seven perimeter insertions and four extracts retain the existing authoritative deployment and extraction flow.
- There are 28 NPCs: 18 infected concentrated in research and 10 scavengers in support buildings. No respawn waves.
- Exactly 128 searchable furnishings: Labs 80, outpatient/admin 24, logistics 16, facilities/security 8.
- Exactly 96 loose sockets: Labs 56, outpatient/admin 16, logistics 16, facilities/security 8. Only 48 are active per raid.
- Container models determine loot profiles. Weapon and ammunition cases are restricted to security storage. Specimens, medical supplies, records, personal possessions, and tools stay in their appropriate container families.
- One keycard has a 10% total spawn chance among accessible security, staff, records, and dispatch sources. Each use consumes a carried card and unlocks only one basement gate. Emergency egress closes without granting entry authorization.
- Basement medical storage guarantees two suppressants; trial control and cure-transfer archives guarantee two drives in total. The cure stock has already left the campus.

## Authoring pipeline

Use the standard Godot 4.7.2 executable and Python 3. No external plugins or Python packages are needed for the build.

```powershell
./tools/build_district.ps1 -Godot 'C:/path/to/godot_console.exe' -Capture
./tests/run.ps1 -Godot 'C:/path/to/godot_console.exe' -Capture
# Capture all rooms and exterior review areas without rebuilding:
godot --path . --resolution 1280x720 --script res://tests/district_review.gd
# Ten-minute rendered traversal/combat benchmark:
godot --path . --resolution 1920x1080 --script res://tests/district_benchmark.gd
```

`tools/campus_scene_author.gd` is the campus architecture and dressing recipe. It extends the existing district mesh/collision/atmosphere tooling; it does not scale or regenerate the old Labs departments. Edit the recipe rather than the generated scene. Build configuration accepts only the authored 350 m footprint and seed 19381. The default map ID remains `medtac_quarantine_district`; inventory IDs and profile schemas are unchanged.

The build authors architecture, rooms, equipment, ruins, loot sockets and encounters, then bakes navigation from final collision. Ordinary doors bake open; basement doors bake closed and use controlled links. Room validation checks equipment bounds, unintended intersections, 1.8 m center aisles, doorway paths, and connectivity to each floor's circulation. Physics rays validate tactical cover. Failed candidates remain in `.godot/district-build/`; only validated scenes and area audits are published.

Campus-only materials, office furniture, smaller warehouse racks, pump and fuel-tank geometry improve proportions without changing the original Labs fixture. Privacy partitions, inward-facing searchable storage, supported instruments, equipment fronts, roof openings and facade debris are authored explicitly. Roof failures avoid the sealed basement structure. Exterior foliage excludes foundations, pavement, and route clearance.

## Review and reproduction

```powershell
godot --path . -- --layout-seed 19381 --raid-seed 94731
```

Other layout seeds are rejected before loadout debit. Loot, loose-item and keycard streams remain independent of fixed architecture.

Rendered captures are saved under `.godot/campus-review/`, with a JSON index. Every room gets entry and reverse views. Exterior areas, circulation, stairs, roof failures, four lighting presets, an overview, and a roof cutaway are included. Captures hide the HUD and actors to expose the architecture; live combat is exercised separately by the benchmark and smoke tests.

F7 opens the inspector; F9 cycles atmosphere, F6 toggles rain, F10 cycles visual contamination, and F8 compares the retained screen treatment. Quality affects rendering rather than physical routes, loot or enemies.

Automated checks cannot establish horror atmosphere, human route preference, difficulty, or visual appeal. See the verification record for actual measurements and remaining manual acceptance.

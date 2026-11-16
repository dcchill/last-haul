# District verification record

Environment: Godot **4.7.2.stable.official.ed1daf0bf**, Windows, Forward+, local
NVIDIA RTX 4090. The accepted performance target is 1920 × 1080 at 60 FPS on a
mainstream desktop GPU (RTX 3060 class), Medium quality. That reference hardware
is not available in this workspace and has **not** been verified.

## Automated checks

The complete Windows regression runner passed after the Forward+ migration and
default-map integration. It includes armory, legacy depot, Labs, inventory/player
behavior, character reset, voxel destruction, sensor settings, hand poses,
application smoke, persistence restart and PCK export. The 200-seed Labs detail
audit passed over 56,000 checks; hand validation passed 1,188,462 checks. Legacy tests
explicitly select Labs where they depend on its authored layout.

The district integration test separately covers 200 reproducible graph seeds and
all three final baked layouts (863 checks). It verifies deploy/loot budgets, seven insertions,
four extracts, far-side assignments, physical routes, entered interiors, actual
player stair ascent/upper-floor entry, locked/unlocked research navigation,
six destructible cover sections, saved foliage transforms, presets, contamination,
world fog independent of screen effects, suppressant caps, actual furniture/loot
interactions, deterministic deployment flags and journaled extraction. The GLB
roundtrip test separately passes six checks for nested transforms, wrapper bounds,
collision persistence and overwrite protection.
See `.godot/district-tests.log` for the current check count and result.

Asset technical review passes all eight references. The authoring pipeline saves
48 asset images, 40 art-showcase captures and 34 district captures. Images were
inspected with the image viewer; there is no claim that triangle counts establish
artistic quality. Review captures freeze encounters for stable lighting comparison;
the separate soak runs live AI and ballistics. Headless tests do not validate rendered appearance.

Current full-suite evidence is `.godot/geometry-full-suite.log` (including rendered
capture checks and PCK export). Earlier full-suite evidence is `.godot/district-final-suite.log`;
earlier headless evidence is `.godot/district-full-suite.log`. Final generated layouts
have their own reports in `resources/district/reports/`. Generated logs/images are
ignored build artifacts; repeat the documented commands to reproduce them.

## Surface and placement verification

The geometry revision rebuilds all three district seeds and all 147 prop meshes.
The surface audit reports zero positive-area coplanar overlaps across those meshes.
The district surface checks pass polygon subtraction (including interior holes),
interior prop and loose-loot clearance, exterior prop separation, and tree clearance
around POI and infill buildings. District integration remains 863 checks with zero
failures. The refreshed reference contact sheet, industrial showcase, clinical
interior and district exterior captures were inspected separately.

The revision also removes overlapping ground patches and contamination-stage
residue, resizes indoor shelving and machinery, and reserves authored yards against
procedural roadside props. See the surface constraints in `world-generation.md` for
the authoring rules and regression entry points.

The complete `tests/run.ps1 -Capture` runner passed after this revision, including
legacy maps, 1,188,462 hand-pose checks, persistence, PCK export/load, and rendered
sensor, player-body, world-prop, depot and application checks.

## Performance

The performance sample below predates the surface-overlap and placement fixes.
It is retained as historical evidence; it has not been rerun for that geometry revision.

The benchmark tool runs a repeatable ten-minute traversal/combat workload with
all 28 NPCs, protected actor health, replenished ammunition, real navigation,
movement, hearing, targeting, ballistics, shadows and effects. It disables VSync,
uses Medium world quality and retains the screen treatment. The machine-readable
record is `.godot/district-benchmark.json`; its log identifies progress and shots.
Player/NPC collision is disabled in this harness so immortal crowds cannot pin
the route; world geometry and NPC/NPC collision remain active. These conditions
are recorded in the JSON. The harness is not a balance playtest.

Completed local soak (600.003 seconds, 1920 × 1080, Medium, Overcast Day, retained
screen treatment):

| Measurement | Result |
| --- | --- |
| Mean / p95 / p99 frame time | 3.08 / 5.65 / 6.58 ms |
| Worst recorded frame | 99.14 ms |
| Warm PackedScene instantiation/deployment | 241.87 ms |
| Peak engine static / video memory | 203.80 / 309.40 MiB |
| Maximum recorded draw calls | 2,845 |
| Player traversal | 1,766.26 m over 14 route legs |
| AI present / observed moving | 28 / 26 |
| Live projectiles | 1,975 |

The raw record is checked in as `resources/district/reports/performance_local.json`.
Deployment timing excludes the initial PackedScene disk load and asset import.
The 99 ms outlier is retained rather than omitted; its cause was not attributed
with a CPU/GPU trace. These results do not establish stutter-free performance.
Short harness runs are smoke checks only. An RTX 4090 result cannot verify the
RTX 3060-class target, even when its frame percentiles are below 16.7 ms.

## Remaining manual acceptance

- Human complete-raid playtests: route choice, scav/infected difficulty, loot
  scarcity, 25-minute infection pressure, extraction camping and readability.
- Human art-direction review of all POIs, architectural repetition, material
  wear, contamination treatment and silhouette quality at gameplay distances.
- Reference-hardware 1080p performance and longer memory/thermal sessions.
- Additional map extents and externally supplied artist assets; only the shipped
  350 m layouts and original reference assets have full integration coverage.

These are explicit limits on verification. They must not be reported as completed
by the automated suite or by successful generation alone.

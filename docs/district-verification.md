# MedTac campus verification

The November 16, 2026 campus replaces the normal district with four buildings, 63 rooms, and fixed layout 19381. Earlier seven-POI district measurements are retained separately in [the historical record](district-verification-legacy.md); they do not describe this campus.

## Geometry and gameplay

The final authoring build passes exterior traversal, insertion/extraction reachability, physically ray-tested cover, and room-level validation. Every room is checked for equipment bounds, unintended furnishing intersections, center-aisle clearance, doorway access, and connection to its floor circulation. This caught and corrected ground-floor lintel headroom, outward-facing storage, and isolated end-room corridors before publication.

The focused campus integration run passes **26,615 checks** with zero failures. It physically walks the player through all 63 room entrances, interacts with all 128 furnishings from their usable sides, walks both restricted basement stairs in both directions, tests independent card consumption and emergency egress, checks security against above-ground/upper-floor bypasses, and exercises physical loot profiles and reproducibility across 200 raid seeds. The district integration test separately covers administration and dispatch stairs with actual player movement, extraction, infection, seeded deployment and invalid-layout rejection.

Machine-readable results and the complete room/area inventory are in `resources/district/reports/layout_19381.json` and `campus-area-audit.json`. Diagnostic logs remain under `.godot/campus-*.log`.

## Rendered review

The capture harness saves 165 images under `.godot/campus-review/`, including two directions in every room, exterior review areas, stairs, roof failures, four atmosphere presets, overview and cutaway. `capture-index.json` records camera positions and filenames. HUD and actors are hidden for architectural inspection; the live benchmark and application smoke tests exercise gameplay separately.

Rendered verification and the complete suite are recorded below after their final run. Successful headless validation alone does not establish appearance.

## Performance and limits

The engine reports **Intel Iris Xe Graphics** for rendered runs in this workspace. The RTX 3060-class 1920 ? 1080 Medium target remains unverified. The previous RTX 4090 district measurements must not be represented as campus results.

Human complete-raid playtests remain necessary for survival-horror atmosphere, route preference, difficulty, loot economy, extraction camping and readability. Automated checks and agent image inspection do not replace that acceptance. No multiplayer, new objectives, contamination gameplay, persistence migration, or cure mechanic was added.

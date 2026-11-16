# Last Haul

A **Godot 4.7.2 stable** single-player extraction shooter. **Enter raid - Medtac Quarantine District** deploys an infected human into a 350 × 350 m district with seven connected POIs, sixteen enterable buildings, upper floors, 28 enemies, and three curated layouts. The project now uses **Forward+**. See the [district guide](docs/world-generation.md), [art standards](docs/art-direction.md), and [verification record](docs/district-verification.md).

The district has 96 searchable furnishings, 48 active loose items from 96 sockets, physical signs, contextual equipment, ray-tested cover, destructible sections and an optional keycard-controlled research room. Loot follows the physical container. Overcast Day is the default; reusable dusk, morning fog and emergency-night presets share geometry. The detailed Labs scene remains available as a [regression fixture](MEDTAC_MAP.md).

Start with **25 minutes until turning** in the district. Suppressants buy three minutes, capped at 25 minutes remaining. Sprinting uses stamina without accelerating infection. Follow the compass to either of your two assigned far-side extracts and remain inside for 15 continuous seconds. Death, turning, and abandonment lose carried equipment and loot. Practice remains isolated from persistent progression. See the [implemented human player notes](PLAYER_MODEL_PLAN.md).

## Run

1. Install the standard Godot **4.7.2 stable** editor; .NET and external voxel plugins are unnecessary.
2. Import `project.godot`, allow the first asset import to finish, and press **F6** only when editing an individual scene, or **F5** to run the complete game.
3. Open **Inventory / stage loadout**. New profiles receive the current one-time rifle, armor, loose ammunition and magazine kit. Existing possessions are migrated without extra grants.
4. Equip gear and stage ammunition. **Enter raid - Medtac Quarantine District** also permits an unarmed loadout.
5. Press **R** to insert a loaded compatible magazine from pockets or an equipped rig. Manage magazines and loose rounds through inventory context actions.
6. Loot crates, medical supplies, and defeated scavs or zombies with **E**. Inventory and looting do not pause combat.
7. Stay in an assigned green extraction zone for **15 continuous seconds**. No loot, objective, equipment, or activation is required; leaving resets the timer. Surviving gear and nested contents return to the persistent stash. Death, turning, and abandonment lose everything carried; there is no secure container.
8. Use **Practice armory** for isolated equipment grants and reset. Practice items never enter your persistent stash.

Command line, with Godot on `PATH`:

```powershell
godot --path . --editor
godot --path .
```

The project uses the Forward+ renderer and Jolt physics. The default viewport is 1280×720 and scales with the window. World quality defaults to Medium; use 1920×1080 for the district performance benchmark.

The game includes an optional visual treatment: 2×2 pixelation, ordered dithering, restrained banding, gray-green grading, distance haze, and rare faint flickers. Settings offers Pixelation **Off / 2x / 3x / 4x**, overall strength, enable, and flicker controls. Larger pixels reduce small details; the HUD stays crisp. Press **F8** in a raid (including pause) for a temporary on/off comparison. See [sensor tuning and runtime controls](docs/signal-decay.md).

## Controls

| Action | Control |
| --- | --- |
| Move / look | WASD / mouse |
| Sprint / jump | Shift / Space |
| Fire / reload | Left mouse / R |
| Inventory | I |
| Inventory move / rotate | Drag / press R while dragging |
| Quick transfer / equip | Ctrl-click / Alt-click |
| Split / inspect / actions | Shift-drag / double-click / right-click |
| Search storage / pick up loose loot | E while aiming within 3.5 meters |
| Pause / close crate / resume | Escape |
| Navigate menus | Tab or arrow keys; Enter/Space activates buttons |

The human starts district raids with **1,500 seconds until turning** (the preserved Labs fixture uses 1,200). Use a carried infection suppressant to restore **180 seconds**, up to the map's starting capacity. Inventory, looting, and extraction keep the clock running; pause freezes it. The character breathes harder below two minutes and coughs below one minute. Symptoms preserve aiming control.

Main menu **Settings ? Reset character** asks for confirmation, then clears character history, pending rewards, stash and staged inventory and restores the original starter kit. It keeps your game settings and is unavailable from raid or practice settings.

Menus release the mouse and show keyboard focus. Pause stops simulation; the loot panel does **not** stop the guard. Settings include mouse sensitivity, master volume, and fullscreen. Placeholder combat currently has visual/text feedback and procedural combat and material footstep sounds.

## Organization and configuration

| Folder | Purpose |
| --- | --- |
| `scenes/` | Main entry, player/guard scenes, district layouts, art showcase, and practice/depot/Labs regression fixtures |
| `scripts/data/` | Typed custom Resource definitions and catalog validation |
| `scripts/raid/` | Raid phase, authoritative requests, and per-player runtime state |
| `scripts/player/`, `scripts/npcs/` | Movement/interaction and guard perception/behavior |
| `scripts/weapons/`, `scripts/combat/` | Ammo/reload state, hitscan/damage, impact presentation |
| `scripts/inventory/`, `scripts/world/` | Bounded inventory, targets, containers, extraction |
| `scripts/persistence/` | Profile transactions, recovery, and settings |
| `resources/` | Editable `.tres` gameplay data, separated by type |
| `ui/` | Minimal HUD and keyboard-operable prototype menus |
| `assets/` | Original textures, shaders, physical signs and source art; baked props live in scenes/resources |
| `tests/`, `docs/` | Dependency-free checks and architecture/networking notes |

Open `.tres` assets in the Inspector to change rifle capacity/timing/range, round damage, material impact color/multiplier, vest protection, crate contents, item stack limits, or guard health/perception/movement/attack values. Definitions never hold live inventory, health, or ammo state. Add new definitions to `Catalog.PATHS`; keep content IDs unique and stable. Existing saves refer to item IDs, so changing an ID requires migrating those saves.

Scene entities use explicit `entity_id` values, including the extraction zone. Duplicates or missing references block deployment. The player's stable ID is generated once in the profile. Targets and containers reset each deployment; the stash does not.

Use the [district authoring pipeline](docs/world-generation.md#authoring-pipeline) for district geometry and navigation. For the legacy yard/depot fixtures, rebake navigation with the NavigationRegion3D editor tools, or:

```powershell
godot --headless --path . --script res://tests/bake_navigation.gd
# Depot (omit the scene argument for the practice yard):
godot --headless --path . --script res://tests/bake_navigation.gd -- res://scenes/raid/veyra_depot.tscn
```

The bake command intentionally updates the yard scene. Ordinary tests do not rewrite source files.

The Labs fixture uses separately baked cover variants and controlled access links. Follow
its [authoring pipeline](MEDTAC_MAP.md#authoring) when regenerating that map.

## Saves and authority

Profiles live at `user://profile.json`; settings at `user://settings.cfg`. On Windows, `user://` normally resolves to `%APPDATA%/Godot/app_userdata/Last Haul/`. The version 6 profile stores the stash, staged equipment and inventories, physical item identities, nested contents, ammunition order, chamber state and committed raid IDs. Versions 1-5 migrate with an original-file backup. Validated temporary writes, backup recovery and corrupt-main preservation remain enabled. Completed results are journaled before credit and retained for retry when the stash is full. A disk failure that prevents journaling still requires retry before quitting.

See [inventory controls, architecture and migration](docs/inventory.md) for exact rules, editable resources and recovery behavior.

`RaidAuthority` validates `request_fire`, `request_reload`, `request_interact`, `request_claim`, `request_extract`, and `request_abandon`. It advances NPC decisions, damage, and extraction using host-owned time and physics. The UI submits requests and observes outcomes; it never transfers loot directly. `RaidParticipant` keeps inventory, weapon, health, opened-container state, and extraction progress indexed by stable player ID. Persistent services outlive the disposable raid scene. See [architecture](docs/architecture.md) and [future networking](docs/networking.md).

## Verify

Run the complete suite on Windows:

```powershell
./tests/run.ps1 -Godot 'C:/path/to/Godot_v4.7.2-stable_win64_console.exe'
# Also run a rendered smoke test and save captures under .godot/:
./tests/run.ps1 -Godot 'C:/path/to/Godot_v4.7.2-stable_win64_console.exe' -Capture
```

Equivalent individual commands work on other platforms:

```text
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/application_smoke.gd
godot --headless --path . --script res://tests/persistence_restart.gd -- --write
godot --headless --path . --script res://tests/persistence_restart.gd -- --read
godot --path . --resolution 1280x720 --script res://tests/application_smoke.gd -- --capture
```

Checks exit nonzero on failure. Test saves live under `.godot/` and do not change the real stash or settings. The headless application test explicitly skips captured-mouse movement; the rendered smoke test covers input-driven walking, sprinting, jumping/landing, mouse-look handling, menus, loot, results, saving, and redeployment. Tests also cover inventory atomicity, resource/entity validation, cooldowns, reload cancellation, damage/material/armor response, sight obstruction, hearing, navigation, NPC death, extraction reset, duplicate rewards, backup recovery, invalid saves, failed writes, and retry. The restart probe verifies persistence across two separate Godot processes.

Verification on this workspace uses the local official `4.7.2.stable` executable. See the [district verification record](docs/district-verification.md) for actual results and remaining manual checks.

## Version control and limits

Commit scenes, `.tres` definitions, source assets, `.import` metadata, and `.gd.uid` files. `.gitignore` excludes `.godot/`, generated builds, credentials, and temporary files. No new remote, published release, or license is created by the map build.

This is a solo prototype with guard and zombie NPCs and a reference armory. Networking/prediction, a trusted online profile service, final item-specific world art and balance tuning remain outside this inventory implementation. Voxel destruction uses our cell-based cover, support checks and capped debris; see [voxel limits](docs/voxels.md). The local save format is editable and provides no anti-cheat guarantee.

# Last Haul

A small **Godot 4.7.2 stable** framework for a voxel-style PvE extraction shooter. This milestone provides a playable first-person block-built yard, editable gameplay resources, and explicit authority boundaries for future co-op. It has no networking or voxel destruction yet.

## Run

1. Install the standard Godot **4.7.2 stable** editor; .NET and third-party dependencies are unnecessary.
2. Import `project.godot`, allow the first asset import to finish, and press **F6** only when editing an individual scene, or **F5** to run the complete game.
3. Choose **Deploy to yard**. You receive a free rifle, 12 loaded rounds, and 48 reserve rounds.
4. Shoot the yellow targets or red guard. Use the blocks as cover. The guard sees, hears shots, navigates, and attacks.
5. Approach the orange salvage crate, aim at it, press **E**, and choose **Take one**. Close the panel with Escape.
6. Enter the green extraction square behind and left of the spawn. Stay inside for three seconds. Leaving resets the countdown; salvage is required.
7. Return to the stash screen. Extracted salvage persists when the application restarts. Death or abandonment loses raid loot. Free starter equipment never enters the stash.

Command line, with Godot on `PATH`:

```powershell
godot --path . --editor
godot --path .
```

The project uses the Compatibility renderer and Jolt physics. The default viewport is 1280×720 and scales with the window.

## Controls

| Action | Control |
| --- | --- |
| Move / look | WASD / mouse |
| Sprint / jump | Shift / Space |
| Fire / reload | Left mouse / R |
| Open crate | E while aiming within three meters |
| Pause / close crate / resume | Escape |
| Navigate menus | Tab or arrow keys; Enter/Space activates buttons |

Menus release the mouse and show keyboard focus. Pause stops simulation; the loot panel does **not** stop the guard. Settings include mouse sensitivity, master volume, and fullscreen. Placeholder combat currently has visual/text feedback and no sound assets.

## Organization and configuration

| Folder | Purpose |
| --- | --- |
| `scenes/` | Main entry, editable player/guard scenes, and baked test yard |
| `scripts/data/` | Typed custom Resource definitions and catalog validation |
| `scripts/raid/` | Raid phase, authoritative requests, and per-player runtime state |
| `scripts/player/`, `scripts/npcs/` | Movement/interaction and guard perception/behavior |
| `scripts/weapons/`, `scripts/combat/` | Ammo/reload state, hitscan/damage, impact presentation |
| `scripts/inventory/`, `scripts/world/` | Bounded inventory, targets, containers, extraction |
| `scripts/persistence/` | Profile transactions, recovery, and settings |
| `resources/` | Editable `.tres` gameplay data, separated by type |
| `ui/` | Minimal HUD and keyboard-operable prototype menus |
| `assets/` | Placeholder asset notes; primitive meshes live in scenes |
| `tests/`, `docs/` | Dependency-free checks and architecture/networking notes |

Open `.tres` assets in the Inspector to change rifle capacity/timing/range, round damage, material impact color/multiplier, vest protection, crate contents, item stack limits, or guard health/perception/movement/attack values. Definitions never hold live inventory, health, or ammo state. Add new definitions to `Catalog.PATHS`; keep content IDs unique and stable. Existing saves refer to item IDs, so changing an ID requires migrating those saves.

Scene entities use explicit `entity_id` values, including the extraction zone. Duplicates or missing references block deployment. The player's stable ID is generated once in the profile. Targets and containers reset each deployment; the stash does not.

After editing static yard geometry, rebake and save navigation with the NavigationRegion3D editor tools, or:

```powershell
godot --headless --path . --script res://tests/bake_navigation.gd
```

The bake command intentionally updates the yard scene. Ordinary tests do not rewrite source files.

## Saves and authority

Profiles live at `user://profile.json`; settings at `user://settings.cfg`. On Windows, `user://` normally resolves to `%APPDATA%/Godot/app_userdata/Last Haul/`. The profile has a version, stable player ID, stash stacks, last result, and committed raid IDs. Writes validate a temporary file, back up a validated previous profile, then replace the main file. A failed write leaves the result pending and offers retry. Deployment and leaving results are blocked while a result is pending; an explicit quit-without-saving option remains available.

An invalid main profile recovers from a valid `.bak` after preserving the unreadable main as `.corrupt-<id>`. Recovery can roll back to the previous successful save. If neither file is valid, deployment is blocked and both originals remain untouched; move or repair those files before starting a new profile. Unsupported save versions and unknown item IDs are rejected rather than silently discarded. There is no migration from older game formats in this first version. A raid interrupted by process termination is lost; ongoing raids are not saved.

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

Verification on this workspace uses the local official `4.7.2.stable` executable. See [verification record](docs/verification.md) for actual results and remaining manual checks.

## Version control and limits

Commit scenes, `.tres` definitions, source assets, `.import` metadata, and `.gd.uid` files. `.gitignore` excludes `.godot/`, generated builds, credentials, and temporary files. No Git repository, remote, release export, or license has been created for you.

This is a solo prototype with one guard and one rifle. Voxel chunks/destruction, penetration/ricochet, networking/prediction, loadout selection, advanced inventory UI, sound assets, and production persistence are deferred. The impact signal is the extension point for future material effects and destructible voxel surfaces. The local save format is editable and provides no anti-cheat guarantee.

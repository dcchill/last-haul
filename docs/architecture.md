# Framework boundaries

`scenes/main.tscn` owns persistent profile/settings services, the UI, and a disposable `RaidAuthority` yard instance. Deployment creates and validates the scene; successful extraction or failure produces one immutable-by-convention result snapshot. The application commits the result once, journaling pending results and retaining the ended raid while a write needs retry. Returning home frees the raid. Nothing in the stash aliases a raid inventory or editable definition.

```mermaid
flowchart LR
    Input[Local input / future host commands] --> Player[Player movement + interaction]
    Player --> Authority[RaidAuthority requests]
    UI[UI] --> Authority
    Authority --> Weapons[WeaponState]
    Authority --> Ballistics[Ballistics trace + damage calculation]
    Authority --> NPC[Guard perception + navigation]
    Authority --> Inventory[Per-player RaidInventory]
    Ballistics --> Impacts[Impact signal / presentation]
    Authority --> Results[Result signal]
    Results --> App[Application]
    App --> Profile[ProfileStore transaction]
    Authority --> UI
```

## Contracts

- Gameplay request methods return `bool`; inventory transaction requests return explicit success/rejection results and revisions. False means no requested gameplay mutation was accepted. Fire consumes ammunition even when the physics trace misses. Reload moves rounds only when its authority-owned timer completes. Loot transfers check the entire quantity/capacity first; rejected claims do not consume crate contents.
- Requests take a stable player ID; object interactions and extraction also identify their target. Actor positions and camera aim come from scene state, not caller-supplied hit reports. Extraction time advances only in authority physics processing.
- `participants[player_id]` owns the actor's raid-only weapon, inventory, health, open-container session, and extraction countdown. The prototype registers one participant; this registry is independent of the profile store.
- `notice(message)`, `container_opened(player_id, container_id)`, `health_changed(player_id, health)`, `shot_fired(player_id, position)`, and `finished(result)` report accepted state or feedback. Shot events feed NPC hearing. Impact events carry position, normal, material ID, and entity ID; world-only hits have an empty entity ID.
- Result dictionaries contain `raid_id`, `success`, and `reason`. Stash commits use a copied loot snapshot and track committed raid IDs, so repeated callbacks or retries cannot add loot twice. Failure results update history without transferring loot.
- `Ballistics` calculates material/armor response without owning health; authority applies the result. `ImpactPresenter` only renders short-lived markers. Guard methods calculate perception/decisions and move the guard only when called by authority; they never mutate stash or player health.
- `RaidPlayer.drive_movement()` accepts movement intent independently of keyboard polling. `accepts_local_input` can disable local controls for remote actors. Physics and input are paused by the pause screen; opening a container merely releases mouse capture.

## Extension points and limits

The editable yard contains collision geometry and baked navigation. Explosions damage our `VoxelDestructible` cover: batch cell edits, check support once, then rebuild a greedily merged surface and matching collision. `VoxelDebrisManager` retains capped physical debris and detached clusters. The external voxel projects are references only; see [voxel optimizations](voxels.md). Navigation stays baked; future networking must send voxel edits as host-confirmed changes. Projectile simulation remains behind `Ballistics`, without changing loot or raid-result ownership. Ordinary bullets stop on these surfaces without penetration or carving.

The catalog explicitly lists prototype resources and validates IDs, references, and gameplay ranges. Add data there rather than scattering path discovery through gameplay. Inventory uses persistent physical instances, rectangular grids, nested containers, equipment roots, ordered magazine ammunition and cumulative carried weight. `InventoryTransactions` validates requests and revisions for both raid and staging contexts; `InventoryManager` commits complete candidate states. The fullscreen inventory only presents state and submits requests. See [inventory architecture and save migration](inventory.md).

The solo raid ends on its sole participant's extraction, death, or abandonment. Multi-player lifecycle policy and remote controller spawning belong in the future session layer; keep per-player outcomes at this boundary rather than putting them in UI. The prototype uses synchronous local disk writes and retains all committed raid IDs. Upgrade to a transactional profile service and compacted outcome ledger before production-scale persistence.

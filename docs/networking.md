# Future co-op: host authority

No RPCs, transport, matchmaking, prediction, or replication run in this milestone.

## Session ownership

Add a session layer that authenticates a joining peer and maps its transport peer ID to a stable player ID. The client must not select a different player ID in a command. The host allocates runtime entity IDs, instantiates actors, registers per-player `RaidParticipant` state, and distributes a spawn manifest. Preserve authored IDs for placed NPCs, containers, and extraction zones; use host-generated IDs for dynamically spawned entities. Godot instance IDs and node paths are not wire identities.

The local player input driver becomes a command producer. Remote actors disable `accepts_local_input`; the host validates movement/aim intents and calls `drive_movement()` in its physics tick. A client may later predict its own movement, but reconciles to host position/velocity. Host physics owns firing origins, line of sight, hit resolution, cooldowns, ammunition, NPC decisions, loot claims, health, objective progress, and extraction timers.

## Commands and replication

Adapt the existing `request_*` methods into host-only handlers. Bind the authenticated player ID server-side, validate command sequence/rate and current state, and return acceptance or rejection with a sequence number. Never accept client-reported damage, container contents, loot transfer totals, elapsed extraction time, or raid success. `_apply_damage`, `_update_extraction`, and `_finish` remain internal host operations, not remotely callable RPCs.

Replicate a versioned initial snapshot of the raid phase, spawn manifest, transforms, NPC health/state, container contents, and per-player raid state. Send transform/velocity updates as sequenced transient snapshots; send claims, health changes, phase transitions, inventory deltas, spawn/despawn, and results as reliable ordered events. Ammo and inventory can be private to their owning peer. Presentation consumes confirmed shot/impact events and may add temporary predicted effects later. Late joiners receive a fresh snapshot before applying subsequent events.

The host serializes competing loot requests. Revalidate ownership, range, line of sight, available quantity, and capacity at claim time, even after a container panel has opened. Preserve the inventory service request IDs, expected revisions and session result cache when adding retransmission; the existing quantity/capacity checks remain necessary.

The solo prototype calls `_finish` when its only participant exits. For co-op, issue per-player extraction/death/abandonment results and keep shared simulation running while any participant remains. Track disconnected players on the host with a reconnect timeout; do not let a disconnect restore claimed loot or grant extraction. End the shared raid only when all participants have a terminal result. A client menu pause must become local UI only and must not pause the host's scene tree.

## Profiles and trust

Keep persistent profiles outside the shared raid. The host emits one result per player, keyed by raid ID and player ID; each profile transaction credits only that player's successfully extracted inventory. The current local store's deduplication is sufficient for a local prototype, not remote trust. In a production service, commits must be authenticated, transactional, and idempotent on `(raid_id, player_id)`.

A listen host remains trusted and can cheat. Client-owned JSON files are editable and can be rolled back or copied. Competitive integrity, authoritative long-term inventory, cloud reconciliation, host migration, and anti-cheat require a separate backend/trust design. Local backups recover files; they do not secure rewards.

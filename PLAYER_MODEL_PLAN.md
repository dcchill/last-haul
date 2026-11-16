# Infected human player

Status: implemented with the MedTac Labs milestone. See [MedTac Labs](MEDTAC_MAP.md).

The default [Quarantine District](docs/world-generation.md) now starts infection
at 25:00 and caps suppressant recovery there. The 20:00 values below describe the
preserved Labs fixture; the character reads its capacity from map data.

The player is an infected civilian scavenger with a worn jacket, work trousers,
boots, gloves, pale exposed skin, dark veins, and a stained wrist bandage. The
first-person hands match the body. Equipped armor and the existing weapon poses
remain supported. Head and body arms cast shadows without obstructing the camera.

The countdown is time until turning: 20:00 at deployment. It advances in literal
simulation seconds while moving, sprinting, looting, or extracting. Pause freezes
it; practice is exempt. A suppressant buys three minutes, capped at twenty minutes
remaining. Treatment delays turning and does not cure infection.

Below two minutes, breathing grows heavier and vein markings appear. Below one
minute, brief coughs accompany the final warning. These symptoms do not disturb
aiming. At zero, the authority ends the raid once; the body then collapses.
Turning wins a simultaneous extraction finish. Failed raids lose carried gear
and loot; a successful extraction starts the next deployment with a fresh clock.

`human_body.gd` supplies the model and poses, `weapon_hands.gd` matches sleeves,
gloves, and the wrist bandage, and `RaidParticipant` owns infection time.
Profile version 6 converts saved power cells throughout nested storage, staged
gear, and pending rewards, retaining original-file backups and item identities.

Human body visibility, weapon-hand clearance, infection, treatments, migration,
pause behavior, and extraction boundaries are covered by the automated and
rendered checks. Character customization and becoming a playable infected are
separate features.

class_name OwnedUpgrade
extends RefCounted
## Ports entities/Player.ts's OwnedUpgrade interface — one entry per distinct
## UpgradeDefinition the player has picked at least once, tracking how many
## times (stacks). A plain RefCounted data holder, not a Resource: nothing
## about ownership is authored content or ever saved to disk (a run's
## upgrades are gone the moment it ends), so there's no reason to pay for
## Resource's serialization machinery here.

var def: UpgradeDefinition = null
var stacks: int = 0

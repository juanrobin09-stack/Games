class_name UnlockDefinition
extends Resource
## Ports data/types.ts's UnlockDefinition + data/unlocks.ts's 6 entries (2
## weapons, 2 abilities, 1 enemy, 1 upgrade-rarity gate) — purchased once
## with Soul Ash via MetaProgression.purchase_unlock(id, cost).

enum Kind { WEAPON, ABILITY, ENEMY, UPGRADE_TIER }

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var cost: int = 0
@export var kind: Kind = Kind.WEAPON
## Id of the WeaponDefinition/AbilityDefinition/EnemyDefinition this
## unlocks, or the upgrade-tier value, depending on `kind`.
@export var ref_id: String = ""

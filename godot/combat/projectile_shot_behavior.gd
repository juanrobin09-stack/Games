class_name ProjectileShotBehavior
extends WeaponBehavior
## The Solar Spear/Bow archetype. The actual spawn logic (shot count from
## stats.projectile_count, the fan spread across them, baking the player's
## live stats into the projectile at fire time) lives in
## CombatManager.fire_player_projectile, a straight port of CombatSystem.ts's
## fireProjectileWeapon — this is just that archetype's entry point into it.

func execute(attacker: PlayerCharacter, weapon_def: WeaponDefinition) -> void:
	CombatManager.fire_player_projectile(attacker, weapon_def)

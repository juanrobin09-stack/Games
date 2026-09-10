class_name WeaponBehavior
extends RefCounted
## Build-order step 5, GODOT_MIGRATION.md §8. Ports the *shape* the doc
## asks for — CombatSystem.ts executes every weapon through one function
## per `kind` (`performMeleeAttack`/`fireProjectileWeapon`), so a third
## archetype means a third branch in that same function and every existing
## weapon keeps passing through it. Godot instead gets one WeaponBehavior
## subclass per attack archetype, each overriding execute(); for_kind() is
## the only place a WeaponDefinition.Kind maps to its behavior instance, so
## a new archetype (Beam, Thrown, Channeled) means one new subclass file
## plus one new line below — never a wider if/else at any call site,
## including player.gd's.
##
## attacker is typed PlayerCharacter, not the wider Node: today only the
## player ever owns a WeaponDefinition/fires through this system (enemies
## attack through their own EnemyDefinition fields via EnemyAI/CombatManager
## entirely, with no weapon_id of their own) — no reason to widen the type
## for a case nothing exercises yet.
##
## The archetype's own hit-resolution logic still lives in CombatManager
## (perform_melee_attack, fire_player_projectile) alongside the rest of the
## damage pipeline it's already part of — same as the Web build, where
## those two functions live in CombatSystem.ts too, not off in Player.ts.
## execute() is the Strategy's entry point, not a reimplementation.

static var _by_kind: Dictionary = {}

static func for_kind(kind: WeaponDefinition.Kind) -> WeaponBehavior:
	if _by_kind.is_empty():
		_by_kind[WeaponDefinition.Kind.MELEE] = MeleeArcBehavior.new()
		_by_kind[WeaponDefinition.Kind.RANGED] = ProjectileShotBehavior.new()
	return _by_kind.get(kind)

func execute(_attacker: PlayerCharacter, _weapon_def: WeaponDefinition) -> void:
	push_error("WeaponBehavior.execute() called on the base class directly — use WeaponBehavior.for_kind(kind) to get a concrete subclass instance")

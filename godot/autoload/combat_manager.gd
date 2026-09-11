extends Node
## Autoload: CombatManager
##
## Ports combat/CombatSystem.ts — the single place every damage source
## (melee, projectiles, contact damage, warden bashes, bloat detonation,
## status-effect ticks) routes through, so every hit gets identical crit
## rolls, knockback, and warden-shield-block handling. Read directly from
## CombatSystem.ts/EnemyAI.ts/Enemy.ts this session — not approximated.
##
## Deferred this pass, on purpose (see GODOT_MIGRATION.md and each
## function's own comment for exactly what and why):
## - Synergies (ashFire/emberCritical/lightHealing/wrath/shadowDodge) —
##   depend on the upgrade-ownership system, build-order step 6.
## - Abilities' actual effects (Ember Burst, Warding Sigil) — deferred to
##   progression, step 6, alongside synergies (see below); weapon execution
##   itself (melee arc + projectile shot) is done, in combat/weapon_behavior.gd.
## - Damage numbers, camera shake, hit-stop, SFX — step 9 (no camera-shake
##   system exists in this port at all yet). Particles are wired (step 8) —
##   see VfxPresets for the ones this file's own hits/deaths/dodges/bursts
##   call, and each call site's own comment for what's still skipped and why.
## - Hazards (spore clouds) — Bloat and the Warden champion still deal
##   their direct-hit damage below; the lingering cloud they'd normally
##   also leave is a self-contained follow-up.
## - `resolve_melee_land`'s exact body isn't a byte-exact port (the
##   relevant Game.ts callback wasn't read this session) — see its own
##   comment for the from-source-principles implementation used instead.

signal hit_landed(attacker: Node, target: Node, damage: float, was_crit: bool)
signal crit_landed(attacker: Node, target: Node)
signal dodge_perfected(character: Node)
signal ability_cast(character: Node, ability_id: String)
signal enemy_died(enemy: Node)
signal player_died()
signal champion_shield_broken(enemy: Node)
## Ports Boss.ts/BossSystem.ts's own gameEvents.emit('bossPhaseChanged'/
## 'bossDefeated') — this port has no generic pub/sub event bus autoload at
## all (grepped project-wide; the closest existing pattern is exactly this:
## a per-concern signal declared directly on the autoload that resolves
## that concern, e.g. champion_shield_broken living here because
## on_champion_shield_break is what detects it), so these two follow suit
## rather than introducing a new bus just for the boss.
signal boss_phase_changed(boss: Node)
signal boss_defeated(boss: Node)

const PROJECTILE_SCENE := preload("res://entities/projectile.tscn")
const ENEMY_SCENE := preload("res://entities/enemy.tscn")

const HIT_ARC_COVERAGE := 0.75
## Damage that gets through a raised warden shield.
const SHIELD_DAMAGE_FACTOR := 0.15

## Ports world/Difficulty.ts's countZoneWeight — enemy *count* stops climbing
## with zoneIndex past the Hollow Ruins; hp_mult/damage_mult below keep
## scaling normally past that point instead (a composition/stats problem,
## not a swarm-density one — see the source's own comment).
func _count_zone_weight(zone_index: int) -> float:
	return minf(float(zone_index), 1.0)

## Ports world/Difficulty.ts's getDifficultyFactors — pure math, no entity
## dependency. corruption_ratio comes from RunState.corruption_ratio().
func difficulty_factors(zone_index: int, corruption_ratio: float) -> Dictionary:
	return {
		"hp_mult": 1.0 + zone_index * 0.32 + corruption_ratio * 0.55,
		"damage_mult": 1.0 + zone_index * 0.22 + corruption_ratio * 0.35,
		"extra_enemies": floori(_count_zone_weight(zone_index) * 0.6 + corruption_ratio * 1.6),
	}

## Ports world/Difficulty.ts's getCombatRoomEnemyCount. rng_roll is a single
## random draw in [0,1) from the caller (LevelGenerator), kept as a plain
## parameter rather than an RNG reference so this stays pure math.
func get_combat_room_enemy_count(zone_index: int, corruption_ratio: float, rng_roll: float) -> int:
	var base: int = 2 + floori(rng_roll * 2.2)
	var extra_enemies: int = difficulty_factors(zone_index, corruption_ratio)["extra_enemies"]
	return base + int(_count_zone_weight(zone_index)) + extra_enemies

func roll_crit(chance: float) -> bool:
	return randf() < clampf(chance, 0.0, 0.95)

func _angle_diff(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)

# ---------------------------------------------------------------- Player -> Enemy

## The player's own weapon swing — checked once, instantly, the moment the
## swing starts (an intentional crowd-clearing choice, not a persistent
## hitbox), against every enemy inside weapon.range within a narrowed arc.
func perform_melee_attack(player: PlayerCharacter) -> void:
	var weapon := player.weapon()
	if weapon == null:
		return
	var attack_range: float = weapon.range * player.stats.range_mult
	var arc_degrees: float = weapon.arc_degrees if weapon.arc_degrees > 0.0 else 100.0
	var half_arc: float = deg_to_rad(arc_degrees * HIT_ARC_COVERAGE) / 2.0
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyCharacter
		if enemy == null or not enemy.alive or enemy.state == EnemyCharacter.State.VANISHED:
			continue
		var offset: Vector2 = enemy.global_position - player.global_position
		var dist: float = offset.length()
		if dist > attack_range + enemy.radius:
			continue
		var angle_to_enemy: float = offset.angle()
		if absf(_angle_diff(player.attack_facing_lock, angle_to_enemy)) > half_arc:
			continue
		var crit: bool = roll_crit(player.stats.crit_chance + weapon.crit_bonus)
		var base_damage: float = weapon.base_damage * player.stats.damage_mult
		var dir: Vector2 = offset.normalized() if dist > 0.01 else Vector2(cos(angle_to_enemy), sin(angle_to_enemy))
		damage_player_to_enemy(player, enemy, base_damage, crit, {
			"knockback_dir": dir,
			"knockback_force": weapon.knockback,
		})

func spawn_enemy_projectile(enemy: EnemyCharacter, angle: float) -> void:
	var parent := enemy.get_parent()
	if parent == null:
		return
	var proj: ProjectileEntity = PROJECTILE_SCENE.instantiate()
	parent.add_child(proj)
	var spawn_pos: Vector2 = enemy.global_position + Vector2(cos(angle), sin(angle)) * (enemy.radius + 4.0)
	var speed: float = enemy.def.projectile_speed if enemy.def.projectile_speed > 0.0 else 220.0
	proj.from_player = false
	proj.setup(spawn_pos, angle, speed, enemy.attack_damage(), 7.0)

## Ports fireProjectileWeapon: ProjectileShotBehavior's own entry point
## (build-order step 5). Shot count is 1 + floor(stats.projectile_count),
## fanned across a small spread once there's more than one — everything
## baked from the player's live stats at fire time into each bolt, exactly
## like the Web build's own spawnProjectile(options) snapshot (a projectile
## never re-reads the player after launch).
func fire_player_projectile(player: PlayerCharacter, weapon: WeaponDefinition) -> void:
	var parent := player.get_parent()
	if parent == null:
		return
	var count: int = 1 + int(floor(player.stats.projectile_count))
	var spread: float = 0.18 if count > 1 else 0.0
	var speed: float = weapon.projectile_speed if weapon.projectile_speed > 0.0 else 500.0
	var range_val: float = weapon.range if weapon.range > 0.0 else 400.0
	var base_damage: float = weapon.base_damage * player.stats.damage_mult
	for i in range(count):
		var t: float = (float(i) / float(count - 1) - 0.5) if count > 1 else 0.0
		var angle: float = player.attack_facing_lock + t * spread * count
		var proj: ProjectileEntity = PROJECTILE_SCENE.instantiate()
		parent.add_child(proj)
		var spawn_pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * 22.0
		proj.setup(spawn_pos, angle, speed, base_damage, 6.0)
		proj.from_player = true
		proj.pierce = weapon.pierce
		proj.knockback = weapon.knockback
		proj.crit_chance = player.stats.crit_chance + weapon.crit_bonus
		proj.crit_damage_mult = player.stats.crit_damage
		proj.burn_chance = player.stats.burn_chance
		proj.lifesteal = player.stats.lifesteal
		proj.source_player = player
		proj.max_lifetime = range_val / speed + 0.3

## The Web build's exact onMeleeLand callback body wasn't in the portion of
## Game.ts read this session — implemented here from the same "did you stay
## in the blast" principle resolve_bash_hits/detonate_bloat both already
## use verbatim: a telegraphed hit connects if the player is still within
## the attacker's own attack_range the instant the swing lands.
func resolve_melee_land(enemy: EnemyCharacter, player: PlayerCharacter) -> void:
	if player == null:
		return
	var dist: float = enemy.global_position.distance_to(player.global_position)
	if dist > enemy.def.attack_range + player.radius:
		return
	var dir: Vector2 = player.global_position - enemy.global_position
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(cos(enemy.facing), sin(enemy.facing))
	damage_enemy_to_player(player, enemy.attack_damage(), {
		"knockback_dir": dir,
		"knockback_force": 110.0,
	})

## A chasing enemy that overlaps the player deals contact damage — only
## while state is exactly CHASE (never mid-windup/attack/cooldown), on a
## flat 0.6s per-enemy cooldown.
func check_contact_damage(enemy: EnemyCharacter, player: PlayerCharacter) -> void:
	if player == null or not enemy.alive or enemy.state != EnemyCharacter.State.CHASE or enemy.contact_cooldown_timer > 0.0:
		return
	var dist: float = enemy.global_position.distance_to(player.global_position)
	if dist > enemy.radius + player.radius:
		return
	enemy.contact_cooldown_timer = 0.6
	var dir: Vector2 = player.global_position - enemy.global_position
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	damage_enemy_to_player(player, enemy.contact_damage(), {
		"knockback_dir": dir,
		"knockback_force": 110.0,
	})

## A lunging warden that overlaps the player lands its bash exactly once per lunge.
func check_bash_hit(enemy: EnemyCharacter, player: PlayerCharacter) -> void:
	if player == null or not enemy.alive or enemy.bash_timer <= 0.0 or enemy.bash_hit_landed:
		return
	var dist: float = enemy.global_position.distance_to(player.global_position)
	if dist > enemy.radius + player.radius + 6.0:
		return
	enemy.bash_hit_landed = true
	damage_enemy_to_player(player, enemy.attack_damage(), {
		"knockback_dir": Vector2(cos(enemy.facing), sin(enemy.facing)),
		"knockback_force": 300.0,
	})

## A bloat's swell finished: direct hit on anyone close, then the body is
## consumed. The lingering spore cloud it normally also leaves is deferred
## (hazards aren't ported this pass — see this file's header note).
func detonate_bloat(player: PlayerCharacter, enemy: EnemyCharacter) -> void:
	enemy.pending_burst = false
	if not enemy.alive:
		return
	enemy.burst_detonated = true
	var radius: float = enemy.def.burst_radius if enemy.def.burst_radius > 0.0 else 90.0
	var parent := enemy.get_parent()
	if parent != null:
		VfxPresets.spore_burst_vfx(parent, enemy.global_position, radius)
	if player != null:
		var dist: float = enemy.global_position.distance_to(player.global_position)
		if dist <= radius + player.radius:
			var dir: Vector2 = player.global_position - enemy.global_position
			dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
			damage_enemy_to_player(player, enemy.attack_damage(), {
				"knockback_dir": dir,
				"knockback_force": 230.0,
			})
	enemy.take_damage(enemy.hp + 1.0)

## A champion's shield just shattered (enemy.gd already flipped
## shield_broken before calling this). Spawns the 2 Blightbloat
## reinforcements the Web build grants on this beat, plus the shield-shatter
## stone chips and each new bloat's own spore-burst VFX. Camera shake/
## hit-stop/SFX are still deferred (no camera-shake system ported at all).
func on_champion_shield_break(enemy: EnemyCharacter) -> void:
	champion_shield_broken.emit(enemy)
	var blightbloat_def: EnemyDefinition = DataRegistry.get_enemy("blightbloat")
	var parent := enemy.get_parent()
	if blightbloat_def == null or parent == null:
		return
	var shatter_pos: Vector2 = enemy.global_position + Vector2(cos(enemy.facing), sin(enemy.facing)) * enemy.radius
	VfxPresets.stone_chips(parent, shatter_pos, 26)
	for side in [-1.0, 1.0]:
		var spawn_pos: Vector2 = enemy.global_position + Vector2(side * 260.0, side * 40.0)
		var add: EnemyCharacter = ENEMY_SCENE.instantiate()
		parent.add_child(add)
		add.setup(blightbloat_def, spawn_pos, enemy.difficulty_hp_mult * 0.8, enemy.difficulty_damage_mult * 0.8)
		VfxPresets.spore_burst_vfx(parent, spawn_pos, 30.0)

## Ports combat/BossSystem.ts's resolveBossPendingActions — resolves the
## "pending" flags BossCharacter.tick() sets each frame (see boss.gd) into
## real damage/VFX/summons. Called once per boss frame from EnemyAI.update()
## right after tick() itself, mirroring the source's own per-frame
## tick()-then-resolveBossPendingActions() order.
##
## Camera shake, hit-stop, and SFX are deliberately not ported here — see
## this file's own header and boss.gd's own header for why (no such system
## exists anywhere in this port yet, predating the boss).
func resolve_boss_pending_actions(boss: BossCharacter, player: PlayerCharacter) -> void:
	var parent := boss.get_parent()

	if boss.boss_phase_just_changed:
		boss.boss_phase_just_changed = false
		boss_phase_changed.emit(boss)

	if boss.pending_melee_slam:
		boss.pending_melee_slam = false
		var slam_pos: Vector2 = boss.global_position + Vector2(cos(boss.facing), sin(boss.facing)) * 60.0
		if parent != null:
			VfxPresets.ember_burst_vfx(parent, slam_pos, 90.0)
		var slam_dist: float = boss.global_position.distance_to(player.global_position)
		if slam_dist <= 130.0 + player.radius:
			var dir: Vector2 = player.global_position - boss.global_position
			dir = dir.normalized() if dir.length() > 0.01 else Vector2(cos(boss.facing), sin(boss.facing))
			damage_enemy_to_player(player, boss.attack_damage() * 1.25, {
				"knockback_dir": dir,
				"knockback_force": 280.0,
			})

	if boss.pending_shockwave:
		boss.pending_shockwave = false
		if parent != null:
			VfxPresets.ember_burst_vfx(parent, boss.global_position, 230.0 * 0.9)
		var shock_dist: float = boss.global_position.distance_to(player.global_position)
		if shock_dist <= 230.0 + player.radius:
			var dir: Vector2 = player.global_position - boss.global_position
			dir = dir.normalized() if dir.length() > 0.01 else Vector2(cos(boss.facing), sin(boss.facing))
			damage_enemy_to_player(player, boss.attack_damage() * 1.1, {
				"knockback_dir": dir,
				"knockback_force": 320.0,
			})

	if boss.pending_projectile_angles.size() > 0:
		for angle in boss.pending_projectile_angles:
			spawn_enemy_projectile(boss, angle)
		boss.pending_projectile_angles.clear()

	if boss.pending_summon_count > 0:
		var count: int = boss.pending_summon_count
		boss.pending_summon_count = 0
		var enemy_id: String = "shadowStalker" if boss.phase == BossCharacter.Phase.THREE else "ashCrawler"
		var summon_def: EnemyDefinition = DataRegistry.get_enemy(enemy_id)
		if summon_def != null and parent is RoomContainer:
			var room := parent as RoomContainer
			var factors: Dictionary = difficulty_factors(2, RunState.corruption_ratio())
			for i in range(count):
				var angle: float = (float(i) / float(count)) * TAU + randf() * 0.5
				var dist: float = 160.0 + randf() * 60.0
				var x: float = clampf(boss.global_position.x + cos(angle) * dist, RoomContainer.WALL_THICKNESS + 40.0, RoomContainer.ROOM_WIDTH - RoomContainer.WALL_THICKNESS - 40.0)
				var y: float = clampf(boss.global_position.y + sin(angle) * dist, RoomContainer.WALL_THICKNESS + 40.0, RoomContainer.ROOM_HEIGHT - RoomContainer.WALL_THICKNESS - 40.0)
				var add: EnemyCharacter = ENEMY_SCENE.instantiate()
				room.add_enemy(add)
				add.setup(summon_def, Vector2(x, y), factors["hp_mult"] * 0.8, factors["damage_mult"] * 0.8)

	if boss.pending_meteor_impacts.size() > 0:
		for impact in boss.pending_meteor_impacts:
			if parent != null:
				VfxPresets.ember_burst_vfx(parent, impact, 65.0)
			var impact_dist: float = impact.distance_to(player.global_position)
			if impact_dist <= 70.0 + player.radius:
				var dir: Vector2 = player.global_position - impact
				dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
				damage_enemy_to_player(player, boss.attack_damage() * 0.85, {
					"knockback_dir": dir,
					"knockback_force": 180.0,
				})
		boss.pending_meteor_impacts.clear()

	# Deliberately delayed past the killing blow itself — on_enemy_death
	# (called generically the instant hp hits 0, same as any other enemy)
	# already fires its own single-color death burst well before this;
	# this is BossSystem.ts's own separate, bigger two-tone fanfare, gated
	# on the ~2.2s shrink/drop animation actually finishing, not just hp
	# reaching 0 — see boss_defeat_resolved's own field comment in boss.gd.
	if not boss.alive and boss.death_animation_done and not boss.boss_defeat_resolved:
		boss.boss_defeat_resolved = true
		if parent != null:
			VfxPresets.death_burst(parent, boss.global_position, Palette.EMBER4)
			VfxPresets.death_burst(parent, boss.global_position, Palette.EMBER6)
		boss_defeated.emit(boss)

# ---------------------------------------------------------------- Core damage pipeline

func damage_player_to_enemy(player: PlayerCharacter, enemy: EnemyCharacter, base_damage: float, crit: bool, opts: Dictionary = {}) -> void:
	if player == null or enemy == null or not enemy.alive:
		return
	var dmg: float = base_damage * (player.stats.crit_damage if crit else 1.0)

	# Warden shield: hits arriving inside the frontal arc are mostly turned
	# aside — no knockback, no stagger, no burn.
	var blocked := false
	if enemy.shield_up():
		var source_pos: Vector2 = opts.get("source_pos", player.global_position)
		var to_source: float = (source_pos - enemy.global_position).angle()
		var shield_arc: float = enemy.def.shield_arc if enemy.def.shield_arc > 0.0 else 1.1
		blocked = absf(_angle_diff(enemy.facing, to_source)) <= shield_arc
	if blocked:
		dmg *= SHIELD_DAMAGE_FACTOR
	dmg = maxf(1.0, dmg)

	enemy.take_damage(dmg)
	hit_landed.emit(player, enemy, dmg, crit)

	# Ports CombatSystem.ts's damagePlayerToEnemy: shield-sparks on a
	# blocked hit, a normal hit-impact burst otherwise. Damage numbers/
	# camera shake/hit-stop/SFX stay deferred (see this file's header).
	var parent := enemy.get_parent()
	if parent != null:
		if blocked:
			var spark_pos: Vector2 = enemy.global_position + Vector2(cos(enemy.facing), sin(enemy.facing)) * enemy.radius * 0.9
			VfxPresets.shield_sparks(parent, spark_pos, enemy.facing)
		else:
			VfxPresets.hit_impact(parent, enemy.global_position, enemy.def.accent_color, crit)

	var knockback_force: float = opts.get("knockback_force", 0.0)
	if knockback_force != 0.0 and not blocked:
		enemy.apply_knockback(opts.get("knockback_dir", Vector2.ZERO), knockback_force)

	if crit and not blocked and enemy.alive and enemy.state == EnemyCharacter.State.WINDUP and not enemy.def.is_elite:
		enemy.set_state(EnemyCharacter.State.STAGGER)
	if crit:
		crit_landed.emit(player, enemy)

	if player.stats.lifesteal > 0.0:
		player.heal(dmg * player.stats.lifesteal)

	if not blocked and randf() < player.stats.burn_chance:
		var burn_def: StatusEffectDefinition = DataRegistry.get_status_effect("burn")
		if burn_def != null:
			StatusEffectRuntime.apply(enemy, burn_def, player, maxf(2.0, dmg * 0.16))

	if not enemy.alive:
		on_enemy_death(player, enemy)

## Centralizes the fallout of an enemy dying, however it died (a direct
## hit here, or a status-effect tick discovered in apply_status_tick_damage)
## — every death must go through this exactly once.
func on_enemy_death(_player: PlayerCharacter, enemy: EnemyCharacter) -> void:
	if enemy.death_handled:
		return
	enemy.death_handled = true
	var parent := enemy.get_parent()
	if parent != null:
		VfxPresets.death_burst(parent, enemy.global_position, enemy.def.accent_color)
	enemy_died.emit(enemy)

func damage_enemy_to_player(player: PlayerCharacter, base_damage: float, opts: Dictionary = {}) -> bool:
	if player == null:
		return false
	# Ports CombatSystem.ts's damageEnemyToPlayer: captures is_dodging BEFORE
	# take_damage() resolves the hit, exactly like the source's own
	# `wasDodging` local — take_damage()'s "blocked" result alone can't
	# distinguish a dodge from any other invulnerability source (shield,
	# post-hit i-frames), so this is the one place that still can.
	var was_dodging: bool = player.is_dodging
	var result: Dictionary = player.take_damage(base_damage)
	if result["blocked"]:
		if was_dodging:
			var dodge_parent := player.get_parent()
			if dodge_parent != null:
				VfxPresets.perfect_dodge_burst(dodge_parent, player.global_position)
		return false
	var knockback_force: float = opts.get("knockback_force", 0.0)
	if knockback_force != 0.0:
		player.velocity += opts.get("knockback_dir", Vector2.ZERO) * knockback_force
	var hit_parent := player.get_parent()
	if hit_parent != null:
		VfxPresets.hit_impact(hit_parent, player.global_position, Palette.BLOOD_BRIGHT, false)
	hit_landed.emit(null, player, result["taken"], false)
	if not player.alive:
		player_died.emit()
	return true

## Called by StatusEffectRuntime on every DoT tick — `target` is a
## PlayerCharacter or EnemyCharacter, addressed generically since this is
## the one place both directions share.
func apply_status_tick_damage(target: Node, amount: float) -> void:
	if amount <= 0.0 or not target.has_method("take_damage"):
		return
	target.call("take_damage", amount)
	if target is EnemyCharacter and not (target as EnemyCharacter).alive:
		on_enemy_death(null, target as EnemyCharacter)

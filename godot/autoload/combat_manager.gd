extends Node
## Autoload: CombatManager
##
## Ports combat/CombatSystem.ts — the single place every damage source
## (melee, projectiles, contact damage, warden bashes, bloat detonation,
## status-effect ticks) routes through, so every hit gets identical crit
## rolls, knockback, and warden-shield-block handling. Read directly from
## CombatSystem.ts/EnemyAI.ts/Enemy.ts this session — not approximated.
##
## Synergy effects (ashFire/emberCritical/lightHealing/shadowDodge, plus
## wrath's damage curve on PlayerCharacter itself), the 3 abilities' real
## gameplay effects (Ember Burst/Stormstep/Warding Sigil), damage numbers,
## camera shake, and hit-stop are all real now — see the "Ability" section
## below and PlayerCharacter's own synergy_damage_multiplier()/
## trigger_perfect_dodge()/add_camera_shake(). Synergy FORMATION
## (player.upgrades, MetaProgression, the banner/SFX on completion) was
## already wired before this; this closed the remaining gap, confirmed via
## a grep-based audit that it was still genuinely open, not stale.
##
## Hazards (spore clouds — Bloat's detonation, the Sunken Warden's phase-2
## bash landings) are real now too: see world/hazard_node.gd, spawned from
## detonate_bloat()/consume_pending_cloud() below.
##
## Still deferred, on purpose (see GODOT_MIGRATION.md and each function's
## own comment for exactly what and why):
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

# ---------------------------------------------------------------- Hit-stop
## Ports core/HitStop.ts's HitStopController through Engine.time_scale —
## the native Godot way to get a GLOBAL slowdown (every _process/
## _physics_process delta, animations, timers) without threading a custom
## dt through every system the way the TS source's own loop() does. The
## real-time deadline is tracked via Time.get_ticks_msec() rather than
## accumulating _process()'s own delta, since that delta is ITSELF scaled
## by time_scale once a hit-stop is active — counting down with it would
## make the slowdown outlast its own requested duration.
const NORMAL_SHAKE := 4.0
const CRIT_SHAKE_BONUS := 3.0
const ELITE_SHAKE := 9.0

var _hit_stop_strength: float = 1.0
var _hit_stop_end_msec: int = 0

## `strength` is a fraction of normal speed (0.06 = simulation crawls at
## 6% speed). A longer OR stronger request always wins over one already in
## flight; a shorter, weaker one is dropped rather than cutting the active
## one short — exact port of the source's own trigger() gate.
func trigger_hit_stop(duration_seconds: float, strength: float) -> void:
	var now: int = Time.get_ticks_msec()
	var remaining_seconds: float = maxf(0.0, float(_hit_stop_end_msec - now) / 1000.0)
	var is_longer: bool = duration_seconds > remaining_seconds
	var is_stronger: bool = strength < _hit_stop_strength
	if not is_longer and not is_stronger:
		return
	_hit_stop_end_msec = now + int(maxf(duration_seconds, remaining_seconds) * 1000.0)
	_hit_stop_strength = minf(strength, _hit_stop_strength)
	Engine.time_scale = _hit_stop_strength

func _process(_delta: float) -> void:
	if _hit_stop_end_msec > 0 and Time.get_ticks_msec() >= _hit_stop_end_msec:
		_hit_stop_end_msec = 0
		_hit_stop_strength = 1.0
		Engine.time_scale = 1.0

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
		var base_damage: float = weapon.base_damage * player.stats.damage_mult * player.synergy_damage_multiplier()
		var dir: Vector2 = offset.normalized() if dist > 0.01 else Vector2(cos(angle_to_enemy), sin(angle_to_enemy))
		damage_player_to_enemy(player, enemy, base_damage, crit, {
			"knockback_dir": dir,
			"knockback_force": weapon.knockback,
		})
	AudioEngine.play_sfx("attackSwingHeavy" if weapon.id == "voidScythe" else "attackSwing")

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
	AudioEngine.play_sfx("attackRanged", 90.0)

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
	var base_damage: float = weapon.base_damage * player.stats.damage_mult * player.synergy_damage_multiplier()
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
	AudioEngine.play_sfx("attackRanged")

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
	var landed: bool = damage_enemy_to_player(player, enemy.attack_damage(), {
		"knockback_dir": Vector2(cos(enemy.facing), sin(enemy.facing)),
		"knockback_force": 300.0,
	})
	if landed:
		player.add_camera_shake(9.0, 0.25)
		trigger_hit_stop(0.04, 0.06)

## A bloat's swell finished: direct hit on anyone close, then the body is
## consumed and the lingering spore cloud (HazardNode — see that file's own
## header) takes over for the rest of its duration.
func detonate_bloat(player: PlayerCharacter, enemy: EnemyCharacter) -> void:
	enemy.pending_burst = false
	if not enemy.alive:
		return
	enemy.burst_detonated = true
	var radius: float = enemy.def.burst_radius if enemy.def.burst_radius > 0.0 else 90.0
	var parent := enemy.get_parent()
	if parent != null:
		VfxPresets.spore_burst_vfx(parent, enemy.global_position, radius)
	AudioEngine.play_sfx("sporeBurst", 40.0)
	if player != null:
		player.add_camera_shake(6.0, 0.2)
		var dist: float = enemy.global_position.distance_to(player.global_position)
		if dist <= radius + player.radius:
			var dir: Vector2 = player.global_position - enemy.global_position
			dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
			damage_enemy_to_player(player, enemy.attack_damage(), {
				"knockback_dir": dir,
				"knockback_force": 230.0,
			})
	if parent != null:
		var cloud_radius: float = enemy.def.cloud_radius if enemy.def.cloud_radius > 0.0 else 80.0
		var cloud_duration: float = enemy.def.cloud_duration if enemy.def.cloud_duration > 0.0 else 5.0
		HazardNode.spawn(parent, enemy.global_position, cloud_radius, cloud_duration, 5.0 * enemy.difficulty_damage_mult)
	enemy.take_damage(enemy.hp + 1.0)

## Ports CombatSystem.ts's consumePendingClouds, called per-enemy (see
## enemy.gd's own _physics_process) rather than once per frame over
## room.enemies — same per-node dispatch every other enemy-side check in
## this file already uses. Only ever non-zero on a phase-2 Sunken Warden
## right after a bash lands (ai/EnemyAI.ts's runWarden sets
## pending_cloud_radius = 72 there) — every other enemy's own call here is
## a harmless no-op via the early return, matching the source's own
## `if (e.pendingCloudRadius <= 0) continue`.
func consume_pending_cloud(enemy: EnemyCharacter) -> void:
	if enemy.pending_cloud_radius <= 0.0:
		return
	var parent := enemy.get_parent()
	if parent != null:
		HazardNode.spawn(parent, enemy.global_position, enemy.pending_cloud_radius, 3.5, 5.0 * enemy.difficulty_damage_mult)
		VfxPresets.spore_burst_vfx(parent, enemy.global_position, enemy.pending_cloud_radius * 0.6)
	AudioEngine.play_sfx("sporeHiss", 80.0)
	enemy.pending_cloud_radius = 0.0

## A champion's shield just shattered (enemy.gd already flipped
## shield_broken before calling this). Spawns the 2 Blightbloat
## reinforcements the Web build grants on this beat, plus the shield-shatter
## stone chips and each new bloat's own spore-burst VFX, camera shake, and
## hit-stop — Game.ts's own onChampionShieldBreak literal values
## (camera.addShake(14, 0.5), hitStop.trigger(0.08, 0.05)), found still
## unwired (the header comment here was stale — camera shake/hit-stop
## exist project-wide since the "everything necessary" pass, this one
## call site just never got updated) while auditing for what else was
## left to migrate.
func on_champion_shield_break(enemy: EnemyCharacter, player: PlayerCharacter) -> void:
	AudioEngine.play_sfx("shieldShatter")
	champion_shield_broken.emit(enemy)
	if player != null:
		player.add_camera_shake(14.0, 0.5)
	trigger_hit_stop(0.08, 0.05)
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
## Camera shake and hit-stop are wired now (player.add_camera_shake()/
## this file's own trigger_hit_stop(), see the "everything necessary" pass
## at the README's end) — every magnitude/duration below is the source's
## own literal value, not a guess. SFX (step 10, audio_engine.gd) matches
## every pending-flag branch the source's own resolveBossPendingActions()
## plays one for.
func resolve_boss_pending_actions(boss: BossCharacter, player: PlayerCharacter) -> void:
	var parent := boss.get_parent()

	if boss.intro_just_started:
		boss.intro_just_started = false
		AudioEngine.play_sfx("bossRoar")

	if boss.boss_phase_just_changed:
		boss.boss_phase_just_changed = false
		AudioEngine.play_sfx("bossPhase")
		player.add_camera_shake(16.0, 0.6)
		trigger_hit_stop(0.1, 0.04)
		if parent != null:
			VfxPresets.ember_burst_vfx(parent, boss.global_position, 180.0)
		boss_phase_changed.emit(boss)

	if boss.pending_melee_slam:
		boss.pending_melee_slam = false
		var slam_pos: Vector2 = boss.global_position + Vector2(cos(boss.facing), sin(boss.facing)) * 60.0
		if parent != null:
			VfxPresets.ember_burst_vfx(parent, slam_pos, 90.0)
		AudioEngine.play_sfx("bossHit")
		player.add_camera_shake(13.0, 0.3)
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
		AudioEngine.play_sfx("bossHit")
		player.add_camera_shake(15.0, 0.4)
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
		AudioEngine.play_sfx("bossRoar")

	if boss.pending_meteor_impacts.size() > 0:
		for impact in boss.pending_meteor_impacts:
			if parent != null:
				VfxPresets.ember_burst_vfx(parent, impact, 65.0)
			AudioEngine.play_sfx("impactCrit", 0.0)
			var impact_dist: float = impact.distance_to(player.global_position)
			if impact_dist <= 70.0 + player.radius:
				var dir: Vector2 = player.global_position - impact
				dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
				damage_enemy_to_player(player, boss.attack_damage() * 0.85, {
					"knockback_dir": dir,
					"knockback_force": 180.0,
				})
		boss.pending_meteor_impacts.clear()
		player.add_camera_shake(6.0, 0.2)

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
		AudioEngine.play_sfx("bossDeath")
		player.add_camera_shake(20.0, 0.8)
		trigger_hit_stop(0.14, 0.03)
		boss_defeated.emit(boss)

# ---------------------------------------------------------------- Core damage pipeline

func damage_player_to_enemy(player: PlayerCharacter, enemy: EnemyCharacter, base_damage: float, crit: bool, opts: Dictionary = {}) -> void:
	if player == null or enemy == null or not enemy.alive:
		return
	var dmg: float = base_damage * (player.stats.crit_damage if crit else 1.0)
	if player.has_synergy("ashFire") and enemy.has_burn():
		dmg *= 1.4

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
	RunState.record_damage_dealt(dmg)
	hit_landed.emit(player, enemy, dmg, crit)

	# Ports CombatSystem.ts's damagePlayerToEnemy: shield-sparks on a
	# blocked hit, a normal hit-impact burst (+ damage number, camera
	# shake, hit-stop on a crit) otherwise. `silent` (the warding sigil's
	# own continuous tick) skips all of this — same gate as the source's
	# own `if (!opts.silent)`.
	var parent := enemy.get_parent()
	if not opts.get("silent", false) and parent != null:
		if blocked:
			var spark_pos: Vector2 = enemy.global_position + Vector2(cos(enemy.facing), sin(enemy.facing)) * enemy.radius * 0.9
			VfxPresets.shield_sparks(parent, spark_pos, enemy.facing)
			AudioEngine.play_sfx("shieldClang", 50.0)
			FloatingText.spawn(parent, enemy.global_position + Vector2(0.0, -enemy.radius), str(roundi(dmg)), Color("#8f8a9e"), 12)
		else:
			VfxPresets.hit_impact(parent, enemy.global_position, enemy.def.accent_color, crit)
			AudioEngine.play_sfx("impactCrit" if crit else "impactLight", 20.0)
			FloatingText.spawn(parent, enemy.global_position + Vector2(0.0, -enemy.radius), str(roundi(dmg)), Color(Palette.EMBER6) if crit else Color("#f4ecdd"), 20 if crit else 15)
			if crit:
				player.add_camera_shake(NORMAL_SHAKE + CRIT_SHAKE_BONUS, 0.15)
				trigger_hit_stop(0.045, 0.08)
			if enemy.def.is_elite:
				player.add_camera_shake(2.0, 0.08)

	if crit and not blocked and player.has_synergy("emberCritical") and randf() < 0.35:
		if parent != null:
			VfxPresets.ember_burst_vfx(parent, enemy.global_position, 70.0)
		AudioEngine.play_sfx("impactCrit", 0.0)

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
func on_enemy_death(player: PlayerCharacter, enemy: EnemyCharacter) -> void:
	if enemy.death_handled:
		return
	enemy.death_handled = true
	RunState.record_kill(enemy)
	var parent := enemy.get_parent()
	if parent != null:
		VfxPresets.death_burst(parent, enemy.global_position, enemy.def.accent_color)
	AudioEngine.play_sfx("eliteDeath" if enemy.def.is_elite else "enemyDeath")
	if enemy.def.is_elite and player != null:
		player.add_camera_shake(ELITE_SHAKE, 0.35)
		trigger_hit_stop(0.08, 0.04)
	# Ports CombatSystem.ts's onEnemyDeath: 40% chance to heal 6% max HP when
	# a burning-or-elite enemy dies, gated on the lightHealing synergy.
	if player != null and player.has_synergy("lightHealing") and (enemy.has_burn() or enemy.def.is_elite) and randf() < 0.4:
		var heal_amount: float = player.stats.max_hp * 0.06
		player.heal(heal_amount)
		if parent != null:
			FloatingText.spawn(parent, player.global_position + Vector2(0.0, -player.radius - 6.0), "+%d" % roundi(heal_amount), Color(Palette.EMBER4))
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
			player.trigger_perfect_dodge()
			dodge_perfected.emit(player)
			var dodge_parent := player.get_parent()
			if dodge_parent != null:
				VfxPresets.perfect_dodge_burst(dodge_parent, player.global_position)
			AudioEngine.play_sfx("perfectDodge")
		elif result["shield_consumed"]:
			AudioEngine.play_sfx("shieldBreak")
		return false
	RunState.record_damage_taken(result["taken"])
	var knockback_force: float = opts.get("knockback_force", 0.0)
	if knockback_force != 0.0:
		player.velocity += opts.get("knockback_dir", Vector2.ZERO) * knockback_force
	var hit_parent := player.get_parent()
	# A cloud tick is pressure, not a blow: quieter, greener, no big shake —
	# same distinction the source's own `if (opts.hazard)` branch draws.
	if opts.get("hazard", false):
		if hit_parent != null:
			FloatingText.spawn(hit_parent, player.global_position + Vector2(0.0, -player.radius), str(roundi(result["taken"])), Color(Palette.FUNGUS_BRIGHT), 13)
			VfxPresets.spore_mote(hit_parent, player.global_position + Vector2(0.0, -6.0))
		AudioEngine.play_sfx("sporeHiss", 200.0)
		player.add_camera_shake(2.5, 0.12)
	else:
		if hit_parent != null:
			FloatingText.spawn(hit_parent, player.global_position + Vector2(0.0, -player.radius), str(roundi(result["taken"])), Color(Palette.BLOOD_BRIGHT), 16)
			VfxPresets.hit_impact(hit_parent, player.global_position, Palette.BLOOD_BRIGHT, false)
		AudioEngine.play_sfx("playerHurt")
		player.add_camera_shake(7.0, 0.2)
	hit_landed.emit(null, player, result["taken"], false)
	if not player.alive:
		AudioEngine.play_sfx("playerDeath")
		player_died.emit()
	return true

## Called by StatusEffectRuntime on every DoT tick — `target` is a
## PlayerCharacter or EnemyCharacter, addressed generically since this is
## the one place both directions share. `source` is whoever applied the
## effect (StatusEffectInstance.source) — threaded through to
## on_enemy_death so a burn-DoT kill still counts for lightHealing/elite-
## death feedback, exactly like every TS call site passing a real player
## (this port's status-effect system is more general than the source's
## single hardcoded Enemy.burn field, but a kill is still always credited
## to whoever's damage caused it).
func apply_status_tick_damage(target: Node, amount: float, source: Node = null) -> void:
	if amount <= 0.0 or not target.has_method("take_damage"):
		return
	target.call("take_damage", amount)
	if target is EnemyCharacter and not (target as EnemyCharacter).alive:
		on_enemy_death(source as PlayerCharacter, target as EnemyCharacter)

# ---------------------------------------------------------------- Ability
## Ports Game.ts's private performAbility/performStormstep +
## CombatSystem.ts's emberBurstAbility/wardingSigilTick — every ability's
## actual gameplay effect. Called from PlayerCharacter.start_ability()
## (emberBurst/stormstep) or per-frame from its own _physics_process while
## warding_sigil_active is set, mirroring how start_attack() dispatches
## into this same autoload for weapon damage rather than resolving it
## itself. Every enemy lookup below self-scans get_tree().get_nodes_in_
## group("enemies") rather than taking a pre-filtered targets array —
## matches perform_melee_attack's own established convention (see its
## header), a deliberate simplification of allTargetableEnemies() that's
## already proven correct there.

func ember_burst_ability(player: PlayerCharacter) -> void:
	var radius: float = 140.0 * player.stats.area_damage_mult
	var damage: float = 55.0 * player.stats.ability_damage_mult * player.stats.ember_power * player.synergy_damage_multiplier()
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyCharacter
		if enemy == null or not enemy.alive:
			continue
		var offset: Vector2 = enemy.global_position - player.global_position
		var dist: float = offset.length()
		if dist > radius + enemy.radius:
			continue
		var falloff: float = 1.0 - minf(1.0, dist / (radius + enemy.radius)) * 0.35
		var dir: Vector2 = offset / maxf(0.01, dist)
		damage_player_to_enemy(player, enemy, damage * falloff, false, {
			"knockback_dir": dir,
			"knockback_force": 320.0,
		})
	var parent := player.get_parent()
	if parent != null:
		VfxPresets.ember_burst_vfx(parent, player.global_position, radius)
	player.add_camera_shake(11.0, 0.3)
	trigger_hit_stop(0.06, 0.05)
	AudioEngine.play_sfx("abilityEmberBurst")

## A short dash along the player's current facing, damaging (once each,
## via hit_enemies — TS dedupes by enemy.id, this port's enemies have no
## such numeric id, so the enemy node itself is the dedup key instead)
## everything within 26px of any of 5 evenly-sampled points along the
## dash line. The move itself is a direct position set, not
## move_and_slide() — Stormstep is meant to cut through whatever's in its
## path, not be stopped by it, matching the source's own player.x +=
## dx*dist with no collision resolution.
func perform_stormstep(player: PlayerCharacter) -> void:
	var dist: float = 230.0
	var dir := Vector2(cos(player.facing), sin(player.facing))
	var hit_enemies: Array[EnemyCharacter] = []
	var steps := 5
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var p: Vector2 = player.global_position + dir * dist * t
		for node in player.get_tree().get_nodes_in_group("enemies"):
			var enemy := node as EnemyCharacter
			if enemy == null or not enemy.alive or hit_enemies.has(enemy):
				continue
			if p.distance_to(enemy.global_position) < enemy.radius + 26.0:
				hit_enemies.append(enemy)
				var damage: float = 30.0 * player.stats.ability_damage_mult * player.stats.ember_power * player.synergy_damage_multiplier()
				damage_player_to_enemy(player, enemy, damage, false, {
					"knockback_dir": dir,
					"knockback_force": 200.0,
				})
	player.global_position += dir * dist
	player.invuln_timer = maxf(player.invuln_timer, 0.45)
	AudioEngine.play_sfx("abilityStormstep")
	player.add_camera_shake(6.0, 0.15)

## Called every physics frame from PlayerCharacter._physics_process while
## warding_sigil_active is set (5s duration, ticks continuously — unlike
## emberBurst/stormstep's one-shot effects). `silent` on the damage call
## suppresses the per-hit VFX/SFX/damage-number/camera-shake a normal hit
## gets — a sigil landing dozens of ticks a second would otherwise spam
## all of it. Deliberately NOT multiplied by synergy_damage_multiplier()
## — matches the source's own dps formula exactly, which omits it here
## while emberBurst/stormstep both include it.
func warding_sigil_tick(player: PlayerCharacter, dt: float) -> void:
	if player.warding_sigil_active.is_empty():
		return
	var sigil_pos: Vector2 = player.warding_sigil_active["pos"]
	var radius: float = 90.0 * player.stats.area_damage_mult
	var dps: float = 14.0 * player.stats.ability_damage_mult * player.stats.ember_power
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyCharacter
		if enemy == null or not enemy.alive:
			continue
		var dist: float = sigil_pos.distance_to(enemy.global_position)
		if dist > radius + enemy.radius:
			continue
		damage_player_to_enemy(player, enemy, dps * dt, false, {
			"silent": true,
			"source_pos": sigil_pos,
		})
	player.heal(4.0 * dt)

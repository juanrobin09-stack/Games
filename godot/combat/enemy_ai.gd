class_name EnemyAI
extends RefCounted
## Ports ai/EnemyAI.ts's 6 behavior-dispatch functions + resolveAttackTrigger
## verbatim — every timing constant below was read directly from that file
## this session, not approximated. Called once per physics tick per enemy
## from EnemyCharacter._physics_process via `EnemyAI.update(enemy, player, dt)`.
##
## Not ported this pass, on purpose: applyEnemySeparation (the soft
## push-apart between overlapping enemies — a polish/crowd-control pass,
## not core to whether combat works, and it wants a spatial grid this
## project doesn't have yet either) and Hazards/spore clouds (Bloat's
## detonation and the Warden champion's phase-2 bash both still deal their
## direct-hit damage below; the lingering cloud they'd normally also leave
## is a clearly separate, self-contained follow-up, not silently dropped).
## `bounds`-clamped teleport-on-vanish (reappearAt's wall-inset) is
## simplified to a plain teleport — there are no walls to inset from until
## Room/LevelGenerator lands in build-order step 6.

## BossCharacter is special-cased here rather than in the match below — its
## own tick() needs to keep running even after `alive` flips false (to
## drive its dying-state death animation timer; see boss.gd's own
## _physics_process override for why the shared alive-guard beneath this
## would otherwise cut it off mid-animation), so it's routed to its own FSM
## entry point before that guard runs at all, not folded into
## EnemyDefinition.Behavior (the boss's own ELITE-behavior .tres value is
## never actually read once this branch exists — it was only ever a
## placeholder so the boss wouldn't hit an unhandled-behavior no-op before
## this port had a real boss FSM). CombatManager.resolve_boss_pending_
## actions() runs immediately after tick(), mirroring the source's own
## per-frame tick()-then-resolveBossPendingActions() order.
static func update(enemy: EnemyCharacter, player: PlayerCharacter, dt: float) -> void:
	if enemy is BossCharacter:
		if player != null:
			var boss := enemy as BossCharacter
			boss.tick(dt, player)
			CombatManager.resolve_boss_pending_actions(boss, player)
		return
	if not enemy.alive or player == null:
		return
	var def := enemy.def
	var previous_state := enemy.state
	match def.behavior:
		EnemyDefinition.Behavior.CHASER, EnemyDefinition.Behavior.TANK, EnemyDefinition.Behavior.HEAVY:
			_run_melee_like(enemy, player, dt, def.move_speed)
		EnemyDefinition.Behavior.RANGED:
			var preferred: float = 220.0 if def.id == "cinderWraith" else 240.0
			var can_vanish: bool = def.id == "cinderWraith"
			_run_ranged_like(enemy, player, dt, def.move_speed, preferred, can_vanish)
		EnemyDefinition.Behavior.STALKER:
			_run_stalker(enemy, player, dt)
		EnemyDefinition.Behavior.ELITE:
			_run_elite(enemy, player, dt)
		EnemyDefinition.Behavior.BLOAT:
			_run_bloat(enemy, player, dt)
		EnemyDefinition.Behavior.WARDEN:
			_run_warden(enemy, player, dt)

	if enemy.state == EnemyCharacter.State.ATTACK and previous_state != EnemyCharacter.State.ATTACK:
		_resolve_attack_trigger(enemy, player)
	if def.behavior == EnemyDefinition.Behavior.BLOAT and enemy.state == EnemyCharacter.State.WINDUP and previous_state != EnemyCharacter.State.WINDUP:
		AudioEngine.play_sfx("bloatSwell", 120.0)

# ---------------------------------------------------------------- helpers

static func _dist_to(enemy: EnemyCharacter, player: PlayerCharacter) -> Dictionary:
	var dx: float = player.global_position.x - enemy.global_position.x
	var dy: float = player.global_position.y - enemy.global_position.y
	return {"dist": Vector2(dx, dy).length(), "dx": dx, "dy": dy}

static func _angle_diff(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)

## Rotates enemy.facing toward `target` by at most `max_delta`; returns the
## signed angle still left to turn (0 once facing the target).
static func _turn_toward(enemy: EnemyCharacter, target: float, max_delta: float) -> float:
	var diff: float = _angle_diff(enemy.facing, target)
	var step: float = clampf(diff, -max_delta, max_delta)
	enemy.facing += step
	return diff - step

static func _seek_player(enemy: EnemyCharacter, dx: float, dy: float, dist: float, speed: float) -> void:
	if dist < 0.001:
		enemy.ai_velocity = Vector2.ZERO
		return
	enemy.ai_velocity = Vector2(dx / dist, dy / dist) * speed
	enemy.facing = atan2(dy, dx)

static func _maintain_range(enemy: EnemyCharacter, dx: float, dy: float, dist: float, speed: float, preferred: float) -> void:
	if dist < 0.001:
		return
	var nx: float = dx / dist
	var ny: float = dy / dist
	enemy.facing = atan2(dy, dx)
	if dist < preferred - 30.0:
		enemy.ai_velocity = Vector2(-nx, -ny) * speed
	elif dist > preferred + 30.0:
		enemy.ai_velocity = Vector2(nx, ny) * speed
	else:
		enemy.ai_velocity = Vector2(-ny, nx) * speed * 0.4

static func _begin_windup_if_ready(enemy: EnemyCharacter, dist: float, attack_range: float) -> void:
	if enemy.attack_cooldown_timer <= 0.0 and dist <= attack_range:
		enemy.set_state(EnemyCharacter.State.WINDUP)
		enemy.ai_velocity = Vector2.ZERO

## Teleporting enemies (stalkers, wraiths) reappear on the floor near the
## player — no wall-inset clamp yet, see the file header note.
static func _reappear_at(enemy: EnemyCharacter, player: PlayerCharacter, angle: float, target_dist: float) -> void:
	enemy.global_position = player.global_position + Vector2(cos(angle), sin(angle)) * target_dist

# ---------------------------------------------------------------- behaviors

static func _run_melee_like(enemy: EnemyCharacter, player: PlayerCharacter, dt: float, speed: float) -> void:
	var d := _dist_to(enemy, player)
	var def := enemy.def
	match enemy.state:
		EnemyCharacter.State.SPAWNING:
			if enemy.state_timer > 0.2:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.CHASE:
			_seek_player(enemy, d.dx, d.dy, d.dist, speed)
			_begin_windup_if_ready(enemy, d.dist, def.attack_range)
		EnemyCharacter.State.WINDUP:
			enemy.facing = atan2(d.dy, d.dx)
			if enemy.state_timer >= def.telegraph_time:
				enemy.set_state(EnemyCharacter.State.ATTACK)
		EnemyCharacter.State.ATTACK:
			if enemy.state_timer >= 0.16:
				enemy.attack_cooldown_timer = def.attack_cooldown
				enemy.set_state(EnemyCharacter.State.COOLDOWN)
		EnemyCharacter.State.COOLDOWN:
			if enemy.state_timer >= 0.12:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.STAGGER:
			if enemy.state_timer >= 0.4:
				enemy.set_state(EnemyCharacter.State.CHASE)

static func _run_ranged_like(enemy: EnemyCharacter, player: PlayerCharacter, dt: float, speed: float, preferred_range: float, can_vanish: bool) -> void:
	var d := _dist_to(enemy, player)
	var def := enemy.def
	match enemy.state:
		EnemyCharacter.State.SPAWNING:
			if enemy.state_timer > 0.25:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.CHASE:
			_maintain_range(enemy, d.dx, d.dy, d.dist, speed, preferred_range)
			_begin_windup_if_ready(enemy, d.dist, def.attack_range)
		EnemyCharacter.State.WINDUP:
			enemy.ai_velocity *= 0.85
			enemy.facing = atan2(d.dy, d.dx)
			if enemy.state_timer >= def.telegraph_time:
				enemy.set_state(EnemyCharacter.State.ATTACK)
		EnemyCharacter.State.ATTACK:
			if enemy.state_timer >= 0.1:
				enemy.attack_cooldown_timer = def.attack_cooldown
				enemy.set_state(EnemyCharacter.State.COOLDOWN)
		EnemyCharacter.State.COOLDOWN:
			if enemy.state_timer >= 0.2:
				if can_vanish and randf() < 0.55:
					enemy.set_state(EnemyCharacter.State.VANISHED)
				else:
					enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.VANISHED:
			enemy.ai_velocity = Vector2.ZERO
			if enemy.state_timer >= 0.5:
				var angle: float = randf() * TAU
				var target_dist: float = preferred_range * (0.7 + randf() * 0.5)
				_reappear_at(enemy, player, angle, target_dist)
				enemy.set_state(EnemyCharacter.State.REAPPEARING)
		EnemyCharacter.State.REAPPEARING:
			if enemy.state_timer >= 0.35:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.STAGGER:
			if enemy.state_timer >= 0.4:
				enemy.set_state(EnemyCharacter.State.CHASE)

static func _run_stalker(enemy: EnemyCharacter, player: PlayerCharacter, dt: float) -> void:
	var d := _dist_to(enemy, player)
	var def := enemy.def
	var speed: float = def.move_speed
	match enemy.state:
		EnemyCharacter.State.SPAWNING:
			if enemy.state_timer > 0.2:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.CHASE:
			_seek_player(enemy, d.dx, d.dy, d.dist, speed)
			_begin_windup_if_ready(enemy, d.dist, def.attack_range)
		EnemyCharacter.State.WINDUP:
			enemy.facing = atan2(d.dy, d.dx)
			if enemy.state_timer >= def.telegraph_time:
				enemy.set_state(EnemyCharacter.State.ATTACK)
		EnemyCharacter.State.ATTACK:
			if enemy.state_timer >= 0.14:
				enemy.attack_cooldown_timer = def.attack_cooldown
				enemy.set_state(EnemyCharacter.State.COOLDOWN)
		EnemyCharacter.State.COOLDOWN:
			if enemy.state_timer >= 0.15:
				enemy.set_state(EnemyCharacter.State.VANISHED if randf() < 0.6 else EnemyCharacter.State.CHASE)
		EnemyCharacter.State.VANISHED:
			enemy.ai_velocity = Vector2.ZERO
			var vanish_duration: float = def.vanish_duration if def.vanish_duration > 0.0 else 1.0
			if enemy.state_timer >= vanish_duration:
				var angle: float = randf() * TAU
				var target_dist: float = 70.0 + randf() * 60.0
				_reappear_at(enemy, player, angle, target_dist)
				enemy.set_state(EnemyCharacter.State.REAPPEARING)
		EnemyCharacter.State.REAPPEARING:
			if enemy.state_timer >= 0.3:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.STAGGER:
			if enemy.state_timer >= 0.4:
				enemy.set_state(EnemyCharacter.State.CHASE)

static func _run_elite(enemy: EnemyCharacter, player: PlayerCharacter, dt: float) -> void:
	var d := _dist_to(enemy, player)
	var def := enemy.def
	var speed: float = def.move_speed
	match enemy.state:
		EnemyCharacter.State.SPAWNING:
			if enemy.state_timer > 0.4:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.CHASE:
			_maintain_range(enemy, d.dx, d.dy, d.dist, speed, 150.0)
			if enemy.attack_cooldown_timer <= 0.0 and d.dist <= def.attack_range:
				enemy.set_state(EnemyCharacter.State.WINDUP)
				enemy.ai_velocity = Vector2.ZERO
		EnemyCharacter.State.WINDUP:
			enemy.facing = atan2(d.dy, d.dx)
			if enemy.state_timer >= def.telegraph_time:
				enemy.set_state(EnemyCharacter.State.ATTACK)
		EnemyCharacter.State.ATTACK:
			if enemy.state_timer >= 0.18:
				enemy.attack_cooldown_timer = def.attack_cooldown * 0.85
				enemy.set_state(EnemyCharacter.State.COOLDOWN)
		EnemyCharacter.State.COOLDOWN:
			if enemy.state_timer >= 0.25:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.STAGGER:
			if enemy.state_timer >= 0.35:
				enemy.set_state(EnemyCharacter.State.CHASE)

## Blightbloat: walks at you, plants itself within reach, swells for
## telegraph_time, then bursts (CombatManager.detonate_bloat). The swell is
## a commitment — it goes off wherever it stands, so the read is simply
## "back away now."
static func _run_bloat(enemy: EnemyCharacter, player: PlayerCharacter, dt: float) -> void:
	var d := _dist_to(enemy, player)
	var def := enemy.def
	match enemy.state:
		EnemyCharacter.State.SPAWNING:
			if enemy.state_timer > 0.25:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.CHASE:
			_seek_player(enemy, d.dx, d.dy, d.dist, def.move_speed)
			if d.dist <= def.attack_range + player.radius:
				enemy.set_state(EnemyCharacter.State.WINDUP)
				enemy.ai_velocity = Vector2.ZERO
		EnemyCharacter.State.WINDUP:
			enemy.ai_velocity = Vector2.ZERO
			if enemy.state_timer >= def.telegraph_time:
				enemy.set_state(EnemyCharacter.State.ATTACK)
		EnemyCharacter.State.ATTACK:
			# resolve_attack_trigger raised pending_burst on entry; the body
			# is gone next frame (CombatManager.detonate_bloat kills it).
			enemy.ai_velocity = Vector2.ZERO
		EnemyCharacter.State.COOLDOWN:
			enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.STAGGER:
			if enemy.state_timer >= 0.45:
				enemy.set_state(EnemyCharacter.State.CHASE)

## Hollow Warden / The Sunken Warden: a slow-turning shield wall. It only
## advances along its own facing, so circling it works; it only bashes when
## squared up to you, and the bash leaves its guard down for exposed_
## duration (the flank-or-punish window). The champion variant loses its
## shield for good at half health and switches to a faster double bash.
static func _run_warden(enemy: EnemyCharacter, player: PlayerCharacter, dt: float) -> void:
	var d := _dist_to(enemy, player)
	var def := enemy.def
	var phase2: bool = enemy.shield_broken
	var speed: float = def.move_speed * (1.3 if phase2 else 1.0)
	var turn_rate: float = (def.turn_rate if def.turn_rate > 0.0 else 2.3) * (1.35 if phase2 else 1.0)
	var target: float = atan2(d.dy, d.dx)

	var lead_seconds: float = 0.18
	var lead_pos: Vector2 = player.global_position + player.velocity * lead_seconds
	var chase_target: float = (lead_pos - enemy.global_position).angle()

	if def.champion and not enemy.shield_broken and enemy.state != EnemyCharacter.State.SPAWNING and enemy.hp <= enemy.max_hp * 0.5:
		enemy.shield_broken = true
		enemy.phase_just_changed = true
		enemy.bash_timer = 0.0
		enemy.combo_step = 0
		enemy.exposed_timer = 0.0
		enemy.ai_velocity = Vector2.ZERO
		enemy.set_state(EnemyCharacter.State.STAGGER)
		return

	match enemy.state:
		EnemyCharacter.State.SPAWNING:
			enemy.facing = target
			if enemy.state_timer > 0.35:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.CHASE:
			var remaining: float = _turn_toward(enemy, chase_target, turn_rate * dt)
			var squared_up: bool = absf(remaining) < 0.9
			var holding: bool = d.dist < 78.0
			if squared_up and not holding:
				enemy.ai_velocity = Vector2(cos(enemy.facing), sin(enemy.facing)) * speed
			else:
				enemy.ai_velocity *= 0.6
			if enemy.attack_cooldown_timer <= 0.0 and d.dist <= def.attack_range and absf(remaining) < 0.35:
				enemy.combo_step = 0
				enemy.set_state(EnemyCharacter.State.WINDUP)
				enemy.ai_velocity = Vector2.ZERO
		EnemyCharacter.State.WINDUP:
			_turn_toward(enemy, target, turn_rate * 0.33 * dt)
			enemy.ai_velocity = Vector2.ZERO
			var telegraph: float = def.telegraph_time * 0.45 if enemy.combo_step > 0 else def.telegraph_time
			if enemy.state_timer >= telegraph:
				enemy.set_state(EnemyCharacter.State.ATTACK)
		EnemyCharacter.State.ATTACK:
			if enemy.bash_timer > 0.0:
				enemy.bash_timer -= dt
				var bash_speed: float = def.bash_speed if def.bash_speed > 0.0 else 540.0
				enemy.ai_velocity = Vector2(cos(enemy.facing), sin(enemy.facing)) * bash_speed
				if enemy.bash_timer <= 0.0:
					enemy.ai_velocity = Vector2.ZERO
					if phase2 and def.champion:
						enemy.pending_cloud_radius = 72.0
					if phase2 and def.champion and enemy.combo_step < 1:
						enemy.combo_step += 1
						enemy.set_state(EnemyCharacter.State.WINDUP)
					else:
						enemy.attack_cooldown_timer = def.attack_cooldown * (0.7 if phase2 else 1.0)
						enemy.exposed_timer = def.exposed_duration if def.exposed_duration > 0.0 else 1.4
						enemy.set_state(EnemyCharacter.State.COOLDOWN)
			else:
				enemy.set_state(EnemyCharacter.State.COOLDOWN)
		EnemyCharacter.State.COOLDOWN:
			# Guard down — this is the window.
			enemy.ai_velocity = Vector2.ZERO
			_turn_toward(enemy, target, turn_rate * 0.3 * dt)
			var exposed: float = def.exposed_duration if def.exposed_duration > 0.0 else 1.4
			if enemy.state_timer >= exposed:
				enemy.set_state(EnemyCharacter.State.CHASE)
		EnemyCharacter.State.STAGGER:
			var stagger_time: float = 0.8 if def.champion else 0.4
			if enemy.state_timer >= stagger_time:
				enemy.set_state(EnemyCharacter.State.CHASE)

# ---------------------------------------------------------------- attack trigger

static func _resolve_attack_trigger(enemy: EnemyCharacter, player: PlayerCharacter) -> void:
	var def := enemy.def
	if def.behavior == EnemyDefinition.Behavior.BLOAT:
		enemy.pending_burst = true
		return
	if def.behavior == EnemyDefinition.Behavior.WARDEN:
		enemy.bash_timer = def.bash_duration if def.bash_duration > 0.0 else 0.27
		enemy.bash_hit_landed = false
		AudioEngine.play_sfx("wardenBash", 60.0)
		return
	var d := _dist_to(enemy, player)
	if def.behavior == EnemyDefinition.Behavior.RANGED:
		CombatManager.spawn_enemy_projectile(enemy, atan2(d.dy, d.dx))
	elif def.behavior == EnemyDefinition.Behavior.ELITE and Vector2(d.dx, d.dy).length() > 90.0:
		CombatManager.spawn_enemy_projectile(enemy, atan2(d.dy, d.dx))
	else:
		CombatManager.resolve_melee_land(enemy, player)

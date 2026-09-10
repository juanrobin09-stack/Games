import { Enemy } from '@/entities/Enemy';
import type { Player } from '@/entities/Player';
import type { AABB } from '@/utils/Collision';
import { SpatialGrid } from '@/utils/Collision';
import { clamp, angleDiff } from '@/utils/MathUtils';
import { WALL_THICKNESS } from '@/world/Room';

/** Teleporting enemies (stalkers, wraiths) reappear on the FLOOR — inset past
 * the wall thickness — never inside a wall, where the collision resolver would
 * eject them to whichever side is nearer, sometimes clean out of the room. */
function reappearAt(enemy: Enemy, ctx: EnemyAIContext, angle: number, targetDist: number): void {
  const inset = WALL_THICKNESS + enemy.radius + 6;
  enemy.x = clamp(ctx.player.x + Math.cos(angle) * targetDist, ctx.bounds.x + inset, ctx.bounds.x + ctx.bounds.width - inset);
  enemy.y = clamp(ctx.player.y + Math.sin(angle) * targetDist, ctx.bounds.y + inset, ctx.bounds.y + ctx.bounds.height - inset);
}

export interface EnemyAIContext {
  dt: number;
  player: Player;
  bounds: AABB;
  onMeleeLand: (enemy: Enemy) => void;
  onRangedFire: (enemy: Enemy, angle: number) => void;
  /** A warden just committed to its bash lunge (for the whoosh SFX/VFX). */
  onBashStart?: (enemy: Enemy) => void;
}

/** Rotates `enemy.facing` toward `target` by at most `maxDelta`; returns the
 * signed angle still left to turn (0 once it's facing the target). */
function turnToward(enemy: Enemy, target: number, maxDelta: number): number {
  const diff = angleDiff(enemy.facing, target);
  const step = clamp(diff, -maxDelta, maxDelta);
  enemy.facing += step;
  return diff - step;
}

function distanceTo(enemy: Enemy, player: Player): { dist: number; dx: number; dy: number } {
  const dx = player.x - enemy.x;
  const dy = player.y - enemy.y;
  return { dist: Math.hypot(dx, dy), dx, dy };
}

function seekPlayer(enemy: Enemy, dx: number, dy: number, dist: number, speed: number): void {
  if (dist < 0.001) {
    enemy.vx = 0;
    enemy.vy = 0;
    return;
  }
  enemy.vx = (dx / dist) * speed;
  enemy.vy = (dy / dist) * speed;
  enemy.facing = Math.atan2(dy, dx);
}

function maintainRange(enemy: Enemy, dx: number, dy: number, dist: number, speed: number, preferred: number): void {
  if (dist < 0.001) return;
  const nx = dx / dist;
  const ny = dy / dist;
  enemy.facing = Math.atan2(dy, dx);
  if (dist < preferred - 30) {
    enemy.vx = -nx * speed;
    enemy.vy = -ny * speed;
  } else if (dist > preferred + 30) {
    enemy.vx = nx * speed;
    enemy.vy = ny * speed;
  } else {
    enemy.vx = -ny * speed * 0.4;
    enemy.vy = nx * speed * 0.4;
  }
}

function beginWindupIfReady(enemy: Enemy, dist: number, range: number): void {
  if (enemy.attackCooldownTimer <= 0 && dist <= range) {
    enemy.setState('windup');
    enemy.vx = 0;
    enemy.vy = 0;
  }
}

function runMeleeLike(enemy: Enemy, ctx: EnemyAIContext, speed: number): void {
  const { dist, dx, dy } = distanceTo(enemy, ctx.player);
  switch (enemy.state) {
    case 'spawning':
      if (enemy.stateTimer > 0.2) enemy.setState('chase');
      break;
    case 'chase':
      seekPlayer(enemy, dx, dy, dist, speed);
      beginWindupIfReady(enemy, dist, enemy.def.attackRange);
      break;
    case 'windup':
      enemy.facing = Math.atan2(dy, dx);
      if (enemy.stateTimer >= enemy.def.telegraphTime) enemy.setState('attack');
      break;
    case 'attack':
      if (enemy.stateTimer >= 0.16) {
        enemy.attackCooldownTimer = enemy.def.attackCooldown;
        enemy.setState('cooldown');
      }
      break;
    case 'cooldown':
      if (enemy.stateTimer >= 0.12) enemy.setState('chase');
      break;
    case 'stagger':
      if (enemy.stateTimer >= 0.4) enemy.setState('chase');
      break;
  }
}

function runRangedLike(enemy: Enemy, ctx: EnemyAIContext, speed: number, preferredRange: number, canVanish: boolean): void {
  const { dist, dx, dy } = distanceTo(enemy, ctx.player);
  switch (enemy.state) {
    case 'spawning':
      if (enemy.stateTimer > 0.25) enemy.setState('chase');
      break;
    case 'chase':
      maintainRange(enemy, dx, dy, dist, speed, preferredRange);
      beginWindupIfReady(enemy, dist, enemy.def.attackRange);
      break;
    case 'windup':
      enemy.vx *= 0.85;
      enemy.vy *= 0.85;
      enemy.facing = Math.atan2(dy, dx);
      if (enemy.stateTimer >= enemy.def.telegraphTime) enemy.setState('attack');
      break;
    case 'attack':
      if (enemy.stateTimer >= 0.1) {
        enemy.attackCooldownTimer = enemy.def.attackCooldown;
        enemy.setState('cooldown');
      }
      break;
    case 'cooldown':
      if (enemy.stateTimer >= 0.2) {
        if (canVanish && Math.random() < 0.55) {
          enemy.setState('vanished');
        } else {
          enemy.setState('chase');
        }
      }
      break;
    case 'vanished':
      enemy.vx = 0;
      enemy.vy = 0;
      if (enemy.stateTimer >= 0.5) {
        const angle = Math.random() * Math.PI * 2;
        const targetDist = preferredRange * (0.7 + Math.random() * 0.5);
        reappearAt(enemy, ctx, angle, targetDist);
        enemy.setState('reappearing');
      }
      break;
    case 'reappearing':
      if (enemy.stateTimer >= 0.35) enemy.setState('chase');
      break;
    case 'stagger':
      if (enemy.stateTimer >= 0.4) enemy.setState('chase');
      break;
  }
}

function runStalker(enemy: Enemy, ctx: EnemyAIContext): void {
  const { dist, dx, dy } = distanceTo(enemy, ctx.player);
  const speed = enemy.def.moveSpeed;
  switch (enemy.state) {
    case 'spawning':
      if (enemy.stateTimer > 0.2) enemy.setState('chase');
      break;
    case 'chase':
      seekPlayer(enemy, dx, dy, dist, speed);
      beginWindupIfReady(enemy, dist, enemy.def.attackRange);
      break;
    case 'windup':
      enemy.facing = Math.atan2(dy, dx);
      if (enemy.stateTimer >= enemy.def.telegraphTime) enemy.setState('attack');
      break;
    case 'attack':
      if (enemy.stateTimer >= 0.14) {
        enemy.attackCooldownTimer = enemy.def.attackCooldown;
        enemy.setState('cooldown');
      }
      break;
    case 'cooldown':
      if (enemy.stateTimer >= 0.15) {
        enemy.setState(Math.random() < 0.6 ? 'vanished' : 'chase');
      }
      break;
    case 'vanished':
      enemy.vx = 0;
      enemy.vy = 0;
      if (enemy.stateTimer >= (enemy.def.vanishDuration ?? 1)) {
        const angle = Math.random() * Math.PI * 2;
        const targetDist = 70 + Math.random() * 60;
        reappearAt(enemy, ctx, angle, targetDist);
        enemy.setState('reappearing');
      }
      break;
    case 'reappearing':
      if (enemy.stateTimer >= 0.3) enemy.setState('chase');
      break;
    case 'stagger':
      if (enemy.stateTimer >= 0.4) enemy.setState('chase');
      break;
  }
}

function runElite(enemy: Enemy, ctx: EnemyAIContext): void {
  const { dist, dx, dy } = distanceTo(enemy, ctx.player);
  const speed = enemy.def.moveSpeed;
  switch (enemy.state) {
    case 'spawning':
      if (enemy.stateTimer > 0.4) enemy.setState('chase');
      break;
    case 'chase':
      maintainRange(enemy, dx, dy, dist, speed, 150);
      if (enemy.attackCooldownTimer <= 0 && dist <= enemy.def.attackRange) {
        enemy.setState('windup');
        enemy.vx = 0;
        enemy.vy = 0;
      }
      break;
    case 'windup':
      enemy.facing = Math.atan2(dy, dx);
      if (enemy.stateTimer >= enemy.def.telegraphTime) enemy.setState('attack');
      break;
    case 'attack':
      if (enemy.stateTimer >= 0.18) {
        enemy.attackCooldownTimer = enemy.def.attackCooldown * 0.85;
        enemy.setState('cooldown');
      }
      break;
    case 'cooldown':
      if (enemy.stateTimer >= 0.25) enemy.setState('chase');
      break;
    case 'stagger':
      if (enemy.stateTimer >= 0.35) enemy.setState('chase');
      break;
  }
}

/**
 * Blightbloat: walks at you, plants itself within reach, swells for
 * `telegraphTime`, then bursts (CombatSystem.detonateBloat). The swell is a
 * commitment — it goes off wherever it stands, so the read is simply "back
 * away now": burstRadius is deliberately larger than attackRange, and a
 * crit during the swell staggers it (the interrupt reward).
 */
function runBloat(enemy: Enemy, ctx: EnemyAIContext): void {
  const { dist, dx, dy } = distanceTo(enemy, ctx.player);
  switch (enemy.state) {
    case 'spawning':
      if (enemy.stateTimer > 0.25) enemy.setState('chase');
      break;
    case 'chase':
      seekPlayer(enemy, dx, dy, dist, enemy.def.moveSpeed);
      if (dist <= enemy.def.attackRange + ctx.player.radius) {
        enemy.setState('windup');
        enemy.vx = 0;
        enemy.vy = 0;
      }
      break;
    case 'windup':
      enemy.vx = 0;
      enemy.vy = 0;
      if (enemy.stateTimer >= enemy.def.telegraphTime) enemy.setState('attack');
      break;
    case 'attack':
      // resolveAttackTrigger raised pendingBurst on entry; the body is gone next frame.
      enemy.vx = 0;
      enemy.vy = 0;
      break;
    case 'cooldown':
      enemy.setState('chase');
      break;
    case 'stagger':
      if (enemy.stateTimer >= 0.45) enemy.setState('chase');
      break;
  }
}

/**
 * Hollow Warden: a slow-turning shield wall. It only advances along its own
 * facing, so circling it works; it only bashes when squared up to you, and
 * the bash (a committed lunge along that facing) leaves its guard down for
 * `exposedDuration` — the punish window. The champion variant loses its
 * shield for good at half health and switches to a faster double bash that
 * leaves spore clouds where it lands (see CombatSystem.consumePendingClouds).
 */
function runWarden(enemy: Enemy, ctx: EnemyAIContext): void {
  const { dist, dx, dy } = distanceTo(enemy, ctx.player);
  const def = enemy.def;
  const phase2 = enemy.shieldBroken;
  const speed = def.moveSpeed * (phase2 ? 1.3 : 1);
  const turnRate = (def.turnRate ?? 2.3) * (phase2 ? 1.35 : 1);
  const target = Math.atan2(dy, dx);
  // While still hunting for an angle to commit from, lead a little on the
  // player's current velocity — just enough that circling it at a steady
  // speed no longer keeps it permanently just outside the facing cone.
  // Only 'chase' uses this: 'windup' below tracks the real, un-predicted
  // target at a reduced rate, so an actual change of direction during the
  // telegraph is still a genuine escape, not just a wasted juke.
  const leadSeconds = 0.18;
  const leadX = ctx.player.x + ctx.player.vx * leadSeconds;
  const leadY = ctx.player.y + ctx.player.vy * leadSeconds;
  const chaseTarget = Math.atan2(leadY - enemy.y, leadX - enemy.x);

  if (def.champion && !enemy.shieldBroken && enemy.state !== 'spawning' && enemy.hp <= enemy.maxHp * 0.5) {
    enemy.shieldBroken = true;
    enemy.phaseJustChanged = true;
    enemy.bashTimer = 0;
    enemy.comboStep = 0;
    enemy.exposedTimer = 0;
    enemy.vx = 0;
    enemy.vy = 0;
    enemy.setState('stagger');
    return;
  }

  switch (enemy.state) {
    case 'spawning':
      enemy.facing = target;
      if (enemy.stateTimer > 0.35) enemy.setState('chase');
      break;
    case 'chase': {
      const remaining = turnToward(enemy, chaseTarget, turnRate * ctx.dt);
      const squaredUp = Math.abs(remaining) < 0.9;
      const holding = dist < 78;
      if (squaredUp && !holding) {
        enemy.vx = Math.cos(enemy.facing) * speed;
        enemy.vy = Math.sin(enemy.facing) * speed;
      } else {
        // Turning in place (or holding ground behind the shield): bleed momentum
        // rather than sliding sideways with the shield pointing the wrong way.
        enemy.vx *= 0.6;
        enemy.vy *= 0.6;
      }
      if (enemy.attackCooldownTimer <= 0 && dist <= def.attackRange && Math.abs(remaining) < 0.35) {
        enemy.comboStep = 0;
        enemy.setState('windup');
        enemy.vx = 0;
        enemy.vy = 0;
      }
      break;
    }
    case 'windup': {
      // Committed bash line: keeps tracking, but slowly enough that a sidestep
      // works — held at roughly the ORIGINAL absolute windup turn speed
      // (turnRate above was raised so 'chase' can actually catch up to a
      // circling player; that increase must not also leak into the windup's
      // tracking, or a full-speed sidestep held for the whole telegraph stops
      // being enough to beat it even though nothing about the telegraph
      // itself changed).
      turnToward(enemy, target, turnRate * 0.33 * ctx.dt);
      enemy.vx = 0;
      enemy.vy = 0;
      const telegraph = enemy.comboStep > 0 ? def.telegraphTime * 0.45 : def.telegraphTime;
      if (enemy.stateTimer >= telegraph) enemy.setState('attack');
      break;
    }
    case 'attack': {
      if (enemy.bashTimer > 0) {
        enemy.bashTimer -= ctx.dt;
        const bashSpeed = def.bashSpeed ?? 540;
        enemy.vx = Math.cos(enemy.facing) * bashSpeed;
        enemy.vy = Math.sin(enemy.facing) * bashSpeed;
        if (enemy.bashTimer <= 0) {
          enemy.vx = 0;
          enemy.vy = 0;
          if (phase2 && def.champion) enemy.pendingCloudRadius = 72;
          if (phase2 && def.champion && enemy.comboStep < 1) {
            enemy.comboStep++;
            enemy.setState('windup');
          } else {
            enemy.attackCooldownTimer = def.attackCooldown * (phase2 ? 0.7 : 1);
            enemy.exposedTimer = def.exposedDuration ?? 1.4;
            enemy.setState('cooldown');
          }
        }
      } else {
        enemy.setState('cooldown');
      }
      break;
    }
    case 'cooldown':
      // Guard down — this is the window.
      enemy.vx = 0;
      enemy.vy = 0;
      turnToward(enemy, target, turnRate * 0.3 * ctx.dt);
      if (enemy.stateTimer >= (def.exposedDuration ?? 1.4)) enemy.setState('chase');
      break;
    case 'stagger':
      enemy.vx = 0;
      enemy.vy = 0;
      if (enemy.stateTimer >= (def.champion ? 0.8 : 0.4)) enemy.setState('chase');
      break;
  }
}

/** Advances one enemy's behavior state machine. Actual damage application is
 * delegated to the ctx callbacks so CombatSystem stays the single place
 * where hits are resolved. */
export function updateEnemyAI(enemy: Enemy, ctx: EnemyAIContext): void {
  if (!enemy.alive) return;

  switch (enemy.def.behavior) {
    case 'chaser':
    case 'tank':
    case 'heavy':
      runMeleeLike(enemy, ctx, enemy.def.moveSpeed);
      break;
    case 'ranged':
      runRangedLike(enemy, ctx, enemy.def.moveSpeed, enemy.def.id === 'cinderWraith' ? 220 : 240, enemy.def.id === 'cinderWraith');
      break;
    case 'stalker':
      runStalker(enemy, ctx);
      break;
    case 'elite':
      runElite(enemy, ctx);
      break;
    case 'bloat':
      runBloat(enemy, ctx);
      break;
    case 'warden':
      runWarden(enemy, ctx);
      break;
  }
}

/** Call once per frame, comparing the state captured before updateEnemyAI ran,
 * to detect the exact frame an enemy's state became 'attack'. */
export function isAttackTriggerFrame(enemy: Enemy, previousState: string): boolean {
  return enemy.state === 'attack' && previousState !== 'attack';
}

export function resolveAttackTrigger(enemy: Enemy, ctx: EnemyAIContext): void {
  if (enemy.def.behavior === 'bloat') {
    enemy.pendingBurst = true;
    return;
  }
  if (enemy.def.behavior === 'warden') {
    enemy.bashTimer = enemy.def.bashDuration ?? 0.27;
    enemy.bashHitLanded = false;
    ctx.onBashStart?.(enemy);
    return;
  }
  if (enemy.def.behavior === 'ranged') {
    const angle = Math.atan2(ctx.player.y - enemy.y, ctx.player.x - enemy.x);
    ctx.onRangedFire(enemy, angle);
  } else if (enemy.def.behavior === 'elite' && Math.hypot(ctx.player.x - enemy.x, ctx.player.y - enemy.y) > 90) {
    const angle = Math.atan2(ctx.player.y - enemy.y, ctx.player.x - enemy.x);
    ctx.onRangedFire(enemy, angle);
  } else {
    ctx.onMeleeLand(enemy);
  }
}

export function applyEnemySeparation(enemies: Enemy[], grid: SpatialGrid<Enemy>): void {
  grid.rebuild(enemies.filter((e) => e.alive));
  for (const enemy of enemies) {
    if (!enemy.alive || enemy.state === 'vanished') continue;
    // A lunging warden is a committed line, not a body to be nudged off course.
    if (enemy.bashTimer > 0) continue;
    const neighbors = grid.query(enemy.x, enemy.y, enemy.radius * 2.4);
    let pushX = 0;
    let pushY = 0;
    for (const other of neighbors) {
      if (other === enemy) continue;
      const dx = enemy.x - other.x;
      const dy = enemy.y - other.y;
      const dist = Math.hypot(dx, dy);
      const minDist = enemy.radius + other.radius;
      if (dist > 0.01 && dist < minDist) {
        const overlap = (minDist - dist) / minDist;
        pushX += (dx / dist) * overlap;
        pushY += (dy / dist) * overlap;
      }
    }
    enemy.x += pushX * 40 * (1 / 60);
    enemy.y += pushY * 40 * (1 / 60);
  }
}

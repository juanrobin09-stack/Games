import { Enemy } from '@/entities/Enemy';
import type { Player } from '@/entities/Player';
import type { AABB } from '@/utils/Collision';
import { SpatialGrid } from '@/utils/Collision';
import { clamp } from '@/utils/MathUtils';

export interface EnemyAIContext {
  dt: number;
  player: Player;
  bounds: AABB;
  onMeleeLand: (enemy: Enemy) => void;
  onRangedFire: (enemy: Enemy, angle: number) => void;
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
      if (enemy.stateTimer >= 0.16) enemy.setState('cooldown');
      break;
    case 'cooldown':
      enemy.attackCooldownTimer = enemy.def.attackCooldown;
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
      if (enemy.stateTimer >= 0.1) enemy.setState('cooldown');
      break;
    case 'cooldown':
      enemy.attackCooldownTimer = enemy.def.attackCooldown;
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
        enemy.x = clamp(ctx.player.x + Math.cos(angle) * targetDist, ctx.bounds.x + enemy.radius, ctx.bounds.x + ctx.bounds.width - enemy.radius);
        enemy.y = clamp(ctx.player.y + Math.sin(angle) * targetDist, ctx.bounds.y + enemy.radius, ctx.bounds.y + ctx.bounds.height - enemy.radius);
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
      if (enemy.stateTimer >= 0.14) enemy.setState('cooldown');
      break;
    case 'cooldown':
      enemy.attackCooldownTimer = enemy.def.attackCooldown;
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
        enemy.x = clamp(ctx.player.x + Math.cos(angle) * targetDist, ctx.bounds.x + enemy.radius, ctx.bounds.x + ctx.bounds.width - enemy.radius);
        enemy.y = clamp(ctx.player.y + Math.sin(angle) * targetDist, ctx.bounds.y + enemy.radius, ctx.bounds.y + ctx.bounds.height - enemy.radius);
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
  const meleeRange = 70;
  switch (enemy.state) {
    case 'spawning':
      if (enemy.stateTimer > 0.4) enemy.setState('chase');
      break;
    case 'chase':
      maintainRange(enemy, dx, dy, dist, speed, 150);
      if (enemy.attackCooldownTimer <= 0 && dist <= (dist < meleeRange + 20 ? meleeRange : enemy.def.attackRange)) {
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
      if (enemy.stateTimer >= 0.18) enemy.setState('cooldown');
      break;
    case 'cooldown':
      enemy.attackCooldownTimer = enemy.def.attackCooldown * 0.85;
      if (enemy.stateTimer >= 0.25) enemy.setState('chase');
      break;
    case 'stagger':
      if (enemy.stateTimer >= 0.35) enemy.setState('chase');
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
  }
}

/** Call once per frame, comparing the state captured before updateEnemyAI ran,
 * to detect the exact frame an enemy's state became 'attack'. */
export function isAttackTriggerFrame(enemy: Enemy, previousState: string): boolean {
  return enemy.state === 'attack' && previousState !== 'attack';
}

export function resolveAttackTrigger(enemy: Enemy, ctx: EnemyAIContext): void {
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

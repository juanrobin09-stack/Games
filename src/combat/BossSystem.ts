import type { Boss } from '@/entities/Boss';
import type { Player } from '@/entities/Player';
import type { Room } from '@/world/Room';
import type { CombatSystem } from '@/combat/CombatSystem';
import type { ParticleSystem } from '@/rendering/ParticleSystem';
import type { Camera } from '@/core/Camera';
import type { HitStopController } from '@/core/HitStop';
import { Enemy } from '@/entities/Enemy';
import { getEnemyDefinition } from '@/data/enemies';
import { getDifficultyFactors } from '@/world/Difficulty';
import { spawnEmberBurstVfx, spawnDeathBurst } from '@/rendering/ParticlePresets';
import { Palette } from '@/rendering/Palette';
import { playSfx } from '@/audio/SoundFactory';
import { gameEvents } from '@/core/GameEvents';
import { ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS } from '@/world/Room';

export interface BossSystemContext {
  player: Player;
  room: Room;
  combat: CombatSystem;
  particles: ParticleSystem;
  camera: Camera;
  hitStop: HitStopController;
  runMinutes: number;
}

const SUMMON_POOL_BY_PHASE: Record<number, string> = {
  2: 'ashCrawler',
  3: 'shadowStalker',
};

export function resolveBossPendingActions(boss: Boss, ctx: BossSystemContext): void {
  const { player, combat, particles, camera, hitStop } = ctx;

  if (boss.introJustStarted) {
    boss.introJustStarted = false;
    playSfx('bossRoar');
  }

  if (boss.phaseJustChanged) {
    boss.phaseJustChanged = false;
    playSfx('bossPhase');
    camera.addShake(16, 0.6);
    hitStop.trigger(0.1, 0.04);
    spawnEmberBurstVfx(particles, boss.x, boss.y, 180);
    gameEvents.emit('bossPhaseChanged', { phase: boss.phase });
  }

  if (boss.pendingMeleeSlam) {
    boss.pendingMeleeSlam = false;
    const radius = 130;
    const dist = Math.hypot(player.x - boss.x, player.y - boss.y);
    spawnEmberBurstVfx(particles, boss.x + Math.cos(boss.facing) * 60, boss.y + Math.sin(boss.facing) * 60, 90);
    playSfx('bossHit');
    camera.addShake(13, 0.3);
    if (dist <= radius + player.radius) {
      const dirX = (player.x - boss.x) / Math.max(0.01, dist);
      const dirY = (player.y - boss.y) / Math.max(0.01, dist);
      combat.damageEnemyToPlayer(player, boss.attackDamage * 1.25, {
        knockbackDirX: dirX,
        knockbackDirY: dirY,
        knockbackForce: 280,
      });
    }
  }

  if (boss.pendingShockwave) {
    boss.pendingShockwave = false;
    const radius = 230;
    const dist = Math.hypot(player.x - boss.x, player.y - boss.y);
    spawnEmberBurstVfx(particles, boss.x, boss.y, radius * 0.9);
    playSfx('bossHit');
    camera.addShake(15, 0.4);
    if (dist <= radius + player.radius) {
      const dirX = (player.x - boss.x) / Math.max(0.01, dist);
      const dirY = (player.y - boss.y) / Math.max(0.01, dist);
      combat.damageEnemyToPlayer(player, boss.attackDamage * 1.1, {
        knockbackDirX: dirX,
        knockbackDirY: dirY,
        knockbackForce: 320,
      });
    }
  }

  if (boss.pendingProjectileAngles.length > 0) {
    for (const angle of boss.pendingProjectileAngles) {
      combat.spawnEnemyProjectile(boss, angle);
    }
    boss.pendingProjectileAngles = [];
  }

  if (boss.pendingSummonCount > 0) {
    const count = boss.pendingSummonCount;
    boss.pendingSummonCount = 0;
    const enemyId = SUMMON_POOL_BY_PHASE[boss.phase] ?? 'ashCrawler';
    const def = getEnemyDefinition(enemyId);
    const { hpMult, damageMult } = getDifficultyFactors(2, ctx.runMinutes);
    for (let i = 0; i < count; i++) {
      const angle = (i / count) * Math.PI * 2 + Math.random() * 0.5;
      const dist = 160 + Math.random() * 60;
      const x = Math.min(Math.max(boss.x + Math.cos(angle) * dist, WALL_THICKNESS + 40), ROOM_WIDTH - WALL_THICKNESS - 40);
      const y = Math.min(Math.max(boss.y + Math.sin(angle) * dist, WALL_THICKNESS + 40), ROOM_HEIGHT - WALL_THICKNESS - 40);
      const adds = new Enemy(def, x, y, hpMult * 0.8, damageMult * 0.8);
      ctx.room.enemies.push(adds);
    }
    playSfx('bossRoar');
  }

  if (boss.pendingMeteorImpacts.length > 0) {
    for (const impact of boss.pendingMeteorImpacts) {
      spawnEmberBurstVfx(particles, impact.x, impact.y, 65);
      playSfx('impactCrit', { throttleMs: 0 });
      const dist = Math.hypot(player.x - impact.x, player.y - impact.y);
      if (dist <= 70 + player.radius) {
        const dirX = (player.x - impact.x) / Math.max(0.01, dist);
        const dirY = (player.y - impact.y) / Math.max(0.01, dist);
        combat.damageEnemyToPlayer(player, boss.attackDamage * 0.85, {
          knockbackDirX: dirX,
          knockbackDirY: dirY,
          knockbackForce: 180,
        });
      }
    }
    boss.pendingMeteorImpacts = [];
    camera.addShake(6, 0.2);
  }

  if (!boss.alive && boss.deathAnimationDone && !boss.deathHandled) {
    boss.deathHandled = true;
    spawnDeathBurst(particles, boss.x, boss.y, Palette.ember4);
    spawnDeathBurst(particles, boss.x, boss.y, Palette.ember6);
    playSfx('bossDeath');
    camera.addShake(20, 0.8);
    hitStop.trigger(0.14, 0.03);
    gameEvents.emit('bossDefeated', {});
  }
}

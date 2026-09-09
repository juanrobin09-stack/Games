import type { Player } from '@/entities/Player';
import { Enemy } from '@/entities/Enemy';
import { Projectile, type ProjectileOptions } from '@/entities/Projectile';
import type { Obstacle } from '@/entities/Obstacle';
import type { Camera } from '@/core/Camera';
import type { HitStopController } from '@/core/HitStop';
import type { ParticleSystem } from '@/rendering/ParticleSystem';
import { createDamageNumber, updateDamageNumbers, type DamageNumber } from '@/combat/DamageNumber';
import {
  spawnHitImpact,
  spawnDeathBurst,
  spawnEmberBurstVfx,
  spawnPerfectDodgeBurst,
  spawnSporeBurstVfx,
  spawnSporeMote,
  spawnShieldSparks,
} from '@/rendering/ParticlePresets';
import { Palette } from '@/rendering/Palette';
import { playSfx } from '@/audio/SoundFactory';
import { gameEvents } from '@/core/GameEvents';
import { angleDiff, clamp } from '@/utils/MathUtils';
import { circleIntersect, resolveCircleAABB, type AABB } from '@/utils/Collision';

export interface MeleeAttackResult {
  hitCount: number;
  crit: boolean;
}

export interface DamageOptions {
  crit?: boolean;
  knockbackDirX?: number;
  knockbackDirY?: number;
  knockbackForce?: number;
  isAbility?: boolean;
  silent?: boolean;
  /** Where the hit came from, for a warden's frontal shield check (defaults to the player). */
  sourceX?: number;
  sourceY?: number;
  /** Environmental damage-over-time tick (spore cloud): softer feedback, no knockback. */
  hazard?: boolean;
}

/** A lingering floor hazard — currently only the Hollow Ruins' spore clouds. */
export interface Hazard {
  kind: 'spores';
  x: number;
  y: number;
  radius: number;
  timer: number;
  duration: number;
  tickDamage: number;
  tickTimer: number;
  emitTimer: number;
  seed: number;
}

const ELITE_SHAKE = 9;
const NORMAL_SHAKE = 4;
const CRIT_SHAKE_BONUS = 3;
const HIT_ARC_COVERAGE = 0.75;
/** Damage that gets through a raised warden shield. */
const SHIELD_DAMAGE_FACTOR = 0.15;
const HAZARD_TICK_INTERVAL = 0.6;
/** Hard cap so a long bloat-heavy fight can't pile up clouds without bound. */
const MAX_HAZARDS = 10;

export class CombatSystem {
  projectiles: Projectile[] = [];
  damageNumbers: DamageNumber[] = [];
  hazards: Hazard[] = [];
  onDamageDealtToEnemy: ((amount: number) => void) | null = null;
  onDamageDealtToPlayer: ((amount: number) => void) | null = null;

  constructor(private particles: ParticleSystem, private camera: Camera, private hitStop: HitStopController) {}

  reset(): void {
    this.projectiles.length = 0;
    this.damageNumbers.length = 0;
    this.hazards.length = 0;
  }

  // ---------------------------------------------------------------- Hazards
  spawnSporeCloud(x: number, y: number, radius: number, duration: number, tickDamage: number): void {
    if (this.hazards.length >= MAX_HAZARDS) this.hazards.shift();
    this.hazards.push({
      kind: 'spores',
      x,
      y,
      radius,
      timer: 0,
      duration,
      tickDamage,
      tickTimer: 0.35,
      emitTimer: 0,
      seed: Math.random() * 100,
    });
  }

  updateHazards(dt: number, player: Player): void {
    let expired = false;
    for (const h of this.hazards) {
      h.timer += dt;
      if (h.timer >= h.duration) {
        expired = true;
        continue;
      }
      h.emitTimer -= dt;
      if (h.emitTimer <= 0) {
        h.emitTimer = 0.07;
        const angle = Math.random() * Math.PI * 2;
        const r = Math.sqrt(Math.random()) * h.radius * 0.9;
        spawnSporeMote(this.particles, h.x + Math.cos(angle) * r, h.y + Math.sin(angle) * r);
      }
      h.tickTimer -= dt;
      if (h.tickTimer <= 0) {
        h.tickTimer = HAZARD_TICK_INTERVAL;
        const dist = Math.hypot(player.x - h.x, player.y - h.y);
        if (player.alive && dist <= h.radius + player.radius * 0.5) {
          this.damageEnemyToPlayer(player, h.tickDamage, { hazard: true });
        }
      }
    }
    if (expired) this.hazards = this.hazards.filter((h) => h.timer < h.duration);
  }

  /** A bloat's swell finished: direct hit on anyone close, then the cloud.
   * The body is consumed by the burst — the caller's normal death path
   * (onEnemyDeath) still runs for loot, but sees `burstDetonated` and skips
   * the second, smaller "killed early" cloud. */
  detonateBloat(player: Player, enemy: Enemy): void {
    enemy.pendingBurst = false;
    if (!enemy.alive) return;
    enemy.burstDetonated = true;
    const radius = enemy.def.burstRadius ?? 90;
    spawnSporeBurstVfx(this.particles, enemy.x, enemy.y, radius);
    playSfx('sporeBurst', { throttleMs: 40 });
    this.camera.addShake(6, 0.2);
    const dist = Math.hypot(player.x - enemy.x, player.y - enemy.y);
    if (dist <= radius + player.radius) {
      this.damageEnemyToPlayer(player, enemy.attackDamage, {
        knockbackDirX: (player.x - enemy.x) / Math.max(0.01, dist),
        knockbackDirY: (player.y - enemy.y) / Math.max(0.01, dist),
        knockbackForce: 230,
      });
    }
    this.spawnSporeCloud(enemy.x, enemy.y, enemy.def.cloudRadius ?? 80, enemy.def.cloudDuration ?? 5, 5 * enemy.difficultyDamageMult);
    enemy.takeDamage(enemy.hp + 1);
  }

  /** Wardens flag a cloud where they stand (phase-2 champion bash landings). */
  consumePendingClouds(enemies: Enemy[]): void {
    for (const e of enemies) {
      if (e.pendingCloudRadius <= 0) continue;
      this.spawnSporeCloud(e.x, e.y, e.pendingCloudRadius, 3.5, 5 * e.difficultyDamageMult);
      spawnSporeBurstVfx(this.particles, e.x, e.y, e.pendingCloudRadius * 0.6);
      playSfx('sporeHiss', { throttleMs: 80 });
      e.pendingCloudRadius = 0;
    }
  }

  /** A lunging warden that overlaps the player lands its bash exactly once per lunge. */
  resolveBashHits(player: Player, enemies: Enemy[]): void {
    for (const e of enemies) {
      if (!e.alive || e.bashTimer <= 0 || e.bashHitLanded) continue;
      const dist = Math.hypot(player.x - e.x, player.y - e.y);
      if (dist > e.radius + player.radius + 6) continue;
      e.bashHitLanded = true;
      const landed = this.damageEnemyToPlayer(player, e.attackDamage, {
        knockbackDirX: Math.cos(e.facing),
        knockbackDirY: Math.sin(e.facing),
        knockbackForce: 300,
      });
      if (landed) {
        this.camera.addShake(9, 0.25);
        this.hitStop.trigger(0.04, 0.06);
      }
    }
  }

  // ---------------------------------------------------------------- Player -> Enemy
  performMeleeAttack(player: Player, enemies: Enemy[]): MeleeAttackResult {
    const weapon = player.weapon;
    const range = weapon.range * player.stats.rangeMult;
    // The hit check runs once, instantly, the moment the swing starts (attackFacingLock
    // is set then) — but the blade sprite only reaches that angle by sweeping across the
    // full arcDegrees over the swing's duration, so at t=0 it's still sitting at one edge
    // of the nominal arc. Checking the full arc would land hits on the far edge before the
    // blade is anywhere near it; HIT_ARC_COVERAGE narrows the checked cone so a hit always
    // corresponds to roughly where the blade actually is early in its swing.
    const halfArc = ((weapon.arcDegrees ?? 100) * HIT_ARC_COVERAGE * Math.PI) / 180 / 2;
    let hitCount = 0;
    let anyCrit = false;

    for (const enemy of enemies) {
      if (!enemy.alive || enemy.state === 'vanished') continue;
      const dx = enemy.x - player.x;
      const dy = enemy.y - player.y;
      const dist = Math.hypot(dx, dy);
      if (dist > range + enemy.radius) continue;
      const angleToEnemy = Math.atan2(dy, dx);
      if (Math.abs(angleDiff(player.attackFacingLock, angleToEnemy)) > halfArc) continue;

      const crit = this.rollCrit(player.stats.critChance + weapon.critBonus);
      anyCrit = anyCrit || crit;
      const baseDamage = weapon.baseDamage * player.stats.damageMult * player.synergyDamageMultiplier;
      const dirX = dist > 0.01 ? dx / dist : Math.cos(angleToEnemy);
      const dirY = dist > 0.01 ? dy / dist : Math.sin(angleToEnemy);
      this.damagePlayerToEnemy(player, enemy, baseDamage, crit, {
        knockbackDirX: dirX,
        knockbackDirY: dirY,
        knockbackForce: weapon.knockback,
      });
      hitCount++;
    }

    playSfx(weapon.id === 'voidScythe' ? 'attackSwingHeavy' : 'attackSwing');
    return { hitCount, crit: anyCrit };
  }

  fireProjectileWeapon(player: Player): void {
    const weapon = player.weapon;
    const count = 1 + Math.floor(player.stats.projectileCount);
    const spread = count > 1 ? 0.18 : 0;
    for (let i = 0; i < count; i++) {
      const t = count > 1 ? i / (count - 1) - 0.5 : 0;
      const angle = player.attackFacingLock + t * spread * count;
      this.spawnProjectile({
        x: player.x + Math.cos(angle) * 22,
        y: player.y + Math.sin(angle) * 22,
        angle,
        speed: weapon.projectileSpeed ?? 500,
        damage: weapon.baseDamage * player.stats.damageMult * player.synergyDamageMultiplier,
        radius: 6,
        fromPlayer: true,
        pierce: weapon.pierce ?? 0,
        knockback: weapon.knockback,
        critChance: player.stats.critChance + weapon.critBonus,
        critDamageMult: player.stats.critDamage,
        burnChance: player.stats.burnChance,
        lifesteal: player.stats.lifesteal,
        visual: 'solarBolt',
        maxLifetime: (weapon.range ?? 400) / (weapon.projectileSpeed ?? 500) + 0.3,
      });
    }
    playSfx('attackRanged');
  }

  spawnEnemyProjectile(enemy: Enemy, angle: number): void {
    this.spawnProjectile({
      x: enemy.x + Math.cos(angle) * (enemy.radius + 4),
      y: enemy.y + Math.sin(angle) * (enemy.radius + 4),
      angle,
      speed: enemy.def.projectileSpeed ?? 220,
      damage: enemy.attackDamage,
      radius: 7,
      fromPlayer: false,
      pierce: 0,
      knockback: 60,
      critChance: 0,
      critDamageMult: 1,
      burnChance: 0,
      lifesteal: 0,
      visual: enemy.def.id === 'cinderWraith' ? 'shadowBolt' : 'emberBolt',
    });
    playSfx('attackRanged', { throttleMs: 90 });
  }

  private spawnProjectile(opts: ProjectileOptions): void {
    this.projectiles.push(new Projectile(opts));
  }

  updateProjectiles(dt: number, player: Player, enemies: Enemy[], obstacles: Obstacle[]): void {
    for (const proj of this.projectiles) {
      if (!proj.alive) continue;
      proj.update(dt);

      for (const o of obstacles) {
        if (!o.blocksProjectiles) continue;
        if (circleIntersect(proj, o)) {
          proj.alive = false;
          this.particles.burst(4, () => ({
            x: proj.x,
            y: proj.y,
            vx: (Math.random() - 0.5) * 80,
            vy: (Math.random() - 0.5) * 80,
            size: 2,
            color: Palette.bg3,
            life: 0.3,
            shape: 'circle',
          }));
          break;
        }
      }
      if (!proj.alive) continue;

      if (proj.fromPlayer) {
        for (const enemy of enemies) {
          if (!enemy.alive || enemy.state === 'vanished') continue;
          if (!circleIntersect(proj, enemy)) continue;
          if (!proj.registerHit(enemy.id)) continue;
          const crit = this.rollCrit(proj.critChance);
          const dirX = enemy.x - proj.x || Math.cos(proj.angle);
          const dirY = enemy.y - proj.y || Math.sin(proj.angle);
          const len = Math.hypot(dirX, dirY) || 1;
          this.damagePlayerToEnemy(player, enemy, proj.damage, crit, {
            knockbackDirX: dirX / len,
            knockbackDirY: dirY / len,
            knockbackForce: proj.knockback,
            // A bolt's "origin" for the shield check is back along its flight, not the player.
            sourceX: proj.x - Math.cos(proj.angle) * 60,
            sourceY: proj.y - Math.sin(proj.angle) * 60,
          });
        }
      } else if (circleIntersect(proj, player)) {
        proj.alive = false;
        this.damageEnemyToPlayer(player, proj.damage, {
          knockbackDirX: Math.cos(proj.angle),
          knockbackDirY: Math.sin(proj.angle),
          knockbackForce: 70,
        });
      }
    }
    this.projectiles = this.projectiles.filter((p) => p.alive);
  }

  resolveProjectileWalls(walls: AABB[]): void {
    for (const proj of this.projectiles) {
      if (!proj.alive) continue;
      for (const wall of walls) {
        const push = resolveCircleAABB(proj, wall);
        if (push.x !== 0 || push.y !== 0) {
          proj.alive = false;
          break;
        }
      }
    }
  }

  resolveContactDamage(player: Player, enemies: Enemy[]): void {
    for (const enemy of enemies) {
      if (!enemy.alive || enemy.state === 'vanished' || enemy.state !== 'chase') continue;
      if (enemy.contactCooldownTimer > 0) continue;
      if (!circleIntersect(player, enemy)) continue;
      enemy.contactCooldownTimer = 0.6;
      const dist = Math.hypot(player.x - enemy.x, player.y - enemy.y) || 1;
      this.damageEnemyToPlayer(player, enemy.contactDamage, {
        knockbackDirX: (player.x - enemy.x) / dist,
        knockbackDirY: (player.y - enemy.y) / dist,
        knockbackForce: 110,
      });
    }
  }

  // ---------------------------------------------------------------- Ability
  emberBurstAbility(player: Player, enemies: Enemy[]): void {
    const radius = 140 * player.stats.areaDamageMult;
    const damage = 55 * player.stats.abilityDamageMult * player.stats.emberPower * player.synergyDamageMultiplier;
    for (const enemy of enemies) {
      if (!enemy.alive) continue;
      const dist = Math.hypot(enemy.x - player.x, enemy.y - player.y);
      if (dist > radius + enemy.radius) continue;
      const falloff = 1 - Math.min(1, dist / (radius + enemy.radius)) * 0.35;
      const dirX = (enemy.x - player.x) / Math.max(0.01, dist);
      const dirY = (enemy.y - player.y) / Math.max(0.01, dist);
      this.damagePlayerToEnemy(player, enemy, damage * falloff, false, {
        knockbackDirX: dirX,
        knockbackDirY: dirY,
        knockbackForce: 320,
        isAbility: true,
      });
    }
    spawnEmberBurstVfx(this.particles, player.x, player.y, radius);
    this.camera.addShake(11, 0.3);
    this.hitStop.trigger(0.06, 0.05);
    playSfx('abilityEmberBurst');
  }

  wardingSigilTick(player: Player, enemies: Enemy[], dt: number): void {
    if (!player.wardingSigilActive) return;
    const sigil = player.wardingSigilActive;
    const radius = 90 * player.stats.areaDamageMult;
    const dps = 14 * player.stats.abilityDamageMult * player.stats.emberPower;
    for (const enemy of enemies) {
      if (!enemy.alive) continue;
      const dist = Math.hypot(enemy.x - sigil.x, enemy.y - sigil.y);
      if (dist > radius + enemy.radius) continue;
      this.damagePlayerToEnemy(player, enemy, dps * dt, false, { isAbility: true, silent: true, sourceX: sigil.x, sourceY: sigil.y });
    }
    player.heal(4 * dt);
  }

  // ---------------------------------------------------------------- Core damage pipeline
  damagePlayerToEnemy(player: Player, enemy: Enemy, baseDamage: number, crit: boolean, opts: DamageOptions = {}): void {
    let dmg = baseDamage * (crit ? player.stats.critDamage : 1);
    const ashFireActive = player.hasSynergy('ashFire') && !!enemy.burn;
    if (ashFireActive) dmg *= 1.4;

    // Warden shield: hits arriving inside the frontal arc are mostly turned
    // aside — no knockback, no stagger, no burn — and say so loudly, so the
    // player learns to flank or wait for the guard to drop.
    let blocked = false;
    if (enemy.shieldUp) {
      const sx = opts.sourceX ?? player.x;
      const sy = opts.sourceY ?? player.y;
      const toSource = Math.atan2(sy - enemy.y, sx - enemy.x);
      blocked = Math.abs(angleDiff(enemy.facing, toSource)) <= (enemy.def.shieldArc ?? 1.1);
    }
    if (blocked) dmg *= SHIELD_DAMAGE_FACTOR;
    dmg = Math.max(1, dmg);

    enemy.takeDamage(dmg);
    this.onDamageDealtToEnemy?.(dmg);
    if (opts.knockbackForce && !blocked) {
      enemy.applyKnockback(opts.knockbackDirX ?? 0, opts.knockbackDirY ?? 0, opts.knockbackForce);
    }
    if (crit && !blocked && enemy.alive && enemy.state === 'windup' && !enemy.def.isElite) {
      enemy.setState('stagger');
    }

    if (player.stats.lifesteal > 0) player.heal(dmg * player.stats.lifesteal);
    if (!blocked && Math.random() < player.stats.burnChance) enemy.applyBurn(Math.max(2, dmg * 0.16), 3, crit);

    if (!opts.silent) {
      if (blocked) {
        this.damageNumbers.push(createDamageNumber(enemy.x, enemy.y - enemy.radius, Math.round(dmg).toString(), '#8f8a9e', 12));
        spawnShieldSparks(this.particles, enemy.x + Math.cos(enemy.facing) * enemy.radius * 0.9, enemy.y + Math.sin(enemy.facing) * enemy.radius * 0.9, enemy.facing);
        playSfx('shieldClang', { throttleMs: 50 });
      } else {
        this.damageNumbers.push(
          createDamageNumber(enemy.x, enemy.y - enemy.radius, Math.round(dmg).toString(), crit ? Palette.ember6 : '#f4ecdd', crit ? 20 : 15)
        );
        spawnHitImpact(this.particles, enemy.x, enemy.y, enemy.def.accentColor, crit);
        playSfx(crit ? 'impactCrit' : 'impactLight', { throttleMs: 20 });
        if (crit) {
          gameEvents.emit('critHit', { x: enemy.x, y: enemy.y });
          this.camera.addShake(NORMAL_SHAKE + CRIT_SHAKE_BONUS, 0.15);
          this.hitStop.trigger(0.045, 0.08);
        }
        if (enemy.def.isElite) this.camera.addShake(2, 0.08);
      }
    }

    if (crit && !blocked && player.hasSynergy('emberCritical') && Math.random() < 0.35) {
      this.triggerEmberDetonation(enemy.x, enemy.y);
    }

    if (!enemy.alive) {
      this.onEnemyDeath(player, enemy);
    }
  }

  private triggerEmberDetonation(x: number, y: number): void {
    spawnEmberBurstVfx(this.particles, x, y, 70);
    playSfx('impactCrit', { throttleMs: 0 });
  }

  /** Centralizes the loot/VFX/SFX/stats/event fallout of an enemy dying, however it
   * died (direct hit here, or a damage-over-time tick discovered in Game's update
   * loop) — every death must go through this exactly once. */
  onEnemyDeath(player: Player, enemy: Enemy): void {
    if (enemy.deathHandled) return;
    enemy.deathHandled = true;
    spawnDeathBurst(this.particles, enemy.x, enemy.y, enemy.def.accentColor);
    playSfx(enemy.def.isElite ? 'eliteDeath' : 'enemyDeath');
    // A bloat killed before it could swell still ruptures — a smaller, shorter
    // cloud, but right where it died. Killing it is the right call; killing it
    // where you want to stand is not.
    if (enemy.def.behavior === 'bloat' && !enemy.burstDetonated) {
      const radius = (enemy.def.cloudRadius ?? 80) * 0.7;
      this.spawnSporeCloud(enemy.x, enemy.y, radius, (enemy.def.cloudDuration ?? 5) * 0.7, 4 * enemy.difficultyDamageMult);
      spawnSporeBurstVfx(this.particles, enemy.x, enemy.y, radius * 0.8);
      playSfx('sporeHiss', { throttleMs: 40 });
    }
    if (enemy.def.isElite) {
      this.camera.addShake(ELITE_SHAKE, 0.35);
      this.hitStop.trigger(0.08, 0.04);
    }
    const lightHealing = player.hasSynergy('lightHealing') && (!!enemy.burn || enemy.def.isElite);
    gameEvents.emit('enemyKilled', { enemy, x: enemy.x, y: enemy.y, wasElite: !!enemy.def.isElite });
    if (lightHealing && Math.random() < 0.4) {
      player.heal(player.stats.maxHp * 0.06);
      gameEvents.emit('playerHealed', { amount: player.stats.maxHp * 0.06 });
    }
  }

  damageEnemyToPlayer(player: Player, baseDamage: number, opts: DamageOptions = {}): boolean {
    const wasDodging = player.isDodging;
    const result = player.takeDamage(baseDamage);
    if (result.blocked) {
      if (wasDodging) {
        player.triggerPerfectDodge();
        spawnPerfectDodgeBurst(this.particles, player.x, player.y);
        playSfx('perfectDodge');
      } else if (result.shieldConsumed) playSfx('shieldBreak');
      return false;
    }
    if (opts.knockbackForce) {
      player.vx += (opts.knockbackDirX ?? 0) * opts.knockbackForce;
      player.vy += (opts.knockbackDirY ?? 0) * opts.knockbackForce;
    }
    if (opts.hazard) {
      // A cloud tick is pressure, not a blow: quieter, greener, no big shake.
      this.damageNumbers.push(createDamageNumber(player.x, player.y - player.radius, Math.round(result.taken).toString(), Palette.fungusBright, 13));
      spawnSporeMote(this.particles, player.x, player.y - 6);
      playSfx('sporeHiss', { throttleMs: 200 });
      this.camera.addShake(2.5, 0.12);
    } else {
      this.damageNumbers.push(createDamageNumber(player.x, player.y - player.radius, Math.round(result.taken).toString(), Palette.bloodBright, 16));
      spawnHitImpact(this.particles, player.x, player.y, Palette.bloodBright, false);
      playSfx('playerHurt');
      this.camera.addShake(7, 0.2);
    }
    this.onDamageDealtToPlayer?.(result.taken);
    gameEvents.emit('playerDamaged', { amount: result.taken });
    if (!player.alive) {
      playSfx('playerDeath');
      gameEvents.emit('playerDied', {});
    }
    return true;
  }

  private rollCrit(chance: number): boolean {
    return Math.random() < clamp(chance, 0, 0.95);
  }

  update(dt: number): void {
    updateDamageNumbers(this.damageNumbers, dt);
  }
}

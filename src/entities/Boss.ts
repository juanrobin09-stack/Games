import { Enemy } from '@/entities/Enemy';
import { getEnemyDefinition } from '@/data/enemies';
import type { AABB } from '@/utils/Collision';

export type BossPhase = 1 | 2 | 3;

export type BossState =
  | 'intro'
  | 'idle'
  | 'telegraphSlam'
  | 'telegraphCombo'
  | 'telegraphShockwave'
  | 'telegraphProjectile'
  | 'summoning'
  | 'recover'
  | 'phaseTransition'
  | 'dying';

export interface MeteorTarget {
  x: number;
  y: number;
  timer: number;
  duration: number;
  resolved: boolean;
}

const PHASE_THRESHOLDS = [0.64, 0.3];

/** Boss body reuses Enemy for physics/rendering plumbing; all fight-specific
 * logic (phases, attack selection, meteor rain) lives here as declarative
 * "pending" flags that BossSystem resolves into damage/VFX/SFX each frame. */
export class Boss extends Enemy {
  phase: BossPhase = 1;
  bossState: BossState = 'intro';
  bossStateTimer = 0;
  attackChoiceCooldown = 1.4;
  invulnerable = true;
  comboStep = 0;
  meteorTargets: MeteorTarget[] = [];
  meteorSpawnTimer = 4;
  deathAnimationDone = false;
  deathHandled = false;
  introDone = false;
  rageGlow = 0;

  pendingMeleeSlam = false;
  pendingShockwave = false;
  pendingProjectileAngles: number[] = [];
  pendingSummonCount = 0;
  pendingMeteorImpacts: { x: number; y: number }[] = [];
  phaseJustChanged = false;
  introJustStarted = true;

  constructor(x: number, y: number, hpMult: number, damageMult: number) {
    super(getEnemyDefinition('ashenColossus'), x, y, hpMult, damageMult);
  }

  get moveSpeedForPhase(): number {
    const factor = this.phase === 1 ? 1 : this.phase === 2 ? 1.3 : 1.55;
    return this.def.moveSpeed * factor;
  }

  beginFight(): void {
    this.introDone = true;
    this.enterState('idle');
    this.invulnerable = false;
  }

  private enterState(state: BossState): void {
    this.bossState = state;
    this.bossStateTimer = 0;
    // Only reset on a fresh entry from chooseNextAttack — the mid-combo continuation
    // (see the 'telegraphCombo' case) advances comboStep without calling enterState,
    // so an interrupted combo (e.g. a phase transition) can't leave a stale step behind.
    if (state === 'telegraphCombo') this.comboStep = 0;
  }

  private hpRatio(): number {
    return this.hp / this.maxHp;
  }

  override takeDamage(amount: number): void {
    if (this.invulnerable) return;
    super.takeDamage(amount);
  }

  tick(dt: number, player: { x: number; y: number }, bounds: AABB): void {
    super.update(dt);
    if (!this.alive && this.bossState !== 'dying') {
      this.enterState('dying');
      this.hp = 0;
    }

    this.bossStateTimer += dt;
    this.rageGlow = this.phase === 1 ? 0 : this.phase === 2 ? 0.5 : 1;

    if (this.bossState === 'dying') {
      if (this.bossStateTimer >= 2.2) this.deathAnimationDone = true;
      this.vx = 0;
      this.vy = 0;
      return;
    }

    if (!this.introDone) return;

    if (this.bossState !== 'phaseTransition' && this.phase < 3) {
      const nextThreshold = PHASE_THRESHOLDS[this.phase - 1];
      if (this.hpRatio() <= nextThreshold) {
        this.enterState('phaseTransition');
        this.invulnerable = true;
      }
    }

    const dx = player.x - this.x;
    const dy = player.y - this.y;
    const dist = Math.hypot(dx, dy);
    if (dist > 0.01) this.facing = Math.atan2(dy, dx);

    if (this.phase === 3) {
      this.updateMeteors(dt, player, bounds);
    }

    switch (this.bossState) {
      case 'idle': {
        const preferred = this.phase === 1 ? 160 : 120;
        if (dist > preferred + 20) {
          this.vx = (dx / dist) * this.moveSpeedForPhase;
          this.vy = (dy / dist) * this.moveSpeedForPhase;
        } else if (dist < preferred - 40) {
          this.vx = -(dx / dist) * this.moveSpeedForPhase * 0.6;
          this.vy = -(dy / dist) * this.moveSpeedForPhase * 0.6;
        } else {
          this.vx *= 0.8;
          this.vy *= 0.8;
        }
        this.attackChoiceCooldown -= dt;
        if (this.attackChoiceCooldown <= 0) this.chooseNextAttack(dist);
        break;
      }
      case 'telegraphSlam':
        this.vx = 0;
        this.vy = 0;
        if (this.bossStateTimer >= this.def.telegraphTime) {
          this.pendingMeleeSlam = true;
          this.enterState('recover');
        }
        break;
      case 'telegraphCombo':
        this.vx = 0;
        this.vy = 0;
        if (this.bossStateTimer >= this.def.telegraphTime * 0.75) {
          this.pendingMeleeSlam = true;
          this.comboStep++;
          if (this.comboStep >= 2) {
            this.comboStep = 0;
            this.enterState('recover');
          } else {
            this.bossStateTimer = 0;
          }
        }
        break;
      case 'telegraphShockwave':
        this.vx = 0;
        this.vy = 0;
        if (this.bossStateTimer >= this.def.telegraphTime * 1.3) {
          this.pendingShockwave = true;
          this.enterState('recover');
        }
        break;
      case 'telegraphProjectile':
        this.vx = 0;
        this.vy = 0;
        if (this.bossStateTimer >= this.def.telegraphTime) {
          const base = Math.atan2(dy, dx);
          this.pendingProjectileAngles.push(base - 0.22, base, base + 0.22);
          this.enterState('recover');
        }
        break;
      case 'summoning':
        this.vx = 0;
        this.vy = 0;
        if (this.bossStateTimer >= 0.6) {
          this.pendingSummonCount = this.phase >= 3 ? 3 : 2;
          this.enterState('recover');
        }
        break;
      case 'recover':
        if (this.bossStateTimer >= 0.55) {
          this.attackChoiceCooldown = this.phase === 3 ? 0.9 : 1.3;
          this.enterState('idle');
        }
        break;
      case 'phaseTransition':
        this.vx = 0;
        this.vy = 0;
        if (this.bossStateTimer >= 1.3) {
          this.phase = (this.phase + 1) as BossPhase;
          this.invulnerable = false;
          this.phaseJustChanged = true;
          if (this.phase === 2) this.pendingSummonCount = 2;
          this.enterState('idle');
          this.attackChoiceCooldown = 1.6;
        }
        break;
    }
  }

  private chooseNextAttack(dist: number): void {
    const roll = Math.random();
    if (this.phase === 1) {
      this.enterState(dist < 150 ? 'telegraphSlam' : 'telegraphProjectile');
      return;
    }
    if (this.phase === 2) {
      if (roll < 0.22) {
        this.enterState('summoning');
      } else if (dist < 160) {
        this.enterState(roll < 0.65 ? 'telegraphShockwave' : 'telegraphSlam');
      } else {
        this.enterState('telegraphProjectile');
      }
      return;
    }
    if (roll < 0.18) {
      this.enterState('summoning');
    } else if (roll < 0.42) {
      this.enterState('telegraphCombo');
    } else if (dist < 170) {
      this.enterState(roll < 0.75 ? 'telegraphShockwave' : 'telegraphSlam');
    } else {
      this.enterState('telegraphProjectile');
    }
  }

  private updateMeteors(dt: number, player: { x: number; y: number }, bounds: AABB): void {
    this.meteorSpawnTimer -= dt;
    if (this.meteorSpawnTimer <= 0 && this.meteorTargets.length < 2) {
      this.meteorSpawnTimer = 3.4;
      const margin = 90;
      const angle = Math.random() * Math.PI * 2;
      const dist = 40 + Math.random() * 160;
      const x = Math.min(Math.max(player.x + Math.cos(angle) * dist, bounds.x + margin), bounds.x + bounds.width - margin);
      const y = Math.min(Math.max(player.y + Math.sin(angle) * dist, bounds.y + margin), bounds.y + bounds.height - margin);
      this.meteorTargets.push({ x, y, timer: 0, duration: 1.5, resolved: false });
    }
    for (const meteor of this.meteorTargets) {
      if (meteor.resolved) continue;
      meteor.timer += dt;
      if (meteor.timer >= meteor.duration) {
        meteor.resolved = true;
        this.pendingMeteorImpacts.push({ x: meteor.x, y: meteor.y });
      }
    }
    this.meteorTargets = this.meteorTargets.filter((m) => !m.resolved);
  }
}

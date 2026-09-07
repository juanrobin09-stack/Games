import { nextEntityId } from '@/entities/EntityId';
import type { EnemyDefinition } from '@/data/types';

export type EnemyState =
  | 'spawning'
  | 'idle'
  | 'chase'
  | 'windup'
  | 'attack'
  | 'cooldown'
  | 'vanished'
  | 'reappearing'
  | 'stagger'
  | 'dead';

export interface BurnStatus {
  timer: number;
  tickTimer: number;
  dps: number;
  sourceCrit: boolean;
}

export class Enemy {
  readonly id = nextEntityId();
  def: EnemyDefinition;
  x = 0;
  y = 0;
  vx = 0;
  vy = 0;
  knockbackVx = 0;
  knockbackVy = 0;
  radius: number;
  facing = 0;

  hp: number;
  maxHp: number;
  alive = true;
  deathTimer = 0;

  state: EnemyState = 'spawning';
  stateTimer = 0;
  attackCooldownTimer = 0;
  contactCooldownTimer = 0;
  hitFlashTimer = 0;
  animPhase = Math.random() * 10;

  burn: BurnStatus | null = null;
  vanishAlpha = 1;

  difficultyHpMult: number;
  difficultyDamageMult: number;
  isEliteInstance = false;
  displayName: string | null = null;

  lastPlayerX = 0;
  lastPlayerY = 0;

  constructor(def: EnemyDefinition, x: number, y: number, hpMult: number, damageMult: number) {
    this.def = def;
    this.x = x;
    this.y = y;
    this.radius = def.radius;
    this.difficultyHpMult = hpMult;
    this.difficultyDamageMult = damageMult;
    this.maxHp = Math.round(def.baseHp * hpMult);
    this.hp = this.maxHp;
    this.attackCooldownTimer = def.attackCooldown * (0.4 + Math.random() * 0.4);
    this.stateTimer = 0.15 + Math.random() * 0.2;
  }

  get contactDamage(): number {
    return this.def.contactDamage * this.difficultyDamageMult;
  }

  get attackDamage(): number {
    return this.def.baseDamage * this.difficultyDamageMult;
  }

  setState(state: EnemyState): void {
    this.state = state;
    this.stateTimer = 0;
  }

  applyBurn(dps: number, duration: number, isCrit: boolean): void {
    if (this.burn && this.burn.dps >= dps) {
      this.burn.timer = Math.max(this.burn.timer, duration);
      return;
    }
    this.burn = { timer: duration, tickTimer: 0, dps, sourceCrit: isCrit };
  }

  takeDamage(amount: number): void {
    if (!this.alive) return;
    this.hp -= amount;
    this.hitFlashTimer = 0.16;
    if (this.hp <= 0) {
      this.hp = 0;
      this.alive = false;
      this.setState('dead');
    }
  }

  applyKnockback(dirX: number, dirY: number, force: number): void {
    this.knockbackVx += dirX * force;
    this.knockbackVy += dirY * force;
  }

  update(dt: number): void {
    this.stateTimer += dt;
    this.animPhase += dt;
    if (this.hitFlashTimer > 0) this.hitFlashTimer -= dt;

    if (!this.alive) {
      this.deathTimer += dt;
      return;
    }

    if (this.attackCooldownTimer > 0) this.attackCooldownTimer -= dt;
    if (this.contactCooldownTimer > 0) this.contactCooldownTimer -= dt;

    this.knockbackVx *= Math.max(0, 1 - 8 * dt);
    this.knockbackVy *= Math.max(0, 1 - 8 * dt);

    if (this.burn) {
      this.burn.timer -= dt;
      this.burn.tickTimer -= dt;
      if (this.burn.tickTimer <= 0) {
        this.burn.tickTimer += 0.5;
        this.takeDamage(this.burn.dps * 0.5);
      }
      if (this.burn.timer <= 0 || !this.alive) this.burn = null;
    }

    if (this.state === 'vanished') {
      this.vanishAlpha = Math.max(0.12, this.vanishAlpha - dt * 4);
    } else if (this.state === 'reappearing') {
      this.vanishAlpha = Math.min(1, this.vanishAlpha + dt * 5);
    } else {
      this.vanishAlpha = 1;
    }

    this.x += (this.vx + this.knockbackVx) * dt;
    this.y += (this.vy + this.knockbackVy) * dt;
  }
}

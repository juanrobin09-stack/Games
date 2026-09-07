import { nextEntityId } from '@/entities/EntityId';

export type ProjectileVisual = 'solarBolt' | 'emberBolt' | 'shadowBolt' | 'voidOrb';

export interface ProjectileOptions {
  x: number;
  y: number;
  angle: number;
  speed: number;
  damage: number;
  radius: number;
  fromPlayer: boolean;
  pierce: number;
  knockback: number;
  critChance: number;
  critDamageMult: number;
  burnChance: number;
  lifesteal: number;
  visual: ProjectileVisual;
  maxLifetime?: number;
  homing?: boolean;
}

export class Projectile {
  readonly id = nextEntityId();
  x: number;
  y: number;
  vx: number;
  vy: number;
  angle: number;
  speed: number;
  radius: number;
  damage: number;
  fromPlayer: boolean;
  pierce: number;
  knockback: number;
  critChance: number;
  critDamageMult: number;
  burnChance: number;
  lifesteal: number;
  visual: ProjectileVisual;
  alive = true;
  age = 0;
  maxLifetime: number;
  hitIds = new Set<number>();
  trailTimer = 0;

  constructor(opts: ProjectileOptions) {
    this.x = opts.x;
    this.y = opts.y;
    this.angle = opts.angle;
    this.speed = opts.speed;
    this.vx = Math.cos(opts.angle) * opts.speed;
    this.vy = Math.sin(opts.angle) * opts.speed;
    this.radius = opts.radius;
    this.damage = opts.damage;
    this.fromPlayer = opts.fromPlayer;
    this.pierce = opts.pierce;
    this.knockback = opts.knockback;
    this.critChance = opts.critChance;
    this.critDamageMult = opts.critDamageMult;
    this.burnChance = opts.burnChance;
    this.lifesteal = opts.lifesteal;
    this.visual = opts.visual;
    this.maxLifetime = opts.maxLifetime ?? 2.4;
  }

  update(dt: number): void {
    this.age += dt;
    this.x += this.vx * dt;
    this.y += this.vy * dt;
    this.trailTimer -= dt;
    if (this.age >= this.maxLifetime) this.alive = false;
  }

  registerHit(targetId: number): boolean {
    if (this.hitIds.has(targetId)) return false;
    this.hitIds.add(targetId);
    if (this.hitIds.size > this.pierce) this.alive = false;
    return true;
  }
}

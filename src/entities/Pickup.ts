import { nextEntityId } from '@/entities/EntityId';

export type PickupKind = 'ember' | 'heart';

export class Pickup {
  readonly id = nextEntityId();
  kind: PickupKind;
  x: number;
  y: number;
  value: number;
  radius = 8;
  alive = true;
  age = 0;
  bobPhase = Math.random() * 10;
  vx: number;
  vy: number;
  settleTimer = 0.25;
  magnetSpeed = 0;

  constructor(kind: PickupKind, x: number, y: number, value: number, popAngle = Math.random() * Math.PI * 2) {
    this.kind = kind;
    this.x = x;
    this.y = y;
    this.value = value;
    this.vx = Math.cos(popAngle) * 90;
    this.vy = Math.sin(popAngle) * 90;
  }

  /** Returns true the frame it reaches the target and should be collected. */
  update(dt: number, targetX: number, targetY: number, pickupRange: number): boolean {
    this.age += dt;
    this.bobPhase += dt;

    if (this.settleTimer > 0) {
      this.settleTimer -= dt;
      this.x += this.vx * dt;
      this.y += this.vy * dt;
      this.vx *= Math.max(0, 1 - 6 * dt);
      this.vy *= Math.max(0, 1 - 6 * dt);
      return false;
    }

    const dx = targetX - this.x;
    const dy = targetY - this.y;
    const dist = Math.hypot(dx, dy);
    if (dist < pickupRange) {
      this.magnetSpeed = Math.min(760, this.magnetSpeed + 1400 * dt);
      const nx = dx / Math.max(0.001, dist);
      const ny = dy / Math.max(0.001, dist);
      this.x += nx * this.magnetSpeed * dt;
      this.y += ny * this.magnetSpeed * dt;
      if (dist < 14) return true;
    } else {
      this.magnetSpeed = 0;
    }
    return false;
  }
}

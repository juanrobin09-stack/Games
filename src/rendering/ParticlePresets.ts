import type { ParticleSystem } from '@/rendering/ParticleSystem';
import { Palette } from '@/rendering/Palette';

const rand = (min: number, max: number) => min + Math.random() * (max - min);

export function spawnHitImpact(ps: ParticleSystem, x: number, y: number, color: string, crit: boolean): void {
  const count = crit ? 14 : 8;
  ps.burst(count, () => {
    const angle = rand(0, Math.PI * 2);
    const speed = rand(60, crit ? 320 : 200);
    return {
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      gravity: 260,
      drag: 2.2,
      size: rand(2, crit ? 5 : 3.4),
      color,
      endColor: Palette.bg0,
      life: rand(0.25, 0.5),
      glow: true,
      shape: 'spark',
    };
  });
  ps.spawn({
    x,
    y,
    size: crit ? 22 : 14,
    endSize: crit ? 60 : 32,
    color: Palette.ember6,
    alpha: 0.55,
    endAlpha: 0,
    life: 0.22,
    glow: true,
    shape: 'ring',
  });
}

export function spawnBloodlessDust(ps: ParticleSystem, x: number, y: number): void {
  ps.burst(5, () => ({
    x: x + rand(-4, 4),
    y: y + rand(-4, 4),
    vx: rand(-40, 40),
    vy: rand(-60, -10),
    gravity: 120,
    drag: 1.8,
    size: rand(2, 4),
    color: Palette.bg3,
    endColor: Palette.bg0,
    alpha: 0.7,
    life: rand(0.3, 0.55),
    shape: 'circle',
  }));
}

export function spawnDeathBurst(ps: ParticleSystem, x: number, y: number, color: string): void {
  ps.burst(22, () => {
    const angle = rand(0, Math.PI * 2);
    const speed = rand(40, 260);
    return {
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      gravity: 200,
      drag: 1.6,
      size: rand(2, 6),
      color,
      endColor: Palette.bg0,
      life: rand(0.4, 0.9),
      glow: true,
      shape: Math.random() > 0.5 ? 'spark' : 'circle',
    };
  });
  ps.spawn({
    x,
    y,
    size: 10,
    endSize: 70,
    color,
    alpha: 0.6,
    endAlpha: 0,
    life: 0.4,
    glow: true,
    shape: 'ring',
  });
}

export function spawnEmberBurstVfx(ps: ParticleSystem, x: number, y: number, radius: number): void {
  ps.burst(36, () => {
    const angle = rand(0, Math.PI * 2);
    const speed = rand(radius * 1.5, radius * 3.2);
    return {
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      gravity: -20,
      drag: 1.4,
      size: rand(3, 8),
      color: Palette.ember5,
      endColor: Palette.ember2,
      life: rand(0.4, 0.85),
      glow: true,
      shape: 'spark',
    };
  });
  for (let i = 0; i < 3; i++) {
    ps.spawn({
      x,
      y,
      size: radius * 0.3,
      endSize: radius * (1.6 + i * 0.4),
      color: Palette.ember4,
      alpha: 0.5 - i * 0.1,
      endAlpha: 0,
      life: 0.35 + i * 0.12,
      glow: true,
      shape: 'ring',
    });
  }
}

export function spawnFireFlicker(ps: ParticleSystem, x: number, y: number, scale = 1): void {
  ps.spawn({
    x: x + rand(-2, 2) * scale,
    y,
    vx: rand(-6, 6) * scale,
    vy: rand(-50, -25) * scale,
    gravity: -30,
    drag: 1,
    size: rand(3, 6) * scale,
    endSize: 1,
    color: Palette.ember5,
    endColor: Palette.ember1,
    alpha: 0.9,
    life: rand(0.35, 0.7),
    glow: true,
    shape: 'circle',
  });
}

export function spawnSmoke(ps: ParticleSystem, x: number, y: number, scale = 1): void {
  ps.spawn({
    x: x + rand(-4, 4),
    y,
    vx: rand(-8, 8),
    vy: rand(-30, -14) * scale,
    gravity: 0,
    drag: 0.6,
    size: rand(6, 10) * scale,
    endSize: rand(16, 26) * scale,
    color: '#3a3540',
    endColor: '#14121a',
    alpha: 0.35,
    endAlpha: 0,
    life: rand(0.9, 1.6),
    shape: 'circle',
  });
}

export function spawnMagicSparkle(ps: ParticleSystem, x: number, y: number, color: string): void {
  ps.spawn({
    x: x + rand(-10, 10),
    y: y + rand(-10, 10),
    vx: rand(-14, 14),
    vy: rand(-30, -10),
    gravity: 10,
    drag: 1.2,
    size: rand(1.5, 3),
    color,
    endColor: Palette.bg1,
    alpha: 0.9,
    life: rand(0.4, 0.8),
    glow: true,
    shape: 'circle',
  });
}

export function spawnHealSparkle(ps: ParticleSystem, x: number, y: number): void {
  ps.burst(10, () => ({
    x: x + rand(-14, 14),
    y: y + rand(-6, 6),
    vx: rand(-10, 10),
    vy: rand(-70, -30),
    gravity: 40,
    drag: 1,
    size: rand(2, 4),
    color: Palette.toxic,
    endColor: '#dff7d0',
    alpha: 0.9,
    life: rand(0.5, 0.9),
    glow: true,
    shape: 'circle',
  }));
}

export function spawnPickupTrail(ps: ParticleSystem, x: number, y: number, color: string): void {
  ps.spawn({
    x,
    y,
    size: rand(2, 3.5),
    endSize: 0.5,
    color,
    endColor: Palette.bg0,
    alpha: 0.8,
    life: 0.3,
    glow: true,
    shape: 'circle',
  });
}

export function spawnDodgeTrail(ps: ParticleSystem, x: number, y: number, angle: number, color: string): void {
  ps.spawn({
    x,
    y,
    vx: Math.cos(angle + Math.PI) * 20,
    vy: Math.sin(angle + Math.PI) * 20,
    size: 10,
    endSize: 2,
    color,
    endColor: Palette.bg1,
    alpha: 0.5,
    life: 0.25,
    glow: true,
    shape: 'circle',
  });
}

export function spawnChestOpenBurst(ps: ParticleSystem, x: number, y: number, color: string): void {
  ps.burst(26, () => {
    const angle = rand(-Math.PI, 0);
    const speed = rand(80, 260);
    return {
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      gravity: 320,
      drag: 1,
      size: rand(2, 5),
      color,
      endColor: Palette.ember6,
      life: rand(0.5, 1),
      glow: true,
      shape: 'spark',
    };
  });
}

export function spawnLevelUpBurst(ps: ParticleSystem, x: number, y: number): void {
  ps.burst(30, (i) => {
    const angle = (i / 30) * Math.PI * 2;
    const speed = rand(80, 160);
    return {
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      gravity: -40,
      drag: 1.6,
      size: rand(2, 4),
      color: Palette.goldBright,
      endColor: Palette.ember3,
      life: rand(0.5, 0.9),
      glow: true,
      shape: 'spark',
    };
  });
}

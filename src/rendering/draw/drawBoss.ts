import type { Boss } from '@/entities/Boss';
import { Palette, rgba, mixColor } from '@/rendering/Palette';
import { drawSoftShadow, drawGlowCircle } from '@/rendering/DrawUtils';
import { clamp, easeOutCubic } from '@/utils/MathUtils';
import type { Camera } from '@/core/Camera';
import type { MeteorTarget } from '@/entities/Boss';

export function drawBoss(ctx: CanvasRenderingContext2D, boss: Boss, screenX: number, screenY: number): void {
  const r = boss.radius;
  const dying = boss.bossState === 'dying';
  const deathT = dying ? clamp(boss.bossStateTimer / 2.2, 0, 1) : 0;

  ctx.save();
  ctx.translate(screenX, screenY);

  drawSoftShadow(ctx, 0, r * 0.7, r * 1.3, r * 0.5, 0.55);

  if (boss.bossState === 'telegraphSlam' || boss.bossState === 'telegraphCombo') {
    const t = boss.bossStateTimer / boss.def.telegraphTime;
    ctx.globalAlpha = 0.5 * t;
    ctx.strokeStyle = Palette.bloodBright;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(Math.cos(boss.facing) * 60, Math.sin(boss.facing) * 60, 130 * t, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }
  if (boss.bossState === 'telegraphShockwave') {
    const t = Math.min(1, boss.bossStateTimer / (boss.def.telegraphTime * 1.3));
    ctx.globalAlpha = 0.4 + 0.3 * Math.sin(t * 20);
    ctx.strokeStyle = Palette.ember4;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(0, 0, 230 * t, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  if (dying) {
    ctx.globalAlpha = Math.max(0, 1 - deathT);
    ctx.scale(1 - deathT * 0.3, 1 - deathT * 0.5);
    ctx.translate(0, deathT * 30);
  }

  if (boss.invulnerable && boss.introDone) {
    drawGlowCircle(ctx, 0, 0, r * 1.6, Palette.soulBright, 0.35 + Math.sin(boss.bossStateTimer * 10) * 0.15);
  }

  const rage = boss.rageGlow;
  drawGlowCircle(ctx, 0, r * 0.1, r * 1.4, mixColor(Palette.ember3, Palette.bloodBright, rage), 0.28 + rage * 0.2);

  const bodyGrad = ctx.createLinearGradient(-r, -r, r, r * 0.6);
  bodyGrad.addColorStop(0, mixColor('#3a2c22', Palette.bloodBright, rage * 0.3));
  bodyGrad.addColorStop(1, Palette.ember1);
  ctx.fillStyle = bodyGrad;
  ctx.beginPath();
  ctx.moveTo(-r * 0.95, r * 0.7);
  ctx.lineTo(-r * 1.05, -r * 0.1);
  ctx.lineTo(-r * 0.55, -r * 0.95);
  ctx.lineTo(0, -r * 1.15);
  ctx.lineTo(r * 0.55, -r * 0.95);
  ctx.lineTo(r * 1.05, -r * 0.1);
  ctx.lineTo(r * 0.95, r * 0.7);
  ctx.quadraticCurveTo(0, r * 0.95, -r * 0.95, r * 0.7);
  ctx.closePath();
  ctx.fill();

  const crackPulse = 0.5 + Math.sin(boss.animPhase * (3 + rage * 4)) * 0.3 + rage * 0.3;
  ctx.strokeStyle = rgba(Palette.ember4, clamp(crackPulse, 0.2, 1));
  ctx.lineWidth = 2.4;
  ctx.shadowColor = Palette.ember4;
  ctx.shadowBlur = 8 + rage * 8;
  const cracks: [number, number, number, number][] = [
    [-r * 0.5, -r * 0.4, -r * 0.1, r * 0.3],
    [r * 0.1, -r * 0.8, r * 0.4, -r * 0.1],
    [-r * 0.2, r * 0.1, r * 0.25, r * 0.55],
    [r * 0.5, r * 0.1, r * 0.2, r * 0.6],
  ];
  for (const [x1, y1, x2, y2] of cracks) {
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo((x1 + x2) / 2 + 6, (y1 + y2) / 2);
    ctx.lineTo(x2, y2);
    ctx.stroke();
  }
  ctx.shadowBlur = 0;

  ctx.save();
  ctx.rotate(boss.facing * 0.12);
  const eyeGlow = boss.bossState === 'telegraphProjectile' ? 0.6 + Math.sin(boss.bossStateTimer * 18) * 0.4 : 0.55;
  ctx.fillStyle = Palette.ember6;
  ctx.shadowColor = Palette.ember5;
  ctx.shadowBlur = 10 * eyeGlow;
  ctx.beginPath();
  ctx.ellipse(-r * 0.22, -r * 0.75, 5, 3, 0, 0, Math.PI * 2);
  ctx.ellipse(r * 0.22, -r * 0.75, 5, 3, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.restore();

  const armSwing = boss.bossState === 'telegraphSlam' || boss.bossState === 'telegraphCombo' ? easeOutCubic(Math.min(1, boss.bossStateTimer / boss.def.telegraphTime)) : 0;
  ctx.save();
  ctx.translate(r * 0.9, -r * 0.2);
  ctx.rotate(-0.3 - armSwing * 0.8);
  ctx.fillStyle = Palette.ember1;
  ctx.fillRect(-14, 0, 28, r * 1.1);
  ctx.restore();
  ctx.save();
  ctx.translate(-r * 0.9, -r * 0.2);
  ctx.rotate(0.3 + armSwing * 0.8);
  ctx.fillStyle = Palette.ember1;
  ctx.fillRect(-14, 0, 28, r * 1.1);
  ctx.restore();

  ctx.restore();
}

export function drawMeteorTelegraph(ctx: CanvasRenderingContext2D, meteor: MeteorTarget, camera: Camera): void {
  const screen = camera.worldToScreen(meteor.x, meteor.y);
  const t = clamp(meteor.timer / meteor.duration, 0, 1);
  const radius = 70 * camera.zoom;

  ctx.save();
  ctx.translate(screen.x, screen.y);
  ctx.globalAlpha = 0.25 + t * 0.5;
  ctx.fillStyle = mixColor(Palette.ember5, Palette.bloodBright, t);
  ctx.beginPath();
  ctx.arc(0, 0, radius, 0, Math.PI * 2);
  ctx.fill();

  ctx.globalAlpha = 0.7;
  ctx.strokeStyle = mixColor(Palette.ember6, Palette.bloodBright, t);
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.arc(0, 0, radius * (1 - t) + 6, 0, Math.PI * 2);
  ctx.stroke();
  ctx.restore();
}

import type { Pickup } from '@/entities/Pickup';
import { Palette } from '@/rendering/Palette';
import { drawGlowCircle } from '@/rendering/DrawUtils';

export function drawPickup(ctx: CanvasRenderingContext2D, p: Pickup, screenX: number, screenY: number): void {
  const bob = Math.sin(p.bobPhase * 4) * 3;
  const color = p.kind === 'ember' ? Palette.ember4 : Palette.toxic;
  ctx.save();
  ctx.translate(screenX, screenY + bob);
  drawGlowCircle(ctx, 0, 0, p.radius * 2.4, color, 0.65);
  ctx.fillStyle = color;
  if (p.kind === 'ember') {
    ctx.beginPath();
    ctx.moveTo(0, -p.radius);
    ctx.lineTo(p.radius * 0.7, 0);
    ctx.lineTo(0, p.radius);
    ctx.lineTo(-p.radius * 0.7, 0);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = Palette.ember6;
    ctx.globalAlpha = 0.8;
    ctx.beginPath();
    ctx.arc(0, 0, p.radius * 0.35, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.beginPath();
    ctx.moveTo(0, p.radius * 0.8);
    ctx.bezierCurveTo(-p.radius, 0, -p.radius * 0.5, -p.radius, 0, -p.radius * 0.3);
    ctx.bezierCurveTo(p.radius * 0.5, -p.radius, p.radius, 0, 0, p.radius * 0.8);
    ctx.fill();
  }
  ctx.restore();
}

import type { Projectile } from '@/entities/Projectile';
import { Palette } from '@/rendering/Palette';
import { drawGlowCircle } from '@/rendering/DrawUtils';

const VISUAL_COLORS: Record<Projectile['visual'], { core: string; glow: string }> = {
  solarBolt: { core: Palette.ember6, glow: Palette.ember5 },
  emberBolt: { core: Palette.ember5, glow: Palette.ember3 },
  shadowBolt: { core: Palette.soulBright, glow: Palette.soul },
  voidOrb: { core: '#c4b0f0', glow: Palette.soulDim },
};

export function drawProjectile(ctx: CanvasRenderingContext2D, p: Projectile, screenX: number, screenY: number): void {
  const colors = VISUAL_COLORS[p.visual];
  ctx.save();
  ctx.translate(screenX, screenY);
  ctx.rotate(p.angle);

  drawGlowCircle(ctx, 0, 0, p.radius * 2.6, colors.glow, 0.75);

  ctx.fillStyle = colors.glow;
  ctx.globalAlpha = 0.55;
  ctx.beginPath();
  ctx.moveTo(-p.radius * 3.2, -p.radius * 0.5);
  ctx.lineTo(-p.radius * 0.6, 0);
  ctx.lineTo(-p.radius * 3.2, p.radius * 0.5);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = 1;

  ctx.fillStyle = colors.core;
  ctx.beginPath();
  ctx.arc(0, 0, p.radius, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}

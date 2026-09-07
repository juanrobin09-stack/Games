import type { Chest } from '@/entities/Chest';
import { RARITY_COLORS } from '@/data/types';
import { drawSoftShadow, drawGlowCircle, roundedRectPath } from '@/rendering/DrawUtils';
import { easeOutBack } from '@/utils/MathUtils';

export function drawChest(ctx: CanvasRenderingContext2D, chest: Chest, screenX: number, screenY: number): void {
  const color = RARITY_COLORS[chest.tier];
  const w = 34;
  const h = 24;
  const glowPulse = 0.6 + Math.sin(chest.glowPhase * 2) * 0.25;

  ctx.save();
  ctx.translate(screenX, screenY);
  drawSoftShadow(ctx, 0, h * 0.55, w * 0.7, h * 0.3, 0.45);
  drawGlowCircle(ctx, 0, -4, w * (chest.state === 'opened' ? 1.6 : 1.1) * glowPulse, color, chest.state === 'opened' ? 0.55 : 0.4);

  const lidOpen = chest.state === 'opening' ? easeOutBack(Math.min(1, chest.stateTimer / 0.5)) : chest.state === 'opened' ? 1 : 0;

  ctx.fillStyle = '#241a12';
  roundedRectPath(ctx, -w / 2, -h / 2, w, h, 4);
  ctx.fill();
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  roundedRectPath(ctx, -w / 2, -h / 2, w, h, 4);
  ctx.stroke();

  ctx.save();
  ctx.translate(-w / 2, -h / 2);
  ctx.rotate((-lidOpen * Math.PI) / 2.4);
  ctx.fillStyle = '#2e2118';
  roundedRectPath(ctx, 0, -8, w, 10, 3);
  ctx.fill();
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  roundedRectPath(ctx, 0, -8, w, 10, 3);
  ctx.stroke();
  ctx.restore();

  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(0, -h * 0.1, 2.4, 0, Math.PI * 2);
  ctx.fill();

  if (chest.state === 'opened') {
    ctx.globalAlpha = 0.5 + Math.sin(chest.glowPhase * 4) * 0.3;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(0, -h * 0.6 - 6, 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  ctx.restore();
}

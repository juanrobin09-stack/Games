import type { DamageNumber } from '@/combat/DamageNumber';
import type { Camera } from '@/core/Camera';
import { drawFloatingText } from '@/rendering/DrawUtils';

export function drawDamageNumbers(ctx: CanvasRenderingContext2D, numbers: DamageNumber[], camera: Camera): void {
  for (const n of numbers) {
    const screen = camera.worldToScreen(n.x, n.y);
    const t = n.age / n.life;
    const alpha = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
    drawFloatingText(ctx, n.text, screen.x, screen.y, n.size, n.color, Math.max(0, alpha));
  }
}

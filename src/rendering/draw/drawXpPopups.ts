import type { XpPopup } from '@/combat/XpPopup';
import type { Camera } from '@/core/Camera';
import { drawFloatingText } from '@/rendering/DrawUtils';

/** Same fade-in/fade-out curve as drawDamageNumbers: a quick fade-in over the
 * first 15% of life, then a gradual fade-out over the rest — never an
 * instant pop in or out. */
export function drawXpPopups(ctx: CanvasRenderingContext2D, popups: XpPopup[], camera: Camera): void {
  for (const p of popups) {
    const screen = camera.worldToScreen(p.x, p.y);
    const t = p.age / p.life;
    const alpha = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
    drawFloatingText(ctx, p.text, screen.x, screen.y, 14, '#ffffff', Math.max(0, alpha));
  }
}

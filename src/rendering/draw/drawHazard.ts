import type { Hazard } from '@/combat/CombatSystem';
import type { Camera } from '@/core/Camera';
import { Palette, rgba } from '@/rendering/Palette';
import { hashJitter } from '@/rendering/DrawUtils';

/**
 * Spore clouds: a few soft, slowly-drifting teal blobs with a darker heart
 * and a faint rim, so the danger zone's edge is readable at a glance from a
 * top-down camera. Fades in over its first third of a second and out over
 * its last 0.8s, so it never pops into or out of existence.
 */
export function drawHazards(ctx: CanvasRenderingContext2D, hazards: Hazard[], camera: Camera, time: number): void {
  if (hazards.length === 0) return;
  const zoom = camera.zoom;
  ctx.save();
  for (const h of hazards) {
    const s = camera.worldToScreen(h.x, h.y);
    const fadeIn = Math.min(1, h.timer / 0.3);
    const fadeOut = Math.min(1, Math.max(0, (h.duration - h.timer) / 0.8));
    const alpha = fadeIn * fadeOut;
    if (alpha <= 0.01) continue;
    const r = h.radius * zoom * (0.85 + fadeIn * 0.15);

    ctx.globalCompositeOperation = 'source-over';
    // Body: three offset lobes breathing around the centre.
    for (let i = 0; i < 3; i++) {
      const phase = time * 0.7 + h.seed + i * 2.1;
      const ox = Math.cos(phase) * r * 0.18;
      const oy = Math.sin(phase * 1.3) * r * 0.14;
      const lr = r * (0.72 + hashJitter(h.seed, i) * 0.2);
      const grad = ctx.createRadialGradient(s.x + ox, s.y + oy, 0, s.x + ox, s.y + oy, lr);
      grad.addColorStop(0, rgba(Palette.fungusDim, 0.55 * alpha));
      grad.addColorStop(0.55, rgba(Palette.fungus, 0.3 * alpha));
      grad.addColorStop(1, rgba(Palette.fungus, 0));
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(s.x + ox, s.y + oy, lr, 0, Math.PI * 2);
      ctx.fill();
    }
    // Dark heart — the thick of it.
    const core = ctx.createRadialGradient(s.x, s.y, 0, s.x, s.y, r * 0.5);
    core.addColorStop(0, `rgba(10,30,26,${0.35 * alpha})`);
    core.addColorStop(1, 'rgba(10,30,26,0)');
    ctx.fillStyle = core;
    ctx.beginPath();
    ctx.arc(s.x, s.y, r * 0.5, 0, Math.PI * 2);
    ctx.fill();
    // Rim: the actual damage boundary, pulsing gently — drawn additive so it
    // stays legible even under the darkness overlay.
    const pulse = 0.75 + Math.sin(time * 3 + h.seed) * 0.25;
    ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = rgba(Palette.fungusBright, 0.5 * alpha * pulse);
    ctx.lineWidth = Math.max(1.5, 2.2 * zoom);
    ctx.setLineDash([7 * zoom, 5 * zoom]);
    ctx.lineDashOffset = -time * 24;
    ctx.beginPath();
    ctx.arc(s.x, s.y, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.globalCompositeOperation = 'source-over';
  }
  ctx.restore();
}

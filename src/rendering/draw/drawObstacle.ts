import type { Obstacle } from '@/entities/Obstacle';
import { Palette, rgba } from '@/rendering/Palette';
import { drawSoftShadow, drawGlowCircle, blobPath, roundedRectPath } from '@/rendering/DrawUtils';

const SEEDS = [0.1, -0.06, 0.12, -0.09, 0.07, -0.11];

export function drawObstacle(ctx: CanvasRenderingContext2D, o: Obstacle, screenX: number, screenY: number, time: number): void {
  ctx.save();
  ctx.translate(screenX, screenY);
  drawSoftShadow(ctx, 0, o.radius * 0.6, o.radius * 1.1, o.radius * 0.4, 0.4);

  switch (o.visual) {
    case 'tree': {
      ctx.fillStyle = '#120f0a';
      ctx.beginPath();
      ctx.ellipse(0, o.radius * 0.3, o.radius * 0.35, o.radius * 0.7, 0, 0, Math.PI * 2);
      ctx.fill();
      const grad = ctx.createRadialGradient(-o.radius * 0.3, -o.radius * 0.6, 2, 0, -o.radius * 0.3, o.radius);
      grad.addColorStop(0, '#232b1a');
      grad.addColorStop(1, '#0e130a');
      ctx.fillStyle = grad;
      blobPath(ctx, 0, -o.radius * 0.5, o.radius, 7, 0.18, SEEDS);
      ctx.fill();
      break;
    }
    case 'rock': {
      const grad = ctx.createLinearGradient(-o.radius, -o.radius, o.radius, o.radius);
      grad.addColorStop(0, '#3a352f');
      grad.addColorStop(1, '#171410');
      ctx.fillStyle = grad;
      blobPath(ctx, 0, 0, o.radius, 6, 0.12, SEEDS);
      ctx.fill();
      break;
    }
    case 'pillar': {
      ctx.fillStyle = '#1b1720';
      ctx.fillRect(-o.radius * 0.5, -o.radius * 2.2, o.radius, o.radius * 2.6);
      ctx.fillStyle = '#2c2734';
      ctx.fillRect(-o.radius * 0.6, -o.radius * 2.3, o.radius * 1.2, o.radius * 0.3);
      ctx.fillRect(-o.radius * 0.6, o.radius * 0.15, o.radius * 1.2, o.radius * 0.3);
      break;
    }
    case 'statue': {
      ctx.fillStyle = '#211d29';
      ctx.beginPath();
      ctx.ellipse(0, -o.radius * 0.4, o.radius * 0.6, o.radius * 1.3, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(0, -o.radius * 1.5, o.radius * 0.4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = rgba(Palette.soul, 0.6);
      ctx.beginPath();
      ctx.arc(0, -o.radius * 1.5, 1.6, 0, Math.PI * 2);
      ctx.fill();
      break;
    }
    case 'rubble': {
      ctx.fillStyle = '#221e1a';
      for (let i = 0; i < 3; i++) {
        const a = (i / 3) * Math.PI * 2 + o.seed;
        ctx.beginPath();
        ctx.ellipse(Math.cos(a) * o.radius * 0.4, Math.sin(a) * o.radius * 0.3, o.radius * 0.4, o.radius * 0.28, a, 0, Math.PI * 2);
        ctx.fill();
      }
      break;
    }
    case 'brazier': {
      ctx.fillStyle = '#2a241c';
      ctx.beginPath();
      ctx.moveTo(-o.radius * 0.5, o.radius * 0.6);
      ctx.lineTo(-o.radius * 0.3, -o.radius * 0.2);
      ctx.lineTo(o.radius * 0.3, -o.radius * 0.2);
      ctx.lineTo(o.radius * 0.5, o.radius * 0.6);
      ctx.closePath();
      ctx.fill();
      const flick = 0.85 + Math.sin(time * 8 + o.seed) * 0.15;
      drawGlowCircle(ctx, 0, -o.radius * 0.5, o.radius * 1.8 * flick, Palette.ember4, 0.6);
      ctx.fillStyle = Palette.ember5;
      ctx.beginPath();
      ctx.moveTo(0, -o.radius * 1.1 * flick);
      ctx.quadraticCurveTo(o.radius * 0.3, -o.radius * 0.4, 0, -o.radius * 0.1);
      ctx.quadraticCurveTo(-o.radius * 0.3, -o.radius * 0.4, 0, -o.radius * 1.1 * flick);
      ctx.fill();
      break;
    }
    case 'crystal': {
      const flick = 0.8 + Math.sin(time * 2 + o.seed) * 0.2;
      drawGlowCircle(ctx, 0, 0, o.radius * 2.2 * flick, Palette.soul, 0.5);
      ctx.fillStyle = Palette.soulBright;
      ctx.beginPath();
      ctx.moveTo(0, -o.radius * 1.4);
      ctx.lineTo(o.radius * 0.5, 0);
      ctx.lineTo(0, o.radius * 0.6);
      ctx.lineTo(-o.radius * 0.5, 0);
      ctx.closePath();
      ctx.fill();
      break;
    }
    case 'merchantStall': {
      const r = o.radius;
      const sway = Math.sin(time * 1.3 + o.seed) * 0.03;
      // Posts
      ctx.fillStyle = '#1c150e';
      ctx.fillRect(-r * 1.15, -r * 0.1, r * 0.22, r * 1.5);
      ctx.fillRect(r * 0.95, -r * 0.1, r * 0.22, r * 1.5);
      // Counter
      const counterGrad = ctx.createLinearGradient(0, -r * 0.2, 0, r * 0.15);
      counterGrad.addColorStop(0, '#3a2c1c');
      counterGrad.addColorStop(1, '#221a10');
      ctx.fillStyle = counterGrad;
      ctx.fillRect(-r * 1.3, -r * 0.2, r * 2.6, r * 0.35);
      // Wares on the counter
      const wareColors = [Palette.blood, Palette.soulDim, Palette.gold];
      for (let i = 0; i < 3; i++) {
        ctx.fillStyle = wareColors[i];
        roundedRectPath(ctx, -r * 0.9 + i * r * 0.75, -r * 0.42, r * 0.5, r * 0.28, r * 0.08);
        ctx.fill();
      }
      // Awning
      ctx.save();
      ctx.rotate(sway);
      const awningGrad = ctx.createLinearGradient(-r * 1.5, -r * 2, r * 1.5, -r * 1.2);
      awningGrad.addColorStop(0, Palette.goldDim);
      awningGrad.addColorStop(1, Palette.gold);
      ctx.fillStyle = awningGrad;
      ctx.beginPath();
      ctx.moveTo(-r * 1.5, -r * 1.75);
      ctx.quadraticCurveTo(0, -r * 2.15, r * 1.5, -r * 1.75);
      ctx.lineTo(r * 1.3, -r * 1.35);
      ctx.quadraticCurveTo(0, -r * 1.7, -r * 1.3, -r * 1.35);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
      // Hanging ember lantern
      const flick = 0.8 + Math.sin(time * 7 + o.seed) * 0.2;
      drawGlowCircle(ctx, 0, -r * 0.9, r * 1.6 * flick, Palette.ember4, 0.55);
      ctx.fillStyle = Palette.ember5;
      ctx.beginPath();
      ctx.arc(0, -r * 0.9, r * 0.14, 0, Math.PI * 2);
      ctx.fill();
      break;
    }
    case 'shrine': {
      const r = o.radius;
      // Plinth
      const stoneGrad = ctx.createLinearGradient(-r, 0, r, 0);
      stoneGrad.addColorStop(0, '#241f2c');
      stoneGrad.addColorStop(0.5, '#332b3d');
      stoneGrad.addColorStop(1, '#241f2c');
      ctx.fillStyle = stoneGrad;
      ctx.beginPath();
      ctx.moveTo(-r * 0.9, r * 0.6);
      ctx.lineTo(-r * 0.55, -r * 0.15);
      ctx.lineTo(r * 0.55, -r * 0.15);
      ctx.lineTo(r * 0.9, r * 0.6);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = '#3d3448';
      ctx.fillRect(-r * 0.65, -r * 0.25, r * 1.3, r * 0.16);
      // Faint worn rune marks
      ctx.strokeStyle = rgba(Palette.soulDim, 0.55);
      ctx.lineWidth = Math.max(1, r * 0.05);
      ctx.beginPath();
      ctx.moveTo(-r * 0.35, r * 0.15);
      ctx.lineTo(-r * 0.1, r * 0.4);
      ctx.moveTo(r * 0.1, r * 0.15);
      ctx.lineTo(r * 0.35, r * 0.4);
      ctx.stroke();
      // Slow, unresolved pulse — this landmark stays ambiguous until the event triggers
      const pulse = 0.7 + Math.sin(time * 1.6 + o.seed) * 0.3;
      drawGlowCircle(ctx, 0, -r * 0.75, r * 1.9 * pulse, Palette.soul, 0.45);
      ctx.fillStyle = Palette.soulBright;
      ctx.beginPath();
      ctx.arc(0, -r * 0.75, r * 0.22 * pulse, 0, Math.PI * 2);
      ctx.fill();
      break;
    }
  }

  ctx.restore();
}

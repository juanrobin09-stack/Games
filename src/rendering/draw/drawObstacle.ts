import type { Obstacle } from '@/entities/Obstacle';
import { Palette, rgba } from '@/rendering/Palette';
import { drawSoftShadow, drawGlowCircle, blobPath } from '@/rendering/DrawUtils';

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
  }

  ctx.restore();
}

import type { Obstacle } from '@/entities/Obstacle';
import { Palette, rgba } from '@/rendering/Palette';
import { drawSoftShadow, drawGlowCircle, blobPath, roundedRectPath } from '@/rendering/DrawUtils';
import { getStallSprite } from '@/rendering/ShopAsset';
import { clamp, easeInOutSine, TAU } from '@/utils/MathUtils';

const SEEDS = [0.1, -0.06, 0.12, -0.09, 0.07, -0.11];

/**
 * A stairwell seen from above: a stone-framed rectangular well, six steps
 * along its `facing`, ending in darkness (going down) or in a faint warm
 * light from the world above (the arrival stairs, going up). The descent
 * stairwell starts sealed under a rune-carved lid that slides aside once the
 * heart room is cleared, with the ruins' cold light rising out of it.
 */
function drawStairwell(ctx: CanvasRenderingContext2D, o: Obstacle, time: number, kind: 'down' | 'up'): void {
  const r = o.radius;
  const L = r * 2.5;
  const W = r * 1.7;
  ctx.rotate(o.facing);

  // Worked stone frame.
  ctx.fillStyle = '#332e44';
  roundedRectPath(ctx, -L / 2 - 10, -W / 2 - 10, L + 20, W + 20, 7);
  ctx.fill();
  const rim = ctx.createLinearGradient(0, -W / 2, 0, W / 2);
  rim.addColorStop(0, '#665f80');
  rim.addColorStop(0.5, '#4f4866');
  rim.addColorStop(1, '#3a3450');
  ctx.fillStyle = rim;
  roundedRectPath(ctx, -L / 2 - 7, -W / 2 - 7, L + 14, W + 14, 6);
  ctx.fill();
  ctx.strokeStyle = 'rgba(0,0,0,0.55)';
  ctx.lineWidth = 1.5;
  roundedRectPath(ctx, -L / 2 - 7, -W / 2 - 7, L + 14, W + 14, 6);
  ctx.stroke();
  // Rim joints.
  ctx.strokeStyle = 'rgba(0,0,0,0.35)';
  ctx.lineWidth = 1;
  for (const jx of [-L * 0.3, 0, L * 0.3]) {
    ctx.beginPath();
    ctx.moveTo(jx, -W / 2 - 7);
    ctx.lineTo(jx, -W / 2);
    ctx.moveTo(jx, W / 2);
    ctx.lineTo(jx, W / 2 + 7);
    ctx.stroke();
  }

  // The well: steps along +x.
  const steps = 6;
  const stepL = L / steps;
  for (let i = 0; i < steps; i++) {
    const t = i / (steps - 1);
    const lum = kind === 'down' ? 1 - t : t;
    const shade = Math.round(16 + lum * 72);
    ctx.fillStyle = `rgb(${shade - 3}, ${shade - 5}, ${shade + 8})`;
    ctx.fillRect(-L / 2 + i * stepL, -W / 2, stepL + 0.6, W);
    ctx.fillStyle = `rgba(255,255,255,${0.04 + lum * 0.1})`;
    ctx.fillRect(-L / 2 + i * stepL, -W / 2, 1.6, W);
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    ctx.fillRect(-L / 2 + (i + 1) * stepL - 2.2, -W / 2, 2.2, W);
  }
  // Inner side shadows so the well reads as sunken, not painted on.
  for (const side of [-1, 1]) {
    const g = ctx.createLinearGradient(0, side * (W / 2), 0, side * (W / 2 - 12));
    g.addColorStop(0, 'rgba(0,0,0,0.55)');
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(-L / 2, side === -1 ? -W / 2 : W / 2 - 12, L, 12);
  }
  // Far end: swallowed by dark (down) or touched by the light above (up).
  const deep = ctx.createLinearGradient(L / 2 - L * 0.45, 0, L / 2, 0);
  if (kind === 'down') {
    deep.addColorStop(0, 'rgba(4,3,8,0)');
    deep.addColorStop(1, 'rgba(4,3,8,0.96)');
  } else {
    deep.addColorStop(0, 'rgba(255,150,80,0)');
    deep.addColorStop(1, 'rgba(255,170,90,0.3)');
  }
  ctx.fillStyle = deep;
  ctx.fillRect(L / 2 - L * 0.45, -W / 2, L * 0.45, W);

  if (kind === 'down') {
    const reveal = o.activated ? clamp((time - o.activatedAt) / 1.1, 0, 1) : 0;
    if (reveal > 0) {
      const pulse = 0.8 + Math.sin(time * 2.2 + o.seed) * 0.2;
      ctx.globalCompositeOperation = 'lighter';
      drawGlowCircle(ctx, L * 0.28, 0, W * 0.95 * reveal * pulse, Palette.fungus, 0.42 * reveal);
      ctx.globalCompositeOperation = 'source-over';
    }
    {
      // The seal: a carved lid that grinds sideways out of the well and stays
      // lying beside it — a slab that was moved, not one that vanished.
      const slide = easeInOutSine(reveal) * (W + 18);
      ctx.save();
      ctx.translate(0, slide);
      if (reveal >= 1) {
        ctx.fillStyle = 'rgba(0,0,0,0.35)';
        roundedRectPath(ctx, -L / 2 + 2, -W / 2 + 3, L + 4, W + 4, 4);
        ctx.fill();
      }
      const lid = ctx.createLinearGradient(-L / 2, 0, L / 2, 0);
      lid.addColorStop(0, '#45405a');
      lid.addColorStop(0.5, '#5c5674');
      lid.addColorStop(1, '#3b364e');
      ctx.fillStyle = lid;
      roundedRectPath(ctx, -L / 2 - 2, -W / 2 - 2, L + 4, W + 4, 4);
      ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,0.55)';
      ctx.lineWidth = 2;
      roundedRectPath(ctx, -L / 2 - 2, -W / 2 - 2, L + 4, W + 4, 4);
      ctx.stroke();
      ctx.strokeStyle = 'rgba(0,0,0,0.3)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(-L * 0.42, -W * 0.3);
      ctx.lineTo(-L * 0.2, -W * 0.05);
      ctx.lineTo(-L * 0.3, W * 0.25);
      ctx.stroke();
      // The binding rune, pulsing while the seal holds.
      const seam = (0.45 + Math.sin(time * 1.5 + o.seed) * 0.2) * (1 - reveal);
      ctx.strokeStyle = rgba(Palette.soul, seam);
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.moveTo(-L * 0.36, 0);
      ctx.lineTo(-L * 0.12, -W * 0.26);
      ctx.lineTo(L * 0.12, W * 0.26);
      ctx.lineTo(L * 0.36, 0);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(0, 0, W * 0.2, 0, TAU);
      ctx.stroke();
      ctx.restore();
    }
  } else {
    ctx.globalCompositeOperation = 'lighter';
    drawGlowCircle(ctx, L * 0.42, 0, W * 0.75, Palette.ember3, 0.2 + Math.sin(time * 1.3 + o.seed) * 0.05);
    ctx.globalCompositeOperation = 'source-over';
  }

  // Two broken column stubs framing the far end (round tops: rotation-safe).
  for (const side of [-1, 1]) {
    const px = L / 2 + 6;
    const py = side * (W / 2 + 8);
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath();
    ctx.arc(px + 2, py + 2, 9.5, 0, TAU);
    ctx.fill();
    ctx.fillStyle = '#3d374f';
    ctx.beginPath();
    ctx.arc(px, py, 9, 0, TAU);
    ctx.fill();
    ctx.fillStyle = '#5d5775';
    ctx.beginPath();
    ctx.arc(px, py, 6.5, 0, TAU);
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.4)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(px - 3, py - 4);
    ctx.lineTo(px + 2, py + 3);
    ctx.stroke();
  }
}

export function drawObstacle(ctx: CanvasRenderingContext2D, o: Obstacle, screenX: number, screenY: number, time: number): void {
  ctx.save();
  ctx.translate(screenX, screenY);
  // A stairwell is a hole in the floor, not a body standing on it: no contact shadow.
  if (o.visual !== 'stairsDown' && o.visual !== 'stairsUp') {
    drawSoftShadow(ctx, 0, o.radius * 0.6, o.radius * 1.1, o.radius * 0.4, 0.4);
  }

  switch (o.visual) {
    case 'stairsDown':
      drawStairwell(ctx, o, time, 'down');
      break;
    case 'stairsUp':
      drawStairwell(ctx, o, time, 'up');
      break;
    case 'fungus': {
      // A cluster of bioluminescent caps — the ruins' light source. Non-blocking
      // to projectiles, soft to walk around, and it casts a real dynamic light
      // (see Game.registerLights) in the zone's cold fungal colour.
      const r = o.radius;
      const glow = 0.75 + Math.sin(time * 1.8 + o.seed) * 0.2;
      ctx.globalCompositeOperation = 'lighter';
      drawGlowCircle(ctx, 0, -r * 0.2, r * 2.4 * glow, Palette.fungus, 0.32);
      ctx.globalCompositeOperation = 'source-over';
      const caps: [number, number, number][] = [
        [-0.55, 0.25, 0.6],
        [0.5, 0.3, 0.7],
        [0.15, -0.5, 0.5],
        [-0.3, -0.35, 0.42],
        [0, 0, 1],
      ];
      for (const [cx, cy, s] of caps) {
        const capR = r * 0.55 * s;
        const px = cx * r;
        const py = cy * r;
        ctx.fillStyle = '#a9b8b0';
        ctx.fillRect(px - capR * 0.18, py - capR * 0.2, capR * 0.36, capR * 0.9);
        const g = ctx.createRadialGradient(px - capR * 0.3, py - capR * 0.75, 1, px, py - capR * 0.4, capR * 1.2);
        g.addColorStop(0, Palette.fungusBright);
        g.addColorStop(0.6, Palette.fungus);
        g.addColorStop(1, Palette.fungusDim);
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.ellipse(px, py - capR * 0.4, capR, capR * 0.7, 0, 0, TAU);
        ctx.fill();
        ctx.fillStyle = 'rgba(255,255,255,0.35)';
        ctx.beginPath();
        ctx.arc(px - capR * 0.3, py - capR * 0.6, capR * 0.16, 0, TAU);
        ctx.arc(px + capR * 0.35, py - capR * 0.42, capR * 0.12, 0, TAU);
        ctx.fill();
      }
      break;
    }
    case 'sarcophagus': {
      // A long stone coffin, lid still on, slightly askew — cover you can't shoot through.
      const r = o.radius;
      ctx.rotate((o.seed % 1) * 0.6 - 0.3);
      const w = r * 2.7;
      const h = r * 1.35;
      ctx.fillStyle = '#17141f';
      roundedRectPath(ctx, -w / 2 - 3, -h / 2 + 3, w + 6, h + 5, 4);
      ctx.fill();
      const body = ctx.createLinearGradient(0, -h / 2, 0, h / 2);
      body.addColorStop(0, '#4d4664');
      body.addColorStop(1, '#2a2638');
      ctx.fillStyle = body;
      roundedRectPath(ctx, -w / 2, -h / 2 - 6, w, h, 5);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.12)';
      ctx.lineWidth = 1.5;
      roundedRectPath(ctx, -w / 2 + 4, -h / 2 - 3, w - 8, h - 7, 4);
      ctx.stroke();
      // The carved effigy: a long line for the body, a circle for the face.
      ctx.strokeStyle = 'rgba(0,0,0,0.5)';
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.moveTo(-w * 0.3, -2);
      ctx.lineTo(w * 0.28, -2);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(-w * 0.34, -2, r * 0.16, 0, TAU);
      ctx.stroke();
      ctx.fillStyle = rgba(Palette.fungusDim, 0.55);
      ctx.beginPath();
      ctx.ellipse(w * 0.32, h * 0.22 - 6, r * 0.42, r * 0.22, 0.4, 0, TAU);
      ctx.fill();
      break;
    }
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
      const sprite = getStallSprite();
      if (sprite) {
        // Scaled from the real reference sprite (stone canopy, counter,
        // wares and banner) rather than drawn procedurally. It's painterly,
        // low-contrast detail rather than the old bold flat-shaded icon, so
        // it needs real screen size to read clearly against the equally
        // photo-textured floor/walls — sized generously, as befits the
        // room's one true landmark, rather than matched to the old sprite's
        // modest footprint. Anchored so the counter — roughly 60% of the
        // way down the crop — lands near the obstacle's own origin, where
        // interaction distance is measured from, with the canopy above it.
        const spriteW = r * 7.2;
        const spriteH = spriteW * (sprite.height / sprite.width);
        ctx.drawImage(sprite, -spriteW / 2, -spriteH * 0.6, spriteW, spriteH);
      } else {
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
      }
      // A dynamic flicker light stays layered on top either way, roughly
      // where the sprite's own painted candle sits on the counter — the
      // sprite already supplies the flame itself, so only the procedural
      // fallback also needs a hard bright dot to read as a light source.
      const flick = 0.8 + Math.sin(time * 7 + o.seed) * 0.2;
      drawGlowCircle(ctx, -r * 0.2, -r * 0.85, r * 1.6 * flick, Palette.ember4, 0.55);
      if (!sprite) {
        ctx.fillStyle = Palette.ember5;
        ctx.beginPath();
        ctx.arc(-r * 0.2, -r * 0.85, r * 0.14, 0, Math.PI * 2);
        ctx.fill();
      }
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

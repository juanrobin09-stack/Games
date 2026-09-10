import type { Enemy } from '@/entities/Enemy';
import { Palette, rgba, mixColor } from '@/rendering/Palette';
import { drawSoftShadow, drawGlowCircle, blobPath, hashJitter, roundedRectPath } from '@/rendering/DrawUtils';
import { TAU } from '@/utils/MathUtils';
import { tc } from '@/i18n';

const WOBBLE_SEEDS = [0.1, -0.08, 0.14, -0.05, 0.09, -0.12, 0.06, -0.1];

function statusOverlay(ctx: CanvasRenderingContext2D, enemy: Enemy, radius: number): void {
  if (enemy.burn && enemy.alive) {
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.35 + Math.sin(enemy.animPhase * 16) * 0.12;
    ctx.fillStyle = Palette.ember4;
    ctx.beginPath();
    ctx.arc(0, -radius * 0.2, radius * 0.9, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }
  if (enemy.hitFlashTimer > 0) {
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = (enemy.hitFlashTimer / 0.16) * 0.75;
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(0, 0, radius * 1.05, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }
}

function healthBar(ctx: CanvasRenderingContext2D, enemy: Enemy, radius: number): void {
  if (enemy.hp >= enemy.maxHp || !enemy.alive) return;
  const w = Math.max(24, radius * 1.8);
  const y = -radius - 12;
  const ratio = Math.max(0, enemy.hp / enemy.maxHp);
  ctx.fillStyle = 'rgba(8,6,10,0.7)';
  ctx.fillRect(-w / 2, y, w, 4);
  ctx.fillStyle = ratio > 0.3 ? Palette.ember4 : Palette.bloodBright;
  ctx.fillRect(-w / 2, y, w * ratio, 4);
}

function telegraphRing(ctx: CanvasRenderingContext2D, enemy: Enemy, radius: number): void {
  if (enemy.state !== 'windup') return;
  const telegraphTime = enemy.def.telegraphTime * (enemy.comboStep > 0 ? 0.45 : 1);
  const t = Math.min(1, enemy.stateTimer / Math.max(0.05, telegraphTime));
  ctx.save();
  if (enemy.def.behavior === 'warden') {
    // The bash is a line, so its telegraph is one: a lane along the facing
    // that fills up as the lunge gets closer. Step out of the lane.
    const len = enemy.def.attackRange + 40;
    const w = radius * 1.7;
    ctx.rotate(enemy.facing);
    const lane = ctx.createLinearGradient(0, 0, len, 0);
    lane.addColorStop(0, rgba(Palette.bloodBright, 0.7));
    lane.addColorStop(1, rgba(Palette.bloodBright, 0.12));
    ctx.globalAlpha = 0.35 + 0.5 * t;
    ctx.fillStyle = lane;
    ctx.fillRect(0, -w / 2, len * t, w);
    ctx.globalAlpha = 0.45 + 0.45 * t;
    ctx.strokeStyle = Palette.bloodBright;
    ctx.lineWidth = 2;
    ctx.strokeRect(0, -w / 2, len, w);
    ctx.beginPath();
    ctx.moveTo(len * t, -w / 2);
    ctx.lineTo(len * t + 10, 0);
    ctx.lineTo(len * t, w / 2);
    ctx.stroke();
  } else if (enemy.def.behavior === 'bloat') {
    // The burst radius, growing to full as the swell completes — and the
    // cloud it will leave, in the same cold colour.
    const R = enemy.def.burstRadius ?? enemy.def.attackRange;
    const cur = R * (0.4 + 0.6 * t);
    ctx.fillStyle = rgba(Palette.fungus, 0.14 * t);
    ctx.beginPath();
    ctx.arc(0, 0, cur, 0, TAU);
    ctx.fill();
    ctx.globalAlpha = 0.35 + 0.45 * t;
    ctx.strokeStyle = Palette.fungusBright;
    ctx.lineWidth = 2 + t * 2;
    ctx.setLineDash([7, 5]);
    ctx.beginPath();
    ctx.arc(0, 0, cur, 0, TAU);
    ctx.stroke();
    ctx.setLineDash([]);
  } else {
    ctx.globalAlpha = 0.5 * t;
    ctx.strokeStyle = Palette.bloodBright;
    ctx.lineWidth = 2 + t * 2;
    ctx.beginPath();
    ctx.arc(0, 0, enemy.def.attackRange * t, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.restore();
}

function drawAshCrawler(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  const legPhase = e.animPhase * 12;
  ctx.strokeStyle = e.def.color;
  ctx.lineWidth = 2;
  for (let i = 0; i < 4; i++) {
    const side = i < 2 ? -1 : 1;
    const front = i % 2 === 0;
    const swing = Math.sin(legPhase + i * 1.6) * 5;
    const baseX = side * r * 0.6;
    const baseY = front ? -r * 0.3 : r * 0.3;
    ctx.beginPath();
    ctx.moveTo(baseX, baseY);
    ctx.lineTo(baseX + side * 6, baseY + swing);
    ctx.stroke();
  }
  const grad = ctx.createRadialGradient(-2, -3, 1, 0, 0, r);
  grad.addColorStop(0, mixColor(e.def.color, '#000000', -0.4 < 0 ? 0 : 0));
  grad.addColorStop(0, '#5a4a3a');
  grad.addColorStop(1, e.def.color);
  ctx.fillStyle = grad;
  blobPath(ctx, 0, 0, r, 8, 0.08, WOBBLE_SEEDS);
  ctx.fill();
  ctx.fillStyle = e.def.accentColor;
  ctx.shadowColor = e.def.accentColor;
  ctx.shadowBlur = 5;
  ctx.beginPath();
  ctx.arc(-3, -2, 1.6, 0, Math.PI * 2);
  ctx.arc(3, -2, 1.6, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
}

function drawHollow(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  const lean = Math.sin(e.animPhase * 1.6) * 0.05;
  ctx.rotate(lean);
  const grad = ctx.createLinearGradient(0, -r, 0, r);
  grad.addColorStop(0, '#3a3a44');
  grad.addColorStop(1, e.def.color);
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.ellipse(0, r * 0.2, r * 0.78, r, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(0, -r * 0.55, r * 0.5, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = e.def.accentColor;
  ctx.globalAlpha = 0.85;
  ctx.beginPath();
  ctx.ellipse(-r * 0.16, -r * 0.55, 2.4, 3, 0, 0, Math.PI * 2);
  ctx.ellipse(r * 0.16, -r * 0.55, 2.4, 3, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
}

function drawFlameWisp(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  const flicker = Math.sin(e.animPhase * 9) * 0.15 + 1;
  drawGlowCircle(ctx, 0, 0, r * 1.8 * flicker, e.def.accentColor, 0.55);
  for (let i = 0; i < 6; i++) {
    const angle = (i / 6) * Math.PI * 2 + e.animPhase * 2;
    const len = r * (0.8 + hashJitter(e.id, i) * 0.6) * flicker;
    ctx.strokeStyle = rgba(e.def.color, 0.7);
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(Math.cos(angle) * len, Math.sin(angle) * len);
    ctx.stroke();
  }
  const grad = ctx.createRadialGradient(0, 0, 1, 0, 0, r);
  grad.addColorStop(0, '#fff2d9');
  grad.addColorStop(0.5, e.def.accentColor);
  grad.addColorStop(1, e.def.color);
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.75, 0, Math.PI * 2);
  ctx.fill();
}

function drawGravebound(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  const stomp = Math.abs(Math.sin(e.animPhase * 3)) * 2;
  const grad = ctx.createLinearGradient(-r, -r, r, r);
  grad.addColorStop(0, '#4a4238');
  grad.addColorStop(1, e.def.color);
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.moveTo(-r * 0.9, r * 0.6);
  ctx.lineTo(-r, -r * 0.3 - stomp);
  ctx.lineTo(-r * 0.4, -r * 0.9 - stomp);
  ctx.lineTo(r * 0.4, -r * 0.9 - stomp);
  ctx.lineTo(r, -r * 0.3 - stomp);
  ctx.lineTo(r * 0.9, r * 0.6);
  ctx.closePath();
  ctx.fill();
  const armSwing = e.state === 'attack' ? -0.9 : e.state === 'windup' ? 0.6 : 0;
  ctx.save();
  ctx.translate(r * 0.75, -r * 0.1);
  ctx.rotate(armSwing);
  ctx.fillStyle = e.def.color;
  ctx.fillRect(-4, 0, 10, r * 1.1);
  ctx.fillStyle = mixColor(e.def.accentColor, '#000000', 0.1);
  ctx.beginPath();
  ctx.arc(0, r * 1.1, 8, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  ctx.fillStyle = e.def.accentColor;
  ctx.shadowColor = e.def.accentColor;
  ctx.shadowBlur = 6;
  ctx.beginPath();
  ctx.arc(-4, -r * 0.6 - stomp, 1.8, 0, Math.PI * 2);
  ctx.arc(4, -r * 0.6 - stomp, 1.8, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
}

function drawShadowStalker(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  ctx.globalAlpha *= e.vanishAlpha;
  const sway = Math.sin(e.animPhase * 5) * 3;
  const grad = ctx.createLinearGradient(0, -r, 0, r * 1.4);
  grad.addColorStop(0, e.def.accentColor);
  grad.addColorStop(1, 'rgba(20,16,30,0)');
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.moveTo(-r * 0.6, -r * 0.2);
  ctx.quadraticCurveTo(-r * 0.9 + sway, r * 0.8, -r * 0.3, r * 1.5);
  ctx.quadraticCurveTo(0, r * 1.1, r * 0.3, r * 1.5);
  ctx.quadraticCurveTo(r * 0.9 + sway, r * 0.8, r * 0.6, -r * 0.2);
  ctx.quadraticCurveTo(0, -r * 0.5, -r * 0.6, -r * 0.2);
  ctx.fill();
  ctx.fillStyle = e.def.color;
  ctx.beginPath();
  ctx.arc(0, -r * 0.3, r * 0.55, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = e.def.accentColor;
  ctx.shadowColor = e.def.accentColor;
  ctx.shadowBlur = 8;
  ctx.beginPath();
  ctx.ellipse(-3, -r * 0.32, 1.8, 1.2, 0, 0, Math.PI * 2);
  ctx.ellipse(3, -r * 0.32, 1.8, 1.2, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
}

function drawCinderWraith(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  ctx.globalAlpha *= 0.55 + 0.35 * e.vanishAlpha;
  const float = Math.sin(e.animPhase * 2.4) * 3;
  ctx.translate(0, float);
  const grad = ctx.createLinearGradient(0, -r, 0, r);
  grad.addColorStop(0, mixColor(e.def.color, '#ffffff', 0.15));
  grad.addColorStop(1, e.def.color);
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.moveTo(0, -r);
  ctx.quadraticCurveTo(r * 0.9, -r * 0.2, r * 0.6, r * 0.9);
  ctx.quadraticCurveTo(0, r * 0.6, -r * 0.6, r * 0.9);
  ctx.quadraticCurveTo(-r * 0.9, -r * 0.2, 0, -r);
  ctx.fill();
  drawGlowCircle(ctx, 0, -r * 0.1, r * 0.5, e.def.accentColor, 0.7);
}

function drawEmberDevourer(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  drawGlowCircle(ctx, 0, 0, r * 1.6, e.def.accentColor, 0.35);
  const pulse = 0.85 + Math.sin(e.animPhase * 4) * 0.15;
  const grad = ctx.createRadialGradient(-r * 0.2, -r * 0.3, 2, 0, 0, r);
  grad.addColorStop(0, '#6a2c18');
  grad.addColorStop(1, e.def.color);
  ctx.fillStyle = grad;
  blobPath(ctx, 0, 0, r, 10, 0.1, WOBBLE_SEEDS);
  ctx.fill();
  for (let i = 0; i < 5; i++) {
    const angle = (i / 5) * Math.PI * 2 - Math.PI / 2;
    ctx.strokeStyle = rgba(e.def.accentColor, 0.5 + 0.3 * pulse);
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(Math.cos(angle) * r * 0.3, Math.sin(angle) * r * 0.3);
    ctx.lineTo(Math.cos(angle) * r * 0.95, Math.sin(angle) * r * 0.95);
    ctx.stroke();
  }
  ctx.fillStyle = e.def.accentColor;
  ctx.shadowColor = e.def.accentColor;
  ctx.shadowBlur = 10 * pulse;
  ctx.beginPath();
  ctx.arc(-r * 0.22, -r * 0.15, 3.2, 0, Math.PI * 2);
  ctx.arc(r * 0.22, -r * 0.15, 3.2, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
}

function drawBlightbloat(ctx: CanvasRenderingContext2D, e: Enemy): void {
  const r = e.radius;
  const swelling = e.state === 'windup';
  const swellT = swelling ? Math.min(1, e.stateTimer / Math.max(0.05, e.def.telegraphTime)) : 0;
  const strain = swelling ? Math.sin(e.animPhase * 30) * 0.03 * swellT : 0;
  const scale = (1 + swellT * 0.42 + strain) * (1 + Math.sin(e.animPhase * 3) * 0.04);
  ctx.save();
  ctx.scale(scale, scale);
  ctx.globalCompositeOperation = 'lighter';
  drawGlowCircle(ctx, 0, 0, r * (1.6 + swellT * 1.2), Palette.fungus, 0.22 + swellT * 0.45);
  ctx.globalCompositeOperation = 'source-over';
  // Stubby legs, dragging.
  ctx.strokeStyle = '#2a3122';
  ctx.lineWidth = 3;
  const legPhase = e.animPhase * 6;
  for (let i = 0; i < 4; i++) {
    const side = i < 2 ? -1 : 1;
    const front = i % 2 === 0 ? -1 : 1;
    const swing = Math.sin(legPhase + i * 1.7) * 3;
    ctx.beginPath();
    ctx.moveTo(side * r * 0.5, front * r * 0.35);
    ctx.lineTo(side * r * 0.95, front * r * 0.55 + swing);
    ctx.stroke();
  }
  // The sac.
  const grad = ctx.createRadialGradient(-r * 0.3, -r * 0.35, 1, 0, 0, r);
  grad.addColorStop(0, '#6c7a56');
  grad.addColorStop(0.7, e.def.color);
  grad.addColorStop(1, '#232a1c');
  ctx.fillStyle = grad;
  blobPath(ctx, 0, 0, r, 9, 0.1, WOBBLE_SEEDS);
  ctx.fill();
  ctx.fillStyle = 'rgba(255,255,255,0.07)';
  ctx.beginPath();
  ctx.ellipse(-r * 0.25, -r * 0.3, r * 0.45, r * 0.3, -0.4, 0, TAU);
  ctx.fill();
  // Glowing pustules — brighter and bigger the closer it is to bursting.
  const spots: [number, number, number][] = [
    [-0.35, -0.1, 0.22],
    [0.3, -0.25, 0.18],
    [0.1, 0.35, 0.2],
    [-0.1, 0.05, 0.12],
    [0.42, 0.25, 0.11],
  ];
  // All five pustules in ONE path and one fill: a shadowBlur fill is a whole
  // blur pass, so five separate fills were five passes per bloat per frame.
  ctx.shadowColor = Palette.fungus;
  ctx.shadowBlur = 6 + swellT * 10;
  ctx.fillStyle = swellT > 0.5 ? Palette.fungusBright : Palette.fungus;
  ctx.beginPath();
  for (const [sx, sy, ss] of spots) {
    const pr = ss * r * (1 + swellT * 0.5);
    ctx.moveTo(sx * r + pr, sy * r);
    ctx.arc(sx * r, sy * r, pr, 0, TAU);
  }
  ctx.fill();
  ctx.shadowBlur = 0;
  // What's left of the Hollow it grew from: a small skull leaning out the front.
  const hx = Math.cos(e.facing) * r * 0.78;
  const hy = Math.sin(e.facing) * r * 0.78;
  ctx.fillStyle = '#2c2c34';
  ctx.beginPath();
  ctx.arc(hx, hy, r * 0.3, 0, TAU);
  ctx.fill();
  ctx.fillStyle = Palette.fungusBright;
  ctx.beginPath();
  ctx.arc(hx - 2.2, hy - 1, 1.3, 0, TAU);
  ctx.arc(hx + 2.2, hy - 1, 1.3, 0, TAU);
  ctx.fill();
  ctx.restore();
}

function drawWarden(ctx: CanvasRenderingContext2D, e: Enemy, champion: boolean): void {
  const r = e.radius;
  const guardDown = e.alive && !e.shieldUp;
  const bashing = e.bashTimer > 0;
  const stomp = Math.abs(Math.sin(e.animPhase * 4)) * 1.5;
  ctx.save();
  ctx.rotate(e.facing);

  if (champion) {
    // Captain's cloak trailing behind, in the ruins' own violet.
    const sway = Math.sin(e.animPhase * 2.2) * r * 0.25;
    ctx.fillStyle = rgba(Palette.soul, e.shieldBroken ? 0.7 : 0.5);
    ctx.beginPath();
    ctx.moveTo(-r * 0.5, -r * 0.55);
    ctx.quadraticCurveTo(-r * 1.8, sway, -r * 0.5, r * 0.55);
    ctx.closePath();
    ctx.fill();
  }
  // Legs.
  ctx.fillStyle = '#26222f';
  ctx.fillRect(-r * 0.45, -r * 0.6, r * 0.38, r * 0.28 + stomp);
  ctx.fillRect(-r * 0.45, r * 0.32, r * 0.38, r * 0.28 + stomp);
  // Torso: hunched, armoured, leaning into the shield. Plate reads pale
  // against the ruins' dark stone, with a rim-light outline so the
  // silhouette holds up under the zone's heavier darkness.
  const torso = ctx.createLinearGradient(-r, 0, r, 0);
  torso.addColorStop(0, '#2b2738');
  torso.addColorStop(0.5, champion ? '#5a5178' : '#57536a');
  torso.addColorStop(1, '#3d3a4c');
  ctx.fillStyle = torso;
  ctx.beginPath();
  ctx.ellipse(-r * 0.1, 0, r * 0.85, r * 0.7, 0, 0, TAU);
  ctx.fill();
  ctx.strokeStyle = 'rgba(214,208,232,0.4)';
  ctx.lineWidth = 1.4;
  ctx.stroke();
  // Pauldrons.
  ctx.fillStyle = champion ? '#7a7096' : '#6f6a84';
  ctx.beginPath();
  ctx.arc(-r * 0.15, -r * 0.56, r * 0.32, 0, TAU);
  ctx.arc(-r * 0.15, r * 0.56, r * 0.32, 0, TAU);
  ctx.fill();
  ctx.strokeStyle = 'rgba(0,0,0,0.45)';
  ctx.lineWidth = 1;
  ctx.stroke();
  // Mace arm on the +y side.
  ctx.fillStyle = '#3a3546';
  ctx.fillRect(r * 0.2, r * 0.5, r * 0.75, r * 0.16);
  ctx.fillStyle = '#8b8499';
  ctx.beginPath();
  ctx.arc(r * 0.98, r * 0.58, r * 0.22, 0, TAU);
  ctx.fill();
  // Helm.
  ctx.fillStyle = champion ? '#7a7296' : '#77728a';
  ctx.beginPath();
  ctx.arc(r * 0.35, 0, r * 0.38, 0, TAU);
  ctx.fill();
  ctx.strokeStyle = 'rgba(0,0,0,0.5)';
  ctx.lineWidth = 1;
  ctx.stroke();
  if (champion) {
    // A broken crown of iron.
    ctx.fillStyle = '#7a7290';
    for (const off of [-0.22, 0, 0.22]) {
      ctx.fillRect(r * 0.1, off * r - 2, r * 0.14, 4);
    }
  }
  const eye = champion ? Palette.soulBright : '#d8d2e8';
  ctx.fillStyle = eye;
  ctx.shadowColor = eye;
  ctx.shadowBlur = champion ? 9 : 4;
  ctx.fillRect(r * 0.5, -r * 0.14, r * 0.15, r * 0.28);
  ctx.shadowBlur = 0;

  if (!e.shieldBroken) {
    // The shield: a door-sized slab of worked stone. Raised, it stands
    // square across the front; with the guard down it swings out to the -y
    // side and tilts, leaving the front open.
    ctx.save();
    if (guardDown) {
      ctx.translate(-r * 0.05, -r * 0.95);
      ctx.rotate(-1.1);
    } else {
      ctx.translate(r * 0.74, 0);
    }
    const sw = r * 0.42;
    const sh = r * 2.15;
    const slab = ctx.createLinearGradient(0, -sh / 2, 0, sh / 2);
    slab.addColorStop(0, '#7f7998');
    slab.addColorStop(0.5, '#a49ebb');
    slab.addColorStop(1, '#5a5470');
    ctx.fillStyle = slab;
    roundedRectPath(ctx, -sw / 2, -sh / 2, sw, sh, sw * 0.4);
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    ctx.lineWidth = 1.5;
    roundedRectPath(ctx, -sw / 2, -sh / 2, sw, sh, sw * 0.4);
    ctx.stroke();
    // Carved door-lines and a rune.
    ctx.strokeStyle = rgba(champion ? Palette.soul : '#d2cce4', 0.7);
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.moveTo(0, -sh * 0.36);
    ctx.lineTo(0, sh * 0.36);
    ctx.moveTo(-sw * 0.3, -sh * 0.12);
    ctx.lineTo(sw * 0.3, -sh * 0.12);
    ctx.moveTo(-sw * 0.3, sh * 0.12);
    ctx.lineTo(sw * 0.3, sh * 0.12);
    ctx.stroke();
    if (champion && e.hp < e.maxHp * 0.75) {
      // Cracks spreading as the shatter gets close.
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.lineWidth = 1.3;
      ctx.beginPath();
      ctx.moveTo(-sw * 0.4, -sh * 0.3);
      ctx.lineTo(sw * 0.1, -sh * 0.05);
      ctx.lineTo(-sw * 0.2, sh * 0.25);
      ctx.moveTo(sw * 0.35, sh * 0.1);
      ctx.lineTo(0, sh * 0.32);
      ctx.stroke();
    }
    ctx.restore();
  } else {
    // What's left strapped to the arm: a jagged stub.
    ctx.fillStyle = '#6a6482';
    ctx.beginPath();
    ctx.moveTo(r * 0.6, -r * 0.55);
    ctx.lineTo(r * 0.9, -r * 0.4);
    ctx.lineTo(r * 0.78, -r * 0.05);
    ctx.lineTo(r * 0.95, r * 0.2);
    ctx.lineTo(r * 0.6, r * 0.3);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    ctx.lineWidth = 1.2;
    ctx.stroke();
  }

  if (bashing) {
    ctx.strokeStyle = 'rgba(220,214,235,0.4)';
    ctx.lineWidth = 2;
    for (const off of [-0.5, 0, 0.5]) {
      ctx.beginPath();
      ctx.moveTo(-r * 1.1, off * r);
      ctx.lineTo(-r * 2.2, off * r * 1.3);
      ctx.stroke();
    }
  }
  ctx.restore();

  // Guard-down cue, rotation-independent: a bright pulsing ring — "now".
  if (guardDown && !e.shieldBroken && e.state === 'cooldown') {
    const p = 0.45 + Math.sin(e.animPhase * 18) * 0.3;
    ctx.strokeStyle = rgba(Palette.goldBright, p);
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, 0, r * 1.18, 0, TAU);
    ctx.stroke();
  }
  if (champion && e.shieldBroken && e.alive) {
    // Phase two: spores leaking from the cracks.
    ctx.globalCompositeOperation = 'lighter';
    drawGlowCircle(ctx, 0, 0, r * 1.5, Palette.fungus, 0.16 + Math.sin(e.animPhase * 5) * 0.06);
    ctx.globalCompositeOperation = 'source-over';
  }
}

const DRAWERS: Record<string, (ctx: CanvasRenderingContext2D, e: Enemy) => void> = {
  ashCrawler: drawAshCrawler,
  hollow: drawHollow,
  flameWisp: drawFlameWisp,
  gravebound: drawGravebound,
  shadowStalker: drawShadowStalker,
  cinderWraith: drawCinderWraith,
  emberDevourer: drawEmberDevourer,
  blightbloat: drawBlightbloat,
  hollowWarden: (ctx, e) => drawWarden(ctx, e, false),
  sunkenWarden: (ctx, e) => drawWarden(ctx, e, true),
};

export function drawEnemy(ctx: CanvasRenderingContext2D, enemy: Enemy, screenX: number, screenY: number): void {
  const r = enemy.radius;
  const deathT = enemy.alive ? 0 : Math.min(1, enemy.deathTimer / 0.4);

  ctx.save();
  ctx.translate(screenX, screenY);

  if (enemy.def.behavior !== 'ranged' || enemy.def.id === 'flameWisp') {
    drawSoftShadow(ctx, 0, r * 0.75, r * 0.9, r * 0.35, enemy.def.id === 'flameWisp' || enemy.def.id === 'cinderWraith' ? 0.2 : 0.4);
  }

  if (enemy.isEliteInstance && enemy.alive) {
    const pulse = 0.5 + Math.sin(enemy.animPhase * 3) * 0.2;
    ctx.strokeStyle = rgba(Palette.ember5, pulse);
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.arc(0, r * 0.6, r * 1.15, 0, Math.PI * 2);
    ctx.stroke();
    drawGlowCircle(ctx, 0, 0, r * 2, Palette.ember4, 0.22);
  }

  if (enemy.isMutatedVariant && enemy.alive) {
    // A colder violet tainting the Citadel's warm palette — the game's existing
    // visual language for "something otherworldly" (Shadow Stalker, Cinder
    // Wraith, the Sunken Warden), reused here rather than inventing a new one.
    const pulse = 0.45 + Math.sin(enemy.animPhase * 4.2) * 0.25;
    ctx.strokeStyle = rgba(Palette.soulBright, pulse);
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, r * 0.6, r * 1.05, 0, Math.PI * 2);
    ctx.stroke();
    drawGlowCircle(ctx, 0, 0, r * 1.6, Palette.soul, 0.2);
  }

  telegraphRing(ctx, enemy, r);

  if (deathT > 0) {
    ctx.globalAlpha = Math.max(0, 1 - deathT);
    ctx.scale(1 + deathT * 0.4, 1 - deathT * 0.7);
  }

  const drawer = DRAWERS[enemy.def.id] ?? drawAshCrawler;
  drawer(ctx, enemy);

  statusOverlay(ctx, enemy, r);
  ctx.restore();

  ctx.save();
  ctx.translate(screenX, screenY);
  healthBar(ctx, enemy, r);
  if (enemy.def.isElite || enemy.isEliteInstance || enemy.isMutatedVariant) {
    ctx.font = '700 11px Georgia, serif';
    ctx.textAlign = 'center';
    ctx.fillStyle = enemy.isMutatedVariant && !enemy.isEliteInstance && !enemy.def.isElite ? Palette.soulBright : Palette.ember5;
    ctx.shadowColor = 'rgba(0,0,0,0.8)';
    ctx.shadowBlur = 3;
    ctx.fillText((enemy.displayName ?? tc(enemy.def.id, 'name', enemy.def.name)).toUpperCase(), 0, -r - 18);
    ctx.shadowBlur = 0;
  }
  ctx.restore();
}

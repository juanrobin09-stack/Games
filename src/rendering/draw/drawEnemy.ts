import type { Enemy } from '@/entities/Enemy';
import { Palette, rgba, mixColor } from '@/rendering/Palette';
import { drawSoftShadow, drawGlowCircle, blobPath, hashJitter } from '@/rendering/DrawUtils';

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
  const t = Math.min(1, enemy.stateTimer / Math.max(0.05, enemy.def.telegraphTime));
  ctx.save();
  ctx.globalAlpha = 0.5 * t;
  ctx.strokeStyle = Palette.bloodBright;
  ctx.lineWidth = 2 + t * 2;
  ctx.beginPath();
  ctx.arc(0, 0, enemy.def.attackRange * t, 0, Math.PI * 2);
  ctx.stroke();
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

const DRAWERS: Record<string, (ctx: CanvasRenderingContext2D, e: Enemy) => void> = {
  ashCrawler: drawAshCrawler,
  hollow: drawHollow,
  flameWisp: drawFlameWisp,
  gravebound: drawGravebound,
  shadowStalker: drawShadowStalker,
  cinderWraith: drawCinderWraith,
  emberDevourer: drawEmberDevourer,
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
  if (enemy.def.isElite || enemy.isEliteInstance) {
    ctx.font = '700 11px Georgia, serif';
    ctx.textAlign = 'center';
    ctx.fillStyle = Palette.ember5;
    ctx.shadowColor = 'rgba(0,0,0,0.8)';
    ctx.shadowBlur = 3;
    ctx.fillText((enemy.displayName ?? enemy.def.name).toUpperCase(), 0, -r - 18);
    ctx.shadowBlur = 0;
  }
  ctx.restore();
}

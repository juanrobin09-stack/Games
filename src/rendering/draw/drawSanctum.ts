import type { Camera } from '@/core/Camera';
import { ROOM_WIDTH, ROOM_HEIGHT } from '@/world/Room';
import { Palette, rgba } from '@/rendering/Palette';
import { drawGlowCircle } from '@/rendering/DrawUtils';
import { SANCTUM_RING_RADIUS, SANCTUM_WAVE_COUNT } from '@/world/LevelGenerator';

export const SANCTUM_CANDLE_COUNT = 6;
const CANDLE_RADIUS = SANCTUM_RING_RADIUS * 0.82;

/** World-space position of the i-th candle around the rite. */
export function sanctumCandlePosition(i: number): { x: number; y: number } {
  const angle = -Math.PI / 2 + (i / SANCTUM_CANDLE_COUNT) * Math.PI * 2;
  return {
    x: ROOM_WIDTH / 2 + Math.cos(angle) * CANDLE_RADIUS,
    y: ROOM_HEIGHT / 2 + Math.sin(angle) * CANDLE_RADIUS * 0.72,
  };
}

/** How many candles are burning for a given rite progress: two per wave
 * survived, all six once it's done. */
export function sanctumLitCandles(ritualActive: boolean, wave: number, complete: boolean): number {
  if (complete) return SANCTUM_CANDLE_COUNT;
  if (!ritualActive) return 0;
  return Math.min(SANCTUM_CANDLE_COUNT, Math.max(0, wave) * 2);
}

/**
 * The carved part of the rite (sunken disc, bands, runes, sigil) never
 * changes within one state, so it's baked once per (zoom, colour, alpha)
 * onto an offscreen canvas and blitted — the per-frame cost of the sanctum
 * is then just the breathing glow and the candles. A handful of variants at
 * most (dormant / three wave states / complete, times a zoom or two).
 */
const decalCache = new Map<string, HTMLCanvasElement>();
const MAX_DECALS = 12;

function sanctumDecal(zoom: number, lineColor: string, bandAlpha: number, energy: number): HTMLCanvasElement {
  const key = `${zoom.toFixed(2)}:${lineColor}:${bandAlpha.toFixed(2)}:${energy.toFixed(2)}`;
  const cached = decalCache.get(key);
  if (cached) return cached;
  const R = SANCTUM_RING_RADIUS * zoom;
  const size = Math.ceil(R * 2 + 8);
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  ctx.translate(size / 2, size / 2);

  const disc = ctx.createRadialGradient(0, 0, 0, 0, 0, R);
  disc.addColorStop(0, `rgba(6,5,12,${0.18 + energy * 0.3})`);
  disc.addColorStop(0.85, `rgba(6,5,12,${0.3 + energy * 0.2})`);
  disc.addColorStop(1, 'rgba(6,5,12,0)');
  ctx.fillStyle = disc;
  ctx.beginPath();
  ctx.arc(0, 0, R, 0, Math.PI * 2);
  ctx.fill();

  ctx.strokeStyle = rgba(lineColor, bandAlpha);
  ctx.lineWidth = Math.max(1, 2.2 * zoom);
  ctx.beginPath();
  ctx.arc(0, 0, R, 0, Math.PI * 2);
  ctx.stroke();
  ctx.lineWidth = Math.max(1, 1.2 * zoom);
  ctx.beginPath();
  ctx.arc(0, 0, R * 0.62, 0, Math.PI * 2);
  ctx.stroke();
  const runeCount = 24;
  for (let i = 0; i < runeCount; i++) {
    const a = (i / runeCount) * Math.PI * 2;
    const inner = R * 0.68;
    const outer = R * (i % 3 === 0 ? 0.9 : 0.8);
    ctx.strokeStyle = rgba(lineColor, bandAlpha * (i % 3 === 0 ? 1 : 0.6));
    ctx.beginPath();
    ctx.moveTo(Math.cos(a) * inner, Math.sin(a) * inner);
    ctx.lineTo(Math.cos(a) * outer, Math.sin(a) * outer);
    ctx.stroke();
  }
  ctx.strokeStyle = rgba(lineColor, bandAlpha);
  ctx.lineWidth = Math.max(1, 1.6 * zoom);
  ctx.beginPath();
  ctx.arc(0, 0, R * 0.16, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  for (let i = 0; i < 3; i++) {
    const a = -Math.PI / 2 + (i / 3) * Math.PI * 2;
    const x = Math.cos(a) * R * 0.11;
    const y = Math.sin(a) * R * 0.11;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.stroke();

  if (decalCache.size >= MAX_DECALS) {
    const oldest = decalCache.keys().next().value;
    if (oldest !== undefined) decalCache.delete(oldest);
  }
  decalCache.set(key, canvas);
  return canvas;
}

/**
 * The Drowned Sanctum's floor rite: a sunken disc ringed by carved bands and
 * runes, with six candle cups around it. Dormant, it's a dim violet
 * suggestion on the flagstones; once begun, each wave survived lights two
 * more candles cold-teal, and completion turns the whole thing warm — the
 * one warm light in the ruins that isn't the player's own.
 */
export function drawSanctumCircle(
  ctx: CanvasRenderingContext2D,
  camera: Camera,
  time: number,
  ritualActive: boolean,
  wave: number,
  complete: boolean
): void {
  const c = camera.worldToScreen(ROOM_WIDTH / 2, ROOM_HEIGHT / 2);
  const zoom = camera.zoom;
  const R = SANCTUM_RING_RADIUS * zoom;
  const squash = 0.72;
  const lit = sanctumLitCandles(ritualActive, wave, complete);
  const progress = complete ? 1 : Math.min(1, wave / SANCTUM_WAVE_COUNT);
  const energy = ritualActive ? 0.55 + progress * 0.45 : 0.34;
  const glowColor = complete ? Palette.ember4 : Palette.fungus;
  const lineColor = complete ? Palette.ember5 : ritualActive ? Palette.fungusBright : Palette.soul;
  const bandAlpha = 0.28 + energy * 0.5;

  ctx.save();
  ctx.translate(c.x, c.y);
  ctx.scale(1, squash);
  // Slow turn of the whole carving: barely perceptible dormant, a little
  // more once the rite is running.
  ctx.rotate(time * (ritualActive ? 0.08 : 0.02));
  const decal = sanctumDecal(zoom, lineColor, bandAlpha, energy);
  ctx.drawImage(decal, -decal.width / 2, -decal.height / 2);
  ctx.rotate(-time * (ritualActive ? 0.08 : 0.02));
  ctx.globalCompositeOperation = 'lighter';
  if (ritualActive || complete) {
    drawGlowCircle(ctx, 0, 0, R * 0.55, glowColor, 0.16 * energy * (0.8 + Math.sin(time * 1.7) * 0.2));
  } else {
    // Dormant: a slow violet breath, so the circle invites without shouting.
    drawGlowCircle(ctx, 0, 0, R * 0.7, Palette.soul, 0.07 + Math.sin(time * 1.1) * 0.03);
  }
  ctx.globalCompositeOperation = 'source-over';
  ctx.restore();

  // Candles, drawn unsquashed at their real positions (they stand up).
  for (let i = 0; i < SANCTUM_CANDLE_COUNT; i++) {
    const p = sanctumCandlePosition(i);
    const s = camera.worldToScreen(p.x, p.y);
    const burning = i < lit;
    const cr = 6 * zoom;
    ctx.save();
    ctx.translate(s.x, s.y);
    // Stone cup.
    ctx.fillStyle = '#1c1826';
    ctx.beginPath();
    ctx.ellipse(0, cr * 0.5, cr * 1.3, cr * 0.7, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#2d2838';
    ctx.fillRect(-cr * 0.9, -cr * 0.9, cr * 1.8, cr * 1.4);
    ctx.fillStyle = '#3b3548';
    ctx.beginPath();
    ctx.ellipse(0, -cr * 0.9, cr * 0.9, cr * 0.45, 0, 0, Math.PI * 2);
    ctx.fill();
    if (burning) {
      const flick = 0.85 + Math.sin(time * 9 + i * 1.7) * 0.15;
      const flame = complete ? Palette.ember5 : Palette.fungusBright;
      ctx.globalCompositeOperation = 'lighter';
      drawGlowCircle(ctx, 0, -cr * 1.4, cr * 3.2 * flick, complete ? Palette.ember4 : Palette.fungus, 0.5);
      ctx.globalCompositeOperation = 'source-over';
      ctx.fillStyle = flame;
      ctx.beginPath();
      ctx.moveTo(0, -cr * 2.6 * flick);
      ctx.quadraticCurveTo(cr * 0.55, -cr * 1.5, 0, -cr * 1.0);
      ctx.quadraticCurveTo(-cr * 0.55, -cr * 1.5, 0, -cr * 2.6 * flick);
      ctx.fill();
    } else {
      // Cold: a dark wick and a whisper of old smoke.
      ctx.fillStyle = '#0d0b12';
      ctx.fillRect(-cr * 0.12, -cr * 1.6, cr * 0.24, cr * 0.7);
    }
    ctx.restore();
  }
}

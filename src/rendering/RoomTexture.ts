import { ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS, DOOR_WIDTH } from '@/world/Room';
import type { ZoneDefinition } from '@/data/types';
import { Random } from '@/utils/Random';
import { mixColor } from '@/rendering/Palette';
import { paintWallSwatch, paintJambSwatch, tintSwatch } from '@/rendering/StoneAsset';
import { paintFloorSwatch } from '@/rendering/FloorAsset';

/**
 * Bakes the fussy, expensive-to-redraw part of a room's presentation — individual
 * stone blocks, mortar seams, cracks, moss, the irregular masonry around a door
 * opening — to an offscreen canvas ONCE per room, instead of drawing dozens of
 * shapes every frame. drawRoom.ts just blits the cached result and layers the
 * genuinely dynamic bits (the door's state glow/pulse) on top each frame.
 *
 * Supersampled 2x so it stays crisp at typical zoom levels without retracing at
 * the current camera scale. Cache is a simple capped FIFO keyed by room identity
 * (not just zone+orientation+door), so every room gets its own unique-looking
 * stonework rather than a small set of assets visibly repeating — bounded so a
 * long run can't grow it without limit.
 */

const SUPERSAMPLE = 2;
// 4 wall strips + 1 floor per room now share this cache, so the limit is
// bumped from the original 32 (4/room) to keep roughly the same room headroom.
const MAX_CACHE_ENTRIES = 40;

type WallOrientation = 'horizontal' | 'vertical';

interface WallTextureKey {
  roomKey: string;
  zoneId: string;
  dir: string;
}

const cache = new Map<string, HTMLCanvasElement>();

export function clearRoomTextureCache(): void {
  cache.clear();
}

function cacheKey(k: WallTextureKey): string {
  return `${k.zoneId}:${k.roomKey}:${k.dir}`;
}

function jitterColor(hex: string, rng: Random, spread = 0.16): string {
  const t = rng.range(-spread, spread);
  return t >= 0 ? mixColor(hex, '#fdf6e8', t * 0.5) : mixColor(hex, '#000000', -t);
}

/** Lays out a run of masonry blocks (varying width, shared height) along [0, length],
 * calling `paint` for each with its rect — used identically for straight wall runs
 * and for the two stub runs flanking a door gap. */
function layBlocks(
  rng: Random,
  length: number,
  minW: number,
  maxW: number,
  paint: (x: number, w: number) => void
): void {
  let x = 0;
  while (x < length) {
    const w = Math.min(rng.range(minW, maxW), length - x);
    paint(x, w);
    x += w;
  }
}

function drawBlockFace(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  rng: Random,
  baseColor: string,
  topColor: string
): void {
  // Every block fills its FULL rect edge-to-edge — no inset gap. An earlier
  // version inset each block a couple of px to let the strip's flat dark
  // base fill show through as a "mortar groove," but against real
  // photographic stone that flat, textureless sliver reads as a void — a
  // hole in the wall — rather than a joint, especially once neighboring
  // blocks are themselves detailed photo material. Coverage is guaranteed by
  // construction now (adjacent blocks' full rects touch exactly, since
  // layBlocks lays them out with zero spacing); the seam is suggested purely
  // by a thin stroke drawn on top at the very end, never by leaving a gap.
  const painted = paintWallSwatch(ctx, x, y, w, h, rng.next(), rng.bool(0.5));
  if (painted) {
    tintSwatch(ctx, x, y, w, h, topColor, 0.4);
  } else {
    const grad = ctx.createLinearGradient(0, y, 0, y + h);
    grad.addColorStop(0, jitterColor(mixColor(topColor, '#fffaf0', 0.1), rng, 0.14));
    grad.addColorStop(0.55, jitterColor(topColor, rng, 0.16));
    grad.addColorStop(1, jitterColor(mixColor(topColor, baseColor, 0.55), rng, 0.14));
    ctx.fillStyle = grad;
    ctx.fillRect(x, y, w, h);
  }

  // A brighter top-edge highlight per block, as if each one catches a sliver of ambient light.
  if (h > 3) {
    ctx.fillStyle = `rgba(255,255,255,${0.1 + rng.next() * 0.08})`;
    ctx.fillRect(x, y, w, Math.min(2.5, h * 0.2));
  }
  // A soft shadow along the bottom edge, deepening the groove below each block.
  if (h > 4) {
    ctx.fillStyle = 'rgba(0,0,0,0.22)';
    ctx.fillRect(x, y + h - Math.min(2.5, h * 0.16), w, Math.min(2.5, h * 0.16));
  }

  // Occasional chipped corner — a tiny dark wedge, never on every block.
  if (rng.bool(0.22) && w > 10 && h > 10) {
    const corner = rng.pick([0, 1, 2, 3]);
    const cs = Math.min(w, h) * rng.range(0.15, 0.3);
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath();
    const cx = corner % 2 === 0 ? x : x + w;
    const cy = corner < 2 ? y : y + h;
    const sx = corner % 2 === 0 ? 1 : -1;
    const sy = corner < 2 ? 1 : -1;
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + sx * cs, cy);
    ctx.lineTo(cx, cy + sy * cs);
    ctx.closePath();
    ctx.fill();
  }

  // The mortar joint itself: a thin stroke along the block's own boundary,
  // drawn last so it sits on top of the fill and every overlay above. Two
  // adjacent blocks each stroke the same shared edge, which just doubles a
  // hairline rather than leaving either side unpainted.
  ctx.strokeStyle = 'rgba(0,0,0,0.45)';
  ctx.lineWidth = 1.6;
  ctx.strokeRect(x + 0.8, y + 0.8, Math.max(0, w - 1.6), Math.max(0, h - 1.6));
}

function drawCracks(ctx: CanvasRenderingContext2D, w: number, h: number, rng: Random, count: number): void {
  ctx.strokeStyle = 'rgba(0,0,0,0.4)';
  ctx.lineWidth = 1;
  for (let i = 0; i < count; i++) {
    const startX = rng.range(0, w);
    const startY = rng.range(0, h);
    let cx = startX;
    let cy = startY;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    const segs = rng.int(2, 4);
    for (let s = 0; s < segs; s++) {
      cx += rng.range(-14, 14);
      cy += rng.range(-6, 6);
      ctx.lineTo(cx, cy);
    }
    ctx.stroke();
  }
}

function drawMoss(ctx: CanvasRenderingContext2D, w: number, h: number, rng: Random, count: number): void {
  for (let i = 0; i < count; i++) {
    const x = rng.range(0, w);
    const y = rng.range(h * 0.4, h);
    const r = rng.range(3, 8);
    const grad = ctx.createRadialGradient(x, y, 0, x, y, r);
    grad.addColorStop(0, 'rgba(70,90,55,0.16)');
    grad.addColorStop(1, 'rgba(70,90,55,0)');
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.ellipse(x, y, r, r * 0.6, rng.next() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
}

/** Full-strip solid wall (no door): a straight run of coursing blocks. */
function bakeSolidStrip(canvas: HTMLCanvasElement, length: number, thickness: number, zone: ZoneDefinition, rng: Random): void {
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = mixColor(zone.palette.wall, '#000000', 0.35);
  ctx.fillRect(0, 0, length, thickness);
  layBlocks(rng, length, 34 * SUPERSAMPLE, 64 * SUPERSAMPLE, (x, w) => {
    drawBlockFace(ctx, x, 0, w, thickness, rng, zone.palette.wall, zone.palette.wallTop);
  });
  drawCracks(ctx, length, thickness, rng, rng.int(1, 3));
  drawMoss(ctx, length, thickness, rng, rng.int(1, 3));
}

/** A run of blocks up to a door gap, then chunkier worked jamb stones, then void. */
function bakeDoorStrip(canvas: HTMLCanvasElement, length: number, thickness: number, zone: ZoneDefinition, rng: Random): void {
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = mixColor(zone.palette.wall, '#000000', 0.35);
  ctx.fillRect(0, 0, length, thickness);

  // The gap itself must land exactly on Room.getWalls()'s door boundary — no
  // jitter here. Irregularity comes from the blocks' own varied widths and the
  // jamb detail, never from moving the true opening away from the collision gap.
  const doorW = DOOR_WIDTH * SUPERSAMPLE;
  const gapStart = length / 2 - doorW / 2;
  const gapEnd = length / 2 + doorW / 2;

  layBlocks(rng, gapStart, 34 * SUPERSAMPLE, 64 * SUPERSAMPLE, (x, w) => {
    drawBlockFace(ctx, x, 0, w, thickness, rng, zone.palette.wall, zone.palette.wallTop);
  });
  layBlocks(rng, length - gapEnd, 34 * SUPERSAMPLE, 64 * SUPERSAMPLE, (x, w) => {
    drawBlockFace(ctx, gapEnd + x, 0, w, thickness, rng, zone.palette.wall, zone.palette.wallTop);
  });
  drawCracks(ctx, gapStart, thickness, rng, rng.int(1, 2));
  drawCracks(ctx, length - gapEnd, thickness, rng, rng.int(1, 2));
  drawMoss(ctx, gapStart, thickness, rng, rng.int(0, 2));

  // Void behind the opening — nothing else is ever simulated back there.
  ctx.fillStyle = '#050308';
  ctx.fillRect(gapStart, 0, gapEnd - gapStart, thickness);

  // Chunkier, more uniform worked-stone jambs flanking the opening, proud of the
  // rough coursing on either side and tall enough to read as a real threshold.
  const jambW = 15 * SUPERSAMPLE;
  const jambProtrusion = 10 * SUPERSAMPLE;
  const jambY = -jambProtrusion * 0.3;
  const jambH = thickness + jambProtrusion;
  for (const [gx, flip] of [[gapStart, false], [gapEnd - jambW, true]] as const) {
    // The same source pillar-and-torch swatch is mirrored for the far jamb,
    // so a doorway reads as one deliberately-built, symmetric threshold.
    const painted = paintJambSwatch(ctx, gx, jambY, jambW, jambH, flip);
    if (painted) {
      tintSwatch(ctx, gx, jambY, jambW, jambH, zone.palette.wallTop, 0.35);
    } else {
      const grad = ctx.createLinearGradient(gx, 0, gx + jambW, 0);
      grad.addColorStop(0, zone.palette.wall);
      grad.addColorStop(0.5, mixColor(zone.palette.wallTop, '#ffffff', 0.12));
      grad.addColorStop(1, zone.palette.wall);
      ctx.fillStyle = grad;
      ctx.fillRect(gx, jambY, jambW, jambH);
    }
    // Two or three horizontal seams so the jamb itself reads as stacked stone, not a monolith.
    ctx.strokeStyle = 'rgba(0,0,0,0.35)';
    ctx.lineWidth = 1;
    const seams = rng.int(2, 3);
    for (let s = 1; s <= seams; s++) {
      const sy = jambY + (jambH / (seams + 1)) * s;
      ctx.beginPath();
      ctx.moveTo(gx, sy);
      ctx.lineTo(gx + jambW, sy);
      ctx.stroke();
    }
  }

  // A couple of loose stone fragments at the threshold.
  for (let i = 0; i < rng.int(2, 4); i++) {
    const rx = rng.range(gapStart + jambW * 0.6, gapEnd - jambW * 0.6);
    const ry = thickness - rng.range(2, 8) * SUPERSAMPLE;
    const r = rng.range(2, 5) * SUPERSAMPLE;
    ctx.fillStyle = mixColor(zone.palette.wall, '#000000', 0.15);
    ctx.beginPath();
    ctx.ellipse(rx, ry, r, r * 0.6, rng.next() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
}

function bakeStrip(orientation: WallOrientation, hasDoor: boolean, zone: ZoneDefinition, rng: Random): HTMLCanvasElement {
  const length = (orientation === 'horizontal' ? ROOM_WIDTH : ROOM_HEIGHT) * SUPERSAMPLE;
  const thickness = WALL_THICKNESS * SUPERSAMPLE;
  const canvas = document.createElement('canvas');
  canvas.width = orientation === 'horizontal' ? length : thickness;
  canvas.height = orientation === 'horizontal' ? thickness : length;
  const ctx = canvas.getContext('2d')!;

  if (orientation === 'vertical') {
    // Author every strip in canonical horizontal space, then rotate the whole
    // canvas 90° so the block-laying logic only has to exist once.
    const scratch = document.createElement('canvas');
    scratch.width = length;
    scratch.height = thickness;
    if (hasDoor) bakeDoorStrip(scratch, length, thickness, zone, rng);
    else bakeSolidStrip(scratch, length, thickness, zone, rng);
    ctx.save();
    ctx.translate(0, length);
    ctx.rotate(-Math.PI / 2);
    ctx.drawImage(scratch, 0, 0);
    ctx.restore();
    return canvas;
  }

  if (hasDoor) bakeDoorStrip(canvas, length, thickness, zone, rng);
  else bakeSolidStrip(canvas, length, thickness, zone, rng);
  return canvas;
}

/** Returns the cached (or freshly baked) wall-strip texture for one side of one room. */
export function getWallStrip(
  roomKey: string,
  zone: ZoneDefinition,
  dir: 'N' | 'S' | 'E' | 'W',
  hasDoor: boolean
): HTMLCanvasElement {
  const key = cacheKey({ roomKey, zoneId: zone.id, dir });
  const existing = cache.get(key);
  if (existing) return existing;

  const orientation: WallOrientation = dir === 'N' || dir === 'S' ? 'horizontal' : 'vertical';
  const rng = Random.fromString(`walltex:${zone.id}:${roomKey}:${dir}`);
  const texture = bakeStrip(orientation, hasDoor, zone, rng);

  if (cache.size >= MAX_CACHE_ENTRIES) {
    const oldest = cache.keys().next().value;
    if (oldest !== undefined) cache.delete(oldest);
  }
  cache.set(key, texture);
  return texture;
}

/**
 * Real flagstone, not a flat fill with ruled grid lines: the room's floor is
 * tiled, once per room, from jittered/irregularly-sized "slabs" that each
 * resample a random window of the reference floor photo (FloorAsset.ts) —
 * mirrored, tinted to the zone, and lightly re-shaded per slab so neighbors
 * read as individually-set stone rather than one continuous sampled sheet.
 * Falls back to a flat jittered fill per slab if the asset isn't loaded yet.
 */
function bakeFloor(canvas: HTMLCanvasElement, zone: ZoneDefinition, rng: Random): void {
  const w = ROOM_WIDTH * SUPERSAMPLE;
  const h = ROOM_HEIGHT * SUPERSAMPLE;
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d')!;

  // Deep base fill — reads through the slim gap between slabs as mortar/
  // shadow, and is the whole floor's color if the asset isn't loaded yet.
  ctx.fillStyle = mixColor(zone.palette.floor, '#000000', 0.4);
  ctx.fillRect(0, 0, w, h);

  const targetCell = 165 * SUPERSAMPLE;
  const cols = Math.max(1, Math.round(w / targetCell));
  const rows = Math.max(1, Math.round(h / targetCell));
  const cellW = w / cols;
  const cellH = h / rows;
  const gap = 3 * SUPERSAMPLE;

  for (let cy = 0; cy < rows; cy++) {
    // Alternating rows offset by half a cell (running-bond, like real coursed
    // pavement) — without this, even heavily-jittered slabs still leave every
    // row's seams aligned into straight vertical bands that read as a grid.
    const rowOffset = (cy % 2) * cellW * 0.5;
    for (let cx = -1; cx <= cols; cx++) {
      const jitterW = cellW * rng.range(0.85, 1.05);
      const jitterH = cellH * rng.range(0.85, 1.05);
      const dx = cx * cellW + rowOffset + (cellW - jitterW) / 2 + (rng.next() - 0.5) * cellW * 0.22 + gap;
      const dy = cy * cellH + (cellH - jitterH) / 2 + (rng.next() - 0.5) * cellH * 0.22 + gap;
      const dw = Math.max(4, jitterW - gap * 2);
      const dh = Math.max(4, jitterH - gap * 2);
      if (dx + dw < 0 || dx > w || dy + dh < 0 || dy > h) continue;

      const painted = paintFloorSwatch(ctx, dx, dy, dw, dh, rng.next(), rng.next(), rng.next(), rng.bool(0.5), rng.bool(0.35));
      if (painted) {
        tintSwatch(ctx, dx, dy, dw, dh, zone.palette.floor, 0.32);
        // Faint flat shading per slab — real uneven flagstone rarely sits at
        // exactly the same tone as its neighbor.
        ctx.fillStyle = rng.bool(0.5)
          ? `rgba(255,255,255,${rng.range(0.02, 0.06)})`
          : `rgba(0,0,0,${rng.range(0.04, 0.1)})`;
        ctx.fillRect(dx, dy, dw, dh);
      } else {
        ctx.fillStyle = jitterColor(zone.palette.floorAccent, rng, 0.12);
        ctx.fillRect(dx, dy, dw, dh);
      }
    }
  }

  // Hairline cracks in the same style as the walls, so floor and masonry
  // read as one continuous, ancient, worn material.
  drawCracks(ctx, w, h, rng, rng.int(5, 8));
}

function floorCacheKey(zoneId: string, roomKey: string): string {
  return `floor:${zoneId}:${roomKey}`;
}

/** Returns the cached (or freshly baked) floor texture for one room. */
export function getFloorTexture(roomKey: string, zone: ZoneDefinition): HTMLCanvasElement {
  const key = floorCacheKey(zone.id, roomKey);
  const existing = cache.get(key);
  if (existing) return existing;

  const rng = Random.fromString(`floortex:${zone.id}:${roomKey}`);
  const canvas = document.createElement('canvas');
  bakeFloor(canvas, zone, rng);

  if (cache.size >= MAX_CACHE_ENTRIES) {
    const oldest = cache.keys().next().value;
    if (oldest !== undefined) cache.delete(oldest);
  }
  cache.set(key, canvas);
  return canvas;
}

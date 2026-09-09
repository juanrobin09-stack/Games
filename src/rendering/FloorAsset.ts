import floorShopUrl from '@/assets/textures/floor-and-shop.png';
import { computeLevels, applyLevels, type Levels } from '@/rendering/ImageLevels';

/**
 * The second real photographic asset: one reference image whose left half is
 * a top-down flagstone floor and whose right half is a sheet of individual
 * shop props (see ShopAsset.ts, which reuses this same loaded image rather
 * than fetching it twice). Only the floor half is sampled here, from two
 * separate bands (top and bottom of the panel) — using two spatially
 * distinct sources, on top of the per-slab position/mirror jitter already
 * applied in RoomTexture.ts's bakeFloor, is what keeps a room's floor from
 * reading as the same handful of recognizable chunks tiled in a visible
 * pattern, which a single narrow band can't avoid no matter how much you
 * jitter within it.
 */

interface FloorRegion {
  x: number;
  y: number;
  w: number;
  h: number;
}

const FLOOR_BANDS: FloorRegion[] = [
  { x: 15, y: 520, w: 845, h: 340 },
  { x: 15, y: 20, w: 845, h: 250 },
];

let img: HTMLImageElement | null = null;
let ready = false;
let loadPromise: Promise<void> | null = null;

/** Kicks off the (near-instant, locally-bundled) image load. Safe to call
 * repeatedly — later calls just return the same in-flight/settled promise. */
export function preloadFloorAsset(): Promise<void> {
  if (loadPromise) return loadPromise;
  const el = new Image();
  img = el;
  loadPromise = new Promise((resolve) => {
    el.onload = () => {
      ready = true;
      resolve();
    };
    el.onerror = () => resolve();
    el.src = floorShopUrl;
  });
  return loadPromise;
}

/** Raw accessor to the loaded image (or null before it's ready) — reused by
 * ShopAsset.ts so the second half of the same sheet doesn't load twice. */
export function floorAssetImage(): HTMLImageElement | null {
  return ready ? img : null;
}

const levelsCache = new Map<FloorRegion, Levels>();

function regionLevels(source: HTMLImageElement, region: FloorRegion): Levels {
  let levels = levelsCache.get(region);
  if (!levels) {
    levels = computeLevels(source, region);
    levelsCache.set(region, levels);
  }
  return levels;
}

/** Paints a randomized window of one of the two floor bands (mirrored on
 * either/both axes) into the destination rect, clipped to it. `bandPick`
 * (0..1) chooses which band; the crop is deliberately smaller relative to
 * the destination than a naive fill would use, so there's real room to
 * reposition it within the band — a crop nearly as big as the band itself
 * barely moves between draws no matter how the jitter is randomized.
 * Returns false (paints nothing) if the source image isn't loaded yet. */
export function paintFloorSwatch(
  ctx: CanvasRenderingContext2D,
  dx: number,
  dy: number,
  dw: number,
  dh: number,
  bandPick: number,
  jitterX: number,
  jitterY: number,
  flipH: boolean,
  flipV: boolean
): boolean {
  const source = floorAssetImage();
  if (!source) return false;
  const region = FLOOR_BANDS[bandPick < 0.5 ? 0 : 1];
  const sw = Math.min(region.w, Math.max(dw * 0.55, 90));
  const sh = Math.min(region.h, Math.max(dh * 0.55, 90));
  const sx = region.x + jitterX * Math.max(0, region.w - sw);
  const sy = region.y + jitterY * Math.max(0, region.h - sh);

  ctx.save();
  ctx.beginPath();
  ctx.rect(dx, dy, dw, dh);
  ctx.clip();
  ctx.translate(dx + dw / 2, dy + dh / 2);
  ctx.scale(flipH ? -1 : 1, flipV ? -1 : 1);
  ctx.drawImage(source, sx, sy, sw, sh, -dw / 2, -dh / 2, dw, dh);
  ctx.restore();

  // Same reasoning as StoneAsset.ts: the source photo is only really lit
  // right around its own torch glow, so a crop from elsewhere in frame
  // needs its brightness stretched back up or it bakes in as a dark void.
  applyLevels(ctx, dx, dy, dw, dh, regionLevels(source, region));
  return true;
}

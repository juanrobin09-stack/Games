import floorShopUrl from '@/assets/textures/floor-and-shop.png';

/**
 * The second real photographic asset: one reference image whose left half is
 * a top-down flagstone floor and whose right half is a sheet of individual
 * shop props (see ShopAsset.ts, which reuses this same loaded image rather
 * than fetching it twice). Only the floor half is sampled here, from a band
 * along its lower portion chosen to stay clear of the image's own baked-in
 * central torchlight hotspot — tiling a copy of *that* would fight the
 * game's real dynamic lighting with a second, static highlight in whatever
 * position the tile happens to land.
 */

const FLOOR_BAND = { x: 15, y: 500, w: 845, h: 370 };

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

/** Paints a randomized window of the floor band (mirrored if `flip`) into the
 * destination rect, clipped to it. Returns false (paints nothing) if the
 * source image isn't loaded yet. */
export function paintFloorSwatch(
  ctx: CanvasRenderingContext2D,
  dx: number,
  dy: number,
  dw: number,
  dh: number,
  jitterX: number,
  jitterY: number,
  flip: boolean
): boolean {
  const source = floorAssetImage();
  if (!source) return false;
  const sw = Math.min(FLOOR_BAND.w, Math.max(dw * 0.9, 60));
  const sh = Math.min(FLOOR_BAND.h, Math.max(dh * 0.9, 60));
  const sx = FLOOR_BAND.x + jitterX * Math.max(0, FLOOR_BAND.w - sw);
  const sy = FLOOR_BAND.y + jitterY * Math.max(0, FLOOR_BAND.h - sh);

  ctx.save();
  ctx.beginPath();
  ctx.rect(dx, dy, dw, dh);
  ctx.clip();
  if (flip) {
    ctx.translate(dx + dw, dy);
    ctx.scale(-1, 1);
    ctx.drawImage(source, sx, sy, sw, sh, 0, 0, dw, dh);
  } else {
    ctx.drawImage(source, sx, sy, sw, sh, dx, dy, dw, dh);
  }
  ctx.restore();
  return true;
}

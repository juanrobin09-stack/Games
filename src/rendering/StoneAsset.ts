import wallTextureUrl from '@/assets/textures/ancient-wall.png';
import { rgba } from '@/rendering/Palette';
import { computeLevels, applyLevels, type Levels } from '@/rendering/ImageLevels';

/**
 * The one real photographic asset in the game: a painted top-down stone wall
 * and doorway (1675x939) supplied as the visual reference for Emberfall's
 * masonry. Rather than stretching it across every wall as one giant repeating
 * poster — which would read as an obvious, identical texture in every room —
 * small hand-picked regions of it are resampled as material swatches: a clean
 * run of coursed ashlar (no door, no corner, no torch in frame), the corner
 * pilaster block, and one door jamb pillar with its mounted torch (the second
 * jamb of a doorway just mirrors the first). RoomTexture.ts composites these
 * swatches into the same per-room baked layout — block coursing, mortar
 * grooves, door gap — that used to be filled with solid gradients, so real
 * stone detail now sits under those grooves/highlights instead of flat color.
 */

interface StoneRegion {
  x: number;
  y: number;
  w: number;
  h: number;
}

const PLAIN_WALL: StoneRegion = { x: 115, y: 168, w: 500, h: 78 };
const CORNER_BLOCK: StoneRegion = { x: 20, y: 163, w: 80, h: 130 };
const DOOR_JAMB: StoneRegion = { x: 662, y: 93, w: 70, h: 202 };

let img: HTMLImageElement | null = null;
let ready = false;
let loadPromise: Promise<void> | null = null;

/** Kicks off the (near-instant, locally-bundled) image load. Safe to call
 * repeatedly — later calls just return the same in-flight/settled promise. */
export function preloadStoneAsset(): Promise<void> {
  if (loadPromise) return loadPromise;
  const el = new Image();
  img = el;
  loadPromise = new Promise((resolve) => {
    el.onload = () => {
      ready = true;
      resolve();
    };
    // If the asset ever fails to load, every swatch call below simply returns
    // false and its caller falls back to the old procedural fill — never a
    // crash, never a blank wall.
    el.onerror = () => resolve();
    el.src = wallTextureUrl;
  });
  return loadPromise;
}

function stoneImage(): HTMLImageElement | null {
  return ready ? img : null;
}

export function stoneAssetReady(): boolean {
  return ready;
}

const levelsCache = new Map<StoneRegion, Levels>();

/** Each region's brightness range is only measured once (on first use) and
 * reused for every block drawn from it — a shared, consistent "exposure"
 * rather than every individual block auto-leveling itself differently. */
function regionLevels(source: HTMLImageElement, region: StoneRegion): Levels {
  let levels = levelsCache.get(region);
  if (!levels) {
    levels = computeLevels(source, region);
    levelsCache.set(region, levels);
  }
  return levels;
}

/** Paints a randomized horizontal window of `region` (mirrored if `flip`) into
 * the destination rect, clipped to it. `jitter01` (0..1) picks where within
 * the region's width that window starts — callers pass a seeded value so a
 * given room's masonry stays stable across cache rebakes. Returns false (and
 * paints nothing) if the source image isn't loaded yet. */
function paintSwatch(
  ctx: CanvasRenderingContext2D,
  region: StoneRegion,
  dx: number,
  dy: number,
  dw: number,
  dh: number,
  jitter01: number,
  flip: boolean
): boolean {
  const source = stoneImage();
  if (!source) return false;
  const sw = Math.min(region.w, Math.max(dw * 0.85, 36));
  const sx = region.w > sw ? region.x + jitter01 * (region.w - sw) : region.x;

  ctx.save();
  ctx.beginPath();
  ctx.rect(dx, dy, dw, dh);
  ctx.clip();
  if (flip) {
    ctx.translate(dx + dw, dy);
    ctx.scale(-1, 1);
    ctx.drawImage(source, sx, region.y, sw, region.h, 0, 0, dw, dh);
  } else {
    ctx.drawImage(source, sx, region.y, sw, region.h, dx, dy, dw, dh);
  }
  ctx.restore();

  // The source photo is lit almost entirely by its own torches — everywhere
  // else in frame (which is most of where these regions sample from) sits
  // far below a legible brightness by the artist's own design. Left as-is,
  // that bakes in as a near-black void once tiled outside the one spot the
  // torches actually lit. Stretching each region's own measured brightness
  // range back up to something legible reveals the real relative detail
  // that's there (block edges, mortar, cracks) instead of flat dark noise.
  applyLevels(ctx, dx, dy, dw, dh, regionLevels(source, region));
  return true;
}

export function paintWallSwatch(ctx: CanvasRenderingContext2D, dx: number, dy: number, dw: number, dh: number, jitter01: number, flip: boolean): boolean {
  return paintSwatch(ctx, PLAIN_WALL, dx, dy, dw, dh, jitter01, flip);
}

export function paintCornerSwatch(ctx: CanvasRenderingContext2D, dx: number, dy: number, dw: number, dh: number, jitter01: number): boolean {
  return paintSwatch(ctx, CORNER_BLOCK, dx, dy, dw, dh, jitter01, false);
}

export function paintJambSwatch(ctx: CanvasRenderingContext2D, dx: number, dy: number, dw: number, dh: number, flip: boolean): boolean {
  return paintSwatch(ctx, DOOR_JAMB, dx, dy, dw, dh, 0.3, flip);
}

/** Recolors whatever was just painted inside (dx,dy,dw,dh) toward `tint`, using
 * the 'color' composite mode so the photo's own shading/depth survives —
 * only its hue/saturation shifts, per zone palette. */
export function tintSwatch(ctx: CanvasRenderingContext2D, dx: number, dy: number, dw: number, dh: number, tint: string, alpha: number): void {
  ctx.save();
  ctx.beginPath();
  ctx.rect(dx, dy, dw, dh);
  ctx.clip();
  ctx.globalCompositeOperation = 'color';
  ctx.fillStyle = rgba(tint, alpha);
  ctx.fillRect(dx, dy, dw, dh);
  ctx.restore();
}

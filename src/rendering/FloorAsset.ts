import dungeonRoomUrl from '@/assets/textures/dungeon-room-ref.png';
import { computeLevels, applyLevels, type Levels } from '@/rendering/ImageLevels';

/**
 * The floor's real photographic asset: a full top-down dungeon room render
 * (the player, the door and the torch's own light pool in this photo are
 * exactly what the floor renderer must NOT copy — only the stone material
 * itself). Two bands are sampled, both from well outside the photo's own
 * torch hotspot (roughly x:520-970, y:300-480) so a baked-in "this exact
 * spot is lit" doesn't get tiled across every floor in the game and fight
 * the actual dynamic light — everywhere else in this particular photo is
 * lit evenly enough to read as neutral, undirected ambient stone.
 */

interface FloorRegion {
  x: number;
  y: number;
  w: number;
  h: number;
}

const FLOOR_BANDS: FloorRegion[] = [
  { x: 170, y: 80, w: 340, h: 740 },
  { x: 1010, y: 80, w: 600, h: 740 },
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
    el.src = dungeonRoomUrl;
  });
  return loadPromise;
}

function floorImage(): HTMLImageElement | null {
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
 * either/both axes) into the destination rect. Unlike the wall swatches,
 * this does NOT clip to (dx,dy,dw,dh) itself — RoomTexture.ts's organic
 * slab shapes establish their own clip path before calling this, so the
 * photo fill follows that silhouette rather than a plain rectangle.
 * `bandPick` (0..1) chooses which band; the crop is deliberately smaller
 * relative to the destination than a naive fill would use, so there's real
 * room to reposition it within the band — a crop nearly as big as the band
 * itself barely moves between draws no matter how the jitter is
 * randomized. Returns false (paints nothing) if the source isn't loaded. */
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
  const source = floorImage();
  if (!source) return false;
  const region = FLOOR_BANDS[bandPick < 0.5 ? 0 : 1];
  const sw = Math.min(region.w, Math.max(dw * 0.5, 80));
  const sh = Math.min(region.h, Math.max(dh * 0.5, 80));
  const sx = region.x + jitterX * Math.max(0, region.w - sw);
  const sy = region.y + jitterY * Math.max(0, region.h - sh);

  // The levels stretch below needs putImageData, which writes raw pixels
  // straight into the canvas bitmap ignoring whatever clip is active — fine
  // against a plain rect clip (the old flat-rect slabs), but against an
  // organic blob clip it would paint a visible rectangular halo right
  // through the silhouette. So the crop is drawn and corrected on a small
  // unclipped scratch canvas first, and only the finished result is
  // composited into the real destination via drawImage, which — unlike
  // putImageData — does respect the caller's clip path.
  const scratchW = Math.max(1, Math.round(dw));
  const scratchH = Math.max(1, Math.round(dh));
  const scratch = document.createElement('canvas');
  scratch.width = scratchW;
  scratch.height = scratchH;
  // Read back once for the levels pass: flag it so the browser keeps this
  // scratch bitmap CPU-side instead of round-tripping through the GPU.
  const sctx = scratch.getContext('2d', { willReadFrequently: true })!;
  sctx.save();
  sctx.translate(scratchW / 2, scratchH / 2);
  sctx.scale(flipH ? -1 : 1, flipV ? -1 : 1);
  sctx.drawImage(source, sx, sy, sw, sh, -scratchW / 2, -scratchH / 2, scratchW, scratchH);
  sctx.restore();
  // Same reasoning as the walls: even the photo's "evenly lit" areas sit at
  // a fairly low ambient brightness (this is a dark scene, not a lit
  // material scan), so a per-region levels stretch keeps the real stone
  // detail — cracks, edges, grain — legible once tiled.
  applyLevels(sctx, 0, 0, scratchW, scratchH, regionLevels(source, region));

  ctx.drawImage(scratch, dx, dy);
  return true;
}

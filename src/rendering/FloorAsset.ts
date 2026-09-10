import dungeonRoomUrl from '@/assets/textures/dungeon-room-ref.png';
import { computeLevels, applyLevels, type Levels } from '@/rendering/ImageLevels';

/**
 * The floor's real photographic asset: a full top-down dungeon room render
 * (the player, the door and the torch's own light pool in this photo are
 * exactly what the floor renderer must NOT copy — only the stone material
 * itself). The photo's own floor is ALREADY a mosaic of large individual
 * flagstones, each bordered by a bright, high-contrast mortar seam — which
 * matters here because our own procedural slab grid (RoomTexture.ts) draws
 * its own independent flagstone shapes and grout on top. Early on, the crop
 * window sampled from two wide, loosely-bounded regions of the photo at
 * roughly the same physical scale as the photo's own flagstones, so a crop
 * would often straddle one of the photo's real seams — baking a second,
 * misaligned mortar line into the middle of one of our own slabs, which
 * read as an extra, wrong "segmentation" cutting the floor into more pieces
 * than the procedural grid actually draws.
 *
 * The fix is to only ever crop from hand-picked patches that sit fully
 * *inside* one real flagstone's interior, well clear of every seam, so no
 * crop can ever reintroduce one. These four were found by scanning the
 * photo for windows with no coherent high-contrast line running through
 * them (a real seam always shows up as one column or row whose edge-pixel
 * count towers over the rest — ordinary pebble/grain texture never
 * concentrates that way, and — this mattered — the check has to run on
 * the same brightness range `applyLevels` stretches into afterwards, since
 * the raw source is dim enough that a real seam can hide under a fixed
 * brightness threshold and only turn visible post-stretch) and then
 * confirming each by eye at 3x, both raw and stretched — a first pass keyed
 * on raw brightness alone quietly passed several patches that turned out to
 * still have a seam in them once actually rendered in-game, so this second
 * pass doesn't trust the metric without a visual check to back it up.
 * Each patch is sized generously relative to the small crop actually taken
 * from it, leaving real jitter room so repeated samples of the same patch
 * still vary. Also kept clear of the photo's own torch hotspot (roughly
 * x:540-990, y:110-690) so a baked-in "this exact spot is lit" doesn't get
 * tiled across every floor in the game and fight the actual dynamic light.
 */

interface FloorRegion {
  x: number;
  y: number;
  w: number;
  h: number;
}

const FLOOR_SAFE_PATCHES: FloorRegion[] = [
  { x: 216, y: 312, w: 130, h: 130 },
  { x: 1432, y: 104, w: 130, h: 130 },
  { x: 1080, y: 664, w: 130, h: 130 },
  { x: 180, y: 642, w: 110, h: 125 },
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

/** Paints a randomized window of one of the five seam-free patches (mirrored
 * on either/both axes) into the destination rect. Unlike the wall swatches,
 * this does NOT clip to (dx,dy,dw,dh) itself — RoomTexture.ts's organic
 * slab shapes establish their own clip path before calling this, so the
 * photo fill follows that silhouette rather than a plain rectangle.
 * `patchPick` (0..1) chooses which of the five patches; the crop stays
 * meaningfully smaller than the patch itself (never the reverse) so it can
 * jitter freely within the patch's verified-clean interior without ever
 * reaching back out to a real seam. Returns false (paints nothing) if the
 * source isn't loaded. */
export function paintFloorSwatch(
  ctx: CanvasRenderingContext2D,
  dx: number,
  dy: number,
  dw: number,
  dh: number,
  patchPick: number,
  jitterX: number,
  jitterY: number,
  flipH: boolean,
  flipV: boolean
): boolean {
  const source = floorImage();
  if (!source) return false;
  const index = Math.min(FLOOR_SAFE_PATCHES.length - 1, Math.floor(patchPick * FLOOR_SAFE_PATCHES.length));
  const region = FLOOR_SAFE_PATCHES[index];
  const sw = Math.min(region.w, Math.max(dw * 0.35, 64));
  const sh = Math.min(region.h, Math.max(dh * 0.35, 64));
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

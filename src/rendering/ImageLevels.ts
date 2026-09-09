/**
 * Both reference photographs (wall and floor-and-shop) are dark, atmospheric
 * scene renders lit almost entirely by a couple of torches — everywhere else
 * in frame sits far below a legible brightness, by the artist's own design,
 * not because detail is missing. Sampling those areas verbatim for a tiled
 * material bakes that low, scene-specific exposure straight into the wall
 * and floor textures: a "material swatch" cropped from one of those darker
 * regions reads as a near-black void once it's tiled outside the one spot in
 * the original image where the torches actually lit it.
 *
 * The fix is a per-region levels stretch — the same idea as a photo editor's
 * "auto levels": remap the region's own actually-observed brightness range
 * up to a legible one. Because it's a monotonic remap of the existing
 * distribution (not a flat brighten or a different texture), the real
 * relative surface detail already in the source — block edges, mortar
 * grooves, cracks — becomes visible instead of stretched-thin noise.
 */

export interface Levels {
  lo: number;
  hi: number;
}

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** Measures one region's brightness range, clipped to the `percentile`..
 * `1-percentile` band so a handful of outlier pixels (a torch flame's own
 * near-white core, a single stray highlight) can't skew the whole stretch.
 * Call once per region, right after the source image loads — not per draw. */
export function computeLevels(source: HTMLImageElement, region: Rect, percentile = 0.02): Levels {
  const canvas = document.createElement('canvas');
  canvas.width = region.w;
  canvas.height = region.h;
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(source, region.x, region.y, region.w, region.h, 0, 0, region.w, region.h);
  const data = ctx.getImageData(0, 0, region.w, region.h).data;

  const hist = new Array(256).fill(0);
  let total = 0;
  for (let i = 0; i < data.length; i += 4) {
    hist[Math.round((data[i] + data[i + 1] + data[i + 2]) / 3)]++;
    total++;
  }
  let cum = 0;
  let lo = 0;
  for (let v = 0; v < 256; v++) {
    cum += hist[v];
    if (cum >= total * percentile) {
      lo = v;
      break;
    }
  }
  cum = 0;
  let hi = 255;
  for (let v = 255; v >= 0; v--) {
    cum += hist[v];
    if (cum >= total * percentile) {
      hi = v;
      break;
    }
  }
  return { lo, hi: Math.max(hi, lo + 8) };
}

/** Stretches whatever was just painted inside (dx,dy,dw,dh) from `levels`'
 * measured range up to [floor,ceiling], with `gamma` < 1 lifting midtones a
 * touch further — so a swatch cropped from a dim part of the source photo
 * still reads as detailed stone rather than a flat dark patch. Operates in
 * destination pixel space, so it applies equally whether the swatch was
 * drawn flipped/mirrored or not. */
export function applyLevels(
  ctx: CanvasRenderingContext2D,
  dx: number,
  dy: number,
  dw: number,
  dh: number,
  levels: Levels,
  floor = 18,
  ceiling = 228,
  gamma = 0.82
): void {
  const x = Math.round(dx);
  const y = Math.round(dy);
  const w = Math.max(1, Math.round(dw));
  const h = Math.max(1, Math.round(dh));
  const frame = ctx.getImageData(x, y, w, h);
  const px = frame.data;
  const span = Math.max(1, levels.hi - levels.lo);
  for (let i = 0; i < px.length; i += 4) {
    for (let c = 0; c < 3; c++) {
      const t = Math.pow(Math.max(0, Math.min(1, (px[i + c] - levels.lo) / span)), gamma);
      px[i + c] = Math.round(floor + t * (ceiling - floor));
    }
  }
  ctx.putImageData(frame, x, y);
}

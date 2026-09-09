import shopPropsUrl from '@/assets/textures/shop-props.png';

/**
 * A sprite sheet of individual shop props painted on a flat near-black
 * background rather than a photo with real transparency. Since the source
 * has no alpha channel, each sprite crop is chroma-keyed once — near-black
 * pixels erased to transparent, feathered rather than hard-cut so the
 * silhouette's edge doesn't look jagged — and the processed result cached,
 * so every subsequent draw is a normal, cheap drawImage.
 */

interface SpriteRegion {
  x: number;
  y: number;
  w: number;
  h: number;
}

const STALL_STONE: SpriteRegion = { x: 948, y: 45, w: 465, h: 340 };

let img: HTMLImageElement | null = null;
let ready = false;
let loadPromise: Promise<void> | null = null;

/** Kicks off the (near-instant, locally-bundled) image load. Safe to call
 * repeatedly — later calls just return the same in-flight/settled promise. */
export function preloadShopAsset(): Promise<void> {
  if (loadPromise) return loadPromise;
  const el = new Image();
  img = el;
  loadPromise = new Promise((resolve) => {
    el.onload = () => {
      ready = true;
      resolve();
    };
    el.onerror = () => resolve();
    el.src = shopPropsUrl;
  });
  return loadPromise;
}

function shopImage(): HTMLImageElement | null {
  return ready ? img : null;
}

const processedCache = new Map<string, HTMLCanvasElement>();

function chromaKey(region: SpriteRegion): HTMLCanvasElement | null {
  const source = shopImage();
  if (!source) return null;
  const key = `${region.x},${region.y},${region.w},${region.h}`;
  const existing = processedCache.get(key);
  if (existing) return existing;

  const canvas = document.createElement('canvas');
  canvas.width = region.w;
  canvas.height = region.h;
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(source, region.x, region.y, region.w, region.h, 0, 0, region.w, region.h);

  const frame = ctx.getImageData(0, 0, region.w, region.h);
  const px = frame.data;
  // Measured directly off the sheet: its background sits at luminance ~5-9,
  // but this is a *dark* dungeon painting — a lot of the sprite's own real
  // stone-in-shadow detail also reads well under luminance 30. A wide ramp
  // (as a naive "anything dim is background" rule would use) was fading out
  // a huge share of legitimate dark material along with the background,
  // leaving the whole stall looking faint/ghostly in play. The ramp here is
  // narrow and sits just above the measured background range, so it only
  // feathers the true edge instead of bleeding into real material.
  const zero = 10;
  const full = 19;
  for (let i = 0; i < px.length; i += 4) {
    const lum = (px[i] + px[i + 1] + px[i + 2]) / 3;
    const alpha = Math.min(1, Math.max(0, (lum - zero) / (full - zero)));
    px[i + 3] = Math.round(px[i + 3] * alpha);
  }
  ctx.putImageData(frame, 0, 0);
  processedCache.set(key, canvas);
  return canvas;
}

/** The stone-canopy merchant stall, background keyed to transparent — or
 * null if the source image hasn't loaded yet, so callers can fall back. */
export function getStallSprite(): HTMLCanvasElement | null {
  return chromaKey(STALL_STONE);
}

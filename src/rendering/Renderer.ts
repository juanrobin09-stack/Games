/**
 * Owns the canvas element, its backing-store resolution and DPI scaling.
 * Keeps a stable logical resolution (matched to CSS size) while rendering at
 * device pixel ratio for crispness — this is the only place that touches
 * canvas sizing so responsive behavior stays consistent everywhere else.
 */
export class Renderer {
  readonly canvas: HTMLCanvasElement;
  readonly ctx: CanvasRenderingContext2D;
  width = 960;
  height = 540;
  private dpr = 1;
  private resizeObserver: ResizeObserver;
  qualityScale = 1;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    const ctx = canvas.getContext('2d', { alpha: false });
    if (!ctx) throw new Error('Canvas 2D context unavailable');
    this.ctx = ctx;
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(canvas.parentElement ?? canvas);
    this.resize();
  }

  resize(): void {
    const parent = this.canvas.parentElement;
    const cssWidth = parent ? parent.clientWidth : window.innerWidth;
    const cssHeight = parent ? parent.clientHeight : window.innerHeight;
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.width = Math.max(320, Math.floor(cssWidth));
    this.height = Math.max(240, Math.floor(cssHeight));
    const backingW = Math.floor(this.width * this.dpr * this.qualityScale);
    const backingH = Math.floor(this.height * this.dpr * this.qualityScale);
    if (this.canvas.width !== backingW || this.canvas.height !== backingH) {
      this.canvas.width = backingW;
      this.canvas.height = backingH;
    }
    this.canvas.style.width = `${this.width}px`;
    this.canvas.style.height = `${this.height}px`;
    this.ctx.setTransform(this.dpr * this.qualityScale, 0, 0, this.dpr * this.qualityScale, 0, 0);
  }

  setQualityScale(scale: number): void {
    this.qualityScale = scale;
    this.resize();
  }

  clear(color: string): void {
    this.ctx.save();
    this.ctx.setTransform(this.dpr * this.qualityScale, 0, 0, this.dpr * this.qualityScale, 0, 0);
    this.ctx.fillStyle = color;
    this.ctx.fillRect(0, 0, this.width, this.height);
    this.ctx.restore();
  }

  destroy(): void {
    this.resizeObserver.disconnect();
  }
}

import type { Camera } from '@/core/Camera';

export type ParticleShape = 'circle' | 'spark' | 'square' | 'ring';

interface Particle {
  active: boolean;
  x: number;
  y: number;
  vx: number;
  vy: number;
  gravity: number;
  drag: number;
  size: number;
  endSize: number;
  color: string;
  endColor: string | null;
  alpha: number;
  endAlpha: number;
  life: number;
  age: number;
  rotation: number;
  spin: number;
  glow: boolean;
  shape: ParticleShape;
}

export interface ParticleOptions {
  x: number;
  y: number;
  vx?: number;
  vy?: number;
  gravity?: number;
  drag?: number;
  size: number;
  endSize?: number;
  color: string;
  endColor?: string;
  alpha?: number;
  endAlpha?: number;
  life: number;
  rotation?: number;
  spin?: number;
  glow?: boolean;
  shape?: ParticleShape;
}

export type ParticleQuality = 'low' | 'medium' | 'high';

const QUALITY_LIMITS: Record<ParticleQuality, number> = {
  low: 160,
  medium: 340,
  high: 600,
};

/**
 * Fixed-capacity particle pool. Never allocates once warmed up: spawning past
 * the cap recycles the oldest particle instead of growing (keeps the frame
 * budget flat no matter how chaotic combat gets).
 */
export class ParticleSystem {
  private particles: Particle[];
  private cursor = 0;
  private capacity: number;
  quality: ParticleQuality = 'high';
  enabled = true;

  constructor(capacity = QUALITY_LIMITS.high) {
    this.capacity = capacity;
    this.particles = Array.from({ length: capacity }, () => this.blank());
  }

  private blank(): Particle {
    return {
      active: false,
      x: 0,
      y: 0,
      vx: 0,
      vy: 0,
      gravity: 0,
      drag: 0,
      size: 1,
      endSize: 1,
      color: '#fff',
      endColor: null,
      alpha: 1,
      endAlpha: 0,
      life: 1,
      age: 0,
      rotation: 0,
      spin: 0,
      glow: false,
      shape: 'circle',
    };
  }

  setQuality(q: ParticleQuality): void {
    this.quality = q;
  }

  private get activeLimit(): number {
    return Math.min(this.capacity, QUALITY_LIMITS[this.quality]);
  }

  spawn(opts: ParticleOptions): void {
    if (!this.enabled) return;
    if (this.cursor >= this.activeLimit) this.cursor = 0;
    const p = this.particles[this.cursor];
    this.cursor = (this.cursor + 1) % this.capacity;
    p.active = true;
    p.x = opts.x;
    p.y = opts.y;
    p.vx = opts.vx ?? 0;
    p.vy = opts.vy ?? 0;
    p.gravity = opts.gravity ?? 0;
    p.drag = opts.drag ?? 0;
    p.size = opts.size;
    p.endSize = opts.endSize ?? opts.size * 0.3;
    p.color = opts.color;
    p.endColor = opts.endColor ?? null;
    p.alpha = opts.alpha ?? 1;
    p.endAlpha = opts.endAlpha ?? 0;
    p.life = opts.life;
    p.age = 0;
    p.rotation = opts.rotation ?? 0;
    p.spin = opts.spin ?? 0;
    p.glow = opts.glow ?? false;
    p.shape = opts.shape ?? 'circle';
  }

  burst(count: number, make: (i: number) => ParticleOptions): void {
    const limited = this.quality === 'low' ? Math.ceil(count * 0.5) : count;
    for (let i = 0; i < limited; i++) this.spawn(make(i));
  }

  update(dt: number): void {
    for (const p of this.particles) {
      if (!p.active) continue;
      p.age += dt;
      if (p.age >= p.life) {
        p.active = false;
        continue;
      }
      p.vy += p.gravity * dt;
      const dragF = Math.max(0, 1 - p.drag * dt);
      p.vx *= dragF;
      p.vy *= dragF;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rotation += p.spin * dt;
    }
  }

  render(ctx: CanvasRenderingContext2D, camera: Camera): void {
    for (const p of this.particles) {
      if (!p.active) continue;
      const screen = camera.worldToScreen(p.x, p.y);
      if (screen.x < -60 || screen.x > camera.width + 60 || screen.y < -60 || screen.y > camera.height + 60) continue;
      const t = p.age / p.life;
      const size = p.size + (p.endSize - p.size) * t;
      const alpha = Math.max(0, p.alpha + (p.endAlpha - p.alpha) * t);
      if (alpha <= 0.003 || size <= 0.05) continue;
      const color = p.endColor ? mixHex(p.color, p.endColor, t) : p.color;

      ctx.save();
      ctx.globalCompositeOperation = p.glow ? 'lighter' : 'source-over';
      ctx.globalAlpha = alpha;
      ctx.fillStyle = color;
      ctx.translate(screen.x, screen.y);
      ctx.rotate(p.rotation);

      switch (p.shape) {
        case 'circle':
          ctx.beginPath();
          ctx.arc(0, 0, size, 0, Math.PI * 2);
          ctx.fill();
          break;
        case 'square':
          ctx.fillRect(-size / 2, -size / 2, size, size);
          break;
        case 'spark':
          ctx.beginPath();
          ctx.moveTo(-size * 1.6, 0);
          ctx.lineTo(0, -size * 0.5);
          ctx.lineTo(size * 1.6, 0);
          ctx.lineTo(0, size * 0.5);
          ctx.closePath();
          ctx.fill();
          break;
        case 'ring':
          ctx.strokeStyle = color;
          ctx.lineWidth = Math.max(1, size * 0.25);
          ctx.beginPath();
          ctx.arc(0, 0, size, 0, Math.PI * 2);
          ctx.stroke();
          break;
      }
      ctx.restore();
    }
  }

  get activeCount(): number {
    let n = 0;
    for (const p of this.particles) if (p.active) n++;
    return n;
  }

  clear(): void {
    for (const p of this.particles) p.active = false;
  }
}

const mixCache = new Map<string, [number, number, number]>();
function parseHex(hex: string): [number, number, number] {
  let cached = mixCache.get(hex);
  if (cached) return cached;
  const clean = hex.replace('#', '');
  const bigint = parseInt(clean.length === 3 ? clean.split('').map((c) => c + c).join('') : clean, 16);
  cached = [(bigint >> 16) & 255, (bigint >> 8) & 255, bigint & 255];
  mixCache.set(hex, cached);
  return cached;
}
function mixHex(a: string, b: string, t: number): string {
  const [ar, ag, ab] = parseHex(a);
  const [br, bg, bb] = parseHex(b);
  const r = Math.round(ar + (br - ar) * t);
  const g = Math.round(ag + (bg - ag) * t);
  const bl = Math.round(ab + (bb - ab) * t);
  return `rgb(${r},${g},${bl})`;
}

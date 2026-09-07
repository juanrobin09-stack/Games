import { el } from '@/ui/dom';
import { Palette } from '@/rendering/Palette';

export interface MainMenuCallbacks {
  onPlay: (seed?: number) => void;
  onUpgrades: () => void;
  onArmory: () => void;
  onSettings: () => void;
  onCredits: () => void;
}

function parseSeedInput(raw: string): number | undefined {
  const trimmed = raw.trim();
  if (!trimmed) return undefined;
  // Accept a raw number, or the base-36 label shown on end screens (e.g. "K3F1Z").
  if (/^\d+$/.test(trimmed)) return Math.floor(Number(trimmed)) % 1_000_000_000;
  const fromBase36 = parseInt(trimmed, 36);
  return Number.isFinite(fromBase36) && fromBase36 >= 0 ? fromBase36 : undefined;
}

interface EmberMote {
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  alpha: number;
  flicker: number;
}

export class MainMenu {
  root: HTMLElement;
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private motes: EmberMote[] = [];
  private rafId = 0;
  private lastTime = performance.now();
  private resizeHandler = () => this.resize();

  constructor(container: HTMLElement, callbacks: MainMenuCallbacks) {
    this.canvas = el('canvas', { class: 'main-menu-canvas' });
    this.ctx = this.canvas.getContext('2d')!;

    const urlSeed = new URLSearchParams(window.location.search).get('seed') ?? '';
    const seedInput = el('input', {
      type: 'text',
      class: 'seed-input',
      placeholder: 'Seed (optional)',
      value: urlSeed,
      maxlength: '12',
      'aria-label': 'Run seed',
    }) as HTMLInputElement;

    const content = el('div', { class: 'main-menu-content' }, [
      el('h1', { class: 'game-title' }, ['EMBERFALL']),
      el('div', { class: 'game-subtitle' }, ['Last Light']),
      el('div', { class: 'main-menu-buttons' }, [
        el('button', { class: 'btn primary', onClick: () => callbacks.onPlay(parseSeedInput(seedInput.value)) }, ['Play']),
        el('button', { class: 'btn', onClick: callbacks.onUpgrades }, ['Upgrades']),
        el('button', { class: 'btn', onClick: callbacks.onArmory }, ['Armory']),
        el('button', { class: 'btn', onClick: callbacks.onSettings }, ['Settings']),
        el('button', { class: 'btn ghost', onClick: callbacks.onCredits }, ['Credits']),
        seedInput,
      ]),
    ]);

    this.root = el('div', { class: 'screen-overlay fade-screen' }, [
      this.canvas,
      content,
      el('div', { class: 'main-menu-footer' }, ['The Ember is dying. Someone must carry the last light.']),
    ]);
    container.appendChild(this.root);

    this.resize();
    window.addEventListener('resize', this.resizeHandler);
    for (let i = 0; i < 46; i++) this.motes.push(this.spawnMote(true));
    this.rafId = requestAnimationFrame(this.tick);
  }

  private resize(): void {
    this.canvas.width = this.canvas.clientWidth * devicePixelRatio;
    this.canvas.height = this.canvas.clientHeight * devicePixelRatio;
  }

  private spawnMote(randomY = false): EmberMote {
    const w = this.canvas.clientWidth || window.innerWidth;
    const h = this.canvas.clientHeight || window.innerHeight;
    return {
      x: Math.random() * w,
      y: randomY ? Math.random() * h : h + 20,
      vx: (Math.random() - 0.5) * 10,
      vy: -18 - Math.random() * 26,
      size: 1 + Math.random() * 2.6,
      alpha: 0.3 + Math.random() * 0.5,
      flicker: Math.random() * 10,
    };
  }

  private tick = (): void => {
    const now = performance.now();
    const dt = Math.min(0.05, (now - this.lastTime) / 1000);
    this.lastTime = now;
    const ctx = this.ctx;
    const w = this.canvas.width;
    const h = this.canvas.height;
    const dpr = devicePixelRatio || 1;

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, '#0b0910');
    grad.addColorStop(0.6, '#120c10');
    grad.addColorStop(1, '#1a0f0a');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    ctx.save();
    ctx.scale(dpr, dpr);
    for (const mote of this.motes) {
      mote.x += mote.vx * dt;
      mote.y += mote.vy * dt;
      mote.flicker += dt * 4;
      if (mote.y < -20) Object.assign(mote, this.spawnMote());
      const a = mote.alpha * (0.7 + Math.sin(mote.flicker) * 0.3);
      const grd = ctx.createRadialGradient(mote.x, mote.y, 0, mote.x, mote.y, mote.size * 4);
      grd.addColorStop(0, `rgba(255,171,84,${a})`);
      grd.addColorStop(1, 'rgba(255,123,61,0)');
      ctx.fillStyle = grd;
      ctx.beginPath();
      ctx.arc(mote.x, mote.y, mote.size * 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = Palette.ember5;
      ctx.beginPath();
      ctx.arc(mote.x, mote.y, mote.size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    this.rafId = requestAnimationFrame(this.tick);
  };

  destroy(): void {
    cancelAnimationFrame(this.rafId);
    window.removeEventListener('resize', this.resizeHandler);
    this.root.remove();
  }
}

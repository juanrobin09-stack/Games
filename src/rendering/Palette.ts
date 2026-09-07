export const Palette = {
  void: '#07060a',
  bg0: '#0b0a10',
  bg1: '#14121a',
  bg2: '#1d1a24',
  bg3: '#29242f',

  ember1: '#3a1608',
  ember2: '#8a2e10',
  ember3: '#e8542a',
  ember4: '#ff7b3d',
  ember5: '#ffab54',
  ember6: '#ffd9a0',

  gold: '#d4af6a',
  goldDim: '#8a7248',
  goldBright: '#f2d38f',

  blood: '#c0392b',
  bloodBright: '#e74c3c',

  soul: '#9b7ed9',
  soulDim: '#6a5596',
  soulBright: '#c4b0f0',

  frost: '#6fc3d9',
  toxic: '#7dd35a',
  shadow: '#4a3d63',

  textWarm: '#ece3d2',
} as const;

export function hexToRgb(hex: string): [number, number, number] {
  const clean = hex.replace('#', '');
  const bigint = parseInt(clean.length === 3 ? clean.split('').map((c) => c + c).join('') : clean, 16);
  return [(bigint >> 16) & 255, (bigint >> 8) & 255, bigint & 255];
}

export function rgba(hex: string, alpha: number): string {
  const [r, g, b] = hexToRgb(hex);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export function mixColor(hexA: string, hexB: string, t: number): string {
  const [ar, ag, ab] = hexToRgb(hexA);
  const [br, bg, bb] = hexToRgb(hexB);
  const r = Math.round(ar + (br - ar) * t);
  const g = Math.round(ag + (bg - ag) * t);
  const b = Math.round(ab + (bb - ab) * t);
  return `rgb(${r}, ${g}, ${b})`;
}

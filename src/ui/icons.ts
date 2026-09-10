import type { UpgradeIconId } from '@/data/types';

const ICONS: Record<UpgradeIconId, string> = {
  blade: '<path d="M5 19L16 8M16 8l3-3 2 2-3 3M16 8l-3-3-2 2 3 3M5 19l-2 2M5 19l2 2"/>',
  boots: '<path d="M6 3v9l-3 4v3h8v-4h5a3 3 0 0 0 3-3v-1c0-2-2-3-4-3h-2V3z"/>',
  heart: '<path d="M12 20s-7-4.4-9.5-9C1 8 2 4.5 5.5 4A5 5 0 0 1 12 6.5 5 5 0 0 1 18.5 4C22 4.5 23 8 21.5 11 19 15.6 12 20 12 20z"/>',
  crit: '<path d="M12 2l2.2 6.8H21l-5.6 4.1 2.1 6.9L12 15.8 6.5 19.8l2.1-6.9L3 8.8h6.8z"/>',
  critDamage: '<path d="M13 2 4 14h6l-1 8 9-12h-6z"/>',
  dodge: '<path d="M4 17c3-6 6-9 10-9M14 8l-3-3M14 8l-3 3M20 6c-2 4-2 8 0 12"/>',
  ability: '<circle cx="12" cy="12" r="3.2"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M6 6l2 2M16 16l2 2M18 6l-2 2M8 16l-2 2"/>',
  ember: '<path d="M12 2c2 4-2 5-2 8a4 4 0 0 0 8 1c1 3-1 8-6 8-4.4 0-7-3-7-6.5C5 8 9 6 12 2z"/>',
  magnet: '<path d="M6 4h4v9a2 2 0 0 0 4 0V4h4v9a6 6 0 0 1-12 0z"/><path d="M6 4v3M10 4v3M14 4v3M18 4v3"/>',
  projectile: '<path d="M3 12h13M12 6l6 6-6 6"/>',
  area: '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="8" stroke-dasharray="3 3"/>',
  lifesteal: '<path d="M12 20s-7-4.4-9.5-9C1 8 2 4.5 5.5 4A5 5 0 0 1 12 6.5 5 5 0 0 1 18.5 4C22 4.5 23 8 21.5 11 19 15.6 12 20 12 20z"/><path d="M9 11l1.5 1.5L15 8"/>',
  shield: '<path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/>',
  burn: '<path d="M12 2c2 4-2 5-2 8a4 4 0 0 0 8 1c1 3-1 8-6 8-4.4 0-7-3-7-6.5C5 8 9 6 12 2z"/><path d="M12 12c.6 1 .6 2-.3 2.8"/>',
  armor: '<path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/><path d="M9 11l2 2 4-4"/>',
  regen: '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4v4h-4"/>',
  luck: '<path d="M12 2l2.2 6.8H21l-5.6 4.1 2.1 6.9L12 15.8 6.5 19.8l2.1-6.9L3 8.8h6.8z"/><path d="M4 4l1 1M20 4l-1 1"/>',
  stamina: '<path d="M6 16l6-5 6 5"/><path d="M6 10l6-5 6 5"/>',
  range: '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>',
  haste: '<path d="M4 6l6 6-6 6"/><path d="M12 6l6 6-6 6"/>',
};

export function iconSvg(id: UpgradeIconId, size = 22): string {
  const inner = ICONS[id] ?? ICONS.blade;
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${inner}</svg>`;
}

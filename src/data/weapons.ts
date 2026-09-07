import type { WeaponDefinition } from '@/data/types';

export const WEAPONS: Record<string, WeaponDefinition> = {
  emberBlade: {
    id: 'emberBlade',
    name: 'Ember Blade',
    description: 'A balanced shortsword warmed by a sliver of the last light. Reliable in any hand.',
    kind: 'melee',
    baseDamage: 16,
    attackCooldown: 0.45,
    range: 50,
    arcDegrees: 100,
    knockback: 95,
    critBonus: 0,
    color: '#ff7b3d',
  },
  voidScythe: {
    id: 'voidScythe',
    name: 'Void Scythe',
    description: 'A ponderous blade that drinks momentum. Slow, but every swing is a verdict.',
    kind: 'melee',
    baseDamage: 34,
    attackCooldown: 0.85,
    range: 62,
    arcDegrees: 155,
    knockback: 170,
    critBonus: 0.08,
    unlockCost: 150,
    color: '#9b7ed9',
  },
  solarSpear: {
    id: 'solarSpear',
    name: 'Solar Spear',
    description: 'A thrown lance of hardened light. Pierces through the crowd it was thrown at.',
    kind: 'ranged',
    baseDamage: 14,
    attackCooldown: 0.55,
    range: 440,
    knockback: 50,
    critBonus: 0.05,
    projectileSpeed: 640,
    pierce: 2,
    unlockCost: 220,
    color: '#ffd9a0',
  },
};

export const WEAPON_LIST = Object.values(WEAPONS);

export function getWeaponDefinition(id: string): WeaponDefinition {
  const def = WEAPONS[id];
  if (!def) throw new Error(`Unknown weapon definition: ${id}`);
  return def;
}

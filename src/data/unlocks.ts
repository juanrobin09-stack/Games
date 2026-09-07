import type { UnlockDefinition } from '@/data/types';

export const UNLOCKS: UnlockDefinition[] = [
  {
    id: 'unlock-void-scythe',
    name: 'Void Scythe',
    description: 'Unlock a slow, devastating melee weapon.',
    cost: 150,
    kind: 'weapon',
    refId: 'voidScythe',
  },
  {
    id: 'unlock-solar-spear',
    name: 'Solar Spear',
    description: 'Unlock a piercing ranged weapon.',
    cost: 220,
    kind: 'weapon',
    refId: 'solarSpear',
  },
  {
    id: 'unlock-stormstep',
    name: 'Stormstep',
    description: 'Unlock a blinking dash ability.',
    cost: 140,
    kind: 'ability',
    refId: 'stormstep',
  },
  {
    id: 'unlock-warding-sigil',
    name: 'Warding Sigil',
    description: 'Unlock a defensive totem ability.',
    cost: 190,
    kind: 'ability',
    refId: 'wardingSigil',
  },
  {
    id: 'awakenDeep',
    name: 'Awaken the Deep',
    description: 'Something stirs. The Cinder Wraith now haunts the ruins and the citadel.',
    cost: 130,
    kind: 'enemy',
    refId: 'cinderWraith',
  },
  {
    id: 'emberSight',
    name: 'Ember Sight',
    description: 'See further into what the Ember could become. Legendary upgrades may now appear.',
    cost: 260,
    kind: 'upgradeTier',
    refId: 'legendary',
  },
];

export function getUnlock(id: string): UnlockDefinition {
  const def = UNLOCKS.find((u) => u.id === id);
  if (!def) throw new Error(`Unknown unlock: ${id}`);
  return def;
}

import type { AbilityDefinition } from '@/data/types';

export const ABILITIES: Record<string, AbilityDefinition> = {
  emberBurst: {
    id: 'emberBurst',
    name: 'Ember Burst',
    description: 'Release the Ember in a violent bloom of light, scorching and hurling back all nearby.',
    cooldown: 8,
    energyCost: 45,
    color: '#ff7b3d',
  },
  stormstep: {
    id: 'stormstep',
    name: 'Stormstep',
    description: 'Blink through the dark in a burst of speed, cutting down anything in your path.',
    cooldown: 6.5,
    energyCost: 35,
    unlockCost: 140,
    color: '#6fc3d9',
  },
  wardingSigil: {
    id: 'wardingSigil',
    name: 'Warding Sigil',
    description: 'Plant a sigil of the last light that mends your wounds and sears the corrupted.',
    cooldown: 15,
    energyCost: 60,
    unlockCost: 190,
    color: '#f2d38f',
  },
};

export const ABILITY_LIST = Object.values(ABILITIES);

export function getAbilityDefinition(id: string) {
  const def = ABILITIES[id];
  if (!def) throw new Error(`Unknown ability definition: ${id}`);
  return def;
}

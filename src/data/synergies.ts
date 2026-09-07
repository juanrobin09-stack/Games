import type { SynergyDefinition } from '@/data/types';

export const SYNERGIES: SynergyDefinition[] = [
  {
    id: 'emberCritical',
    name: 'Ember & Critical',
    description: 'Critical hits have a chance to detonate the target in a burst of Ember light.',
    requires: ['ember', 'critical'],
    icon: 'crit',
  },
  {
    id: 'ashFire',
    name: 'Ash & Fire',
    description: 'Burning enemies take 40% more damage from all sources.',
    requires: ['ash', 'fire'],
    icon: 'burn',
  },
  {
    id: 'shadowDodge',
    name: 'Shadow & Dodge',
    description: 'A perfectly-timed dodge grants a brief surge of damage.',
    requires: ['shadow', 'dodge'],
    icon: 'dodge',
  },
  {
    id: 'lightHealing',
    name: 'Light & Healing',
    description: 'Enemies slain while burning or warded have a chance to drop a healing mote.',
    requires: ['light', 'healing'],
    icon: 'heart',
  },
  {
    id: 'wrath',
    name: 'Wrath of the Warden',
    description: 'The lower your HP, the more damage you deal — up to +50% at the brink of death.',
    requires: ['wrath', 'wrath'],
    icon: 'critDamage',
  },
];

export function getSynergy(id: string): SynergyDefinition {
  const def = SYNERGIES.find((s) => s.id === id);
  if (!def) throw new Error(`Unknown synergy: ${id}`);
  return def;
}

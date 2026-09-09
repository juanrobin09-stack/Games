import type { ZoneDefinition } from '@/data/types';

export const ZONES: ZoneDefinition[] = [
  {
    id: 'ashenWoods',
    name: 'Ashen Woods',
    subtitle: 'Where the trees remember fire',
    index: 0,
    roomCount: 8,
    palette: {
      floor: '#252d1e',
      floorAccent: '#313d26',
      wall: '#171d11',
      wallTop: '#44532f',
      fog: 'rgba(9,13,7,0.5)',
      ambient: '#3c4a2c',
      accent: '#ff7b3d',
    },
    enemyPool: ['ashCrawler', 'hollow', 'flameWisp'],
    heartGuardian: 'gravebound',
    ambientParticle: 'ash',
  },
  {
    // Level 2. Reached by descending the stairwell in the Ashen Woods' heart
    // room: a buried city of the same stone, further down and further gone —
    // colder, damper, darker, lit by what grows on the dead rather than by
    // fire. Only the Warden's own ember light stays warm.
    id: 'hollowRuins',
    name: 'The Hollow Ruins',
    subtitle: 'Stone remembers what flesh forgets',
    index: 1,
    roomCount: 10,
    palette: {
      floor: '#22213a',
      floorAccent: '#2c2a48',
      wall: '#131120',
      wallTop: '#433c5e',
      fog: 'rgba(8,7,16,0.6)',
      ambient: '#3a4a5a',
      accent: '#9b7ed9',
    },
    enemyPool: ['ashCrawler', 'hollow', 'gravebound', 'shadowStalker', 'cinderWraith', 'blightbloat', 'hollowWarden'],
    heartGuardian: 'sunkenWarden',
    ambientParticle: 'spores',
    darkness: 0.5,
    fungalColor: '#6fe3c4',
    sporeColors: ['#8de9cf', '#9b7ed9', '#b9f5e2', '#8de9cf'],
    material: {
      mossColor: '#3a7062',
      mossDensity: 2.6,
      rubbleDensity: 1.8,
      crackDensity: 1.5,
      dampPatches: 5,
    },
  },
  {
    id: 'emberCitadel',
    name: 'Ember Citadel',
    subtitle: 'The last light burns behind these walls',
    index: 2,
    roomCount: 7,
    palette: {
      floor: '#2e1e19',
      floorAccent: '#3a2620',
      wall: '#1c110d',
      wallTop: '#5a3220',
      fog: 'rgba(20,6,4,0.55)',
      ambient: '#5a2a18',
      accent: '#ffab54',
    },
    enemyPool: ['gravebound', 'shadowStalker', 'flameWisp', 'emberDevourer', 'cinderWraith'],
    heartGuardian: 'emberDevourer',
    ambientParticle: 'embers',
  },
];

export function getZone(index: number): ZoneDefinition {
  const zone = ZONES[index];
  if (!zone) throw new Error(`Unknown zone index: ${index}`);
  return zone;
}

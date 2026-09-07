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
    id: 'hollowRuins',
    name: 'The Hollow Ruins',
    subtitle: 'Stone remembers what flesh forgets',
    index: 1,
    roomCount: 9,
    palette: {
      floor: '#282437',
      floorAccent: '#332c44',
      wall: '#181420',
      wallTop: '#4a4260',
      fog: 'rgba(10,8,16,0.55)',
      ambient: '#4a4460',
      accent: '#9b7ed9',
    },
    enemyPool: ['ashCrawler', 'hollow', 'gravebound', 'shadowStalker', 'cinderWraith'],
    heartGuardian: 'shadowStalker',
    ambientParticle: 'spores',
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

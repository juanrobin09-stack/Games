import { Random } from '@/utils/Random';
import type { ZoneDefinition, Rarity } from '@/data/types';
import { Room, OPPOSITE, DIRECTION_DELTA, type Direction, ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS } from '@/world/Room';
import { Enemy } from '@/entities/Enemy';
import { Obstacle, type ObstacleVisual } from '@/entities/Obstacle';
import { Chest } from '@/entities/Chest';
import { getEnemyDefinition } from '@/data/enemies';
import { getCombatRoomEnemyCount, getDifficultyFactors } from '@/world/Difficulty';
import { RARITY_ORDER } from '@/data/types';
import { clamp } from '@/utils/MathUtils';
import { t, tc } from '@/i18n';

const ALL_DIRECTIONS: Direction[] = ['N', 'S', 'E', 'W'];

export interface ZoneLayout {
  zone: ZoneDefinition;
  rooms: Map<string, Room>;
  startKey: string;
  endKey: string;
}

export function generateZoneLayout(zone: ZoneDefinition, rng: Random): ZoneLayout {
  const rooms = new Map<string, Room>();
  const start = new Room(0, 0, 'start');
  start.visited = true;
  start.cleared = true;
  rooms.set(start.key, start);

  interface FrontierEdge {
    from: Room;
    dir: Direction;
  }
  const frontier: FrontierEdge[] = ALL_DIRECTIONS.map((dir) => ({ from: start, dir }));
  const maxRadius = 3;

  while (rooms.size < zone.roomCount && frontier.length > 0) {
    const idx = rng.int(0, frontier.length - 1);
    const { from, dir } = frontier.splice(idx, 1)[0];
    const delta = DIRECTION_DELTA[dir];
    const nx = from.gridX + delta.dx;
    const ny = from.gridY + delta.dy;
    const key = `${nx},${ny}`;
    if (rooms.has(key)) continue;
    if (Math.abs(nx) > maxRadius || Math.abs(ny) > maxRadius) continue;
    if (rooms.size > 2 && rng.next() < 0.12) continue;

    const room = new Room(nx, ny, 'combat');
    room.doors.add(OPPOSITE[dir]);
    from.doors.add(dir);
    rooms.set(key, room);

    for (const d2 of ALL_DIRECTIONS) {
      if (d2 === OPPOSITE[dir]) continue;
      frontier.push({ from: room, dir: d2 });
    }
  }

  // BFS distances from start
  const queue: Room[] = [start];
  start.distanceFromStart = 0;
  const seen = new Set<string>([start.key]);
  let farthest = start;
  while (queue.length > 0) {
    const current = queue.shift()!;
    for (const dir of current.doors) {
      const delta = DIRECTION_DELTA[dir];
      const key = `${current.gridX + delta.dx},${current.gridY + delta.dy}`;
      const neighbor = rooms.get(key);
      if (!neighbor || seen.has(key)) continue;
      seen.add(key);
      neighbor.distanceFromStart = current.distanceFromStart + 1;
      if (neighbor.distanceFromStart > farthest.distanceFromStart) farthest = neighbor;
      queue.push(neighbor);
    }
  }

  if (rooms.size < 2) {
    // Degenerate layout (extremely unlucky rolls) — force one guaranteed room so the zone is always completable.
    const fallback = new Room(0, 1, 'combat');
    fallback.doors.add('N');
    start.doors.add('S');
    fallback.distanceFromStart = 1;
    rooms.set(fallback.key, fallback);
    farthest = fallback;
  }

  // The layout is a spanning tree grown outward from the start, so the
  // farthest room is always a leaf with exactly one door — which is what
  // lets the heart room place its stairwell "behind" the guardian, on the
  // far side from the way in (see placeStairsDown).
  const endRoom = farthest;
  endRoom.type = zone.index === 2 ? 'boss' : 'heart';

  const others = Array.from(rooms.values()).filter((r) => r !== start && r !== endRoom);
  const shuffled = rng.shuffle(others);

  const takeFrom = (pool: Room[], predicate: (r: Room) => boolean, count: number): Room[] => {
    const taken: Room[] = [];
    for (let i = 0; i < pool.length && taken.length < count; i++) {
      if (predicate(pool[i])) {
        taken.push(pool[i]);
      }
    }
    for (const room of taken) {
      const idx = pool.indexOf(room);
      if (idx >= 0) pool.splice(idx, 1);
    }
    return taken;
  };

  // Elite, shop and chest are the three room types that most directly serve
  // "the player should always have interesting choices" — a risk/reward
  // fight, a currency sink, and a guaranteed upgrade. They're reserved first,
  // unconditionally, so a small or unlucky zone layout can never starve a
  // whole run of a shop or a chest. Whatever remains is split between a
  // guaranteed combat minimum and secondary specials (event/rest/a bonus
  // 2nd event or chest for bigger zones); any leftover room defaults to combat.
  const ALWAYS = () => true;
  const takeOne = (predicate: (r: Room) => boolean, type: Room['type']): void => {
    let taken = takeFrom(shuffled, predicate, 1);
    if (taken.length === 0 && predicate !== ALWAYS) taken = takeFrom(shuffled, ALWAYS, 1);
    if (taken.length > 0) taken[0].type = type;
  };

  takeOne((r) => r.distanceFromStart >= 2, 'elite');
  takeOne(ALWAYS, 'shop');
  takeOne(ALWAYS, 'chest');
  // The Hollow Ruins' one guaranteed set-piece: the Drowned Sanctum, an opt-in
  // three-wave rite. Reserved like the other specials so every Level 2 has one.
  if (zone.index === 1) takeOne((r) => r.distanceFromStart >= 2, 'sanctum');

  const minCombat = Math.max(1, Math.floor(shuffled.length * 0.5));
  let bonusBudget = Math.max(0, shuffled.length - minCombat);
  const spendBonus = (type: Room['type']): void => {
    if (bonusBudget <= 0) return;
    const taken = takeFrom(shuffled, ALWAYS, 1);
    if (taken.length > 0) {
      taken[0].type = type;
      bonusBudget--;
    }
  };
  spendBonus('event');
  spendBonus('rest');
  spendBonus('event');
  spendBonus('chest');

  return { zone, rooms, startKey: start.key, endKey: endRoom.key };
}

const OBSTACLE_VISUALS_BY_ZONE: ObstacleVisual[][] = [
  ['tree', 'rock', 'rubble', 'brazier'],
  // Level 2: the same ruined stone, but colonised — fungus clusters are the
  // zone's light source, and sarcophagi its cover.
  ['pillar', 'statue', 'rubble', 'crystal', 'fungus', 'fungus', 'sarcophagus'],
  ['pillar', 'brazier', 'rubble', 'statue'],
];

function obstacleRadiusFor(visual: ObstacleVisual, rng: Random): number {
  switch (visual) {
    case 'pillar':
    case 'statue':
      return 22;
    case 'sarcophagus':
      return 26;
    case 'fungus':
      return rng.range(14, 20);
    default:
      return rng.range(16, 28);
  }
}

/** True if a circle at (x, y) keeps `padding` clear of every obstacle already in the room. */
function clearOfObstacles(room: Room, x: number, y: number, radius: number, padding: number): boolean {
  for (const o of room.obstacles) {
    if (Math.hypot(x - o.x, y - o.y) < radius + o.radius + padding) return false;
  }
  return true;
}

/** How deep into the room a door's "approach lane" is kept clear of scatter. */
const DOOR_LANE_DEPTH = 150;

/** Distance from (x, y) to the straight lane running from a door into the room. */
function distanceToDoorLane(dir: Direction, x: number, y: number): number {
  switch (dir) {
    case 'N':
      return y <= WALL_THICKNESS + DOOR_LANE_DEPTH ? Math.abs(x - ROOM_WIDTH / 2) : Math.hypot(x - ROOM_WIDTH / 2, y - (WALL_THICKNESS + DOOR_LANE_DEPTH));
    case 'S':
      return y >= ROOM_HEIGHT - WALL_THICKNESS - DOOR_LANE_DEPTH
        ? Math.abs(x - ROOM_WIDTH / 2)
        : Math.hypot(x - ROOM_WIDTH / 2, y - (ROOM_HEIGHT - WALL_THICKNESS - DOOR_LANE_DEPTH));
    case 'W':
      return x <= WALL_THICKNESS + DOOR_LANE_DEPTH ? Math.abs(y - ROOM_HEIGHT / 2) : Math.hypot(x - (WALL_THICKNESS + DOOR_LANE_DEPTH), y - ROOM_HEIGHT / 2);
    case 'E':
      return x >= ROOM_WIDTH - WALL_THICKNESS - DOOR_LANE_DEPTH
        ? Math.abs(y - ROOM_HEIGHT / 2)
        : Math.hypot(x - (ROOM_WIDTH - WALL_THICKNESS - DOOR_LANE_DEPTH), y - ROOM_HEIGHT / 2);
  }
}

/** True if a circle keeps `padding` clear of every door's approach lane, so
 * walking straight in through any door never runs face-first into a rock. */
function clearOfDoorLanes(room: Room, x: number, y: number, radius: number, padding: number): boolean {
  for (const dir of room.doors) {
    if (distanceToDoorLane(dir, x, y) < radius + padding) return false;
  }
  return true;
}

interface KeepClear {
  x: number;
  y: number;
  radius: number;
}

function scatterObstacles(
  room: Room,
  rng: Random,
  zoneIndex: number,
  count: number,
  avoidCenterRadius = 130,
  keepClear: KeepClear[] = []
): void {
  const visuals = OBSTACLE_VISUALS_BY_ZONE[zoneIndex] ?? OBSTACLE_VISUALS_BY_ZONE[0];
  const margin = WALL_THICKNESS + 90;
  for (let i = 0; i < count; i++) {
    const visual = rng.pick(visuals);
    const radius = obstacleRadiusFor(visual, rng);
    let x = 0;
    let y = 0;
    let attempts = 0;
    let ok = false;
    do {
      x = rng.range(margin, ROOM_WIDTH - margin);
      y = rng.range(margin, ROOM_HEIGHT - margin);
      attempts++;
      ok =
        Math.hypot(x - ROOM_WIDTH / 2, y - ROOM_HEIGHT / 2) >= avoidCenterRadius &&
        clearOfObstacles(room, x, y, radius, 34) &&
        clearOfDoorLanes(room, x, y, radius, 40) &&
        keepClear.every((k) => Math.hypot(x - k.x, y - k.y) >= radius + k.radius);
    } while (attempts < 18 && !ok);
    // Rather than stack a rock onto a landmark (the stairwell, a stall) or
    // into a doorway when the room is crowded, simply place one fewer.
    if (!ok) continue;
    room.obstacles.push(new Obstacle(x, y, radius, visual));
  }
}

/**
 * A room's single "landmark" object (chest, brazier, stall, shrine) used to sit
 * dead-center — which, for rooms whose N/S or E/W doors are both open, put it
 * squarely on the straight line between them and blocked the room's most direct
 * traversal. Offsetting on both axes keeps it visually central (and still the
 * obvious, single point of interest) while actually clearing both centerlines.
 */
function landmarkPosition(rng: Random): { x: number; y: number } {
  const offsetX = rng.pick([-1, 1]) * rng.range(90, 160);
  const offsetY = rng.pick([-1, 1]) * rng.range(60, 110);
  return { x: ROOM_WIDTH / 2 + offsetX, y: ROOM_HEIGHT / 2 + offsetY };
}

function randomSpawnPosition(rng: Random, avoidCenterRadius = 150, room: Room | null = null): { x: number; y: number } {
  const margin = WALL_THICKNESS + 70;
  let x = 0;
  let y = 0;
  let attempts = 0;
  let ok = false;
  do {
    x = rng.range(margin, ROOM_WIDTH - margin);
    y = rng.range(margin, ROOM_HEIGHT - margin);
    attempts++;
    ok =
      Math.hypot(x - ROOM_WIDTH / 2, y - ROOM_HEIGHT / 2) >= avoidCenterRadius &&
      (room === null || clearOfObstacles(room, x, y, 22, 12));
  } while (attempts < 18 && !ok);
  return { x, y };
}

// ---------------------------------------------------------------- Stairs

export const STAIRS_RADIUS = 44;

/** Where the zone's exit stairwell sits in a heart room: on the far side from
 * the single entrance door, descending away from it — so the player sees the
 * way down over the guardian's shoulder from the moment they walk in. */
function stairsDownAnchor(entryDoor: Direction): { x: number; y: number; facing: number } {
  switch (entryDoor) {
    case 'S':
      return { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 - 165, facing: -Math.PI / 2 };
    case 'N':
      return { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 + 165, facing: Math.PI / 2 };
    case 'W':
      return { x: ROOM_WIDTH / 2 + 270, y: ROOM_HEIGHT / 2, facing: 0 };
    case 'E':
      return { x: ROOM_WIDTH / 2 - 270, y: ROOM_HEIGHT / 2, facing: Math.PI };
  }
}

function placeStairsDown(room: Room): Obstacle {
  const entry = room.doors.values().next().value as Direction | undefined;
  const anchor = stairsDownAnchor(entry ?? 'S');
  const stairs = new Obstacle(anchor.x, anchor.y, STAIRS_RADIUS, 'stairsDown', { facing: anchor.facing, blocksProjectiles: false });
  room.obstacles.push(stairs);
  return stairs;
}

/** The arrival stairwell in a zone's first room: against a wall with no door
 * (ascending toward it), or tucked into a quadrant off both centerlines if
 * every wall has one. */
function placeStairsUp(room: Room): Obstacle {
  const free = ALL_DIRECTIONS.find((d) => !room.doors.has(d)) ?? null;
  let x: number;
  let y: number;
  let facing: number;
  switch (free) {
    case 'N':
      x = ROOM_WIDTH / 2;
      y = WALL_THICKNESS + 72;
      facing = -Math.PI / 2;
      break;
    case 'S':
      x = ROOM_WIDTH / 2;
      y = ROOM_HEIGHT - WALL_THICKNESS - 72;
      facing = Math.PI / 2;
      break;
    case 'W':
      x = WALL_THICKNESS + 82;
      y = ROOM_HEIGHT / 2;
      facing = Math.PI;
      break;
    case 'E':
      x = ROOM_WIDTH - WALL_THICKNESS - 82;
      y = ROOM_HEIGHT / 2;
      facing = 0;
      break;
    default:
      x = ROOM_WIDTH * 0.27;
      y = ROOM_HEIGHT * 0.3;
      facing = -Math.PI / 2;
      break;
  }
  const stairs = new Obstacle(x, y, STAIRS_RADIUS, 'stairsUp', { facing, blocksProjectiles: false });
  room.obstacles.push(stairs);
  return stairs;
}

/** The spot at the foot of a stairwell (just outside its collision circle, on
 * the room side), where the player stands to descend or arrives from above. */
export function stairsFootPosition(stairs: Obstacle): { x: number; y: number } {
  const dist = stairs.radius + 48;
  return {
    x: stairs.x - Math.cos(stairs.facing) * dist,
    y: stairs.y - Math.sin(stairs.facing) * dist,
  };
}

/** A point a little way INTO the stairwell along its descent — the scripted
 * walk target during the transition, still short of its far end. */
export function stairsMouthPosition(stairs: Obstacle): { x: number; y: number } {
  return {
    x: stairs.x + Math.cos(stairs.facing) * stairs.radius * 0.35,
    y: stairs.y + Math.sin(stairs.facing) * stairs.radius * 0.35,
  };
}

// ---------------------------------------------------------------- Encounters

/**
 * Level 2 combat rooms are composed, not rolled: each template is a specific
 * tactical problem (a shield wall to flank, a field of bloats to kite, a
 * vanguard that mixes both), weighted by how deep into the zone the room
 * sits so the two new mechanics are met one at a time before they combine.
 */
interface EncounterTemplate {
  id: string;
  weight: (distance: number) => number;
  core: string[];
  filler: string[];
}

const RUINS_ENCOUNTERS: EncounterTemplate[] = [
  { id: 'shieldwall', weight: (d) => (d <= 2 ? 3 : 1.5), core: ['hollowWarden'], filler: ['ashCrawler', 'ashCrawler', 'hollow'] },
  { id: 'bloatfield', weight: (d) => (d <= 2 ? 3 : 1.5), core: ['blightbloat', 'blightbloat'], filler: ['hollow', 'gravebound', 'ashCrawler'] },
  { id: 'vanguard', weight: (d) => (d >= 2 ? 3 : 0.8), core: ['hollowWarden', 'blightbloat'], filler: ['ashCrawler', 'shadowStalker', 'hollow'] },
  { id: 'ambush', weight: (d) => (d >= 2 ? 2 : 0.5), core: ['shadowStalker', 'shadowStalker'], filler: ['cinderWraith', 'ashCrawler', 'blightbloat'] },
  { id: 'phalanx', weight: (d) => (d >= 3 ? 2.2 : 0.4), core: ['hollowWarden', 'hollowWarden'], filler: ['blightbloat', 'ashCrawler', 'hollow'] },
];

function composeRuinsEncounter(rng: Random, count: number, distance: number, pool: string[]): string[] {
  const inPool = (id: string) => pool.includes(id);
  const usable = RUINS_ENCOUNTERS.filter((t) => t.core.every(inPool));
  if (usable.length === 0) return Array.from({ length: count }, () => rng.pick(pool));
  const template = rng.weighted(usable, (t) => t.weight(distance));
  const ids = template.core.slice(0, Math.max(1, count));
  const filler = template.filler.filter(inPool);
  while (ids.length < count) ids.push(filler.length > 0 ? rng.pick(filler) : rng.pick(pool));
  return ids;
}

// ---------------------------------------------------------------- Sanctum rite

export const SANCTUM_WAVE_COUNT = 3;
export const SANCTUM_RING_RADIUS = 150;

/** Each wave escalates one notch: bodies, then both new mechanics, then a
 * proper shield line with stalkers behind it. */
const SANCTUM_WAVES: string[][] = [
  ['hollow', 'hollow', 'ashCrawler', 'ashCrawler', 'ashCrawler'],
  ['blightbloat', 'blightbloat', 'hollowWarden', 'ashCrawler'],
  ['hollowWarden', 'hollowWarden', 'shadowStalker', 'shadowStalker', 'blightbloat'],
];

/** The rite's spawn points: the four cardinal edges of the circle plus four
 * inner diagonals — all chosen to sit clear of the kneeling-warden statues at
 * the corners (±200, ±140) and of every door lane. */
const SANCTUM_SPAWN_SLOTS: { x: number; y: number }[] = [
  { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 - 205 },
  { x: ROOM_WIDTH / 2 + 380, y: ROOM_HEIGHT / 2 },
  { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 + 205 },
  { x: ROOM_WIDTH / 2 - 380, y: ROOM_HEIGHT / 2 },
  { x: ROOM_WIDTH / 2 + 120, y: ROOM_HEIGHT / 2 - 190 },
  { x: ROOM_WIDTH / 2 - 120, y: ROOM_HEIGHT / 2 + 190 },
  { x: ROOM_WIDTH / 2 - 120, y: ROOM_HEIGHT / 2 - 190 },
  { x: ROOM_WIDTH / 2 + 120, y: ROOM_HEIGHT / 2 + 190 },
];

/** Nudges a spawn point out of any obstacle it landed in, then back inside the floor. */
function settleSpawn(room: Room, x: number, y: number, radius: number): { x: number; y: number } {
  const margin = WALL_THICKNESS + radius + 6;
  for (let pass = 0; pass < 3; pass++) {
    for (const o of room.obstacles) {
      const dx = x - o.x;
      const dy = y - o.y;
      const dist = Math.hypot(dx, dy) || 0.001;
      const need = radius + o.radius + 8;
      if (dist < need) {
        x = o.x + (dx / dist) * need;
        y = o.y + (dy / dist) * need;
      }
    }
    x = clamp(x, margin, ROOM_WIDTH - margin);
    y = clamp(y, margin, ROOM_HEIGHT - margin);
  }
  return { x, y };
}

/** Spawns one wave of the rite around the circle's edge (staggered so they
 * rise one after another) and returns the new enemies. */
export function spawnSanctumWave(room: Room, zone: ZoneDefinition, waveIndex: number, opts: SpawnContentOptions): Enemy[] {
  const rng = Random.fromString(`${opts.runSeed}:${zone.id}:${room.key}:wave${waveIndex}`);
  const { hpMult, damageMult } = getDifficultyFactors(zone.index, opts.runMinutes);
  const ids = SANCTUM_WAVES[Math.min(waveIndex, SANCTUM_WAVES.length - 1)];
  const slotOffset = rng.int(0, SANCTUM_SPAWN_SLOTS.length - 1);
  const spawned: Enemy[] = [];
  ids.forEach((id, i) => {
    const def = getEnemyDefinition(id);
    const slot = SANCTUM_SPAWN_SLOTS[(slotOffset + i * 3) % SANCTUM_SPAWN_SLOTS.length];
    const pos = settleSpawn(room, slot.x + rng.range(-16, 16), slot.y + rng.range(-12, 12), def.radius);
    const enemy = new Enemy(def, pos.x, pos.y, hpMult, damageMult);
    enemy.stateTimer = -0.14 * i;
    room.enemies.push(enemy);
    spawned.push(enemy);
  });
  return spawned;
}

/**
 * Weighted rarity roll biased by luck: luck exponentially skews a uniform
 * roll toward 1 before walking the cumulative weight table, so higher luck
 * smoothly shifts probability mass from common toward legendary.
 */
export function rollRarity(rng: Random, luck: number, minTier: Rarity = 'common'): Rarity {
  const minIndex = RARITY_ORDER.indexOf(minTier);
  const weights = [40, 30, 18, 9, 3];
  const total = weights.reduce((a, b) => a + b, 0);
  const biased = Math.pow(rng.next(), 1 / (1 + Math.max(0, luck) * 2));
  let cumulative = 0;
  for (let i = 0; i < RARITY_ORDER.length; i++) {
    cumulative += weights[i] / total;
    if (biased <= cumulative) return RARITY_ORDER[Math.max(i, minIndex)];
  }
  return RARITY_ORDER[Math.max(minIndex, RARITY_ORDER.length - 1)];
}

export interface SpawnContentOptions {
  unlockedEnemyIds: Set<string>;
  runMinutes: number;
  rarityLuck: number;
  runSeed: string;
}

/** Lazily populates a room's enemies/obstacles/chest the first time the player enters it. */
export function populateRoomContent(room: Room, zone: ZoneDefinition, opts: SpawnContentOptions): void {
  if (room.spawnedContent) return;
  room.spawnedContent = true;
  const rng = Random.fromString(`${opts.runSeed}:${zone.id}:${room.key}`);
  const pool = zone.enemyPool.filter((id) => {
    const def = getEnemyDefinition(id);
    return !def.requiresUnlock || opts.unlockedEnemyIds.has(def.requiresUnlock);
  });
  const safePool = pool.length > 0 ? pool : zone.enemyPool;

  switch (room.type) {
    case 'combat': {
      scatterObstacles(room, rng, zone.index, rng.int(2, 5));
      const count = getCombatRoomEnemyCount(zone.index, opts.runMinutes, rng.next());
      const { hpMult, damageMult } = getDifficultyFactors(zone.index, opts.runMinutes);
      const ids =
        zone.index === 1
          ? composeRuinsEncounter(rng, count, room.distanceFromStart, safePool)
          : Array.from({ length: count }, () => rng.pick(safePool));
      for (const id of ids) {
        const def = getEnemyDefinition(id);
        const pos = randomSpawnPosition(rng, 150, room);
        room.enemies.push(new Enemy(def, pos.x, pos.y, hpMult, damageMult));
      }
      break;
    }
    case 'elite': {
      scatterObstacles(room, rng, zone.index, rng.int(1, 3));
      const { hpMult, damageMult } = getDifficultyFactors(zone.index, opts.runMinutes);
      const leaderId = rng.pick(safePool);
      const leaderDef = getEnemyDefinition(leaderId);
      const leaderPos = randomSpawnPosition(rng, 0, room);
      const leader = new Enemy(leaderDef, leaderPos.x, leaderPos.y, hpMult * 2.1, damageMult * 1.35);
      leader.isEliteInstance = true;
      leader.displayName = t('enemy.empoweredFormat', 'Empowered {name}').replace('{name}', tc(leaderDef.id, 'name', leaderDef.name));
      leader.radius *= 1.25;
      room.enemies.push(leader);
      for (let i = 0; i < 2; i++) {
        const id = rng.pick(safePool);
        const def = getEnemyDefinition(id);
        const pos = randomSpawnPosition(rng, 150, room);
        room.enemies.push(new Enemy(def, pos.x, pos.y, hpMult, damageMult));
      }
      break;
    }
    case 'heart': {
      // The sealed stairwell goes in first so nothing else lands on it, then
      // the guardian between it and the door.
      placeStairsDown(room);
      scatterObstacles(room, rng, zone.index, rng.int(2, 4));
      const { hpMult, damageMult } = getDifficultyFactors(zone.index, opts.runMinutes);
      const guardDef = getEnemyDefinition(zone.heartGuardian);
      const pos = { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 - 60 };
      const champion = !!guardDef.champion;
      // A champion's numbers are authored for the role already; a regular
      // enemy promoted to Heart Warden gets scaled up into one.
      const guardian = new Enemy(guardDef, pos.x, pos.y, champion ? hpMult : hpMult * 3.2, champion ? damageMult * 1.1 : damageMult * 1.5);
      guardian.isEliteInstance = true;
      const translatedGuardName = tc(guardDef.id, 'name', guardDef.name);
      guardian.displayName = champion
        ? translatedGuardName
        : t('enemy.heartWardenFormat', '{name}, Heart Warden').replace('{name}', translatedGuardName);
      if (!champion) guardian.radius *= 1.4;
      room.enemies.push(guardian);
      const escortPool = champion ? safePool.filter((id) => id !== 'hollowWarden' && id !== 'blightbloat') : safePool;
      for (let i = 0; i < 2; i++) {
        const id = rng.pick(escortPool.length > 0 ? escortPool : safePool);
        const def = getEnemyDefinition(id);
        const spawnPos = randomSpawnPosition(rng, 150, room);
        room.enemies.push(new Enemy(def, spawnPos.x, spawnPos.y, hpMult, damageMult));
      }
      break;
    }
    case 'chest': {
      scatterObstacles(room, rng, zone.index, rng.int(1, 3));
      const tier = rollRarity(rng, opts.rarityLuck);
      const pos = landmarkPosition(rng);
      room.chest = new Chest(pos.x, pos.y, tier);
      break;
    }
    case 'rest': {
      const pos = landmarkPosition(rng);
      room.obstacles.push(new Obstacle(pos.x, pos.y, 20, 'brazier'));
      scatterObstacles(room, rng, zone.index, rng.int(1, 2));
      break;
    }
    case 'shop': {
      const pos = landmarkPosition(rng);
      room.obstacles.push(new Obstacle(pos.x, pos.y, 26, 'merchantStall'));
      scatterObstacles(room, rng, zone.index, rng.int(1, 2));
      break;
    }
    case 'event': {
      const pos = landmarkPosition(rng);
      room.obstacles.push(new Obstacle(pos.x, pos.y, 22, 'shrine'));
      scatterObstacles(room, rng, zone.index, rng.int(1, 2));
      break;
    }
    case 'sanctum': {
      // Four kneeling wardens at the corners of the rite, off both door
      // centerlines; the circle itself is drawn, not an obstacle, so the
      // arena stays open ground.
      for (const [sx, sy] of [
        [-200, -140],
        [200, -140],
        [-200, 140],
        [200, 140],
      ]) {
        room.obstacles.push(new Obstacle(ROOM_WIDTH / 2 + sx, ROOM_HEIGHT / 2 + sy, 22, 'statue'));
      }
      scatterObstacles(room, rng, zone.index, rng.int(1, 2), 300);
      break;
    }
    case 'start': {
      if (zone.index > 0) {
        // Arriving from above: the stairwell you came down, and a near-empty room
        // around it so the first steps into the zone are about looking, not dodging.
        // The spot the player steps off onto stays clear of everything.
        const stairs = placeStairsUp(room);
        const foot = stairsFootPosition(stairs);
        scatterObstacles(room, rng, zone.index, rng.int(0, 1), 200, [{ x: foot.x, y: foot.y, radius: 70 }]);
      } else {
        scatterObstacles(room, rng, zone.index, rng.int(0, 2));
      }
      break;
    }
    case 'boss':
    default:
      scatterObstacles(room, rng, zone.index, rng.int(0, 2));
      break;
  }
}

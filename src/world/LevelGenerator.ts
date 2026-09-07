import { Random } from '@/utils/Random';
import type { ZoneDefinition, Rarity } from '@/data/types';
import { Room, OPPOSITE, DIRECTION_DELTA, type Direction, ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS } from '@/world/Room';
import { Enemy } from '@/entities/Enemy';
import { Obstacle, type ObstacleVisual } from '@/entities/Obstacle';
import { Chest } from '@/entities/Chest';
import { getEnemyDefinition } from '@/data/enemies';
import { getCombatRoomEnemyCount, getDifficultyFactors } from '@/world/Difficulty';
import { RARITY_ORDER } from '@/data/types';

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
  ['pillar', 'statue', 'rubble', 'crystal'],
  ['pillar', 'brazier', 'rubble', 'statue'],
];

function scatterObstacles(room: Room, rng: Random, zoneIndex: number, count: number): void {
  const visuals = OBSTACLE_VISUALS_BY_ZONE[zoneIndex] ?? OBSTACLE_VISUALS_BY_ZONE[0];
  const margin = WALL_THICKNESS + 90;
  for (let i = 0; i < count; i++) {
    const visual = rng.pick(visuals);
    const radius = visual === 'pillar' || visual === 'statue' ? 22 : rng.range(16, 28);
    let x = 0;
    let y = 0;
    let attempts = 0;
    do {
      x = rng.range(margin, ROOM_WIDTH - margin);
      y = rng.range(margin, ROOM_HEIGHT - margin);
      attempts++;
    } while (
      attempts < 12 &&
      Math.hypot(x - ROOM_WIDTH / 2, y - ROOM_HEIGHT / 2) < 130
    );
    room.obstacles.push(new Obstacle(x, y, radius, visual));
  }
}

function randomSpawnPosition(rng: Random, avoidCenterRadius = 150): { x: number; y: number } {
  const margin = WALL_THICKNESS + 70;
  let x = 0;
  let y = 0;
  let attempts = 0;
  do {
    x = rng.range(margin, ROOM_WIDTH - margin);
    y = rng.range(margin, ROOM_HEIGHT - margin);
    attempts++;
  } while (attempts < 16 && Math.hypot(x - ROOM_WIDTH / 2, y - ROOM_HEIGHT / 2) < avoidCenterRadius);
  return { x, y };
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
      for (let i = 0; i < count; i++) {
        const id = rng.pick(safePool);
        const def = getEnemyDefinition(id);
        const { hpMult, damageMult } = getDifficultyFactors(zone.index, opts.runMinutes);
        const pos = randomSpawnPosition(rng);
        room.enemies.push(new Enemy(def, pos.x, pos.y, hpMult, damageMult));
      }
      break;
    }
    case 'elite': {
      scatterObstacles(room, rng, zone.index, rng.int(1, 3));
      const { hpMult, damageMult } = getDifficultyFactors(zone.index, opts.runMinutes);
      const leaderId = rng.pick(safePool);
      const leaderDef = getEnemyDefinition(leaderId);
      const leaderPos = randomSpawnPosition(rng, 0);
      const leader = new Enemy(leaderDef, leaderPos.x, leaderPos.y, hpMult * 2.1, damageMult * 1.35);
      leader.isEliteInstance = true;
      leader.displayName = `Empowered ${leaderDef.name}`;
      leader.radius *= 1.25;
      room.enemies.push(leader);
      for (let i = 0; i < 2; i++) {
        const id = rng.pick(safePool);
        const def = getEnemyDefinition(id);
        const pos = randomSpawnPosition(rng);
        room.enemies.push(new Enemy(def, pos.x, pos.y, hpMult, damageMult));
      }
      break;
    }
    case 'heart': {
      scatterObstacles(room, rng, zone.index, rng.int(2, 4));
      const { hpMult, damageMult } = getDifficultyFactors(zone.index, opts.runMinutes);
      const guardDef = getEnemyDefinition(zone.heartGuardian);
      const pos = { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 - 60 };
      const guardian = new Enemy(guardDef, pos.x, pos.y, hpMult * 3.2, damageMult * 1.5);
      guardian.isEliteInstance = true;
      guardian.displayName = `${guardDef.name}, Heart Warden`;
      guardian.radius *= 1.4;
      room.enemies.push(guardian);
      for (let i = 0; i < 2; i++) {
        const id = rng.pick(safePool);
        const def = getEnemyDefinition(id);
        const spawnPos = randomSpawnPosition(rng);
        room.enemies.push(new Enemy(def, spawnPos.x, spawnPos.y, hpMult, damageMult));
      }
      break;
    }
    case 'chest': {
      scatterObstacles(room, rng, zone.index, rng.int(1, 3));
      const tier = rollRarity(rng, opts.rarityLuck);
      room.chest = new Chest(ROOM_WIDTH / 2, ROOM_HEIGHT / 2, tier);
      break;
    }
    case 'rest': {
      room.obstacles.push(new Obstacle(ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 20, 'brazier'));
      scatterObstacles(room, rng, zone.index, rng.int(1, 2));
      break;
    }
    case 'shop': {
      room.obstacles.push(new Obstacle(ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 26, 'merchantStall'));
      scatterObstacles(room, rng, zone.index, rng.int(1, 2));
      break;
    }
    case 'event': {
      room.obstacles.push(new Obstacle(ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 22, 'shrine'));
      scatterObstacles(room, rng, zone.index, rng.int(1, 2));
      break;
    }
    case 'start':
    case 'boss':
    default:
      scatterObstacles(room, rng, zone.index, rng.int(0, 2));
      break;
  }
}

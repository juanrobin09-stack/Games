import type { RoomType } from '@/data/types';
import type { Enemy } from '@/entities/Enemy';
import type { Obstacle } from '@/entities/Obstacle';
import type { Chest } from '@/entities/Chest';
import type { Pickup } from '@/entities/Pickup';
import type { AABB } from '@/utils/Collision';

export type Direction = 'N' | 'S' | 'E' | 'W';

export const ROOM_WIDTH = 1000;
export const ROOM_HEIGHT = 620;
export const WALL_THICKNESS = 46;
export const DOOR_WIDTH = 120;

export const OPPOSITE: Record<Direction, Direction> = { N: 'S', S: 'N', E: 'W', W: 'E' };
export const DIRECTION_DELTA: Record<Direction, { dx: number; dy: number }> = {
  N: { dx: 0, dy: -1 },
  S: { dx: 0, dy: 1 },
  E: { dx: 1, dy: 0 },
  W: { dx: -1, dy: 0 },
};

export class Room {
  readonly key: string;
  gridX: number;
  gridY: number;
  type: RoomType;
  doors = new Set<Direction>();
  visited = false;
  cleared = false;
  rewardGranted = false;
  distanceFromStart = 0;
  enemies: Enemy[] = [];
  obstacles: Obstacle[] = [];
  pickups: Pickup[] = [];
  chest: Chest | null = null;
  eventId: string | null = null;
  eventResolved = false;
  spawnedContent = false;
  restUsed = false;
  /** Sanctum rite: opt-in wave fight. Doors seal once it starts and stay sealed
   * until every wave is down (or the player is). */
  ritualActive = false;
  ritualWave = 0;
  ritualWaveTimer = 0;

  constructor(gridX: number, gridY: number, type: RoomType) {
    this.gridX = gridX;
    this.gridY = gridY;
    this.type = type;
    this.key = `${gridX},${gridY}`;
  }

  get locked(): boolean {
    if (this.cleared) return false;
    if (this.type === 'sanctum') return this.ritualActive;
    return this.type === 'combat' || this.type === 'elite' || this.type === 'heart' || this.type === 'boss';
  }

  get requiresClearing(): boolean {
    if (this.type === 'sanctum') return this.ritualActive;
    return this.type === 'combat' || this.type === 'elite' || this.type === 'heart' || this.type === 'boss';
  }

  checkCleared(): boolean {
    if (this.cleared) return true;
    if (!this.requiresClearing) {
      this.cleared = true;
      return true;
    }
    if (this.spawnedContent && this.enemies.length > 0 && this.enemies.every((e) => !e.alive)) {
      this.cleared = true;
      return true;
    }
    return false;
  }

  get bounds(): AABB {
    return { x: 0, y: 0, width: ROOM_WIDTH, height: ROOM_HEIGHT };
  }

  doorCenter(dir: Direction): { x: number; y: number } {
    switch (dir) {
      case 'N':
        return { x: ROOM_WIDTH / 2, y: WALL_THICKNESS / 2 };
      case 'S':
        return { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT - WALL_THICKNESS / 2 };
      case 'W':
        return { x: WALL_THICKNESS / 2, y: ROOM_HEIGHT / 2 };
      case 'E':
        return { x: ROOM_WIDTH - WALL_THICKNESS / 2, y: ROOM_HEIGHT / 2 };
    }
  }

  spawnPointFrom(dir: Direction): { x: number; y: number } {
    const inset = WALL_THICKNESS + 60;
    switch (dir) {
      case 'N':
        return { x: ROOM_WIDTH / 2, y: inset };
      case 'S':
        return { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT - inset };
      case 'W':
        return { x: inset, y: ROOM_HEIGHT / 2 };
      case 'E':
        return { x: ROOM_WIDTH - inset, y: ROOM_HEIGHT / 2 };
    }
  }

  getWalls(includeDoorBarriers: boolean): AABB[] {
    const walls: AABB[] = [];
    const t = WALL_THICKNESS;
    const hasN = this.doors.has('N');
    const hasS = this.doors.has('S');
    const hasE = this.doors.has('E');
    const hasW = this.doors.has('W');
    const half = DOOR_WIDTH / 2;

    if (hasN) {
      walls.push({ x: 0, y: 0, width: ROOM_WIDTH / 2 - half, height: t });
      walls.push({ x: ROOM_WIDTH / 2 + half, y: 0, width: ROOM_WIDTH / 2 - half, height: t });
      if (includeDoorBarriers) walls.push({ x: ROOM_WIDTH / 2 - half, y: 0, width: DOOR_WIDTH, height: t });
    } else {
      walls.push({ x: 0, y: 0, width: ROOM_WIDTH, height: t });
    }

    if (hasS) {
      walls.push({ x: 0, y: ROOM_HEIGHT - t, width: ROOM_WIDTH / 2 - half, height: t });
      walls.push({ x: ROOM_WIDTH / 2 + half, y: ROOM_HEIGHT - t, width: ROOM_WIDTH / 2 - half, height: t });
      if (includeDoorBarriers) walls.push({ x: ROOM_WIDTH / 2 - half, y: ROOM_HEIGHT - t, width: DOOR_WIDTH, height: t });
    } else {
      walls.push({ x: 0, y: ROOM_HEIGHT - t, width: ROOM_WIDTH, height: t });
    }

    if (hasW) {
      walls.push({ x: 0, y: 0, width: t, height: ROOM_HEIGHT / 2 - half });
      walls.push({ x: 0, y: ROOM_HEIGHT / 2 + half, width: t, height: ROOM_HEIGHT / 2 - half });
      if (includeDoorBarriers) walls.push({ x: 0, y: ROOM_HEIGHT / 2 - half, width: t, height: DOOR_WIDTH });
    } else {
      walls.push({ x: 0, y: 0, width: t, height: ROOM_HEIGHT });
    }

    if (hasE) {
      walls.push({ x: ROOM_WIDTH - t, y: 0, width: t, height: ROOM_HEIGHT / 2 - half });
      walls.push({ x: ROOM_WIDTH - t, y: ROOM_HEIGHT / 2 + half, width: t, height: ROOM_HEIGHT / 2 - half });
      if (includeDoorBarriers) walls.push({ x: ROOM_WIDTH - t, y: ROOM_HEIGHT / 2 - half, width: t, height: DOOR_WIDTH });
    } else {
      walls.push({ x: ROOM_WIDTH - t, y: 0, width: t, height: ROOM_HEIGHT });
    }

    return walls;
  }
}

import type { AABB } from '@/utils/Collision';
import { resolveCircleAABB } from '@/utils/Collision';
import type { Obstacle } from '@/entities/Obstacle';

export interface Circular {
  x: number;
  y: number;
  radius: number;
}

export function resolveAgainstWalls(entity: Circular, walls: AABB[]): void {
  for (const wall of walls) {
    const push = resolveCircleAABB(entity, wall);
    entity.x += push.x;
    entity.y += push.y;
  }
}

export function resolveAgainstObstacles(entity: Circular, obstacles: Obstacle[]): void {
  for (const o of obstacles) {
    const dx = entity.x - o.x;
    const dy = entity.y - o.y;
    const minDist = entity.radius + o.radius;
    const dist = Math.hypot(dx, dy);
    if (dist < 0.001) {
      entity.x += minDist;
      continue;
    }
    if (dist < minDist) {
      const overlap = minDist - dist;
      entity.x += (dx / dist) * overlap;
      entity.y += (dy / dist) * overlap;
    }
  }
}

export function clampToRoom(entity: Circular, width: number, height: number): void {
  entity.x = Math.min(Math.max(entity.x, -40), width + 40);
  entity.y = Math.min(Math.max(entity.y, -40), height + 40);
}

/** Hard guarantee that a body stays on the room's floor (inside the walls).
 * A last line of defence for enemies only: whatever else pushes one — a
 * bash into a corner, a teleport, a resolver ejecting it the wrong way — it
 * can never end up stranded in a wall or outside the room, unreachable. */
export function clampInsideRoom(entity: Circular, width: number, height: number, wallThickness: number): void {
  const inset = wallThickness + entity.radius;
  if (entity.x < inset) entity.x = inset;
  else if (entity.x > width - inset) entity.x = width - inset;
  if (entity.y < inset) entity.y = inset;
  else if (entity.y > height - inset) entity.y = height - inset;
}

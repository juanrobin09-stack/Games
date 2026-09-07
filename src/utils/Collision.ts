export interface Circle {
  x: number;
  y: number;
  radius: number;
}

export interface AABB {
  x: number;
  y: number;
  width: number;
  height: number;
}

export function circleIntersect(a: Circle, b: Circle): boolean {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const r = a.radius + b.radius;
  return dx * dx + dy * dy <= r * r;
}

export function pointInAABB(px: number, py: number, box: AABB): boolean {
  return px >= box.x && px <= box.x + box.width && py >= box.y && py <= box.y + box.height;
}

export function circleIntersectsAABB(c: Circle, box: AABB): boolean {
  const closestX = clampNum(c.x, box.x, box.x + box.width);
  const closestY = clampNum(c.y, box.y, box.y + box.height);
  const dx = c.x - closestX;
  const dy = c.y - closestY;
  return dx * dx + dy * dy <= c.radius * c.radius;
}

/** Resolves a circle out of an AABB, returning a push vector (0,0 if no overlap). */
export function resolveCircleAABB(c: Circle, box: AABB): { x: number; y: number } {
  if (!circleIntersectsAABB(c, box)) return { x: 0, y: 0 };
  const closestX = clampNum(c.x, box.x, box.x + box.width);
  const closestY = clampNum(c.y, box.y, box.y + box.height);
  let dx = c.x - closestX;
  let dy = c.y - closestY;
  const dist = Math.hypot(dx, dy);
  if (dist < 1e-4) {
    const cx = box.x + box.width / 2;
    const cy = box.y + box.height / 2;
    const overlapX = box.width / 2 + c.radius - Math.abs(c.x - cx);
    const overlapY = box.height / 2 + c.radius - Math.abs(c.y - cy);
    if (overlapX < overlapY) {
      return { x: Math.sign(c.x - cx || 1) * overlapX, y: 0 };
    }
    return { x: 0, y: Math.sign(c.y - cy || 1) * overlapY };
  }
  const overlap = c.radius - dist;
  dx /= dist;
  dy /= dist;
  return { x: dx * overlap, y: dy * overlap };
}

function clampNum(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v;
}

/**
 * Uniform spatial hash grid for broad-phase queries. Rebuilt every frame from
 * scratch (cheap for a few hundred entities) which keeps the implementation
 * simple and avoids stale-cell bugs.
 */
export class SpatialGrid<T> {
  private cellSize: number;
  private cells = new Map<string, T[]>();
  private getPos: (item: T) => { x: number; y: number; radius: number };

  constructor(cellSize: number, getPos: (item: T) => { x: number; y: number; radius: number }) {
    this.cellSize = cellSize;
    this.getPos = getPos;
  }

  private key(cx: number, cy: number): string {
    return `${cx},${cy}`;
  }

  clear(): void {
    this.cells.clear();
  }

  insert(item: T): void {
    const p = this.getPos(item);
    const minCx = Math.floor((p.x - p.radius) / this.cellSize);
    const maxCx = Math.floor((p.x + p.radius) / this.cellSize);
    const minCy = Math.floor((p.y - p.radius) / this.cellSize);
    const maxCy = Math.floor((p.y + p.radius) / this.cellSize);
    for (let cx = minCx; cx <= maxCx; cx++) {
      for (let cy = minCy; cy <= maxCy; cy++) {
        const k = this.key(cx, cy);
        let arr = this.cells.get(k);
        if (!arr) {
          arr = [];
          this.cells.set(k, arr);
        }
        arr.push(item);
      }
    }
  }

  rebuild(items: Iterable<T>): void {
    this.clear();
    for (const item of items) this.insert(item);
  }

  /** Returns unique candidates within radius of (x, y); may include false positives. */
  query(x: number, y: number, radius: number): T[] {
    const minCx = Math.floor((x - radius) / this.cellSize);
    const maxCx = Math.floor((x + radius) / this.cellSize);
    const minCy = Math.floor((y - radius) / this.cellSize);
    const maxCy = Math.floor((y + radius) / this.cellSize);
    const seen = new Set<T>();
    const result: T[] = [];
    for (let cx = minCx; cx <= maxCx; cx++) {
      for (let cy = minCy; cy <= maxCy; cy++) {
        const arr = this.cells.get(this.key(cx, cy));
        if (!arr) continue;
        for (const item of arr) {
          if (!seen.has(item)) {
            seen.add(item);
            result.push(item);
          }
        }
      }
    }
    return result;
  }
}

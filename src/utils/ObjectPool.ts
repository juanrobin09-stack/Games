/**
 * Generic object pool to avoid per-frame allocation/GC churn for
 * high-frequency short-lived objects (particles, damage numbers, projectiles).
 */
export class ObjectPool<T> {
  private free: T[] = [];
  private active: Set<T> = new Set();

  constructor(
    private factory: () => T,
    private reset: (item: T) => void,
    preallocate = 0
  ) {
    for (let i = 0; i < preallocate; i++) {
      this.free.push(this.factory());
    }
  }

  acquire(): T {
    const item = this.free.pop() ?? this.factory();
    this.active.add(item);
    return item;
  }

  release(item: T): void {
    if (!this.active.has(item)) return;
    this.active.delete(item);
    this.reset(item);
    this.free.push(item);
  }

  releaseAll(): void {
    for (const item of this.active) {
      this.reset(item);
      this.free.push(item);
    }
    this.active.clear();
  }

  get activeCount(): number {
    return this.active.size;
  }

  get pooledCount(): number {
    return this.free.length;
  }

  forEachActive(fn: (item: T) => void): void {
    this.active.forEach(fn);
  }
}

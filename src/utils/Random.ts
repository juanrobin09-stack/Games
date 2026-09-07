/**
 * Deterministic PRNG (mulberry32) so a run seed fully reproduces its layout,
 * loot and enemy placement. Never use Math.random() for gameplay decisions —
 * only for purely cosmetic, non-deterministic flourishes.
 */
export class Random {
  private state: number;
  public readonly seed: number;

  constructor(seed: number) {
    this.seed = seed >>> 0;
    this.state = this.seed;
  }

  static fromString(str: string): Random {
    let h = 1779033703 ^ str.length;
    for (let i = 0; i < str.length; i++) {
      h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
      h = (h << 13) | (h >>> 19);
    }
    return new Random(h >>> 0);
  }

  /** Returns a float in [0, 1) */
  next(): number {
    this.state |= 0;
    this.state = (this.state + 0x6d2b79f5) | 0;
    let t = Math.imul(this.state ^ (this.state >>> 15), 1 | this.state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  range(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  int(min: number, max: number): number {
    return Math.floor(this.range(min, max + 1));
  }

  bool(chance = 0.5): boolean {
    return this.next() < chance;
  }

  pick<T>(arr: readonly T[]): T {
    return arr[Math.floor(this.next() * arr.length)];
  }

  shuffle<T>(arr: T[]): T[] {
    const copy = arr.slice();
    for (let i = copy.length - 1; i > 0; i--) {
      const j = Math.floor(this.next() * (i + 1));
      [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
  }

  /** Weighted pick using a `weight` accessor. */
  weighted<T>(arr: readonly T[], weight: (item: T) => number): T {
    const total = arr.reduce((sum, item) => sum + weight(item), 0);
    let roll = this.next() * total;
    for (const item of arr) {
      roll -= weight(item);
      if (roll <= 0) return item;
    }
    return arr[arr.length - 1];
  }

  /** Spawns an independent child RNG stream from this one (stable given the same label). */
  fork(label: string): Random {
    return Random.fromString(`${this.seed}:${label}:${Math.floor(this.next() * 1e9)}`);
  }
}

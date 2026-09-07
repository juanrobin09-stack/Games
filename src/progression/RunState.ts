import { Random } from '@/utils/Random';
import { ZONES } from '@/data/zones';
import { generateZoneLayout, type ZoneLayout } from '@/world/LevelGenerator';
import { Room, DIRECTION_DELTA, type Direction } from '@/world/Room';
import type { Enemy } from '@/entities/Enemy';

export interface RunStats {
  startedAt: number;
  kills: number;
  eliteKills: number;
  damageDealt: number;
  damageTaken: number;
  embersCollected: number;
  soulAshEarned: number;
  upgradesChosen: string[];
  bossDefeated: boolean;
  chestsOpened: number;
  deaths: number;
}

export class RunState {
  readonly seed: number;
  readonly seedLabel: string;
  embers = 0;
  zoneIndex = 0;
  layouts: ZoneLayout[];
  currentRoomKey: string;
  usedEventIds = new Set<string>();
  stats: RunStats;
  ended = false;

  constructor(seed?: number) {
    this.seed = seed ?? Math.floor(Math.random() * 1_000_000_000);
    this.seedLabel = this.seed.toString(36).toUpperCase();
    this.layouts = ZONES.map((zone) => generateZoneLayout(zone, Random.fromString(`${this.seed}:zonegen:${zone.id}`)));
    this.currentRoomKey = this.layouts[0].startKey;
    this.stats = {
      startedAt: performance.now(),
      kills: 0,
      eliteKills: 0,
      damageDealt: 0,
      damageTaken: 0,
      embersCollected: 0,
      soulAshEarned: 0,
      upgradesChosen: [],
      bossDefeated: false,
      chestsOpened: 0,
      deaths: 0,
    };
  }

  get currentZoneDef() {
    return ZONES[this.zoneIndex];
  }

  get currentLayout(): ZoneLayout {
    return this.layouts[this.zoneIndex];
  }

  get currentRoom(): Room {
    const room = this.currentLayout.rooms.get(this.currentRoomKey);
    if (!room) throw new Error(`Room not found: ${this.currentRoomKey}`);
    return room;
  }

  get runSeedString(): string {
    return `${this.seed}`;
  }

  elapsedSeconds(): number {
    return (performance.now() - this.stats.startedAt) / 1000;
  }

  elapsedMinutes(): number {
    return this.elapsedSeconds() / 60;
  }

  neighborRoom(dir: Direction): Room | null {
    const room = this.currentRoom;
    const delta = DIRECTION_DELTA[dir];
    const key = `${room.gridX + delta.dx},${room.gridY + delta.dy}`;
    return this.currentLayout.rooms.get(key) ?? null;
  }

  moveThroughDoor(dir: Direction): Room | null {
    const neighbor = this.neighborRoom(dir);
    if (!neighbor) return null;
    this.currentRoomKey = neighbor.key;
    neighbor.visited = true;
    return neighbor;
  }

  isFinalZone(): boolean {
    return this.zoneIndex >= this.layouts.length - 1;
  }

  advanceZone(): Room {
    this.zoneIndex = Math.min(this.zoneIndex + 1, this.layouts.length - 1);
    const layout = this.currentLayout;
    this.currentRoomKey = layout.startKey;
    const start = this.currentRoom;
    start.visited = true;
    return start;
  }

  addEmbers(amount: number): void {
    if (amount <= 0) return;
    this.embers += amount;
    this.stats.embersCollected += amount;
  }

  spendEmbers(amount: number): boolean {
    if (this.embers < amount) return false;
    this.embers -= amount;
    return true;
  }

  recordKill(enemy: Enemy): void {
    this.stats.kills++;
    if (enemy.def.isElite || enemy.isEliteInstance) this.stats.eliteKills++;
  }

  recordDamageDealt(amount: number): void {
    this.stats.damageDealt += amount;
  }

  recordDamageTaken(amount: number): void {
    this.stats.damageTaken += amount;
  }

  recordUpgrade(id: string): void {
    this.stats.upgradesChosen.push(id);
  }
}

import { loadSave, writeSave, type SaveData } from '@/progression/SaveSystem';
import { PERMANENT_UPGRADES } from '@/data/permanentUpgrades';
import { UNLOCKS } from '@/data/unlocks';
import type { StatModifier } from '@/data/types';

/** Owns the persistent meta-progression save (Soul Ash, permanent upgrades,
 * unlocks, settings, lifetime stats) and keeps it synced to localStorage. */
export class MetaProgression {
  data: SaveData;

  constructor() {
    this.data = loadSave();
  }

  save(): void {
    writeSave(this.data);
  }

  get soulAsh(): number {
    return this.data.soulAsh;
  }

  addSoulAsh(amount: number): void {
    if (amount <= 0) return;
    this.data.soulAsh += Math.round(amount);
    this.data.stats.totalSoulAshEarned += Math.round(amount);
    this.save();
  }

  getPermanentLevel(id: string): number {
    return this.data.permanentLevels[id] ?? 0;
  }

  getPermanentCost(id: string): number | null {
    const def = PERMANENT_UPGRADES.find((p) => p.id === id);
    if (!def) return null;
    const level = this.getPermanentLevel(id);
    if (level >= def.maxLevel) return null;
    return Math.round(def.baseCost * Math.pow(def.costGrowth, level));
  }

  canPurchasePermanent(id: string): boolean {
    const def = PERMANENT_UPGRADES.find((p) => p.id === id);
    if (!def) return false;
    if (def.requires && this.getPermanentLevel(def.requires) === 0) return false;
    const cost = this.getPermanentCost(id);
    return cost !== null && this.data.soulAsh >= cost;
  }

  purchasePermanent(id: string): boolean {
    if (!this.canPurchasePermanent(id)) return false;
    const cost = this.getPermanentCost(id);
    if (cost === null) return false;
    this.data.soulAsh -= cost;
    this.data.permanentLevels[id] = this.getPermanentLevel(id) + 1;
    this.save();
    return true;
  }

  isUnlocked(id: string): boolean {
    return this.data.unlocked.includes(id);
  }

  canPurchaseUnlock(id: string): boolean {
    const def = UNLOCKS.find((u) => u.id === id);
    if (!def) return false;
    return !this.isUnlocked(id) && this.data.soulAsh >= def.cost;
  }

  purchaseUnlock(id: string): boolean {
    if (!this.canPurchaseUnlock(id)) return false;
    const def = UNLOCKS.find((u) => u.id === id)!;
    this.data.soulAsh -= def.cost;
    this.data.unlocked.push(id);
    this.save();
    return true;
  }

  /** Flattened stat modifiers from every purchased permanent-upgrade level, applied as the run's starting stat base. */
  getPermanentStatModifiers(): StatModifier[] {
    const mods: StatModifier[] = [];
    for (const def of PERMANENT_UPGRADES) {
      const level = this.getPermanentLevel(def.id);
      for (let i = 0; i < level; i++) mods.push(...def.modifiers);
    }
    return mods;
  }

  getUnlockedWeaponIds(): string[] {
    return UNLOCKS.filter((u) => u.kind === 'weapon' && this.isUnlocked(u.id)).map((u) => u.refId);
  }

  getUnlockedAbilityIds(): string[] {
    return UNLOCKS.filter((u) => u.kind === 'ability' && this.isUnlocked(u.id)).map((u) => u.refId);
  }

  /** IDs consumed by EnemyDefinition.requiresUnlock (via the unlock's own id, not refId). */
  getUnlockedGateIds(): Set<string> {
    const set = new Set<string>();
    for (const u of UNLOCKS) {
      if (this.isUnlocked(u.id)) set.add(u.id);
    }
    return set;
  }

  recordRunEnd(opts: { kills: number; died: boolean; bossDefeated: boolean; timeSeconds: number; embersCollected: number }): void {
    this.data.stats.totalRuns++;
    this.data.stats.totalKills += opts.kills;
    if (opts.died) this.data.stats.totalDeaths++;
    if (opts.bossDefeated) this.data.stats.bossesDefeated++;
    this.data.stats.totalEmbersCollected += opts.embersCollected;
    if (opts.bossDefeated && (this.data.stats.bestTimeSeconds === null || opts.timeSeconds < this.data.stats.bestTimeSeconds)) {
      this.data.stats.bestTimeSeconds = opts.timeSeconds;
    }
    this.save();
  }

  markTutorialSeen(): void {
    if (this.data.tutorialSeen) return;
    this.data.tutorialSeen = true;
    this.save();
  }
}

export const meta = new MetaProgression();

import { Random } from '@/utils/Random';
import { UPGRADES } from '@/data/upgrades';
import { rollRarity } from '@/world/LevelGenerator';
import { RARITY_ORDER, type Rarity, type UpgradeDefinition } from '@/data/types';
import { effectiveUpgradeMaxLevel } from '@/data/playerProgression';
import type { OwnedUpgrade } from '@/entities/Player';

function getOwnedStacks(owned: OwnedUpgrade[], id: string): number {
  return owned.find((o) => o.def.id === id)?.stacks ?? 0;
}

/**
 * An upgrade is offerable if it's still below its effective level cap for
 * the current zone — not simply "not already owned". Player.addUpgrade()
 * already supports stacking an owned upgrade up to `maxStacks` (see
 * OwnedUpgrade), this is what actually lets that happen: an already-owned
 * upgrade re-offered here and picked again becomes its next level.
 */
function isUpgradeAvailable(u: UpgradeDefinition, owned: OwnedUpgrade[], zoneIndex: number): boolean {
  return getOwnedStacks(owned, u.id) < effectiveUpgradeMaxLevel(u.maxStacks, zoneIndex);
}

export function rollUpgradeChoices(
  rng: Random,
  count: number,
  luck: number,
  unlockedTiers: Set<string>,
  owned: OwnedUpgrade[] = [],
  zoneIndex: number,
  minRarity: Rarity = 'common'
): UpgradeDefinition[] {
  const gated = (u: UpgradeDefinition) => !u.requiresUnlock || unlockedTiers.has(u.requiresUnlock);
  let pool = UPGRADES.filter((u) => gated(u) && isUpgradeAvailable(u, owned, zoneIndex));
  if (pool.length === 0) pool = UPGRADES.filter(gated);
  if (pool.length === 0) pool = UPGRADES;
  const chosen: UpgradeDefinition[] = [];
  const used = new Set<string>();
  let attempts = 0;
  while (chosen.length < count && attempts < count * 25) {
    attempts++;
    const rarity = rollRarity(rng, luck, minRarity);
    const candidates = pool.filter((u) => u.rarity === rarity && !used.has(u.id));
    if (candidates.length === 0) continue;
    const pick = rng.pick(candidates);
    used.add(pick.id);
    chosen.push(pick);
  }
  while (chosen.length < count) {
    const remaining = pool.filter((u) => !used.has(u.id));
    if (remaining.length === 0) break;
    const pick = rng.pick(remaining);
    used.add(pick.id);
    chosen.push(pick);
  }
  return chosen;
}

/** Picks a single upgrade guaranteed to be at or above minRarity (chest rewards, rare-relic offers). */
export function pickUpgradeAtLeastRarity(
  rng: Random,
  minRarity: Rarity,
  unlockedTiers: Set<string>,
  owned: OwnedUpgrade[] = [],
  zoneIndex: number
): UpgradeDefinition {
  const minIndex = RARITY_ORDER.indexOf(minRarity);
  const gated = (u: UpgradeDefinition) => !u.requiresUnlock || unlockedTiers.has(u.requiresUnlock);
  let pool = UPGRADES.filter((u) => RARITY_ORDER.indexOf(u.rarity) >= minIndex && gated(u) && isUpgradeAvailable(u, owned, zoneIndex));
  if (pool.length === 0) pool = UPGRADES.filter((u) => RARITY_ORDER.indexOf(u.rarity) >= minIndex && gated(u));
  if (pool.length === 0) pool = UPGRADES.filter(gated);
  return rng.pick(pool);
}

/** The level an upgrade would become if granted right now (current stacks + 1,
 * or 1 if not yet owned) — for UI display on chest/reward/shop cards. */
export function upcomingUpgradeLevel(id: string, owned: OwnedUpgrade[]): number {
  return getOwnedStacks(owned, id) + 1;
}

import { Random } from '@/utils/Random';
import { UPGRADES } from '@/data/upgrades';
import { rollRarity } from '@/world/LevelGenerator';
import { RARITY_ORDER, type Rarity, type UpgradeDefinition } from '@/data/types';

export function rollUpgradeChoices(
  rng: Random,
  count: number,
  luck: number,
  unlockedTiers: Set<string>,
  exclude: Set<string> = new Set()
): UpgradeDefinition[] {
  const pool = UPGRADES.filter((u) => (!u.requiresUnlock || unlockedTiers.has(u.requiresUnlock)) && !exclude.has(u.id));
  const chosen: UpgradeDefinition[] = [];
  const used = new Set<string>();
  let attempts = 0;
  while (chosen.length < count && attempts < count * 25) {
    attempts++;
    const rarity = rollRarity(rng, luck);
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
  exclude: Set<string> = new Set()
): UpgradeDefinition {
  const minIndex = RARITY_ORDER.indexOf(minRarity);
  const gated = (u: UpgradeDefinition) => !u.requiresUnlock || unlockedTiers.has(u.requiresUnlock);
  let pool = UPGRADES.filter((u) => RARITY_ORDER.indexOf(u.rarity) >= minIndex && gated(u) && !exclude.has(u.id));
  if (pool.length === 0) pool = UPGRADES.filter((u) => RARITY_ORDER.indexOf(u.rarity) >= minIndex && gated(u));
  if (pool.length === 0) pool = UPGRADES.filter(gated);
  return rng.pick(pool);
}

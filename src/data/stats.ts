import { clamp } from '@/utils/MathUtils';
import { createBaseStats, type StatBlock, type StatModifier } from '@/data/types';

/**
 * Combines modifiers onto a base StatBlock. 'flat' adds the raw amount;
 * 'mult' multiplies the stat's current value by (1 + value) — this lets the
 * *Mult fields (base 1.0) compound predictably and lets reduction fields
 * (e.g. dodgeCooldownMult) shrink toward zero safely via negative values.
 * Order: all flats for a stat, in the order given, then all mults.
 */
export function applyModifiers(base: StatBlock, modifiers: StatModifier[]): StatBlock {
  const result: StatBlock = { ...base };
  for (const mod of modifiers) {
    if (mod.mode === 'flat') {
      result[mod.stat] = (result[mod.stat] as number) + mod.value;
    }
  }
  for (const mod of modifiers) {
    if (mod.mode === 'mult') {
      result[mod.stat] = (result[mod.stat] as number) * (1 + mod.value);
    }
  }
  return clampStats(result);
}

export function clampStats(stats: StatBlock): StatBlock {
  stats.critChance = clamp(stats.critChance, 0, 0.85);
  stats.armor = clamp(stats.armor, 0, 0.75);
  stats.lifesteal = clamp(stats.lifesteal, 0, 0.6);
  stats.burnChance = clamp(stats.burnChance, 0, 1);
  stats.dodgeCooldownMult = clamp(stats.dodgeCooldownMult, 0.3, 2);
  stats.attackSpeedMult = clamp(stats.attackSpeedMult, 0.35, 4);
  stats.moveSpeed = Math.max(60, stats.moveSpeed);
  stats.maxHp = Math.max(10, stats.maxHp);
  stats.staminaMax = Math.max(20, stats.staminaMax);
  stats.rangeMult = Math.max(0.4, stats.rangeMult);
  stats.pickupRange = Math.max(20, stats.pickupRange);
  stats.emberGainMult = Math.max(0.1, stats.emberGainMult);
  stats.rarityLuck = clamp(stats.rarityLuck, 0, 1);
  return stats;
}

export function freshStats(): StatBlock {
  return createBaseStats();
}

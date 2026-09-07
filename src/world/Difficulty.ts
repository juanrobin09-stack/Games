/**
 * Central place for every enemy-scaling formula. Difficulty grows with the
 * zone (structural) and with elapsed run time (the "darkness pressure" —
 * dawdling costs you). Keeping this in one module makes the curve easy to
 * retune without touching spawn or AI code.
 */
export interface DifficultyFactors {
  hpMult: number;
  damageMult: number;
  extraEnemies: number;
}

const MINUTES_SOFT_CAP = 14;

export function getCorruptionRatio(runMinutes: number): number {
  return Math.min(1, runMinutes / MINUTES_SOFT_CAP);
}

export function getDifficultyFactors(zoneIndex: number, runMinutes: number): DifficultyFactors {
  const corruption = getCorruptionRatio(runMinutes);
  return {
    hpMult: 1 + zoneIndex * 0.32 + corruption * 0.55,
    damageMult: 1 + zoneIndex * 0.22 + corruption * 0.35,
    extraEnemies: Math.floor(zoneIndex * 0.6 + corruption * 1.6),
  };
}

export function getCombatRoomEnemyCount(zoneIndex: number, runMinutes: number, rngRoll: number): number {
  const base = 2 + Math.floor(rngRoll * 2.2);
  return base + zoneIndex + getDifficultyFactors(zoneIndex, runMinutes).extraEnemies;
}

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

/**
 * Enemy *count* stops climbing with zoneIndex past the Hollow Ruins — Ember
 * Citadel rooms get the same room size as Level 2's, not a further +1 on
 * top. Verified live: individual Citadel enemies are fine (a 2-at-a-time
 * subset of a full room was comfortably survivable even for a modest
 * upgrade set), but the *count* the old linear +zoneIndex term produced
 * there (routinely 6-8 at once) could overwhelm a well-built, sensibly
 * playing character regardless of gear — a swarm-density problem, not a
 * stats one. hpMult/damageMult below are untouched and keep scaling
 * normally: Level 3 should hit harder and have tougher composition
 * (encounter templates, the rare mutated variant), not simply more bodies.
 */
function countZoneWeight(zoneIndex: number): number {
  return Math.min(zoneIndex, 1);
}

export function getDifficultyFactors(zoneIndex: number, runMinutes: number): DifficultyFactors {
  const corruption = getCorruptionRatio(runMinutes);
  return {
    hpMult: 1 + zoneIndex * 0.32 + corruption * 0.55,
    damageMult: 1 + zoneIndex * 0.22 + corruption * 0.35,
    extraEnemies: Math.floor(countZoneWeight(zoneIndex) * 0.6 + corruption * 1.6),
  };
}

export function getCombatRoomEnemyCount(zoneIndex: number, runMinutes: number, rngRoll: number): number {
  const base = 2 + Math.floor(rngRoll * 2.2);
  return base + countZoneWeight(zoneIndex) + getDifficultyFactors(zoneIndex, runMinutes).extraEnemies;
}

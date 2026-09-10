import type { EnemyDefinition, StatKey, UpgradeIconId } from '@/data/types';

/**
 * The run-scoped character-progression layer: kills grant XP, XP grants
 * Player Levels, Player Levels grant stat points, stat points buy levels in
 * one of 7 stats. Entirely separate from — and layered on top of — the
 * existing permanent Soul Ash progression (persists across runs) and the
 * in-run upgrade pool (chests/rewards/shop, see upgrades.ts): this resets to
 * Level 1 at the start of every run, same as the upgrade pool does. See
 * GAME_DESIGN.md's progression hierarchy for how the layers compose.
 *
 * Every tunable number lives in this one file so the curve can be
 * rebalanced later without touching call sites — nothing here is final,
 * it's a reasonable starting point per the brief that introduced it.
 */

// ---------------------------------------------------------------- XP curve

/** Base XP one point of an enemy's existing `xpWeight` is worth. ashCrawler
 * (xpWeight 1, the weakest Zone 1 enemy) gives exactly 5 XP — the requested
 * starting value — for free, since xpWeight already ranks every enemy's
 * relative toughness and was otherwise unused. */
export const XP_PER_WEIGHT = 5;

/** Deeper zones' enemies are worth more XP even at the same xpWeight, since
 * the same enemy type already scales up there via Difficulty.ts too — a
 * placeholder magnitude, not a final curve (see brief §16). */
export const XP_ZONE_BONUS_PER_INDEX = 0.25;

export function getEnemyXpValue(def: EnemyDefinition, zoneIndex: number): number {
  return Math.max(1, Math.round(XP_PER_WEIGHT * def.xpWeight * (1 + zoneIndex * XP_ZONE_BONUS_PER_INDEX)));
}

/** XP required to go from `level` to `level + 1`. Level 1→2 costs exactly
 * XP_TO_LEVEL_2 (25, as requested); every level after grows by
 * XP_CURVE_GROWTH so later levels take progressively more — a real curve,
 * not the same flat cost repeated. Both constants are the whole curve. */
export const XP_TO_LEVEL_2 = 25;
export const XP_CURVE_GROWTH = 1.35;

export function xpRequiredForLevel(level: number): number {
  return Math.round(XP_TO_LEVEL_2 * Math.pow(XP_CURVE_GROWTH, level - 1));
}

/** Stat points granted per Player Level gained. */
export const STAT_POINTS_PER_LEVEL = 1;

/** Hard ceiling on the run-scoped Player Level — XP still accumulates
 * (harmlessly) past it, but no further level or stat point is granted. */
export const MAX_PLAYER_LEVEL = 30;

// ---------------------------------------------------------------- The 6 stats
// M1 damage was removed as a player-levelable stat entirely (base weapon
// damage is now fixed) — see GAME_DESIGN.md's balancing-pass notes.

export type PlayerStatId = 'hp' | 'stamina' | 'abilityDamage' | 'range' | 'moveSpeed' | 'attackSpeed';

export interface PlayerStatDefinition {
  id: PlayerStatId;
  icon: UpgradeIconId;
  /** Which live StatBlock field a level in this stat modifies. */
  stat: StatKey;
  mode: 'flat' | 'mult';
  /** Bonus applied per level beyond 1 — placeholder values, deliberately
   * modest next to a rare in-run upgrade since these accumulate steadily
   * from ordinary combat rather than being a rare discrete pick. */
  valuePerLevel: number;
}

export const PLAYER_STATS: PlayerStatDefinition[] = [
  { id: 'hp', icon: 'heart', stat: 'maxHp', mode: 'flat', valuePerLevel: 6 },
  { id: 'stamina', icon: 'stamina', stat: 'staminaMax', mode: 'flat', valuePerLevel: 8 },
  { id: 'abilityDamage', icon: 'ability', stat: 'abilityDamageMult', mode: 'mult', valuePerLevel: 0.05 },
  { id: 'range', icon: 'range', stat: 'rangeMult', mode: 'mult', valuePerLevel: 0.03 },
  { id: 'moveSpeed', icon: 'boots', stat: 'moveSpeed', mode: 'flat', valuePerLevel: 4 },
  { id: 'attackSpeed', icon: 'haste', stat: 'attackSpeedMult', mode: 'mult', valuePerLevel: 0.03 },
];

export function getPlayerStatDef(id: PlayerStatId): PlayerStatDefinition {
  const def = PLAYER_STATS.find((s) => s.id === id);
  if (!def) throw new Error(`Unknown player stat: ${id}`);
  return def;
}

export function createInitialStatLevels(): Record<PlayerStatId, number> {
  return { hp: 1, stamina: 1, abilityDamage: 1, range: 1, moveSpeed: 1, attackSpeed: 1 };
}

/**
 * Whether a stat-point row is locked right now — the single source of truth
 * both InventoryUI (hides the spend button) and Game.spendStatPoint (refuses
 * the spend even if called directly) check, so the two can never drift out
 * of sync. Attack Speed unlocks with the Bow; ability damage unlocks once
 * the run reaches the Hollow Ruins (zoneIndex 1, "Level 2 du jeu") — see the
 * balancing-pass notes in GAME_DESIGN.md.
 */
export function isPlayerStatLocked(statId: PlayerStatId, hasBow: boolean, zoneIndex: number): boolean {
  if (statId === 'attackSpeed') return !hasBow;
  if (statId === 'abilityDamage') return zoneIndex < 1;
  return false;
}

// ---------------------------------------------------------------- In-run upgrade level cap

/** How high an in-run upgrade's level (stack count) can climb while in a
 * given zone — index 0 (the Ashen Woods, "Level 1") caps at Lv.2 as
 * requested; each zone after allows one more. Extend this array (or make it
 * a formula) when future zones are added — every offer-generation call site
 * reads it through getZoneUpgradeLevelCap, never a hardcoded number. */
export const ZONE_UPGRADE_LEVEL_CAP: number[] = [2, 3, 4];

/** Ceiling for an upgrade that doesn't declare its own `maxStacks` — a
 * backstop against unbounded stacking, comfortably above anything the zone
 * caps above currently allow. */
export const DEFAULT_UPGRADE_MAX_LEVEL = 6;

export function getZoneUpgradeLevelCap(zoneIndex: number): number {
  return ZONE_UPGRADE_LEVEL_CAP[zoneIndex] ?? ZONE_UPGRADE_LEVEL_CAP[ZONE_UPGRADE_LEVEL_CAP.length - 1];
}

/** The effective max level (stack count) a specific upgrade can reach right
 * now: the tighter of its own authored ceiling and the current zone's cap. */
export function effectiveUpgradeMaxLevel(defMaxStacks: number | undefined, zoneIndex: number): number {
  return Math.min(defMaxStacks ?? DEFAULT_UPGRADE_MAX_LEVEL, getZoneUpgradeLevelCap(zoneIndex));
}

// ---------------------------------------------------------------- Level-gated features (architecture only, per brief §11)

/** Optional prerequisites a future ability/feature could declare — level-
 * gating isn't wired to anything yet (no feature currently sets these), this
 * just establishes the shape so one can be added later without a redesign. */
export interface LevelRequirement {
  /** Player Level required before this becomes available at all. */
  minPlayerLevel?: number;
  /** Player Level at which this unlocks for the first time (distinct from
   * minPlayerLevel so "available" and "just unlocked, show a banner" can differ). */
  unlockPlayerLevel?: number;
  /** Player Level required to raise this feature's own internal level further. */
  upgradePlayerLevel?: number;
}

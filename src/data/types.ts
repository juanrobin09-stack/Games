/**
 * Shared data-driven type definitions. Content (enemies, weapons, upgrades...)
 * is authored as plain data objects implementing these interfaces rather than
 * hardcoded in gameplay systems — see src/data/*.ts.
 */

export type Rarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary';

export const RARITY_ORDER: Rarity[] = ['common', 'uncommon', 'rare', 'epic', 'legendary'];

export const RARITY_WEIGHTS: Record<Rarity, number> = {
  common: 100,
  uncommon: 55,
  rare: 26,
  epic: 10,
  legendary: 3,
};

export const RARITY_COLORS: Record<Rarity, string> = {
  common: '#b9b3a6',
  uncommon: '#6fd17a',
  rare: '#5aa9e6',
  epic: '#b06de0',
  legendary: '#f2b53d',
};

/** Every numeric knob on the player/enemy that upgrades and gear can modify. */
export interface StatBlock {
  maxHp: number;
  hpRegen: number;
  moveSpeed: number;
  damageMult: number;
  attackSpeedMult: number;
  rangeMult: number;
  critChance: number;
  critDamage: number;
  armor: number;
  energyMax: number;
  energyRegen: number;
  dodgeCooldownMult: number;
  abilityDamageMult: number;
  emberGainMult: number;
  pickupRange: number;
  projectileCount: number;
  areaDamageMult: number;
  lifesteal: number;
  shieldMax: number;
  burnChance: number;
  emberPower: number;
  rarityLuck: number;
}

export function createBaseStats(): StatBlock {
  return {
    maxHp: 100,
    hpRegen: 0.4,
    moveSpeed: 190,
    damageMult: 1,
    attackSpeedMult: 1,
    rangeMult: 1,
    critChance: 0.05,
    critDamage: 1.5,
    armor: 0,
    energyMax: 100,
    energyRegen: 6,
    dodgeCooldownMult: 1,
    abilityDamageMult: 1,
    emberGainMult: 1,
    pickupRange: 70,
    projectileCount: 0,
    areaDamageMult: 1,
    lifesteal: 0,
    shieldMax: 0,
    burnChance: 0,
    emberPower: 1,
    rarityLuck: 0,
  };
}

export type StatKey = keyof StatBlock;

export interface StatModifier {
  stat: StatKey;
  mode: 'flat' | 'mult';
  value: number;
}

export type SynergyTag =
  | 'ember'
  | 'critical'
  | 'ash'
  | 'fire'
  | 'shadow'
  | 'dodge'
  | 'light'
  | 'healing'
  | 'wrath'
  | 'guard';

export interface UpgradeDefinition {
  id: string;
  name: string;
  description: string;
  rarity: Rarity;
  tags: SynergyTag[];
  modifiers: StatModifier[];
  maxStacks?: number;
  requiresUnlock?: string;
  icon: UpgradeIconId;
}

export type UpgradeIconId =
  | 'blade'
  | 'boots'
  | 'heart'
  | 'crit'
  | 'critDamage'
  | 'dodge'
  | 'ability'
  | 'ember'
  | 'magnet'
  | 'projectile'
  | 'area'
  | 'lifesteal'
  | 'shield'
  | 'burn'
  | 'armor'
  | 'regen'
  | 'luck';

export interface SynergyDefinition {
  id: string;
  name: string;
  description: string;
  requires: [SynergyTag, SynergyTag];
  icon: UpgradeIconId;
}

export type EnemyBehavior = 'chaser' | 'tank' | 'ranged' | 'heavy' | 'stalker' | 'elite';

export interface EnemyDefinition {
  id: string;
  name: string;
  description: string;
  behavior: EnemyBehavior;
  baseHp: number;
  baseDamage: number;
  moveSpeed: number;
  radius: number;
  emberValue: number;
  attackRange: number;
  attackCooldown: number;
  telegraphTime: number;
  contactDamage: number;
  xpWeight: number;
  color: string;
  accentColor: string;
  requiresUnlock?: string;
  projectileSpeed?: number;
  vanishDuration?: number;
  isElite?: boolean;
}

export interface WeaponDefinition {
  id: string;
  name: string;
  description: string;
  kind: 'melee' | 'ranged';
  baseDamage: number;
  attackCooldown: number;
  range: number;
  arcDegrees?: number;
  knockback: number;
  critBonus: number;
  projectileSpeed?: number;
  pierce?: number;
  unlockCost?: number;
  color: string;
}

export type AbilityKind = 'emberBurst' | 'stormstep' | 'wardingSigil';

export interface AbilityDefinition {
  id: AbilityKind;
  name: string;
  description: string;
  cooldown: number;
  energyCost: number;
  unlockCost?: number;
  color: string;
}

export type RoomType = 'start' | 'combat' | 'elite' | 'chest' | 'shop' | 'event' | 'rest' | 'heart' | 'boss';

export interface ZoneDefinition {
  id: string;
  name: string;
  subtitle: string;
  index: number;
  roomCount: number;
  palette: {
    floor: string;
    floorAccent: string;
    wall: string;
    wallTop: string;
    fog: string;
    ambient: string;
    accent: string;
  };
  enemyPool: string[];
  heartGuardian: string;
  ambientParticle: 'embers' | 'ash' | 'spores' | 'dust';
}

export interface WorldEventDefinition {
  id: string;
  title: string;
  description: string;
  options: EventOption[];
}

export interface EventOption {
  id: string;
  label: string;
  detail: string;
  apply: EventEffectKind;
  value?: number;
  cost?: number;
}

export type EventEffectKind =
  | 'gainEmbers'
  | 'gainHp'
  | 'loseHpForRareUpgrade'
  | 'gainRandomUpgrade'
  | 'gambleEmbers'
  | 'gainSoulAshNow'
  | 'nothing';

export interface PermanentUpgradeDefinition {
  id: string;
  name: string;
  description: string;
  maxLevel: number;
  baseCost: number;
  costGrowth: number;
  modifiers: StatModifier[];
  icon: UpgradeIconId;
  tier: number;
  requires?: string;
}

export interface UnlockDefinition {
  id: string;
  name: string;
  description: string;
  cost: number;
  kind: 'weapon' | 'ability' | 'enemy' | 'upgradeTier';
  refId: string;
}

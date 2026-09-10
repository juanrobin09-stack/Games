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
  staminaMax: number;
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
    staminaMax: 100,
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
  | 'luck'
  | 'stamina'
  | 'range'
  | 'haste';

export interface SynergyDefinition {
  id: string;
  name: string;
  description: string;
  requires: [SynergyTag, SynergyTag];
  icon: UpgradeIconId;
}

/**
 * 'bloat'  — closes in, plants itself, swells, and self-detonates into a
 *            lingering spore cloud (see CombatSystem.detonateBloat). Killing it
 *            early still leaves a smaller cloud, so WHERE it dies matters.
 * 'warden' — shield-bearer: heavily reduces damage arriving inside its frontal
 *            arc, turns slowly, and bashes forward along its facing, after which
 *            its guard drops for a moment (the flank-or-punish window).
 */
export type EnemyBehavior = 'chaser' | 'tank' | 'ranged' | 'heavy' | 'stalker' | 'elite' | 'bloat' | 'warden';

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
  /** bloat: radius of the detonation's direct hit, and of the spore cloud it leaves. */
  burstRadius?: number;
  cloudRadius?: number;
  cloudDuration?: number;
  /** warden: half-angle (radians) of the frontal arc its shield covers. */
  shieldArc?: number;
  /** warden: bash lunge speed/duration, and how long its guard stays down afterwards. */
  bashSpeed?: number;
  bashDuration?: number;
  exposedDuration?: number;
  /** warden: max turn rate in rad/s — slow enough that circling it actually works. */
  turnRate?: number;
  /** Heart-room champion: gets a boss-style HP bar and a second phase at half health. */
  champion?: boolean;
}

export interface WeaponDefinition {
  id: string;
  name: string;
  description: string;
  kind: 'melee' | 'ranged';
  baseDamage: number;
  attackCooldown: number;
  staminaCost: number;
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
  unlockCost?: number;
  color: string;
}

/** 'sanctum' — an opt-in ritual arena (Hollow Ruins): kneel at the circle to lock
 * the doors and face three waves for a rare-or-better reward. */
export type RoomType = 'start' | 'combat' | 'elite' | 'chest' | 'shop' | 'event' | 'rest' | 'heart' | 'boss' | 'sanctum';

/** Per-zone knobs for the baked floor/wall material (RoomTexture.ts) — how
 * much moss, rubble, cracking and damp staining a zone's stone carries, and
 * what colour its growth is. Every field is a multiplier on the base zone's
 * density except the colours and the damp-patch count. */
export interface ZoneMaterial {
  mossColor: string;
  mossDensity: number;
  rubbleDensity: number;
  crackDensity: number;
  dampPatches: number;
}

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
  /** LightingSystem ambient darkness while in this zone (default 0.4). */
  darkness?: number;
  /** Colour of the zone's living light (fungal growth, the open stairwell). */
  fungalColor?: string;
  /** Palette the ambient spore/ash motes are drawn from (defaults to the accent). */
  sporeColors?: string[];
  material?: ZoneMaterial;
}

export interface WorldEventDefinition {
  id: string;
  title: string;
  description: string;
  options: EventOption[];
  /** When set, the event only ever appears in this zone (and is preferred there). */
  zoneId?: string;
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
  | 'gainShieldCharge'
  | 'gainMaxHp'
  | 'loseHpForEmbers'
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

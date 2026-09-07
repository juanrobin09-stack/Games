import { Random } from '@/utils/Random';
import { rollUpgradeChoices } from '@/progression/UpgradePool';
import type { UpgradeDefinition, Rarity } from '@/data/types';

export interface ShopOffer {
  id: string;
  kind: 'upgrade' | 'heal';
  upgrade?: UpgradeDefinition;
  cost: number;
  purchased: boolean;
}

const PRICE_BY_RARITY: Record<Rarity, number> = {
  common: 22,
  uncommon: 38,
  rare: 58,
  epic: 88,
  legendary: 145,
};

export const REROLL_COST = 15;
export const HEAL_COST = 30;
export const HEAL_AMOUNT_RATIO = 0.35;

export function generateShopOffers(rng: Random, luck: number, unlockedTiers: Set<string>, exclude: Set<string>): ShopOffer[] {
  const upgrades = rollUpgradeChoices(rng, 3, luck * 0.7, unlockedTiers, exclude);
  const offers: ShopOffer[] = upgrades.map((u, i) => ({
    id: `upg-${i}`,
    kind: 'upgrade',
    upgrade: u,
    cost: PRICE_BY_RARITY[u.rarity],
    purchased: false,
  }));
  offers.push({ id: 'heal', kind: 'heal', cost: HEAL_COST, purchased: false });
  return offers;
}

export function makeShopRng(runSeed: string, roomKey: string, rerollCount: number): Random {
  return Random.fromString(`${runSeed}:shop:${roomKey}:${rerollCount}`);
}

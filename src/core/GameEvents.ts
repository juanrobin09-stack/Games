import type { Enemy } from '@/entities/Enemy';
import type { Rarity, UpgradeDefinition } from '@/data/types';
import { EventBus } from '@/utils/EventBus';

export type GameEventMap = {
  enemyKilled: { enemy: Enemy; x: number; y: number; wasElite: boolean };
  playerDamaged: { amount: number };
  playerHealed: { amount: number };
  playerDied: Record<string, never>;
  chestOpened: { tier: Rarity };
  upgradeChosen: { upgrade: UpgradeDefinition };
  roomCleared: { roomId: string };
  emberCollected: { amount: number };
  bossPhaseChanged: { phase: number };
  bossDefeated: Record<string, never>;
  critHit: { x: number; y: number };
};

export const gameEvents = new EventBus<GameEventMap>();

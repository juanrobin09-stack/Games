import { nextEntityId } from '@/entities/EntityId';
import type { Rarity, UpgradeDefinition } from '@/data/types';

export type ChestState = 'closed' | 'opening' | 'opened';

export class Chest {
  readonly id = nextEntityId();
  x: number;
  y: number;
  radius = 22;
  tier: Rarity;
  state: ChestState = 'closed';
  stateTimer = 0;
  glowPhase = Math.random() * 10;
  rewardDef: UpgradeDefinition | null = null;
  rewardShown = false;

  constructor(x: number, y: number, tier: Rarity) {
    this.x = x;
    this.y = y;
    this.tier = tier;
  }

  get canInteract(): boolean {
    return this.state === 'closed';
  }

  open(): void {
    if (this.state !== 'closed') return;
    this.state = 'opening';
    this.stateTimer = 0;
  }

  update(dt: number): void {
    this.stateTimer += dt;
    this.glowPhase += dt;
    if (this.state === 'opening' && this.stateTimer > 0.55) {
      this.state = 'opened';
      this.stateTimer = 0;
    }
  }
}

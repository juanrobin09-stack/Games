import { nextEntityId } from '@/entities/EntityId';

export type ObstacleVisual =
  | 'tree'
  | 'rock'
  | 'pillar'
  | 'rubble'
  | 'brazier'
  | 'crystal'
  | 'statue'
  | 'merchantStall'
  | 'shrine'
  | 'fungus'
  | 'sarcophagus'
  | 'stairsDown'
  | 'stairsUp';

export class Obstacle {
  readonly id = nextEntityId();
  x: number;
  y: number;
  radius: number;
  visual: ObstacleVisual;
  seed: number;
  blocksProjectiles: boolean;
  lit: boolean;
  /** World-space orientation (radians). Stairs: the direction they descend/ascend in. */
  facing: number;
  /** Stateful landmarks (the sealed stairwell) flip this once their condition is
   * met; `activatedAt` is the wall-clock second it happened, for the reveal animation. */
  activated = false;
  activatedAt = -1;

  constructor(
    x: number,
    y: number,
    radius: number,
    visual: ObstacleVisual,
    opts?: { blocksProjectiles?: boolean; lit?: boolean; facing?: number }
  ) {
    this.x = x;
    this.y = y;
    this.radius = radius;
    this.visual = visual;
    this.seed = Math.random() * 1000;
    this.facing = opts?.facing ?? 0;
    this.blocksProjectiles =
      opts?.blocksProjectiles ?? (visual === 'pillar' || visual === 'statue' || visual === 'rock' || visual === 'sarcophagus');
    this.lit =
      opts?.lit ??
      (visual === 'brazier' ||
        visual === 'crystal' ||
        visual === 'merchantStall' ||
        visual === 'shrine' ||
        visual === 'fungus' ||
        visual === 'stairsDown' ||
        visual === 'stairsUp');
  }
}

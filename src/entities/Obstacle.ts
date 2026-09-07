import { nextEntityId } from '@/entities/EntityId';

export type ObstacleVisual = 'tree' | 'rock' | 'pillar' | 'rubble' | 'brazier' | 'crystal' | 'statue' | 'merchantStall' | 'shrine';

export class Obstacle {
  readonly id = nextEntityId();
  x: number;
  y: number;
  radius: number;
  visual: ObstacleVisual;
  seed: number;
  blocksProjectiles: boolean;
  lit: boolean;

  constructor(x: number, y: number, radius: number, visual: ObstacleVisual, opts?: { blocksProjectiles?: boolean; lit?: boolean }) {
    this.x = x;
    this.y = y;
    this.radius = radius;
    this.visual = visual;
    this.seed = Math.random() * 1000;
    this.blocksProjectiles = opts?.blocksProjectiles ?? (visual === 'pillar' || visual === 'statue' || visual === 'rock');
    this.lit = opts?.lit ?? (visual === 'brazier' || visual === 'crystal' || visual === 'merchantStall' || visual === 'shrine');
  }
}

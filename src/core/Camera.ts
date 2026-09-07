import { Vector2 } from '@/utils/Vector2';
import { damp } from '@/utils/MathUtils';
import { Random } from '@/utils/Random';

export class Camera {
  position = new Vector2();
  target = new Vector2();
  width = 960;
  height = 540;
  zoom = 1;

  private shakeTime = 0;
  private shakeDuration = 0;
  private shakeMagnitude = 0;
  private shakeOffset = new Vector2();
  private shakeRng = new Random(1234);
  shakeEnabled = true;

  bounds: { minX: number; minY: number; maxX: number; maxY: number } | null = null;

  setViewport(width: number, height: number): void {
    this.width = width;
    this.height = height;
  }

  snapTo(x: number, y: number): void {
    this.target.set(x, y);
    this.position.set(x, y);
  }

  follow(x: number, y: number, dt: number): void {
    this.target.set(x, y);
    this.position.x = damp(this.position.x, this.target.x, 9, dt);
    this.position.y = damp(this.position.y, this.target.y, 9, dt);
  }

  addShake(magnitude: number, duration: number): void {
    if (!this.shakeEnabled) return;
    this.shakeMagnitude = Math.max(this.shakeMagnitude * (1 - this.shakeTime / Math.max(this.shakeDuration, 0.001)), magnitude);
    this.shakeDuration = duration;
    this.shakeTime = 0;
  }

  update(dt: number): void {
    if (this.shakeTime < this.shakeDuration) {
      this.shakeTime += dt;
      const t = 1 - this.shakeTime / this.shakeDuration;
      const power = this.shakeMagnitude * Math.max(t, 0);
      this.shakeOffset.set(this.shakeRng.range(-1, 1) * power, this.shakeRng.range(-1, 1) * power);
    } else {
      this.shakeOffset.set(0, 0);
    }
  }

  get renderX(): number {
    let x = this.position.x;
    if (this.bounds) {
      const halfW = this.width / (2 * this.zoom);
      x = Math.min(Math.max(x, this.bounds.minX + halfW), Math.max(this.bounds.maxX - halfW, this.bounds.minX + halfW));
    }
    return x + this.shakeOffset.x;
  }

  get renderY(): number {
    let y = this.position.y;
    if (this.bounds) {
      const halfH = this.height / (2 * this.zoom);
      y = Math.min(Math.max(y, this.bounds.minY + halfH), Math.max(this.bounds.maxY - halfH, this.bounds.minY + halfH));
    }
    return y + this.shakeOffset.y;
  }

  worldToScreen(x: number, y: number): Vector2 {
    return new Vector2(
      (x - this.renderX) * this.zoom + this.width / 2,
      (y - this.renderY) * this.zoom + this.height / 2
    );
  }

  screenToWorld(x: number, y: number): Vector2 {
    return new Vector2(
      (x - this.width / 2) / this.zoom + this.renderX,
      (y - this.height / 2) / this.zoom + this.renderY
    );
  }

  isOnScreen(x: number, y: number, margin = 100): boolean {
    const p = this.worldToScreen(x, y);
    return p.x > -margin && p.x < this.width + margin && p.y > -margin && p.y < this.height + margin;
  }
}

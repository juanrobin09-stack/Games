import type { Camera } from '@/core/Camera';
import { rgba } from '@/rendering/Palette';
import { Vector2 } from '@/utils/Vector2';

export interface LightSource {
  x: number;
  y: number;
  radius: number;
  color: string;
  intensity: number;
}

const MAX_LIGHTS = 48;

/**
 * Cheap Canvas2D "lighting": darken the whole frame with a translucent
 * overlay, then re-brighten with additive radial gradients at each light
 * source. Any system that wants to cast light calls `add()` once per frame;
 * the list is cleared every frame by the renderer.
 */
export class LightingSystem {
  private lights: LightSource[] = [];
  private readonly scratchScreen = new Vector2();
  ambientDarkness = 0.4;
  enabled = true;

  add(x: number, y: number, radius: number, color: string, intensity = 1): void {
    if (this.lights.length >= MAX_LIGHTS) return;
    this.lights.push({ x, y, radius, color, intensity });
  }

  clear(): void {
    this.lights.length = 0;
  }

  render(ctx: CanvasRenderingContext2D, camera: Camera, width: number, height: number): void {
    if (!this.enabled) {
      this.clear();
      return;
    }
    ctx.save();
    ctx.fillStyle = `rgba(4, 3, 8, ${this.ambientDarkness})`;
    ctx.fillRect(0, 0, width, height);

    ctx.globalCompositeOperation = 'lighter';
    for (const light of this.lights) {
      const screen = camera.worldToScreen(light.x, light.y, this.scratchScreen);
      const r = light.radius * camera.zoom;
      if (screen.x < -r || screen.x > width + r || screen.y < -r || screen.y > height + r) continue;
      const grad = ctx.createRadialGradient(screen.x, screen.y, 0, screen.x, screen.y, r);
      grad.addColorStop(0, rgba(light.color, 0.85 * light.intensity));
      grad.addColorStop(0.45, rgba(light.color, 0.32 * light.intensity));
      grad.addColorStop(1, rgba(light.color, 0));
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(screen.x, screen.y, r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
    this.clear();
  }
}

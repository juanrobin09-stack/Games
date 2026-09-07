import type { Room } from '@/world/Room';
import { ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS, DOOR_WIDTH } from '@/world/Room';
import type { ZoneDefinition } from '@/data/types';
import type { Camera } from '@/core/Camera';
import type { ParticleSystem } from '@/rendering/ParticleSystem';
import { hashJitter } from '@/rendering/DrawUtils';
import { rgba } from '@/rendering/Palette';

const DIRS = ['N', 'S', 'E', 'W'] as const;

function doorScreenRect(dir: (typeof DIRS)[number]): { x: number; y: number; w: number; h: number } {
  const t = WALL_THICKNESS;
  switch (dir) {
    case 'N':
      return { x: ROOM_WIDTH / 2 - DOOR_WIDTH / 2, y: 0, w: DOOR_WIDTH, h: t };
    case 'S':
      return { x: ROOM_WIDTH / 2 - DOOR_WIDTH / 2, y: ROOM_HEIGHT - t, w: DOOR_WIDTH, h: t };
    case 'W':
      return { x: 0, y: ROOM_HEIGHT / 2 - DOOR_WIDTH / 2, w: t, h: DOOR_WIDTH };
    case 'E':
      return { x: ROOM_WIDTH - t, y: ROOM_HEIGHT / 2 - DOOR_WIDTH / 2, w: t, h: DOOR_WIDTH };
  }
}

export function drawRoomBackground(
  ctx: CanvasRenderingContext2D,
  room: Room,
  zone: ZoneDefinition,
  camera: Camera,
  time: number
): void {
  const topLeft = camera.worldToScreen(0, 0);
  const scale = camera.zoom;

  ctx.save();
  ctx.fillStyle = zone.palette.floor;
  ctx.fillRect(topLeft.x, topLeft.y, ROOM_WIDTH * scale, ROOM_HEIGHT * scale);

  ctx.fillStyle = zone.palette.floorAccent;
  const seed = room.gridX * 7919 + room.gridY * 104729;
  for (let i = 0; i < 16; i++) {
    const jx = hashJitter(seed, i * 2);
    const jy = hashJitter(seed, i * 2 + 1);
    const x = topLeft.x + jx * ROOM_WIDTH * scale;
    const y = topLeft.y + jy * ROOM_HEIGHT * scale;
    const r = (14 + hashJitter(seed, i + 50) * 26) * scale;
    ctx.globalAlpha = 0.12 + hashJitter(seed, i + 90) * 0.1;
    ctx.beginPath();
    ctx.ellipse(x, y, r, r * 0.7, hashJitter(seed, i) * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;

  const t = WALL_THICKNESS * scale;
  ctx.fillStyle = zone.palette.wall;
  ctx.fillRect(topLeft.x, topLeft.y, ROOM_WIDTH * scale, t);
  ctx.fillRect(topLeft.x, topLeft.y + ROOM_HEIGHT * scale - t, ROOM_WIDTH * scale, t);
  ctx.fillRect(topLeft.x, topLeft.y, t, ROOM_HEIGHT * scale);
  ctx.fillRect(topLeft.x + ROOM_WIDTH * scale - t, topLeft.y, t, ROOM_HEIGHT * scale);

  ctx.fillStyle = zone.palette.wallTop;
  ctx.fillRect(topLeft.x, topLeft.y, ROOM_WIDTH * scale, t * 0.35);
  ctx.fillRect(topLeft.x, topLeft.y, t * 0.35, ROOM_HEIGHT * scale);

  for (const dir of DIRS) {
    const hasDoor = room.doors.has(dir);
    const rect = doorScreenRect(dir);
    const sx = topLeft.x + rect.x * scale;
    const sy = topLeft.y + rect.y * scale;
    const sw = rect.w * scale;
    const sh = rect.h * scale;
    if (hasDoor) {
      ctx.fillStyle = zone.palette.floor;
      ctx.fillRect(sx, sy, sw, sh);
      const locked = room.locked;
      const pulse = 0.55 + Math.sin(time * (locked ? 6 : 2.2)) * 0.25;
      ctx.fillStyle = rgba(locked ? '#c0392b' : zone.palette.accent, pulse * (locked ? 0.55 : 0.4));
      ctx.fillRect(sx, sy, sw, sh);
      ctx.strokeStyle = rgba(locked ? '#c0392b' : zone.palette.accent, 0.7);
      ctx.lineWidth = 2;
      ctx.strokeRect(sx + 1, sy + 1, sw - 2, sh - 2);
    }
  }

  ctx.restore();
}

export function drawRoomVignette(ctx: CanvasRenderingContext2D, width: number, height: number, zoneColor: string): void {
  const grad = ctx.createRadialGradient(width / 2, height / 2, height * 0.35, width / 2, height / 2, height * 0.85);
  grad.addColorStop(0, 'rgba(0,0,0,0)');
  grad.addColorStop(1, 'rgba(3,2,5,0.55)');
  ctx.save();
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);
  ctx.restore();
  void zoneColor;
}

export function spawnZoneAmbientParticle(ps: ParticleSystem, zone: ZoneDefinition, camera: Camera): void {
  const worldX = camera.renderX + (Math.random() - 0.5) * camera.width * 1.1;
  const worldY = camera.renderY + (Math.random() - 0.5) * camera.height * 1.1;
  switch (zone.ambientParticle) {
    case 'ash':
      ps.spawn({
        x: worldX,
        y: worldY - 200,
        vx: (Math.random() - 0.5) * 12,
        vy: 22 + Math.random() * 18,
        size: 2 + Math.random() * 2,
        color: zone.palette.ambient,
        endColor: zone.palette.floor,
        alpha: 0.6,
        life: 4 + Math.random() * 2,
        shape: 'circle',
      });
      break;
    case 'spores':
      ps.spawn({
        x: worldX,
        y: worldY,
        vx: (Math.random() - 0.5) * 10,
        vy: -8 - Math.random() * 8,
        size: 1.6 + Math.random() * 1.8,
        color: zone.palette.accent,
        alpha: 0.5,
        life: 3.5 + Math.random() * 2,
        glow: true,
        shape: 'circle',
      });
      break;
    case 'embers':
    default:
      ps.spawn({
        x: worldX,
        y: worldY + 100,
        vx: (Math.random() - 0.5) * 14,
        vy: -26 - Math.random() * 20,
        gravity: -6,
        size: 2 + Math.random() * 2.4,
        color: zone.palette.accent,
        endColor: zone.palette.wallTop,
        alpha: 0.75,
        life: 3 + Math.random() * 2,
        glow: true,
        shape: 'circle',
      });
      break;
  }
}

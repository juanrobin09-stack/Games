import type { Room, Direction } from '@/world/Room';
import { ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS, DOOR_WIDTH } from '@/world/Room';
import type { ZoneDefinition } from '@/data/types';
import type { Camera } from '@/core/Camera';
import type { ParticleSystem } from '@/rendering/ParticleSystem';
import { hashJitter, roundedRectPath } from '@/rendering/DrawUtils';
import { rgba, mixColor, Palette } from '@/rendering/Palette';

const DIRS = ['N', 'S', 'E', 'W'] as const;

/** World-space rotation that maps "canonical" door-local +Y (into the room) onto
 * the correct world direction for each wall the door sits on. */
const DOOR_ROTATION: Record<Direction, number> = { N: 0, S: Math.PI, W: -Math.PI / 2, E: Math.PI / 2 };

/**
 * Draws one door in canonical local space: origin at the door's center, +X along
 * the wall (the door's width), +Y pointing INTO the room. The caller rotates this
 * into place per direction (see DOOR_ROTATION) so the geometry only has to be
 * authored once. `approach` is 0..1, how close the player currently is to this door.
 */
function drawDoorCanonical(
  ctx: CanvasRenderingContext2D,
  scale: number,
  zone: ZoneDefinition,
  locked: boolean,
  pulse: number,
  approach: number
): void {
  const hw = (DOOR_WIDTH / 2) * scale;
  const ht = (WALL_THICKNESS / 2) * scale;
  const stateColor = locked ? Palette.blood : zone.palette.accent;

  // Depth recess: the passage floor, fading to near-black toward the far/outer
  // edge — nothing exists beyond it (only the current room ever simulates), so a
  // fade to darkness is the honest representation of "you can't see that far yet".
  const recess = ctx.createLinearGradient(0, -ht, 0, ht);
  recess.addColorStop(0, Palette.void);
  recess.addColorStop(0.55, zone.palette.wall);
  recess.addColorStop(1, zone.palette.floor);
  ctx.fillStyle = recess;
  ctx.fillRect(-hw, -ht, hw * 2, ht * 2);

  // Jambs: two carved posts straddling the opening's edges, giving it a worked,
  // built silhouette instead of a raw hole in the wall.
  const jambW = 9 * scale;
  const jambOuter = ht + 9 * scale;
  for (const side of [-1, 1]) {
    const cx = side * hw;
    const grad = ctx.createLinearGradient(cx - jambW, 0, cx + jambW, 0);
    grad.addColorStop(0, zone.palette.wall);
    grad.addColorStop(0.5, zone.palette.wallTop);
    grad.addColorStop(1, zone.palette.wall);
    ctx.fillStyle = grad;
    roundedRectPath(ctx, cx - jambW, -jambOuter, jambW * 2, jambOuter * 2, 3 * scale);
    ctx.fill();
  }

  // Lintel: a bright sliver along the room-facing lip, as if catching ambient light.
  ctx.strokeStyle = rgba(zone.palette.wallTop, 0.8);
  ctx.lineWidth = Math.max(1, 2 * scale);
  ctx.beginPath();
  ctx.moveTo(-hw + jambW, ht - 1 * scale);
  ctx.lineTo(hw - jambW, ht - 1 * scale);
  ctx.stroke();

  // State glow: spills asymmetrically into the room, brighter and wider when the
  // player is close by — a passage that visibly "notices" you approaching it.
  const glowStrength = (locked ? 0.5 : 0.4) * pulse * (1 + approach * 0.6);
  const glowRadius = (locked ? 70 : 85) * scale * (1 + approach * 0.25);
  const glow = ctx.createRadialGradient(0, ht * 0.6, 0, 0, ht * 0.6, glowRadius);
  glow.addColorStop(0, rgba(stateColor, glowStrength));
  glow.addColorStop(0.5, rgba(stateColor, glowStrength * 0.35));
  glow.addColorStop(1, rgba(stateColor, 0));
  ctx.fillStyle = glow;
  ctx.fillRect(-hw * 3, -ht * 2, hw * 6, (ht + glowRadius) * 2);

  if (locked) {
    // A sealed, barred passage — a shape cue that doesn't rely on color alone.
    ctx.strokeStyle = rgba(mixColor(Palette.void, Palette.blood, 0.4), 0.85);
    ctx.lineWidth = Math.max(1.5, 3 * scale);
    for (const bx of [-hw * 0.45, 0, hw * 0.45]) {
      ctx.beginPath();
      ctx.moveTo(bx, -ht);
      ctx.lineTo(bx, ht);
      ctx.stroke();
    }
  }
}

export function drawRoomBackground(
  ctx: CanvasRenderingContext2D,
  room: Room,
  zone: ZoneDefinition,
  camera: Camera,
  time: number,
  playerX: number,
  playerY: number
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

  const locked = room.locked;
  const pulse = 0.55 + Math.sin(time * (locked ? 6 : 2.2)) * 0.25;
  const APPROACH_RADIUS = 260;
  for (const dir of DIRS) {
    if (!room.doors.has(dir)) continue;
    const center = room.doorCenter(dir);
    const screenCenter = camera.worldToScreen(center.x, center.y);
    const distToPlayer = Math.hypot(center.x - playerX, center.y - playerY);
    const approach = Math.max(0, 1 - distToPlayer / APPROACH_RADIUS);

    ctx.save();
    ctx.translate(screenCenter.x, screenCenter.y);
    ctx.rotate(DOOR_ROTATION[dir]);
    drawDoorCanonical(ctx, scale, zone, locked, pulse, approach);
    ctx.restore();
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

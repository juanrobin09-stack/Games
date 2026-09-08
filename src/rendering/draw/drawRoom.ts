import type { Room, Direction } from '@/world/Room';
import { ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS, DOOR_WIDTH } from '@/world/Room';
import type { ZoneDefinition } from '@/data/types';
import type { Camera } from '@/core/Camera';
import type { ParticleSystem } from '@/rendering/ParticleSystem';
import { hashJitter } from '@/rendering/DrawUtils';
import { rgba, mixColor, Palette } from '@/rendering/Palette';
import { getWallStrip } from '@/rendering/RoomTexture';
import { paintCornerSwatch, tintSwatch } from '@/rendering/StoneAsset';

const DIRS = ['N', 'S', 'E', 'W'] as const;
/** Center of each corner's wall-overlap square (inset half a thickness in from
 * the true corner point, not centered ON it — the block must sit fully inside
 * the N/S and E/W strips' own footprint, not straddle out past the wall into
 * the void beyond it). */
const CORNERS: { x: number; y: number }[] = [
  { x: WALL_THICKNESS / 2, y: WALL_THICKNESS / 2 },
  { x: ROOM_WIDTH - WALL_THICKNESS / 2, y: WALL_THICKNESS / 2 },
  { x: WALL_THICKNESS / 2, y: ROOM_HEIGHT - WALL_THICKNESS / 2 },
  { x: ROOM_WIDTH - WALL_THICKNESS / 2, y: ROOM_HEIGHT - WALL_THICKNESS / 2 },
];

/** World-space rotation that maps "canonical" door-local +Y (into the room) onto
 * the correct world direction for each wall the door sits on. */
const DOOR_ROTATION: Record<Direction, number> = { N: 0, S: Math.PI, W: -Math.PI / 2, E: Math.PI / 2 };

/**
 * The N/S and E/W wall strips are baked independently, so at each room corner
 * whichever strip is drawn last simply overwrites the other's corner pixels —
 * not wrong, but not the deliberate, chunkier corner stone real masonry has
 * either. This is cheap enough (4 blocks) to draw fresh every frame rather than
 * bake, tying the two strips together at the joint.
 */
function drawCornerStone(ctx: CanvasRenderingContext2D, screenX: number, screenY: number, size: number, zone: ZoneDefinition, seed: number): void {
  const dx = screenX - size / 2;
  const dy = screenY - size / 2;
  const painted = paintCornerSwatch(ctx, dx, dy, size, size, hashJitter(seed, 777));
  if (painted) {
    tintSwatch(ctx, dx, dy, size, size, zone.palette.wallTop, 0.4);
  } else {
    const grad = ctx.createRadialGradient(screenX - size * 0.2, screenY - size * 0.2, 0, screenX, screenY, size * 0.9);
    grad.addColorStop(0, mixColor(zone.palette.wallTop, '#fffaf0', 0.12));
    grad.addColorStop(0.65, zone.palette.wallTop);
    grad.addColorStop(1, zone.palette.wall);
    ctx.fillStyle = grad;
    ctx.fillRect(dx, dy, size, size);
  }
  ctx.strokeStyle = rgba(zone.palette.wall, 0.6);
  ctx.lineWidth = Math.max(1, size * 0.04);
  ctx.strokeRect(dx, dy, size, size);
  if (hashJitter(seed, 999) > 0.5) {
    ctx.strokeStyle = 'rgba(0,0,0,0.3)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(screenX - size * 0.3, screenY - size * 0.1);
    ctx.lineTo(screenX + size * 0.1, screenY + size * 0.35);
    ctx.stroke();
  }
}

/**
 * Draws the door's dynamic state on top of the room's baked masonry (which already
 * contains the opening itself, its jambs and threshold debris — see RoomTexture.ts).
 * Only the parts that actually change frame to frame live here: the locked/unlocked
 * glow (pulsing, brighter as the player approaches) and the sealed-door bars.
 */
function drawDoorOverlay(
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

  const seed = room.gridX * 7919 + room.gridY * 104729;

  // Large flagstone seams — a coarser grid than the wall's masonry, giving the
  // floor its own distinct scale of texture rather than reading as one flat plane.
  ctx.strokeStyle = rgba(zone.palette.wall, 0.35);
  ctx.lineWidth = Math.max(1, 1.4 * scale);
  const cols = 6;
  const rows = 4;
  for (let c = 1; c < cols; c++) {
    const x = topLeft.x + (c / cols) * ROOM_WIDTH * scale + hashJitter(seed, c + 200) * 14 * scale;
    ctx.beginPath();
    ctx.moveTo(x, topLeft.y);
    ctx.lineTo(x, topLeft.y + ROOM_HEIGHT * scale);
    ctx.stroke();
  }
  for (let r = 1; r < rows; r++) {
    const y = topLeft.y + (r / rows) * ROOM_HEIGHT * scale + hashJitter(seed, r + 260) * 14 * scale;
    ctx.beginPath();
    ctx.moveTo(topLeft.x, y);
    ctx.lineTo(topLeft.x + ROOM_WIDTH * scale, y);
    ctx.stroke();
  }

  ctx.fillStyle = zone.palette.floorAccent;
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

  // Sparse debris hugging the walls — small chips knocked loose from the masonry.
  const margin = WALL_THICKNESS + 60;
  for (let i = 0; i < 10; i++) {
    const edge = Math.floor(hashJitter(seed, i + 400) * 4);
    const along = hashJitter(seed, i + 450);
    let wx: number, wy: number;
    if (edge === 0) { wx = along * ROOM_WIDTH; wy = margin * hashJitter(seed, i + 470); }
    else if (edge === 1) { wx = along * ROOM_WIDTH; wy = ROOM_HEIGHT - margin * hashJitter(seed, i + 480); }
    else if (edge === 2) { wx = margin * hashJitter(seed, i + 490); wy = along * ROOM_HEIGHT; }
    else { wx = ROOM_WIDTH - margin * hashJitter(seed, i + 495); wy = along * ROOM_HEIGHT; }
    const sx = topLeft.x + wx * scale;
    const sy = topLeft.y + wy * scale;
    const r = (2 + hashJitter(seed, i + 500) * 3.5) * scale;
    ctx.globalAlpha = 0.35 + hashJitter(seed, i + 510) * 0.25;
    ctx.fillStyle = mixColor(zone.palette.wall, '#000000', 0.1);
    ctx.beginPath();
    ctx.ellipse(sx, sy, r, r * 0.65, hashJitter(seed, i + 520) * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;

  const t = WALL_THICKNESS * scale;
  const roomKey = room.key;
  const nStrip = getWallStrip(roomKey, zone, 'N', room.doors.has('N'));
  ctx.drawImage(nStrip, topLeft.x, topLeft.y, ROOM_WIDTH * scale, t);
  const sStrip = getWallStrip(roomKey, zone, 'S', room.doors.has('S'));
  ctx.drawImage(sStrip, topLeft.x, topLeft.y + ROOM_HEIGHT * scale - t, ROOM_WIDTH * scale, t);
  const wStrip = getWallStrip(roomKey, zone, 'W', room.doors.has('W'));
  ctx.drawImage(wStrip, topLeft.x, topLeft.y, t, ROOM_HEIGHT * scale);
  const eStrip = getWallStrip(roomKey, zone, 'E', room.doors.has('E'));
  ctx.drawImage(eStrip, topLeft.x + ROOM_WIDTH * scale - t, topLeft.y, t, ROOM_HEIGHT * scale);

  // A soft contact shadow hugging each wall's inner edge, so the floor reads
  // as genuinely meeting a heavy stone wall rather than butting into a flat
  // seam between two independently-drawn textures.
  const shadow = 16 * scale;
  let edgeGrad = ctx.createLinearGradient(0, topLeft.y + t, 0, topLeft.y + t + shadow);
  edgeGrad.addColorStop(0, 'rgba(0,0,0,0.38)');
  edgeGrad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = edgeGrad;
  ctx.fillRect(topLeft.x + t, topLeft.y + t, ROOM_WIDTH * scale - t * 2, shadow);

  edgeGrad = ctx.createLinearGradient(0, topLeft.y + ROOM_HEIGHT * scale - t, 0, topLeft.y + ROOM_HEIGHT * scale - t - shadow);
  edgeGrad.addColorStop(0, 'rgba(0,0,0,0.38)');
  edgeGrad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = edgeGrad;
  ctx.fillRect(topLeft.x + t, topLeft.y + ROOM_HEIGHT * scale - t - shadow, ROOM_WIDTH * scale - t * 2, shadow);

  edgeGrad = ctx.createLinearGradient(topLeft.x + t, 0, topLeft.x + t + shadow, 0);
  edgeGrad.addColorStop(0, 'rgba(0,0,0,0.38)');
  edgeGrad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = edgeGrad;
  ctx.fillRect(topLeft.x + t, topLeft.y + t, shadow, ROOM_HEIGHT * scale - t * 2);

  edgeGrad = ctx.createLinearGradient(topLeft.x + ROOM_WIDTH * scale - t, 0, topLeft.x + ROOM_WIDTH * scale - t - shadow, 0);
  edgeGrad.addColorStop(0, 'rgba(0,0,0,0.38)');
  edgeGrad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = edgeGrad;
  ctx.fillRect(topLeft.x + ROOM_WIDTH * scale - t - shadow, topLeft.y + t, shadow, ROOM_HEIGHT * scale - t * 2);

  CORNERS.forEach((corner, i) => {
    const sx = topLeft.x + corner.x * scale;
    const sy = topLeft.y + corner.y * scale;
    drawCornerStone(ctx, sx, sy, t, zone, seed + i * 37);
  });

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
    drawDoorOverlay(ctx, scale, zone, locked, pulse, approach);
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

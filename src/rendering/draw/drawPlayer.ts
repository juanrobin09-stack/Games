import type { Player } from '@/entities/Player';
import type { WeaponDefinition } from '@/data/types';
import { Palette, rgba } from '@/rendering/Palette';
import { drawSoftShadow, drawGlowCircle, lerpColorHex } from '@/rendering/DrawUtils';
import { easeOutCubic } from '@/utils/MathUtils';

function drawWeapon(
  ctx: CanvasRenderingContext2D,
  weapon: WeaponDefinition,
  length: number,
  swingProgress: number | null
): void {
  ctx.save();
  const glow = weapon.color;
  if (weapon.kind === 'melee') {
    const width = weapon.id === 'voidScythe' ? 9 : 6;
    const curve = weapon.id === 'voidScythe' ? 0.55 : 0.15;
    ctx.beginPath();
    ctx.moveTo(6, 3);
    ctx.quadraticCurveTo(length * 0.55, -width - length * curve, length, -width * 0.4);
    ctx.lineTo(length + 4, 0);
    ctx.quadraticCurveTo(length * 0.55, width * 0.7 + length * curve * 0.6, 6, -3);
    ctx.closePath();
    const grad = ctx.createLinearGradient(0, 0, length, 0);
    grad.addColorStop(0, Palette.bg3);
    grad.addColorStop(0.35, glow);
    grad.addColorStop(1, lerpColorHex(glow, '#ffffff', 0.5));
    ctx.fillStyle = grad;
    ctx.shadowColor = glow;
    ctx.shadowBlur = swingProgress !== null ? 18 : 8;
    ctx.fill();
    ctx.fillStyle = Palette.bg2;
    ctx.fillRect(-6, -3, 12, 6);
  } else {
    ctx.beginPath();
    ctx.moveTo(4, 0);
    ctx.lineTo(length - 14, -4);
    ctx.lineTo(length, 0);
    ctx.lineTo(length - 14, 4);
    ctx.closePath();
    const grad = ctx.createLinearGradient(0, 0, length, 0);
    grad.addColorStop(0, Palette.bg3);
    grad.addColorStop(1, glow);
    ctx.fillStyle = grad;
    ctx.shadowColor = glow;
    ctx.shadowBlur = 10;
    ctx.fill();
    ctx.fillStyle = Palette.bg2;
    ctx.fillRect(-4, -2.5, 10, 5);
  }
  ctx.restore();
}

export function drawPlayer(ctx: CanvasRenderingContext2D, player: Player, screenX: number, screenY: number): void {
  const weapon = player.weapon;
  const facing = player.isAttacking ? player.attackFacingLock : player.facing;
  const moving = Math.hypot(player.vx, player.vy) > 6 && !player.isDodging;
  const bob = moving ? Math.sin(player.moveCyclePhase) * 2.4 : Math.sin(player.animTime * 2) * 0.8;
  const squash = player.isDodging ? 1.15 : 1;

  const isDead = !player.alive;
  const deathT = Math.min(1, player.deathTimer / 0.6);

  ctx.save();
  ctx.translate(screenX, screenY);

  drawSoftShadow(ctx, 0, 20, 22, 9, 0.42);

  if (isDead) {
    ctx.globalAlpha = Math.max(0.15, 1 - deathT * 0.6);
    ctx.rotate((Math.PI / 2) * easeOutCubic(deathT) * (player.facing > 0 ? 1 : -1));
    ctx.translate(0, easeOutCubic(deathT) * 10);
  }

  ctx.translate(0, bob);
  ctx.scale(1 / squash, squash);

  // --- Cape ---
  const capeAngle = moving ? Math.atan2(player.vy, player.vx) : facing;
  const capeSway = Math.sin(player.cloakPhase * 3.4) * 5;
  ctx.save();
  ctx.rotate(capeAngle + Math.PI);
  const capeGrad = ctx.createLinearGradient(0, -14, 30, 14);
  capeGrad.addColorStop(0, Palette.bg1);
  capeGrad.addColorStop(1, '#0a0810');
  ctx.fillStyle = capeGrad;
  ctx.beginPath();
  ctx.moveTo(-4, -12);
  ctx.quadraticCurveTo(18 + Math.abs(capeSway) * 0.4, -18 + capeSway, 30, -4 + capeSway * 0.6);
  ctx.quadraticCurveTo(24, 6, 14, 10);
  ctx.quadraticCurveTo(6, 14, -4, 12);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = rgba(Palette.ember3, 0.35);
  ctx.lineWidth = 1.2;
  ctx.stroke();
  ctx.restore();

  // --- Body ---
  const bodyGrad = ctx.createRadialGradient(-4, -6, 2, 0, 0, 20);
  bodyGrad.addColorStop(0, '#3a3444');
  bodyGrad.addColorStop(1, Palette.bg1);
  ctx.fillStyle = bodyGrad;
  ctx.beginPath();
  ctx.ellipse(0, 2, 13, 16, 0, 0, Math.PI * 2);
  ctx.fill();

  // --- Chest ember (the light he guards) ---
  const pulse = 0.75 + Math.sin(player.runTime * 3.2) * 0.25;
  drawGlowCircle(ctx, 0, 4, 13 * pulse, Palette.ember4, 0.9);
  ctx.fillStyle = Palette.ember6;
  ctx.beginPath();
  ctx.arc(0, 4, 3, 0, Math.PI * 2);
  ctx.fill();

  // --- Head + hood ---
  ctx.save();
  ctx.rotate(facing * 0.18);
  ctx.fillStyle = '#2a2632';
  ctx.beginPath();
  ctx.arc(0, -16, 9, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = Palette.bg0;
  ctx.beginPath();
  ctx.moveTo(-9, -18);
  ctx.quadraticCurveTo(0, -30, 9, -18);
  ctx.quadraticCurveTo(6, -12, 0, -10);
  ctx.quadraticCurveTo(-6, -12, -9, -18);
  ctx.fill();
  const eyeX = Math.cos(facing) * 4;
  const eyeY = -16 + Math.sin(facing) * 2;
  ctx.fillStyle = Palette.ember5;
  ctx.shadowColor = Palette.ember4;
  ctx.shadowBlur = 6;
  ctx.beginPath();
  ctx.ellipse(eyeX, eyeY, 2.6, 1.6, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.restore();

  // --- Arm + Weapon ---
  let weaponAngle = facing;
  let swingProgress: number | null = null;
  if (player.isAttacking) {
    const swingDuration = Math.min(0.32, player.attackCooldownDuration * 0.85);
    swingProgress = Math.min(1, player.attackAnimTimer / swingDuration);
    const arc = ((weapon.arcDegrees ?? 90) * Math.PI) / 180;
    const swingAngle = -arc / 2 + arc * easeOutCubic(swingProgress);
    weaponAngle = facing + swingAngle;
  }
  ctx.save();
  ctx.rotate(weaponAngle);
  ctx.translate(10, 0);
  drawWeapon(ctx, weapon, weapon.kind === 'melee' ? 34 : 40, swingProgress);
  ctx.restore();

  // --- Hit flash overlay ---
  if (player.hitFlashTimer > 0 && !isDead) {
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = (player.hitFlashTimer / 0.28) * 0.55;
    ctx.fillStyle = Palette.bloodBright;
    ctx.beginPath();
    ctx.ellipse(0, 0, 18, 20, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }

  if (player.isInvulnerable && player.alive && !player.isDodging) {
    ctx.globalAlpha = 0.5 + Math.sin(player.runTime * 30) * 0.2;
    ctx.strokeStyle = rgba(Palette.ember5, 0.6);
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.ellipse(0, 2, 17, 20, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  ctx.restore();
}

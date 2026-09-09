import { nextEntityId } from '@/entities/EntityId';
import { createBaseStats, type StatBlock, type StatModifier, type SynergyTag, type UpgradeDefinition } from '@/data/types';
import { applyModifiers } from '@/data/stats';
import { clamp } from '@/utils/MathUtils';
import { getWeaponDefinition } from '@/data/weapons';
import { getAbilityDefinition } from '@/data/abilities';
import { SYNERGIES } from '@/data/synergies';

export type PlayerAnim = 'idle' | 'run' | 'attack' | 'hit' | 'dead' | 'dodge' | 'ability';

export interface OwnedUpgrade {
  def: UpgradeDefinition;
  stacks: number;
}

export class Player {
  readonly id = nextEntityId();
  x = 0;
  y = 0;
  vx = 0;
  vy = 0;
  radius = 15;
  facing = 0;
  moveInputX = 0;
  moveInputY = 0;
  animState: PlayerAnim = 'idle';
  animTime = 0;
  moveCyclePhase = 0;
  cloakPhase = 0;

  hp = 100;
  shieldCharges = 0;
  energy = 100;
  alive = true;
  deathTimer = 0;

  invulnTimer = 0;
  hitFlashTimer = 0;

  weaponId = 'emberBlade';
  abilityId: 'emberBurst' | 'stormstep' | 'wardingSigil' = 'emberBurst';
  unlockedWeapons = new Set<string>(['emberBlade']);
  unlockedAbilities = new Set<string>(['emberBurst']);

  attackCooldownTimer = 0;
  attackAnimTimer = 0;
  isAttacking = false;
  attackFacingLock = 0;
  attackSwingId = 0;

  dodgeCooldownTimer = 0;
  isDodging = false;
  dodgeTimer = 0;
  dodgeDuration = 0.22;
  dodgeDirX = 0;
  dodgeDirY = 0;
  lastDodgeEndTime = -10;

  abilityCooldownTimer = 0;
  isChannelingAbility = false;
  abilityAnimTimer = 0;

  stats: StatBlock = createBaseStats();
  upgrades: OwnedUpgrade[] = [];
  activeSynergies = new Set<string>();
  /** Run-scoped stat bonuses that aren't upgrades (world events like the Spore
   * Mother). Folded into every stat recompute alongside the owned upgrades. */
  bonusModifiers: StatModifier[] = [];

  runTime = 0;
  wardingSigilActive: { x: number; y: number; timer: number; duration: number } | null = null;
  perfectDodgeTimer = 0;

  constructor(private baseStats: StatBlock) {
    this.recomputeStats();
    this.hp = this.stats.maxHp;
    this.energy = this.stats.energyMax;
  }

  private recomputeStats(): void {
    const allModifiers = this.upgrades.flatMap((u) =>
      Array.from({ length: u.stacks }, () => u.def.modifiers).flat()
    );
    this.stats = applyModifiers(this.baseStats, [...allModifiers, ...this.bonusModifiers]);
    this.recomputeSynergies();
  }

  /** Grants a run-long stat bonus outside the upgrade system, keeping current HP
   * proportional (so a max-HP bonus never leaves the bar looking emptier). */
  addBonusModifier(mod: StatModifier): void {
    const hpRatio = this.hp / Math.max(1, this.stats.maxHp);
    this.bonusModifiers.push(mod);
    this.recomputeStats();
    this.hp = Math.min(this.stats.maxHp, Math.max(this.hp, this.stats.maxHp * hpRatio));
  }

  private recomputeSynergies(): void {
    const tagCounts = new Map<SynergyTag, number>();
    for (const owned of this.upgrades) {
      for (const tag of owned.def.tags) {
        tagCounts.set(tag, (tagCounts.get(tag) ?? 0) + owned.stacks);
      }
    }
    this.activeSynergies.clear();
    for (const syn of SYNERGIES) {
      const [a, b] = syn.requires;
      const need = a === b ? 2 : 1;
      const countA = tagCounts.get(a) ?? 0;
      const countB = tagCounts.get(b) ?? 0;
      const active = a === b ? countA >= need : countA >= 1 && countB >= 1;
      if (active) this.activeSynergies.add(syn.id);
    }
  }

  hasSynergy(id: string): boolean {
    return this.activeSynergies.has(id);
  }

  /** Applies the upgrade and returns the IDs of any synergy that just became active for the first time. */
  addUpgrade(def: UpgradeDefinition): string[] {
    const existing = this.upgrades.find((u) => u.def.id === def.id);
    if (existing) {
      if (!def.maxStacks || existing.stacks < def.maxStacks) existing.stacks++;
    } else {
      this.upgrades.push({ def, stacks: 1 });
    }
    const hpRatio = this.hp / Math.max(1, this.stats.maxHp);
    const before = new Set(this.activeSynergies);
    this.recomputeStats();
    this.hp = Math.min(this.stats.maxHp, Math.max(this.hp, this.stats.maxHp * hpRatio));
    return Array.from(this.activeSynergies).filter((id) => !before.has(id));
  }

  get weapon() {
    return getWeaponDefinition(this.weaponId);
  }

  get ability() {
    return getAbilityDefinition(this.abilityId);
  }

  /** Damage multiplier from the Wrath synergy: scales up to +50% as HP drops toward 0. */
  get wrathMultiplier(): number {
    if (!this.hasSynergy('wrath')) return 1;
    const missingRatio = 1 - clamp(this.hp / Math.max(1, this.stats.maxHp), 0, 1);
    return 1 + missingRatio * 0.5;
  }

  /** Combined damage multiplier from all active synergy/state buffs (wrath, perfect dodge). */
  get synergyDamageMultiplier(): number {
    let mult = this.wrathMultiplier;
    if (this.perfectDodgeTimer > 0) mult *= 1.35;
    return mult;
  }

  triggerPerfectDodge(): void {
    if (this.hasSynergy('shadowDodge')) this.perfectDodgeTimer = 3;
  }

  get attackCooldownDuration(): number {
    return this.weapon.attackCooldown / this.stats.attackSpeedMult;
  }

  get dodgeCooldownDuration(): number {
    return 0.95 * this.stats.dodgeCooldownMult;
  }

  get isInvulnerable(): boolean {
    return this.invulnTimer > 0 || this.isDodging;
  }

  canAttack(): boolean {
    return this.alive && !this.isDodging && this.attackCooldownTimer <= 0;
  }

  canDodge(): boolean {
    return this.alive && !this.isDodging && this.dodgeCooldownTimer <= 0;
  }

  canUseAbility(): boolean {
    return (
      this.alive &&
      !this.isDodging &&
      this.abilityCooldownTimer <= 0 &&
      this.energy >= this.ability.energyCost
    );
  }

  startAttack(): void {
    this.isAttacking = true;
    this.attackAnimTimer = 0;
    this.attackFacingLock = this.facing;
    this.attackCooldownTimer = this.attackCooldownDuration;
    this.attackSwingId++;
    this.animState = 'attack';
    this.animTime = 0;
  }

  startDodge(dirX: number, dirY: number): void {
    this.isDodging = true;
    this.dodgeTimer = 0;
    this.dodgeDirX = dirX;
    this.dodgeDirY = dirY;
    this.dodgeCooldownTimer = this.dodgeCooldownDuration;
    this.animState = 'dodge';
    this.animTime = 0;
  }

  startAbility(): void {
    this.energy -= this.ability.energyCost;
    this.abilityCooldownTimer = this.ability.cooldown;
    this.isChannelingAbility = true;
    this.abilityAnimTimer = 0;
    this.animState = 'ability';
    this.animTime = 0;
  }

  takeDamage(amount: number): { taken: number; blocked: boolean; shieldConsumed: boolean } {
    if (this.isInvulnerable || !this.alive) return { taken: 0, blocked: true, shieldConsumed: false };
    let dmg = amount * (1 - this.stats.armor);
    if (this.shieldCharges > 0) {
      this.shieldCharges--;
      this.invulnTimer = 0.4;
      this.hitFlashTimer = 0.25;
      return { taken: 0, blocked: true, shieldConsumed: true };
    }
    dmg = Math.max(1, dmg);
    this.hp -= dmg;
    this.hitFlashTimer = 0.28;
    this.invulnTimer = 0.55;
    this.animState = 'hit';
    this.animTime = 0;
    if (this.hp <= 0) {
      this.hp = 0;
      this.alive = false;
      this.animState = 'dead';
      this.animTime = 0;
    }
    return { taken: dmg, blocked: false, shieldConsumed: false };
  }

  heal(amount: number): void {
    this.hp = clamp(this.hp + amount, 0, this.stats.maxHp);
  }

  update(dt: number): void {
    this.runTime += dt;
    this.animTime += dt;
    if (!this.alive) {
      this.deathTimer += dt;
      return;
    }

    if (this.invulnTimer > 0) this.invulnTimer -= dt;
    if (this.hitFlashTimer > 0) this.hitFlashTimer -= dt;
    if (this.attackCooldownTimer > 0) this.attackCooldownTimer -= dt;
    if (this.dodgeCooldownTimer > 0) this.dodgeCooldownTimer -= dt;
    if (this.abilityCooldownTimer > 0) this.abilityCooldownTimer -= dt;
    if (this.perfectDodgeTimer > 0) this.perfectDodgeTimer -= dt;

    this.hp = clamp(this.hp + this.stats.hpRegen * dt, 0, this.stats.maxHp);
    this.energy = clamp(this.energy + this.stats.energyRegen * dt, 0, this.stats.energyMax);

    if (this.isAttacking) {
      this.attackAnimTimer += dt;
      const swingDuration = Math.min(0.32, this.attackCooldownDuration * 0.85);
      if (this.attackAnimTimer >= swingDuration) {
        this.isAttacking = false;
      }
    }

    if (this.isDodging) {
      this.dodgeTimer += dt;
      const t = this.dodgeTimer / this.dodgeDuration;
      const speed = this.stats.moveSpeed * 3.1 * (1 - t * 0.3);
      this.vx = this.dodgeDirX * speed;
      this.vy = this.dodgeDirY * speed;
      if (this.dodgeTimer >= this.dodgeDuration) {
        this.isDodging = false;
        this.lastDodgeEndTime = this.runTime;
      }
    } else {
      const targetVx = this.moveInputX * this.stats.moveSpeed;
      const targetVy = this.moveInputY * this.stats.moveSpeed;
      const accel = 14;
      this.vx += (targetVx - this.vx) * Math.min(1, accel * dt);
      this.vy += (targetVy - this.vy) * Math.min(1, accel * dt);
    }

    this.x += this.vx * dt;
    this.y += this.vy * dt;

    const moving = this.moveInputX !== 0 || this.moveInputY !== 0;
    if (moving) {
      const speedRatio = Math.hypot(this.vx, this.vy) / Math.max(1, this.stats.moveSpeed);
      this.moveCyclePhase += dt * 7.2 * Math.max(0.4, speedRatio);
    }
    this.cloakPhase += dt;

    if (this.isChannelingAbility) {
      this.abilityAnimTimer += dt;
      if (this.abilityAnimTimer > 0.35) this.isChannelingAbility = false;
    }

    if (this.wardingSigilActive) {
      this.wardingSigilActive.timer += dt;
      if (this.wardingSigilActive.timer >= this.wardingSigilActive.duration) {
        this.wardingSigilActive = null;
      }
    }

    if (!this.isAttacking && !this.isDodging && !this.isChannelingAbility) {
      this.animState = moving ? 'run' : 'idle';
    }
  }

  reset(x: number, y: number): void {
    this.x = x;
    this.y = y;
    this.vx = 0;
    this.vy = 0;
    this.hp = this.stats.maxHp;
    this.energy = this.stats.energyMax;
    this.shieldCharges = this.stats.shieldMax;
    this.alive = true;
    this.deathTimer = 0;
    this.invulnTimer = 1.2;
    this.isAttacking = false;
    this.isDodging = false;
    this.isChannelingAbility = false;
    this.animState = 'idle';
    this.wardingSigilActive = null;
  }
}

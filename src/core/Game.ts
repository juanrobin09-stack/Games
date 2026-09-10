import { Renderer } from '@/rendering/Renderer';
import { Camera } from '@/core/Camera';
import { InputManager } from '@/core/Input';
import { GameState, GameStateMachine } from '@/core/GameState';
import { HitStopController } from '@/core/HitStop';
import { gameEvents } from '@/core/GameEvents';
import { ParticleSystem } from '@/rendering/ParticleSystem';
import { LightingSystem } from '@/rendering/Lighting';
import { Palette, rgba } from '@/rendering/Palette';
import { drawPlayer } from '@/rendering/draw/drawPlayer';
import { drawEnemy } from '@/rendering/draw/drawEnemy';
import { drawProjectile } from '@/rendering/draw/drawProjectile';
import { drawPickup } from '@/rendering/draw/drawPickup';
import { drawChest } from '@/rendering/draw/drawChest';
import { drawObstacle } from '@/rendering/draw/drawObstacle';
import { drawBoss, drawMeteorTelegraph } from '@/rendering/draw/drawBoss';
import { drawDamageNumbers } from '@/rendering/draw/drawDamageNumbers';
import { drawRoomBackground, drawRoomVignette, spawnZoneAmbientParticle } from '@/rendering/draw/drawRoom';
import { drawHazards } from '@/rendering/draw/drawHazard';
import { drawSanctumCircle, sanctumCandlePosition, sanctumLitCandles, SANCTUM_CANDLE_COUNT } from '@/rendering/draw/drawSanctum';
import { clearRoomTextureCache } from '@/rendering/RoomTexture';
import {
  spawnChestOpenBurst,
  spawnDodgeTrail,
  spawnHealSparkle,
  spawnLevelUpBurst,
  spawnSporeMote,
  spawnSporeBurstVfx,
  spawnStoneChips,
  spawnRitualIgnite,
} from '@/rendering/ParticlePresets';
import { audio } from '@/audio/AudioEngine';
import { music } from '@/audio/MusicEngine';
import { playSfx, type SfxId } from '@/audio/SoundFactory';
import { Player } from '@/entities/Player';
import { Enemy } from '@/entities/Enemy';
import { Boss } from '@/entities/Boss';
import { Pickup } from '@/entities/Pickup';
import { CombatSystem } from '@/combat/CombatSystem';
import { resolveBossPendingActions } from '@/combat/BossSystem';
import { updateEnemyAI, isAttackTriggerFrame, resolveAttackTrigger, applyEnemySeparation, type EnemyAIContext } from '@/ai/EnemyAI';
import { Room, OPPOSITE, ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS, type Direction } from '@/world/Room';
import {
  populateRoomContent,
  spawnSanctumWave,
  stairsFootPosition,
  stairsMouthPosition,
  SANCTUM_WAVE_COUNT,
  SANCTUM_RING_RADIUS,
} from '@/world/LevelGenerator';
import { getDifficultyFactors, getCorruptionRatio } from '@/world/Difficulty';
import { getEnemyDefinition } from '@/data/enemies';
import type { Obstacle } from '@/entities/Obstacle';
import { resolveAgainstWalls, resolveAgainstObstacles, clampToRoom, clampInsideRoom } from '@/world/Physics';
import { generateShopOffers, makeShopRng, REROLL_COST, HEAL_AMOUNT_RATIO, type ShopOffer } from '@/world/Shop';
import { RunState } from '@/progression/RunState';
import { meta } from '@/progression/MetaProgression';
import { rollUpgradeChoices, pickUpgradeAtLeastRarity } from '@/progression/UpgradePool';
import { getUpgrade } from '@/data/upgrades';
import { applyModifiers } from '@/data/stats';
import { createBaseStats, RARITY_ORDER, RARITY_COLORS, type Rarity, type UpgradeDefinition, type UpgradeIconId, type EventOption } from '@/data/types';
import { ZONES } from '@/data/zones';
import { getSynergy } from '@/data/synergies';
import { WORLD_EVENTS, getWorldEvent } from '@/data/events';
import { Random } from '@/utils/Random';
import { clamp, formatNumber, lerp, easeInCubic, easeOutCubic, easeInOutSine } from '@/utils/MathUtils';
import { SpatialGrid } from '@/utils/Collision';
import { HUD, type BossHudInfo } from '@/ui/HUD';
import { MainMenu } from '@/ui/MainMenu';
import { PauseMenu } from '@/ui/PauseMenu';
import { SettingsMenu } from '@/ui/SettingsMenu';
import { MetaProgressionMenu, type MetaMenuMode } from '@/ui/MetaProgressionMenu';
import { UpgradeSelectUI } from '@/ui/UpgradeSelectUI';
import { ShopUI } from '@/ui/ShopUI';
import { EventUI } from '@/ui/EventUI';
import { VictoryScreen, DefeatScreen } from '@/ui/VictoryScreen';
import { TouchControls } from '@/ui/TouchControls';
import { CreditsScreen } from '@/ui/CreditsScreen';
import { RewardPopup } from '@/ui/RewardPopup';
import { LoadoutSelectUI } from '@/ui/LoadoutSelectUI';
import { Onboarding } from '@/ui/Onboarding';
import type { SaveSettings } from '@/progression/SaveSystem';
import { el } from '@/ui/dom';

interface Destroyable {
  destroy(): void;
}

function roomTypeLabel(type: Room['type']): string {
  switch (type) {
    case 'start': return 'Entrance';
    case 'combat': return 'Combat';
    case 'elite': return 'Elite Den';
    case 'chest': return 'Vault';
    case 'shop': return 'Merchant';
    case 'event': return 'Unknown';
    case 'rest': return 'Respite';
    case 'heart': return 'Zone Heart';
    case 'boss': return 'The Colossus';
    case 'sanctum': return 'Drowned Sanctum';
  }
}

/**
 * The scripted walk down (or up) a stairwell between zones. 'out': the player
 * walks into the well while the screen goes to black; the zone switches at
 * the end of it; 'in': the screen comes back up on the new zone while the
 * player steps off the arrival stairs. Input is suspended throughout.
 */
interface ZoneTransition {
  phase: 'out' | 'in';
  t: number;
  duration: number;
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
  stairs: Obstacle;
  sporeTimer: number;
}
const DESCENT_OUT_SECONDS = 1.15;
const DESCENT_IN_SECONDS = 1.35;
/** How long the HUD stamina bar's denial pulse stays visible after a single
 * denied action (dodge). A held M1 re-triggers this every frame it's denied,
 * so it stays lit continuously for as long as the button is held regardless
 * of this value — this constant only matters for one-shot inputs. */
const STAMINA_DENIED_FLASH_SECONDS = 0.35;

function iconForAbility(id: string): UpgradeIconId {
  if (id === 'stormstep') return 'dodge';
  if (id === 'wardingSigil') return 'shield';
  return 'ember';
}

function chestSoundFor(tier: Rarity): SfxId {
  if (tier === 'legendary') return 'chestOpenLegendary';
  if (tier === 'epic') return 'chestOpenEpic';
  if (tier === 'rare') return 'chestOpenRare';
  return 'chestOpenCommon';
}

export class Game {
  private renderer: Renderer;
  private camera = new Camera();
  private input: InputManager;
  private particles = new ParticleSystem(600);
  private lighting = new LightingSystem();
  private hitStop = new HitStopController();
  private combat: CombatSystem;
  private stateMachine = new GameStateMachine();
  private enemyGrid = new SpatialGrid<Enemy>(80, (e) => ({ x: e.x, y: e.y, radius: e.radius }));

  private hud: HUD | null = null;
  private touchControls: TouchControls | null = null;
  private onboarding: Onboarding | null = null;
  private modalScreen: Destroyable | null = null;
  private rewardPopups: RewardPopup[] = [];
  private synergyBannerTimers: number[] = [];

  private player: Player | null = null;
  private run: RunState | null = null;
  private boss: Boss | null = null;
  private bossIntroTimer = 0;
  private transition: ZoneTransition | null = null;

  private lastTime = performance.now();
  private ambientTimer = 0.3;
  private fps = 60;
  /** Counts down from STAMINA_DENIED_FLASH_SECONDS whenever M1 or dodge is
   * blocked purely by insufficient stamina (not by their own cooldown) —
   * read by updateHud() to drive the stamina bar's denial pulse. */
  private staminaDeniedTimer = 0;
  private debugEnabled = false;
  private debugEl: HTMLElement | null = null;
  private audioUnlocked = false;

  constructor(private canvas: HTMLCanvasElement, private uiRoot: HTMLElement) {
    this.renderer = new Renderer(canvas);
    this.input = new InputManager(canvas);
    this.camera.zoom = 1.5;
    this.combat = new CombatSystem(this.particles, this.camera, this.hitStop);
    this.combat.onDamageDealtToEnemy = (amount) => this.run?.recordDamageDealt(amount);
    this.combat.onDamageDealtToPlayer = (amount) => this.run?.recordDamageTaken(amount);

    this.applySettings(meta.data.settings);
    this.bindGlobalHandlers();
    this.bindEventBus();
    this.installDevHooks();
    this.showMainMenu();

    requestAnimationFrame(this.loop);
  }

  /**
   * Dev-server-only automation surface for the Playwright QA harness (room
   * teleports, force-clears, state dumps). Compiled out of production builds
   * entirely — `import.meta.env.DEV` is a build-time constant.
   */
  private installDevHooks(): void {
    if (!import.meta.env.DEV) return;
    const api = {
      state: () => {
        const run = this.run;
        const player = this.player;
        if (!run || !player) return { state: this.stateMachine.current, run: false };
        const room = run.currentRoom;
        return {
          state: this.stateMachine.current,
          run: true,
          zoneIndex: run.zoneIndex,
          zoneId: run.currentZoneDef.id,
          roomKey: room.key,
          roomType: room.type,
          doors: Array.from(room.doors),
          locked: room.locked,
          cleared: room.cleared,
          rewardGranted: room.rewardGranted,
          ritualActive: room.ritualActive,
          ritualWave: room.ritualWave,
          player: {
            x: player.x, y: player.y, hp: player.hp, maxHp: player.stats.maxHp, shield: player.shieldCharges, alive: player.alive,
            stamina: player.stamina, staminaMax: player.stats.staminaMax, weaponStaminaCost: player.weapon.staminaCost,
            energy: player.energy, energyMax: player.stats.energyMax, abilityCooldown: player.ability.cooldown,
            attackCooldownTimer: player.attackCooldownTimer, canAttack: player.canAttack(), canUseAbility: player.canUseAbility(),
            isDodging: player.isDodging, dodgeCooldownTimer: player.dodgeCooldownTimer, canDodge: player.canDodge(),
          },
          enemies: room.enemies.map((e) => ({
            id: e.def.id,
            x: e.x,
            y: e.y,
            hp: e.hp,
            maxHp: e.maxHp,
            alive: e.alive,
            state: e.state,
            facing: e.facing,
            shieldUp: e.shieldUp,
            shieldBroken: e.shieldBroken,
            bashTimer: e.bashTimer,
            exposed: e.exposedTimer,
            elite: e.isEliteInstance,
          })),
          obstacles: room.obstacles.map((o) => ({ visual: o.visual, x: o.x, y: o.y, radius: o.radius, activated: o.activated, facing: o.facing })),
          hazards: this.combat.hazards.map((h) => ({ x: h.x, y: h.y, radius: h.radius, timer: h.timer, duration: h.duration })),
          transition: this.transition ? { phase: this.transition.phase, t: this.transition.t, duration: this.transition.duration } : null,
          modal: !!this.modalScreen,
          embers: run.embers,
          fps: this.fps,
          particles: this.particles.activeCount,
          lights: this.lighting.ambientDarkness,
          interaction: this.getRoomInteraction()?.label ?? null,
        };
      },
      rooms: () => {
        const run = this.run;
        if (!run) return [];
        return Array.from(run.currentLayout.rooms.values()).map((r) => ({
          key: r.key,
          type: r.type,
          doors: Array.from(r.doors),
          distance: r.distanceFromStart,
          visited: r.visited,
          cleared: r.cleared,
        }));
      },
      goto: (key: string) => {
        const run = this.run;
        const player = this.player;
        if (!run || !player) return false;
        const room = run.currentLayout.rooms.get(key);
        if (!room) return false;
        run.currentRoomKey = key;
        const entry = room.doors.values().next().value as Direction | undefined;
        const spawn = entry ? room.spawnPointFrom(entry) : { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 };
        player.x = spawn.x;
        player.y = spawn.y;
        this.enterRoom(room, null);
        this.camera.snapTo(player.x, player.y);
        return true;
      },
      teleport: (x: number, y: number) => {
        if (!this.player) return;
        this.player.x = x;
        this.player.y = y;
        this.player.vx = 0;
        this.player.vy = 0;
      },
      killAll: () => {
        const run = this.run;
        const player = this.player;
        if (!run || !player) return 0;
        let n = 0;
        for (const e of this.allTargetableEnemies()) {
          if (!e.alive) continue;
          if (e instanceof Boss) e.invulnerable = false;
          e.takeDamage(e.hp + 1);
          this.combat.onEnemyDeath(player, e);
          n++;
        }
        return n;
      },
      damage: (enemyId: string, fraction: number) => {
        const player = this.player;
        if (!player) return false;
        const target = this.allTargetableEnemies().find((e) => e.alive && e.def.id === enemyId);
        if (!target) return false;
        target.takeDamage(target.maxHp * fraction);
        if (!target.alive) this.combat.onEnemyDeath(player, target);
        return true;
      },
      setHp: (hp: number) => {
        if (this.player) this.player.hp = Math.min(this.player.stats.maxHp, Math.max(1, hp));
      },
      fps: () => this.fps,
      warpZone: (target: number) => {
        const run = this.run;
        const player = this.player;
        if (!run || !player) return false;
        while (run.zoneIndex < target && !run.isFinalZone()) {
          const next = run.advanceZone();
          if (!next.spawnedContent) populateRoomContent(next, run.currentZoneDef, this.spawnOptions());
        }
        const arrival = run.currentRoom.obstacles.find((o) => o.visual === 'stairsUp');
        const foot = arrival ? stairsFootPosition(arrival) : { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 };
        player.x = foot.x;
        player.y = foot.y;
        this.particles.clear();
        this.combat.reset();
        this.camera.snapTo(player.x, player.y);
        this.syncCombatState();
        this.hud?.refreshMinimap(run);
        music.setMood(run.zoneIndex);
        return true;
      },
      interact: () => {
        const interaction = this.getRoomInteraction();
        if (!interaction) return null;
        interaction.action();
        return interaction.label;
      },
      grantUpgrade: (id: string) => {
        if (!this.player) return false;
        this.grantUpgrade(getUpgrade(id));
        return true;
      },
      addSoulAsh: (amount: number) => {
        meta.addSoulAsh(amount);
        return meta.soulAsh;
      },
      purchasePermanent: (id: string) => meta.purchasePermanent(id),
      getPermanentLevel: (id: string) => meta.getPermanentLevel(id),
    };
    (window as unknown as { __emberfall: typeof api }).__emberfall = api;
  }

  // ------------------------------------------------------------ Bootstrapping
  private bindGlobalHandlers(): void {
    // audio.unlock() is safe to call repeatedly — after the first real init it just
    // resumes a suspended AudioContext (e.g. after the tab was backgrounded), so it
    // must NOT be gated behind a one-shot flag. Only music.start() is one-shot.
    const unlock = () => {
      audio.unlock();
      if (!this.audioUnlocked) {
        this.audioUnlocked = true;
        music.start();
      }
    };
    window.addEventListener('pointerdown', unlock, { once: false });
    window.addEventListener('keydown', unlock, { once: false });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') audio.unlock();
    });
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Backquote') this.toggleDebug();
    });
    window.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  private bindEventBus(): void {
    gameEvents.on('enemyKilled', ({ enemy, x, y, wasElite }) => {
      if (!this.run) return;
      this.run.recordKill(enemy);
      const room = this.run.currentRoom;
      const emberTotal = Math.round(enemy.def.emberValue * (0.85 + Math.random() * 0.3));
      if (emberTotal > 0) {
        const count = Math.min(5, Math.max(1, Math.round(emberTotal / 3)));
        const per = Math.max(1, Math.round(emberTotal / count));
        for (let i = 0; i < count; i++) {
          room.pickups.push(new Pickup('ember', x, y, per));
        }
      }
      const healChance = wasElite ? 0.3 : 0.03;
      if (Math.random() < healChance && this.player) {
        room.pickups.push(new Pickup('heart', x, y, Math.round(this.player.stats.maxHp * 0.15)));
      }
    });
    gameEvents.on('playerDied', () => {
      if (this.run && !this.run.ended) {
        this.run.stats.deaths++;
        this.endRun(false);
      }
    });
    gameEvents.on('bossPhaseChanged', ({ phase }) => {
      this.hud?.showPhaseBanner(`PHASE ${phase}`);
    });
  }

  private applySettings(s: SaveSettings): void {
    audio.setMaster(s.masterVolume);
    audio.setMusic(s.musicVolume);
    audio.setSfx(s.sfxVolume);
    audio.setMuted(s.muted);
    this.particles.setQuality(s.particleQuality);
    this.camera.shakeEnabled = s.screenShake;
    this.hitStop.enabled = s.screenShake;
    document.body.classList.toggle('reduced-motion', s.reducedMotion);
    document.body.classList.toggle('high-contrast', s.highContrast);
    document.documentElement.style.setProperty('--ui-scale', String(s.textScale));
    const scale = s.graphicsQuality === 'low' ? 0.7 : s.graphicsQuality === 'medium' ? 0.85 : 1;
    this.renderer.setQualityScale(scale);
  }

  private persistSettings(s: SaveSettings): void {
    meta.data.settings = s;
    meta.save();
    this.applySettings(s);
  }

  // ------------------------------------------------------------ Menu flow
  private closeModal(): void {
    this.modalScreen?.destroy();
    this.modalScreen = null;
  }

  private showMainMenu(): void {
    this.closeModal();
    this.stateMachine.set(GameState.MAIN_MENU);
    this.modalScreen = new MainMenu(this.uiRoot, {
      onPlay: (seed) => this.startNewRun(seed),
      onUpgrades: () => this.showMetaMenu('upgrades'),
      onArmory: () => this.showMetaMenu('armory'),
      onSettings: () => this.showSettingsStandalone(),
      onCredits: () => this.showCredits(),
    });
  }

  private showMetaMenu(mode: MetaMenuMode): void {
    this.closeModal();
    this.modalScreen = new MetaProgressionMenu(this.uiRoot, mode, { onClose: () => this.showMainMenu() });
  }

  private showSettingsStandalone(): void {
    this.closeModal();
    this.modalScreen = new SettingsMenu(this.uiRoot, meta.data.settings, {
      onClose: () => this.showMainMenu(),
      onChange: (s) => this.persistSettings(s),
    });
  }

  private showCredits(): void {
    this.closeModal();
    this.modalScreen = new CreditsScreen(this.uiRoot, () => this.showMainMenu());
  }

  // ------------------------------------------------------------ Run lifecycle
  private startNewRun(seed?: number): void {
    this.closeModal();
    this.rewardPopups.forEach((p) => p.destroy());
    this.rewardPopups.length = 0;
    this.synergyBannerTimers.forEach((id) => window.clearTimeout(id));
    this.synergyBannerTimers.length = 0;
    this.stateMachine.set(GameState.RUN_START);

    this.run = new RunState(seed);
    const baseStats = applyModifiers(createBaseStats(), meta.getPermanentStatModifiers());
    this.player = new Player(baseStats);
    this.player.reset(ROOM_WIDTH / 2, ROOM_HEIGHT / 2);
    this.boss = null;
    this.transition = null;
    music.setMood(0);

    const startRoom = this.run.currentRoom;
    startRoom.visited = true;
    startRoom.spawnedContent = true;
    this.particles.clear();
    clearRoomTextureCache();
    this.combat.reset();

    this.hud = new HUD(this.uiRoot);
    this.hud.refreshMinimap(this.run);
    if (this.input.mode === 'touch') {
      this.touchControls = new TouchControls(this.uiRoot, this.input, { onPause: () => this.pauseGame() });
    }
    this.onboarding = new Onboarding(this.hud, this.input.mode);

    const weapons = Array.from(new Set(['emberBlade', ...meta.getUnlockedWeaponIds()]));
    const abilities = Array.from(new Set(['emberBurst', ...meta.getUnlockedAbilityIds()]));

    const begin = (weaponId: string, abilityId: string) => {
      this.player!.weaponId = weaponId;
      this.player!.abilityId = abilityId as Player['abilityId'];
      this.closeModal();
      this.stateMachine.set(GameState.EXPLORATION);
      music.setIntensity(0);
      this.onboarding?.show('move');
    };

    if (weapons.length > 1 || abilities.length > 1) {
      this.modalScreen = new LoadoutSelectUI(this.uiRoot, weapons, abilities, { onConfirm: begin });
    } else {
      begin(weapons[0], abilities[0]);
    }
  }

  private endRun(victory: boolean): void {
    const run = this.run;
    const player = this.player;
    if (!run || !player || run.ended) return;
    run.ended = true;

    const formulaAsh = Math.floor(run.stats.kills * 0.6 + run.stats.eliteKills * 4 + (victory ? 70 : 0) + run.embers * 0.08);
    meta.addSoulAsh(formulaAsh);
    run.stats.soulAshEarned += formulaAsh;
    meta.recordRunEnd({
      kills: run.stats.kills,
      died: !victory,
      bossDefeated: victory,
      timeSeconds: run.elapsedSeconds(),
      embersCollected: run.stats.embersCollected,
    });
    this.hud?.destroy();
    this.hud = null;
    this.rewardPopups.forEach((p) => p.destroy());
    this.rewardPopups.length = 0;
    this.synergyBannerTimers.forEach((id) => window.clearTimeout(id));
    this.synergyBannerTimers.length = 0;
    this.touchControls?.destroy();
    this.touchControls = null;
    this.closeModal();
    this.transition = null;
    music.setIntensity(0);
    music.setMood(0);

    this.stateMachine.set(victory ? GameState.VICTORY : GameState.DEFEAT);
    if (victory) {
      this.modalScreen = new VictoryScreen(this.uiRoot, run, run.stats.soulAshEarned, {
        onPrimary: () => this.showMainMenu(),
      });
    } else {
      this.modalScreen = new DefeatScreen(this.uiRoot, run, run.stats.soulAshEarned, {
        onPrimary: () => this.startNewRun(),
        onSecondary: () => this.showMainMenu(),
      });
    }
  }

  private pauseGame(): void {
    if (this.modalScreen) return;
    if (!this.stateMachine.is(GameState.EXPLORATION, GameState.COMBAT, GameState.BOSS)) return;
    this.stateMachine.push(GameState.PAUSED);
    playSfx('uiClick');
    this.modalScreen = new PauseMenu(this.uiRoot, this.player!, meta.data.settings, {
      onResume: () => this.resumeGame(),
      onAbandon: () => {
        this.closeModal();
        this.endRun(false);
      },
      onSettingsChange: (s) => this.persistSettings(s),
    });
  }

  private resumeGame(): void {
    this.closeModal();
    if (this.stateMachine.is(GameState.PAUSED)) this.stateMachine.pop();
  }

  // ------------------------------------------------------------ Room flow
  private allTargetableEnemies(): Enemy[] {
    const room = this.run!.currentRoom;
    return this.boss && room.type === 'boss' ? [...room.enemies, this.boss] : room.enemies;
  }

  private enterRoom(room: Room, fromDir: Direction | null): void {
    const run = this.run!;
    const player = this.player!;
    this.particles.clear();
    this.combat.reset();
    room.visited = true;

    if (room.type === 'boss') {
      if (!room.spawnedContent) {
        room.spawnedContent = true;
        const { hpMult, damageMult } = getDifficultyFactors(2, run.elapsedMinutes());
        this.boss = new Boss(ROOM_WIDTH / 2, ROOM_HEIGHT * 0.32, hpMult, damageMult);
        this.bossIntroTimer = 1.4;
      }
    } else if (!room.spawnedContent) {
      populateRoomContent(room, run.currentZoneDef, {
        unlockedEnemyIds: meta.getUnlockedGateIds(),
        runMinutes: run.elapsedMinutes(),
        rarityLuck: player.stats.rarityLuck,
        runSeed: run.runSeedString,
      });
    }

    if (fromDir) {
      const spawn = room.spawnPointFrom(OPPOSITE[fromDir]);
      player.x = spawn.x;
      player.y = spawn.y;
    }

    // Coming back into an already-cleared heart room: the stairwell stays open.
    if (room.type === 'heart' && room.cleared) this.openStairs(room, false);

    this.syncCombatState();
    this.hud?.refreshMinimap(run);

    if (room.type === 'chest') this.onboarding?.show('chest');
    if (room.type === 'shop') this.onboarding?.show('shop');
    if (room.type === 'boss') this.onboarding?.show('boss');
    if (room.type === 'sanctum') this.onboarding?.show('sanctum');
    if (room.enemies.some((e) => e.alive && e.def.behavior === 'warden')) this.onboarding?.show('warden');
    if (room.enemies.some((e) => e.alive && e.def.behavior === 'bloat')) this.onboarding?.show('bloat');
  }

  private syncCombatState(): void {
    if (!this.stateMachine.is(GameState.EXPLORATION, GameState.COMBAT, GameState.BOSS)) return;
    const room = this.run!.currentRoom;
    if (room.type === 'boss') {
      this.stateMachine.set(GameState.BOSS);
      music.setIntensity(2);
      return;
    }
    // The sanctum rite stays "in combat" between its waves too — the doors are sealed.
    const riteRunning = room.type === 'sanctum' && room.ritualActive && !room.cleared;
    const active = riteRunning || (room.requiresClearing && !room.cleared && room.enemies.some((e) => e.alive));
    if (active) {
      this.stateMachine.set(GameState.COMBAT);
      music.setIntensity(1);
    } else {
      this.stateMachine.set(GameState.EXPLORATION);
      music.setIntensity(0);
    }
  }

  private checkDoorCrossing(): void {
    const run = this.run!;
    const player = this.player!;
    const room = run.currentRoom;
    let dir: Direction | null = null;
    if (player.y < -2 && room.doors.has('N')) dir = 'N';
    else if (player.y > ROOM_HEIGHT + 2 && room.doors.has('S')) dir = 'S';
    else if (player.x < -2 && room.doors.has('W')) dir = 'W';
    else if (player.x > ROOM_WIDTH + 2 && room.doors.has('E')) dir = 'E';
    if (!dir) return;
    const neighbor = run.moveThroughDoor(dir);
    if (neighbor) {
      playSfx('doorOpen');
      this.enterRoom(neighbor, dir);
    } else {
      clampToRoom(player, ROOM_WIDTH, ROOM_HEIGHT);
    }
  }

  // ------------------------------------------------------------ Interactions
  private getRoomInteraction(): { label: string; action: () => void } | null {
    const run = this.run!;
    const player = this.player!;
    const room = run.currentRoom;
    if (this.transition) return null;
    const centerDist = Math.hypot(player.x - ROOM_WIDTH / 2, player.y - ROOM_HEIGHT / 2);
    // Shop/event/rest interactions track their own landmark obstacle's position
    // (like chest already does below), not the room's raw center point — the
    // landmark itself is offset off-center so it doesn't sit on the straight
    // line between opposite doors (see LevelGenerator's landmarkPosition).
    const landmarkDist = (visual: string): number => {
      const o = room.obstacles.find((ob) => ob.visual === visual);
      return o ? Math.hypot(player.x - o.x, player.y - o.y) : Infinity;
    };

    if (room.type === 'chest' && room.chest && room.chest.canInteract) {
      const d = Math.hypot(player.x - room.chest.x, player.y - room.chest.y);
      if (d < 75) return { label: 'Open Chest', action: () => this.openChest(room) };
    }
    if (room.type === 'shop' && landmarkDist('merchantStall') < 110) {
      return { label: 'Browse Wares', action: () => this.openShopRoom(room) };
    }
    if (room.type === 'event' && !room.eventResolved && landmarkDist('shrine') < 110) {
      return { label: 'Investigate', action: () => this.openEvent(room) };
    }
    if (room.type === 'rest' && !room.restUsed && landmarkDist('brazier') < 110) {
      return { label: 'Rest at the Brazier', action: () => this.useRest(room) };
    }
    if (room.type === 'sanctum' && !room.ritualActive && !room.cleared && centerDist < SANCTUM_RING_RADIUS * 0.65) {
      return { label: 'Kneel at the Circle', action: () => this.beginRite(room) };
    }
    if (room.type === 'heart' && room.cleared && !run.isFinalZone()) {
      const nextName = ZONES[run.zoneIndex + 1]?.name ?? 'the next zone';
      const stairs = room.obstacles.find((o) => o.visual === 'stairsDown');
      if (stairs) {
        if (stairs.activated && Math.hypot(player.x - stairs.x, player.y - stairs.y) < stairs.radius + 72) {
          return { label: `Descend to ${nextName}`, action: () => this.beginDescent(stairs) };
        }
      } else if (centerDist < 110) {
        // No stairwell in this room (should never happen) — never strand the run.
        return { label: `Descend to ${nextName}`, action: () => this.advanceZone() };
      }
    }
    return null;
  }

  private openChest(room: Room): void {
    const chest = room.chest;
    if (!chest || !chest.canInteract) return;
    chest.open();
    playSfx(chestSoundFor(chest.tier));
    this.run!.stats.chestsOpened++;
    const player = this.player!;
    const rng = Random.fromString(`${this.run!.seed}:chestreward:${room.key}`);
    const owned = new Set(player.upgrades.map((u) => u.def.id));
    const def = pickUpgradeAtLeastRarity(rng, chest.tier, meta.getUnlockedGateIds(), owned);
    chest.rewardDef = def;
    this.grantUpgrade(def);
    this.run!.recordUpgrade(def.id);
  }

  private openShopRoom(room: Room): void {
    let rerollCount = 0;
    const ownedIds = () => new Set(this.player!.upgrades.map((u) => u.def.id));
    const makeOffers = (): ShopOffer[] =>
      generateShopOffers(makeShopRng(this.run!.runSeedString, room.key, rerollCount), this.player!.stats.rarityLuck, meta.getUnlockedGateIds(), ownedIds());
    const offers = makeOffers();
    this.modalScreen = new ShopUI(this.uiRoot, offers, {
      getEmbers: () => this.run!.embers,
      onBuyUpgrade: (offer) => {
        if (!offer.upgrade || offer.purchased) return false;
        if (!this.run!.spendEmbers(offer.cost)) return false;
        this.grantUpgrade(offer.upgrade);
        this.run!.recordUpgrade(offer.upgrade.id);
        return true;
      },
      onBuyHeal: (offer) => {
        if (offer.purchased) return false;
        if (!this.run!.spendEmbers(offer.cost)) return false;
        this.player!.heal(this.player!.stats.maxHp * HEAL_AMOUNT_RATIO);
        spawnHealSparkle(this.particles, this.player!.x, this.player!.y);
        return true;
      },
      onReroll: () => {
        if (!this.run!.spendEmbers(REROLL_COST)) return [];
        rerollCount++;
        return makeOffers();
      },
      onClose: () => {
        this.modalScreen = null;
      },
    });
  }

  private openEvent(room: Room): void {
    if (room.eventResolved) return;
    if (!room.eventId) {
      const used = this.run!.usedEventIds;
      const zoneId = this.run!.currentZoneDef.id;
      // Zone-bound events only ever appear in their zone, and take priority
      // there while unused — the ruins should feel like they have their own stories.
      const eligible = WORLD_EVENTS.filter((e) => !e.zoneId || e.zoneId === zoneId);
      let available = eligible.filter((e) => !used.has(e.id));
      const zoneOwn = available.filter((e) => e.zoneId === zoneId);
      if (zoneOwn.length > 0) available = zoneOwn;
      if (available.length === 0) available = eligible;
      const rng = Random.fromString(`${this.run!.seed}:event:${room.key}`);
      room.eventId = rng.pick(available).id;
    }
    const def = getWorldEvent(room.eventId);
    this.run!.usedEventIds.add(def.id);
    this.modalScreen = new EventUI(this.uiRoot, def, {
      getEmbers: () => this.run!.embers,
      onChoose: (option) => {
        this.applyEventEffect(option, room);
        room.eventResolved = true;
        room.cleared = true;
        this.modalScreen = null;
      },
    });
  }

  private applyEventEffect(option: EventOption, room: Room): void {
    const player = this.player!;
    const run = this.run!;
    if (option.cost && !run.spendEmbers(option.cost)) {
      playSfx('shopError');
      return;
    }
    switch (option.apply) {
      case 'nothing':
        break;
      case 'gainEmbers':
        run.addEmbers(option.value ?? 0);
        playSfx('pickupEmber');
        break;
      case 'gainHp':
        player.heal(option.value ?? 0);
        spawnHealSparkle(this.particles, player.x, player.y);
        playSfx('pickupHeart');
        break;
      case 'gainRandomUpgrade': {
        const minRarity = RARITY_ORDER[option.value ?? 0] ?? 'common';
        const rng = Random.fromString(`${run.seed}:eventupgrade:${room.key}:${option.id}`);
        const owned = new Set(player.upgrades.map((u) => u.def.id));
        const def = pickUpgradeAtLeastRarity(rng, minRarity, meta.getUnlockedGateIds(), owned);
        this.grantUpgrade(def);
        run.recordUpgrade(def.id);
        this.showReward(def, 'The Merchant');
        break;
      }
      case 'loseHpForRareUpgrade': {
        const loss = player.stats.maxHp * (option.value ?? 0.25);
        player.hp = Math.max(1, player.hp - loss);
        const rng = Random.fromString(`${run.seed}:eventupgrade:${room.key}:${option.id}`);
        const owned = new Set(player.upgrades.map((u) => u.def.id));
        const def = pickUpgradeAtLeastRarity(rng, 'rare', meta.getUnlockedGateIds(), owned);
        this.grantUpgrade(def);
        run.recordUpgrade(def.id);
        this.showReward(def, 'The Dying Flame');
        break;
      }
      case 'gambleEmbers': {
        const win = Math.random() < 0.5;
        if (win) {
          run.addEmbers(run.embers);
          playSfx('levelUp');
        } else {
          const loss = Math.floor(run.embers * 0.5);
          run.embers = Math.max(0, run.embers - loss);
          playSfx('shopError');
        }
        break;
      }
      case 'gainSoulAshNow': {
        const amount = option.value ?? 0;
        meta.addSoulAsh(amount);
        run.stats.soulAshEarned += amount;
        playSfx('pickupSoulAsh');
        break;
      }
      case 'gainShieldCharge': {
        player.shieldCharges += option.value ?? 1;
        playSfx('shieldUp');
        this.hud?.showToast('A Warden’s ward settles over you.');
        break;
      }
      case 'gainMaxHp': {
        const amount = option.value ?? 15;
        player.addBonusModifier({ stat: 'maxHp', mode: 'flat', value: amount });
        player.heal(amount);
        spawnHealSparkle(this.particles, player.x, player.y);
        playSfx('pickupHeart');
        break;
      }
      case 'loseHpForEmbers': {
        player.hp = Math.max(1, player.hp - player.stats.maxHp * 0.15);
        run.addEmbers(option.value ?? 50);
        this.camera.addShake(6, 0.25);
        playSfx('playerHurt');
        playSfx('pickupEmber');
        break;
      }
    }
  }

  private showReward(def: UpgradeDefinition, label: string): void {
    this.rewardPopups.push(new RewardPopup(this.uiRoot, def, label));
  }

  private useRest(room: Room): void {
    if (room.restUsed) return;
    room.restUsed = true;
    room.cleared = true;
    const player = this.player!;
    const healAmount = (player.stats.maxHp - player.hp) * 0.55;
    player.heal(healAmount);
    spawnHealSparkle(this.particles, player.x, player.y);
    playSfx('pickupHeart');
    this.hud?.showToast('The brazier\'s warmth mends your wounds.');
  }

  /** Legacy instant zone change — only reachable if a heart room somehow has no
   * stairwell. The real path is beginDescent → updateTransition → completeDescent. */
  private advanceZone(): void {
    const run = this.run!;
    if (run.isFinalZone()) return;
    const nextRoom = run.advanceZone();
    this.particles.clear();
    this.combat.reset();
    this.player!.x = ROOM_WIDTH / 2;
    this.player!.y = ROOM_HEIGHT / 2;
    nextRoom.spawnedContent = true;
    this.syncCombatState();
    this.hud?.refreshMinimap(run);
    this.hud?.showPhaseBanner(run.currentZoneDef.name.toUpperCase());
    music.setMood(run.zoneIndex);
    playSfx('doorOpen');
  }

  // ------------------------------------------------------------ Stairs & descent
  /** Unseals a heart room's stairwell. `animate` plays the grinding reveal;
   * false just restores an already-open state (re-entering the room). */
  private openStairs(room: Room, animate: boolean): void {
    const stairs = room.obstacles.find((o) => o.visual === 'stairsDown');
    if (!stairs || stairs.activated) return;
    stairs.activated = true;
    stairs.activatedAt = animate ? performance.now() / 1000 : -10;
    if (!animate) return;
    playSfx('sealBreak');
    this.camera.addShake(5, 0.5);
    spawnStoneChips(this.particles, stairs.x, stairs.y, 14);
    for (let i = 0; i < 10; i++) spawnSporeMote(this.particles, stairs.x + (Math.random() - 0.5) * 60, stairs.y + (Math.random() - 0.5) * 40);
    this.hud?.showToast('The seal grinds open. The stairs lead down.');
    this.onboarding?.show('stairs');
  }

  private beginDescent(stairs: Obstacle): void {
    if (this.transition) return;
    const player = this.player!;
    const mouth = stairsMouthPosition(stairs);
    this.transition = {
      phase: 'out',
      t: 0,
      duration: DESCENT_OUT_SECONDS,
      fromX: player.x,
      fromY: player.y,
      toX: mouth.x,
      toY: mouth.y,
      stairs,
      sporeTimer: 0,
    };
    player.moveInputX = 0;
    player.moveInputY = 0;
    player.vx = 0;
    player.vy = 0;
    player.invulnTimer = Math.max(player.invulnTimer, DESCENT_OUT_SECONDS + DESCENT_IN_SECONDS + 0.4);
    playSfx('stairsDescend');
    music.setIntensity(0);
  }

  private updateTransition(dt: number): void {
    const tr = this.transition!;
    const player = this.player!;
    // Keep regen/timers ticking, then take over position and pose.
    player.moveInputX = 0;
    player.moveInputY = 0;
    player.update(dt);
    tr.t += dt;
    const k = clamp(tr.t / tr.duration, 0, 1);
    const walk = tr.phase === 'out' ? easeInOutSine(k) : easeOutCubic(k);
    player.x = lerp(tr.fromX, tr.toX, walk);
    player.y = lerp(tr.fromY, tr.toY, walk);
    player.vx = 0;
    player.vy = 0;
    player.facing = Math.atan2(tr.toY - tr.fromY, tr.toX - tr.fromX);
    player.animState = k < 0.97 ? 'run' : 'idle';
    player.moveCyclePhase += dt * 5.5;

    tr.sporeTimer -= dt;
    if (tr.sporeTimer <= 0) {
      tr.sporeTimer = tr.phase === 'out' ? 0.05 : 0.12;
      const s = tr.stairs;
      spawnSporeMote(this.particles, s.x + (Math.random() - 0.5) * 70, s.y + (Math.random() - 0.5) * 50);
    }

    if (k >= 1) {
      if (tr.phase === 'out') this.completeDescent();
      else {
        this.transition = null;
        player.animState = 'idle';
      }
    }
  }

  /** The zone switch itself, at the bottom of the fade: new layout, player
   * placed in the mouth of the arrival stairwell, camera snapped, then the
   * 'in' half of the transition walks them off it. */
  private completeDescent(): void {
    const run = this.run!;
    const player = this.player!;
    const tr = this.transition!;
    const nextRoom = run.advanceZone();
    const zone = run.currentZoneDef;
    this.particles.clear();
    this.combat.reset();
    this.boss = null;
    if (!nextRoom.spawnedContent) {
      populateRoomContent(nextRoom, zone, {
        unlockedEnemyIds: meta.getUnlockedGateIds(),
        runMinutes: run.elapsedMinutes(),
        rarityLuck: player.stats.rarityLuck,
        runSeed: run.runSeedString,
      });
    }
    const arrival = nextRoom.obstacles.find((o) => o.visual === 'stairsUp') ?? null;
    const mouth = arrival ? stairsMouthPosition(arrival) : { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 };
    const foot = arrival ? stairsFootPosition(arrival) : { x: ROOM_WIDTH / 2, y: ROOM_HEIGHT / 2 + 40 };
    player.x = mouth.x;
    player.y = mouth.y;
    this.camera.snapTo(player.x, player.y);
    this.transition = {
      phase: 'in',
      t: 0,
      duration: DESCENT_IN_SECONDS,
      fromX: mouth.x,
      fromY: mouth.y,
      toX: foot.x,
      toY: foot.y,
      stairs: arrival ?? tr.stairs,
      sporeTimer: 0,
    };
    this.syncCombatState();
    this.hud?.refreshMinimap(run);
    this.hud?.showPhaseBanner(zone.name.toUpperCase());
    const subtitleTimer = window.setTimeout(() => this.hud?.showToast(`<em>${zone.subtitle}</em>`), 1100);
    this.synergyBannerTimers.push(subtitleTimer);
    playSfx('zoneArrive');
    music.setMood(run.zoneIndex);
  }

  // ------------------------------------------------------------ Sanctum rite
  private spawnOptions() {
    const run = this.run!;
    const player = this.player!;
    return {
      unlockedEnemyIds: meta.getUnlockedGateIds(),
      runMinutes: run.elapsedMinutes(),
      rarityLuck: player.stats.rarityLuck,
      runSeed: run.runSeedString,
    };
  }

  private beginRite(room: Room): void {
    if (room.ritualActive || room.cleared) return;
    room.ritualActive = true;
    room.ritualWave = 0;
    room.ritualWaveTimer = 1.1;
    this.hud?.showPhaseBanner('THE RITE BEGINS');
    playSfx('ritualCandle');
    playSfx('doorOpen');
    this.camera.addShake(4, 0.4);
    this.syncCombatState();
  }

  private updateRite(room: Room, dt: number): void {
    if (!room.ritualActive || room.cleared) return;
    if (room.enemies.some((e) => e.alive)) return;
    room.ritualWaveTimer -= dt;
    if (room.ritualWaveTimer > 0) return;
    if (room.ritualWave >= SANCTUM_WAVE_COUNT) {
      this.completeRite(room);
      return;
    }
    const spawned = spawnSanctumWave(room, this.run!.currentZoneDef, room.ritualWave, this.spawnOptions());
    for (const e of spawned) spawnSporeBurstVfx(this.particles, e.x, e.y, 26);
    room.ritualWave++;
    room.ritualWaveTimer = 1.6;
    for (const idx of [(room.ritualWave - 1) * 2, (room.ritualWave - 1) * 2 + 1]) {
      if (idx >= SANCTUM_CANDLE_COUNT) continue;
      const p = sanctumCandlePosition(idx);
      spawnRitualIgnite(this.particles, p.x, p.y);
    }
    playSfx('ritualCandle');
    this.camera.addShake(3, 0.3);
    this.hud?.showPhaseBanner(`WAVE ${room.ritualWave}`);
    this.syncCombatState();
  }

  private completeRite(room: Room): void {
    const player = this.player!;
    const run = this.run!;
    room.cleared = true;
    playSfx('ritualComplete');
    this.hud?.showPhaseBanner('THE RITE IS DONE');
    for (let i = 0; i < SANCTUM_CANDLE_COUNT; i++) {
      const p = sanctumCandlePosition(i);
      spawnRitualIgnite(this.particles, p.x, p.y);
    }
    player.heal(player.stats.maxHp * 0.3);
    spawnHealSparkle(this.particles, player.x, player.y);
    run.addEmbers(35);
    this.hud?.showToast('The sanctum yields what it kept: a rare blessing, and 35 Embers.');
    this.syncCombatState();
    this.grantRoomClearReward(room);
  }

  /** The Sunken Warden's shield shatters at half health: a hard stagger, two
   * bloats crawling out of the flanks, and a faster, dirtier second phase. */
  private onChampionShieldBreak(enemy: Enemy, spawnQueue: Enemy[]): void {
    const run = this.run!;
    playSfx('shieldShatter');
    this.camera.addShake(14, 0.5);
    this.hitStop.trigger(0.08, 0.05);
    spawnStoneChips(this.particles, enemy.x + Math.cos(enemy.facing) * enemy.radius, enemy.y + Math.sin(enemy.facing) * enemy.radius, 26);
    this.hud?.showPhaseBanner('THE SHIELD SHATTERS');
    const { hpMult, damageMult } = getDifficultyFactors(run.zoneIndex, run.elapsedMinutes());
    const def = getEnemyDefinition('blightbloat');
    for (const side of [-1, 1]) {
      const x = clamp(enemy.x + side * 260, WALL_THICKNESS + 50, ROOM_WIDTH - WALL_THICKNESS - 50);
      const y = clamp(enemy.y + side * 40, WALL_THICKNESS + 50, ROOM_HEIGHT - WALL_THICKNESS - 50);
      const add = new Enemy(def, x, y, hpMult * 0.8, damageMult * 0.8);
      spawnQueue.push(add);
      spawnSporeBurstVfx(this.particles, x, y, 30);
    }
  }

  private grantRoomClearReward(room: Room): void {
    if (room.rewardGranted) return;
    room.rewardGranted = true;
    const player = this.player!;
    const run = this.run!;
    const bonusLuck = room.type === 'elite' || room.type === 'heart' ? 0.15 : room.type === 'sanctum' ? 0.3 : 0;
    const minRarity: Rarity = room.type === 'sanctum' ? 'rare' : 'common';
    const luck = clamp(player.stats.rarityLuck + bonusLuck, 0, 1);
    const rng = Random.fromString(`${run.seed}:reward:${room.key}`);
    const owned = new Set(player.upgrades.map((u) => u.def.id));
    const choices = rollUpgradeChoices(rng, 3, luck, meta.getUnlockedGateIds(), owned, minRarity);
    playSfx('roomCleared');
    if (choices.length === 0) {
      if (room.type === 'heart') this.openStairs(room, true);
      return;
    }
    this.onboarding?.show('upgrade');
    this.modalScreen = new UpgradeSelectUI(this.uiRoot, choices, {
      onChoose: (def) => {
        this.chooseUpgrade(def);
        this.modalScreen = null;
        // The way down reveals itself once the blessing is chosen, so the
        // reveal isn't buried under the upgrade screen.
        if (room.type === 'heart') this.openStairs(room, true);
      },
    });
  }

  /** Single funnel for granting an upgrade to the player so newly-formed synergies are always announced, wherever the upgrade came from. */
  private grantUpgrade(def: UpgradeDefinition): void {
    const player = this.player!;
    const newSynergies = player.addUpgrade(def);
    for (let i = 0; i < newSynergies.length; i++) {
      const syn = getSynergy(newSynergies[i]);
      const timer = window.setTimeout(() => {
        this.hud?.showSynergyBanner(syn.name, syn.description);
        playSfx('synergyFormed');
      }, i * 900);
      this.synergyBannerTimers.push(timer);
    }
  }

  private chooseUpgrade(def: UpgradeDefinition): void {
    const player = this.player!;
    this.grantUpgrade(def);
    this.run!.recordUpgrade(def.id);
    gameEvents.emit('upgradeChosen', { upgrade: def });
    spawnLevelUpBurst(this.particles, player.x, player.y);
    playSfx('levelUp');
  }

  // ------------------------------------------------------------ Combat glue
  private resolveEnemyMelee(enemy: Enemy): void {
    const player = this.player!;
    const dist = Math.hypot(player.x - enemy.x, player.y - enemy.y);
    if (dist <= enemy.def.attackRange + player.radius + 10) {
      const dx = (player.x - enemy.x) / Math.max(0.01, dist);
      const dy = (player.y - enemy.y) / Math.max(0.01, dist);
      this.combat.damageEnemyToPlayer(player, enemy.attackDamage, { knockbackDirX: dx, knockbackDirY: dy, knockbackForce: 150 });
    }
  }

  private performAttack(): void {
    const player = this.player!;
    player.startAttack();
    if (player.weapon.kind === 'melee') {
      this.combat.performMeleeAttack(player, this.allTargetableEnemies());
    } else {
      this.combat.fireProjectileWeapon(player);
    }
    this.onboarding?.show('attack');
  }

  private performDodge(): void {
    const player = this.player!;
    const move = this.input.getMoveVector();
    let dx = move.x;
    let dy = move.y;
    const len = Math.hypot(dx, dy);
    if (len < 0.1) {
      dx = Math.cos(player.facing);
      dy = Math.sin(player.facing);
    } else {
      dx /= len;
      dy /= len;
    }
    player.startDodge(dx, dy);
    playSfx('dodge');
    this.onboarding?.show('dodge');
  }

  private performAbility(): void {
    const player = this.player!;
    player.startAbility();
    const targets = this.allTargetableEnemies();
    switch (player.abilityId) {
      case 'emberBurst':
        this.combat.emberBurstAbility(player, targets);
        break;
      case 'stormstep':
        this.performStormstep(player, targets);
        break;
      case 'wardingSigil':
        player.wardingSigilActive = { x: player.x, y: player.y, timer: 0, duration: 5 };
        playSfx('abilityWardingSigil');
        break;
    }
    this.onboarding?.show('ability');
  }

  private performStormstep(player: Player, targets: Enemy[]): void {
    const dist = 230;
    const dx = Math.cos(player.facing);
    const dy = Math.sin(player.facing);
    const hitIds = new Set<number>();
    const steps = 5;
    for (let i = 1; i <= steps; i++) {
      const t = i / steps;
      const px = player.x + dx * dist * t;
      const py = player.y + dy * dist * t;
      for (const enemy of targets) {
        if (!enemy.alive || hitIds.has(enemy.id)) continue;
        if (Math.hypot(px - enemy.x, py - enemy.y) < enemy.radius + 26) {
          hitIds.add(enemy.id);
          const damage = 30 * player.stats.abilityDamageMult * player.stats.emberPower * player.synergyDamageMultiplier;
          this.combat.damagePlayerToEnemy(player, enemy, damage, false, {
            knockbackDirX: dx,
            knockbackDirY: dy,
            knockbackForce: 200,
            isAbility: true,
          });
        }
      }
    }
    player.x += dx * dist;
    player.y += dy * dist;
    player.invulnTimer = Math.max(player.invulnTimer, 0.45);
    playSfx('abilityStormstep');
    this.camera.addShake(6, 0.15);
  }

  // ------------------------------------------------------------ Main loop
  private loop = (time: number): void => {
    const rawDt = Math.min(0.05, (time - this.lastTime) / 1000);
    this.lastTime = time;
    this.fps = this.fps + (1 / Math.max(rawDt, 0.0001) - this.fps) * 0.1;
    const dt = this.hitStop.apply(rawDt);

    this.update(dt);
    this.render();
    this.input.endFrame();
    requestAnimationFrame(this.loop);
  };

  private update(dt: number): void {
    music.update(dt);

    if (this.stateMachine.is(GameState.EXPLORATION, GameState.COMBAT, GameState.BOSS)) {
      if (this.input.wasPressed('pause')) {
        this.pauseGame();
      } else if (!this.modalScreen) {
        this.updatePlaying(dt);
      }
    }
  }

  private updatePlaying(dt: number): void {
    const run = this.run!;
    const player = this.player!;

    if (this.transition) {
      // Scripted stairwell walk: no input, no enemies — the world just breathes.
      this.staminaDeniedTimer = 0;
      this.updateTransition(dt);
      this.camera.setViewport(this.renderer.width, this.renderer.height);
      this.updateCameraZoom();
      this.camera.follow(player.x, player.y, dt);
      this.camera.update(dt);
      this.particles.update(dt);
      this.combat.update(dt);
      this.ambientTimer -= dt;
      if (this.ambientTimer <= 0) {
        this.ambientTimer = 0.12;
        spawnZoneAmbientParticle(this.particles, run.currentZoneDef, this.camera);
      }
      this.updateHud();
      return;
    }

    const room = run.currentRoom;

    if (this.staminaDeniedTimer > 0) this.staminaDeniedTimer -= dt;
    this.handlePlayerInput();
    player.update(dt);

    const walls = room.getWalls(room.locked);
    resolveAgainstWalls(player, walls);
    resolveAgainstObstacles(player, room.obstacles);
    if (!room.locked) this.checkDoorCrossing();
    else clampToRoom(player, ROOM_WIDTH, ROOM_HEIGHT);

    const aiCtx: EnemyAIContext = {
      dt,
      player,
      bounds: room.bounds,
      onMeleeLand: (enemy) => this.resolveEnemyMelee(enemy),
      onRangedFire: (enemy, angle) => this.combat.spawnEnemyProjectile(enemy, angle),
      onBashStart: () => playSfx('wardenBash', { throttleMs: 60 }),
    };
    // Enemies that other enemies spawn mid-loop (the champion's bloats) are
    // queued and appended afterwards, never pushed into the array being walked.
    const spawnQueue: Enemy[] = [];
    for (const enemy of room.enemies) {
      if (!enemy.alive) {
        enemy.update(dt);
        continue;
      }
      const prevState = enemy.state;
      updateEnemyAI(enemy, aiCtx);
      if (isAttackTriggerFrame(enemy, prevState)) resolveAttackTrigger(enemy, aiCtx);
      if (enemy.def.behavior === 'bloat' && enemy.state === 'windup' && prevState !== 'windup') playSfx('bloatSwell', { throttleMs: 120 });
      if (enemy.pendingBurst) this.combat.detonateBloat(player, enemy);
      if (enemy.phaseJustChanged) {
        enemy.phaseJustChanged = false;
        this.onChampionShieldBreak(enemy, spawnQueue);
      }
      enemy.update(dt);
      if (!enemy.alive) this.combat.onEnemyDeath(player, enemy);
      resolveAgainstWalls(enemy, walls);
      resolveAgainstObstacles(enemy, room.obstacles);
      clampInsideRoom(enemy, ROOM_WIDTH, ROOM_HEIGHT, WALL_THICKNESS);
    }
    for (const spawned of spawnQueue) room.enemies.push(spawned);
    applyEnemySeparation(room.enemies, this.enemyGrid);
    this.combat.resolveContactDamage(player, room.enemies);
    this.combat.resolveBashHits(player, room.enemies);
    this.combat.consumePendingClouds(room.enemies);

    if (room.type === 'boss' && this.boss) {
      if (this.bossIntroTimer > 0) {
        this.bossIntroTimer -= dt;
        if (this.bossIntroTimer <= 0 && !this.boss.introDone) this.boss.beginFight();
      }
      this.boss.tick(dt, player, room.bounds);
      if (!this.boss.alive) this.combat.onEnemyDeath(player, this.boss);
      resolveBossPendingActions(this.boss, {
        player,
        room,
        combat: this.combat,
        particles: this.particles,
        camera: this.camera,
        hitStop: this.hitStop,
        runMinutes: run.elapsedMinutes(),
      });
      resolveAgainstWalls(this.boss, walls);
      if (!this.boss.alive && this.boss.deathAnimationDone && !run.stats.bossDefeated) {
        run.stats.bossDefeated = true;
        this.endRun(true);
        return;
      }
    }

    const targets = this.allTargetableEnemies();
    this.combat.updateProjectiles(dt, player, targets, room.obstacles);
    this.combat.resolveProjectileWalls(walls);
    this.combat.updateHazards(dt, player);
    this.combat.update(dt);
    if (player.wardingSigilActive) this.combat.wardingSigilTick(player, targets, dt);

    for (let i = room.pickups.length - 1; i >= 0; i--) {
      const p = room.pickups[i];
      const reached = p.update(dt, player.x, player.y, player.stats.pickupRange);
      if (reached) {
        if (p.kind === 'ember') {
          const gained = Math.max(1, Math.round(p.value * player.stats.emberGainMult));
          run.addEmbers(gained);
          playSfx('pickupEmber', { throttleMs: 40 });
        } else {
          player.heal(p.value);
          playSfx('pickupHeart', { throttleMs: 100 });
        }
        room.pickups.splice(i, 1);
      } else if (!p.alive) {
        room.pickups.splice(i, 1);
      }
    }

    room.chest?.update(dt);
    if (room.chest?.state === 'opened' && room.chest.rewardDef && !room.chest.rewardShown) {
      room.chest.rewardShown = true;
      spawnChestOpenBurst(this.particles, room.chest.x, room.chest.y, RARITY_COLORS[room.chest.tier]);
      this.showReward(room.chest.rewardDef, 'Chest Reward');
    }

    if (room.type === 'sanctum') {
      this.updateRite(room, dt);
    } else if (room.type !== 'boss' && room.requiresClearing && !room.rewardGranted) {
      room.checkCleared();
      if (room.cleared) {
        this.syncCombatState();
        this.grantRoomClearReward(room);
      }
    }

    this.camera.setViewport(this.renderer.width, this.renderer.height);
    this.updateCameraZoom();
    this.camera.follow(player.x, player.y, dt);
    this.camera.update(dt);
    this.particles.update(dt);
    if (player.isDodging) spawnDodgeTrail(this.particles, player.x, player.y, player.facing, Palette.ember4);

    this.ambientTimer -= dt;
    if (this.ambientTimer <= 0) {
      this.ambientTimer = 0.12;
      spawnZoneAmbientParticle(this.particles, run.currentZoneDef, this.camera);
    }

    this.updateHud();
  }

  /** Scales zoom so the room fills the viewport well on any aspect ratio/size, from small phones to ultrawide monitors. */
  private updateCameraZoom(): void {
    const widthRatio = this.renderer.width / ROOM_WIDTH;
    const heightRatio = this.renderer.height / ROOM_HEIGHT;
    const fit = Math.min(widthRatio, heightRatio) * 1.15;
    this.camera.zoom = clamp(fit, 1.2, 1.8);
  }

  private handlePlayerInput(): void {
    const player = this.player!;
    const move = this.input.getMoveVector();
    player.moveInputX = move.x;
    player.moveInputY = move.y;

    const playerScreen = this.camera.worldToScreen(player.x, player.y);
    player.facing = this.input.getAimAngle(playerScreen.x, playerScreen.y);

    if (this.input.isAttackHeld()) {
      if (player.canAttack()) {
        this.performAttack();
      } else if (player.alive && !player.isDodging && player.attackCooldownTimer <= 0 && !player.hasEnoughStamina()) {
        this.staminaDeniedTimer = STAMINA_DENIED_FLASH_SECONDS;
      }
    }
    if (this.input.wasPressed('dodge')) {
      if (player.canDodge()) {
        this.performDodge();
      } else if (player.alive && !player.isDodging && player.dodgeCooldownTimer <= 0 && !player.hasEnoughStaminaForDodge()) {
        this.staminaDeniedTimer = STAMINA_DENIED_FLASH_SECONDS;
      }
    }
    if (this.input.wasPressed('ability') && player.canUseAbility()) this.performAbility();
    if (this.input.wasPressed('interact')) {
      const interaction = this.getRoomInteraction();
      if (interaction) {
        playSfx('interact');
        interaction.action();
        this.onboarding?.show('interact');
      }
    }

    if (move.lengthSq() > 0.02) this.onboarding?.show('move');
  }

  private updateHud(): void {
    if (!this.hud || !this.run || !this.player) return;
    const run = this.run;
    const player = this.player;
    const room = run.currentRoom;
    const interaction = this.getRoomInteraction();

    let bossInfo: BossHudInfo | null = null;
    if (room.type === 'boss' && this.boss) {
      bossInfo = {
        name: this.boss.def.name,
        hpRatio: this.boss.hp / this.boss.maxHp,
        phase: this.boss.phase,
        maxPhase: 3,
        invulnerable: this.boss.invulnerable,
      };
    } else if (room.type === 'heart') {
      // A heart-room champion gets the boss bar: it's the zone's real conclusion.
      const champion = room.enemies.find((e) => e.def.champion && e.isEliteInstance);
      if (champion && (champion.alive || champion.deathTimer < 0.5)) {
        bossInfo = {
          name: champion.displayName ?? champion.def.name,
          hpRatio: champion.hp / champion.maxHp,
          phase: champion.shieldBroken ? 2 : 1,
          maxPhase: 2,
          invulnerable: false,
        };
      }
    }

    this.hud.update({
      player,
      embers: run.embers,
      zoneName: run.currentZoneDef.name,
      roomLabel: roomTypeLabel(room.type),
      corruption: getCorruptionRatio(run.elapsedMinutes()),
      weaponName: player.weapon.name,
      abilityName: player.ability.name,
      abilityIcon: iconForAbility(player.abilityId),
      interactPrompt: interaction?.label ?? null,
      boss: bossInfo,
      elapsedSeconds: run.elapsedSeconds(),
      staminaDenied: this.staminaDeniedTimer > 0,
    });

    if (getCorruptionRatio(run.elapsedMinutes()) > 0.5) this.onboarding?.show('corruption');
  }

  // ------------------------------------------------------------ Rendering
  private registerLights(): void {
    const player = this.player!;
    const room = this.run!.currentRoom;
    const zone = this.run!.currentZoneDef;
    const time = performance.now() / 1000;
    // Each zone sets how deep its dark is; the ruins sit under a lower ceiling.
    this.lighting.ambientDarkness = zone.darkness ?? 0.4;
    const fungal = zone.fungalColor ?? Palette.fungus;
    this.lighting.add(player.x, player.y, 260, Palette.ember4, 1);
    for (const o of room.obstacles) {
      if (!o.lit) continue;
      if (o.visual === 'stairsDown') {
        // Sealed, the well is dark. Open, the ruins' cold light climbs out of it.
        if (!o.activated) continue;
        const reveal = clamp((time - o.activatedAt) / 1.2, 0, 1);
        this.lighting.add(o.x + Math.cos(o.facing) * 22, o.y + Math.sin(o.facing) * 22, 150 * reveal, fungal, 0.6 * reveal);
        continue;
      }
      if (o.visual === 'stairsUp') {
        // The world above, faintly: the one warm light down here that isn't yours.
        this.lighting.add(o.x + Math.cos(o.facing) * 34, o.y + Math.sin(o.facing) * 34, 120, Palette.ember3, 0.35);
        continue;
      }
      const color = o.visual === 'crystal' ? Palette.soul : o.visual === 'fungus' ? fungal : Palette.ember4;
      // The merchant stall's real-photo sprite reads as a considerably
      // larger, more detailed structure than the old procedural stand-in —
      // its own light needs to be sized to actually bathe that footprint,
      // not just the small candle at its center, so the stall reads as a
      // real lit landmark rather than fading into the room's darkness.
      const radius = o.visual === 'merchantStall' ? 175 : o.visual === 'fungus' ? 105 : 120;
      const intensity = o.visual === 'merchantStall' ? 0.85 : o.visual === 'fungus' ? 0.6 : 0.75;
      this.lighting.add(o.x, o.y - 8, radius, color, intensity);
    }
    for (const e of room.enemies) {
      if (!e.alive) continue;
      if (e.def.id === 'flameWisp' || e.def.id === 'emberDevourer' || e.def.id === 'cinderWraith') {
        this.lighting.add(e.x, e.y, 90, e.def.accentColor, 0.7);
      } else if (e.def.behavior === 'bloat') {
        const swell = e.state === 'windup' ? Math.min(1, e.stateTimer / Math.max(0.05, e.def.telegraphTime)) : 0;
        this.lighting.add(e.x, e.y, 60 + swell * 60, fungal, 0.4 + swell * 0.5);
      } else if (e.def.champion) {
        this.lighting.add(e.x, e.y, 110, e.shieldBroken ? fungal : Palette.soul, 0.55);
      }
    }
    for (const h of this.combat.hazards) {
      const fade = Math.min(1, h.timer / 0.3) * Math.min(1, Math.max(0, (h.duration - h.timer) / 0.8));
      this.lighting.add(h.x, h.y, h.radius * 1.15, Palette.fungusDim, 0.4 * fade);
    }
    if (room.type === 'sanctum') {
      const complete = room.cleared && room.ritualActive;
      const lit = sanctumLitCandles(room.ritualActive, room.ritualWave, complete);
      for (let i = 0; i < lit; i++) {
        const p = sanctumCandlePosition(i);
        this.lighting.add(p.x, p.y - 6, 75, complete ? Palette.ember4 : fungal, 0.55);
      }
      if (complete) this.lighting.add(ROOM_WIDTH / 2, ROOM_HEIGHT / 2, 150, Palette.ember3, 0.4);
    }
    if (this.transition) {
      // The well swallows/gives up the light as the player passes through it.
      const tr = this.transition;
      const k = clamp(tr.t / tr.duration, 0, 1);
      const strength = tr.phase === 'out' ? k : 1 - k;
      this.lighting.add(tr.stairs.x, tr.stairs.y, 170 * strength + 40, tr.phase === 'out' ? fungal : Palette.ember3, 0.4 * strength);
    }
    if (this.boss && this.boss.alive) {
      this.lighting.add(this.boss.x, this.boss.y, 220, Palette.ember3, 0.55 + this.boss.rageGlow * 0.4);
    }
    for (const p of this.combat.projectiles) {
      this.lighting.add(p.x, p.y, 55, p.fromPlayer ? Palette.ember5 : Palette.soul, 0.8);
    }
    if (room.chest && room.chest.state === 'opened') {
      this.lighting.add(room.chest.x, room.chest.y, 100, RARITY_COLORS[room.chest.tier], 0.7);
    }
    if (player.wardingSigilActive) {
      this.lighting.add(player.wardingSigilActive.x, player.wardingSigilActive.y, 130, Palette.goldBright, 0.6);
    }
  }

  private render(): void {
    const ctx = this.renderer.ctx;
    if (!this.run || !this.player) {
      this.renderer.clear(Palette.void);
      return;
    }
    const run = this.run;
    const player = this.player;
    const room = run.currentRoom;
    const zone = run.currentZoneDef;
    const time = performance.now() / 1000;

    this.renderer.clear(zone.palette.wall);
    this.camera.setViewport(this.renderer.width, this.renderer.height);
    drawRoomBackground(ctx, room, zone, this.camera, time, player.x, player.y);

    if (room.type === 'sanctum') {
      drawSanctumCircle(ctx, this.camera, time, room.ritualActive, room.ritualWave, room.cleared && room.ritualActive);
    }
    drawHazards(ctx, this.combat.hazards, this.camera, time);

    if (room.type === 'boss' && this.boss && this.boss.phase === 3) {
      for (const meteor of this.boss.meteorTargets) drawMeteorTelegraph(ctx, meteor, this.camera);
    }

    if (room.chest) {
      const s = this.camera.worldToScreen(room.chest.x, room.chest.y);
      drawChest(ctx, room.chest, s.x, s.y);
    }
    for (const p of room.pickups) {
      const s = this.camera.worldToScreen(p.x, p.y);
      drawPickup(ctx, p, s.x, s.y);
    }

    interface Layer {
      y: number;
      draw: () => void;
    }
    const layers: Layer[] = [];
    for (const o of room.obstacles) {
      layers.push({
        y: o.y,
        draw: () => {
          const s = this.camera.worldToScreen(o.x, o.y);
          drawObstacle(ctx, o, s.x, s.y, time);
        },
      });
    }
    for (const e of room.enemies) {
      if (!e.alive && e.deathTimer > 0.5) continue;
      layers.push({
        y: e.y,
        draw: () => {
          const s = this.camera.worldToScreen(e.x, e.y);
          drawEnemy(ctx, e, s.x, s.y);
        },
      });
    }
    const transition = this.transition;
    layers.push({
      // Mid-transition the player sorts just under the stairwell, so the
      // well's own drawing swallows them going down and releases them coming up.
      y: transition ? transition.stairs.y - 0.5 : player.y,
      draw: () => {
        const s = this.camera.worldToScreen(player.x, player.y);
        if (transition) {
          const k = clamp(transition.t / transition.duration, 0, 1);
          const presence = transition.phase === 'out' ? 1 - easeInCubic(k) : easeOutCubic(k);
          const scale = 0.72 + 0.28 * presence;
          ctx.save();
          ctx.globalAlpha = Math.max(0, presence);
          ctx.translate(s.x, s.y);
          ctx.scale(scale, scale);
          drawPlayer(ctx, player, 0, 0);
          ctx.restore();
        } else {
          drawPlayer(ctx, player, s.x, s.y);
        }
      },
    });
    if (room.type === 'boss' && this.boss) {
      const boss = this.boss;
      layers.push({
        y: boss.y,
        draw: () => {
          const s = this.camera.worldToScreen(boss.x, boss.y);
          drawBoss(ctx, boss, s.x, s.y);
        },
      });
    }
    layers.sort((a, b) => a.y - b.y);
    for (const layer of layers) layer.draw();

    for (const proj of this.combat.projectiles) {
      const s = this.camera.worldToScreen(proj.x, proj.y);
      drawProjectile(ctx, proj, s.x, s.y);
    }

    this.particles.render(ctx, this.camera);
    drawDamageNumbers(ctx, this.combat.damageNumbers, this.camera);

    this.registerLights();
    this.lighting.render(ctx, this.camera, this.renderer.width, this.renderer.height);
    drawRoomVignette(ctx, this.renderer.width, this.renderer.height, zone.palette.accent);

    if (this.transition) {
      // Down into black, then back up out of it — held at full dark for the
      // first stretch of the arrival so the zone switch itself is never seen.
      const tr = this.transition;
      const k = clamp(tr.t / tr.duration, 0, 1);
      const alpha = tr.phase === 'out' ? easeInCubic(k) : 1 - easeOutCubic(clamp((k - 0.15) / 0.85, 0, 1));
      if (alpha > 0.002) {
        ctx.fillStyle = `rgba(3,2,6,${alpha.toFixed(3)})`;
        ctx.fillRect(0, 0, this.renderer.width, this.renderer.height);
      }
    }

    if (this.debugEnabled) this.renderDebug();
  }

  private toggleDebug(): void {
    this.debugEnabled = !this.debugEnabled;
    if (this.debugEnabled && !this.debugEl) {
      this.debugEl = el('div', {
        id: 'debug-overlay',
        style:
          'position:absolute;top:6px;left:6px;background:rgba(6,4,8,0.78);color:#8fe08f;font:11px/1.5 monospace;padding:8px 10px;z-index:99999;white-space:pre;pointer-events:none;border-radius:6px;border:1px solid rgba(143,224,143,0.3);',
      });
      this.uiRoot.appendChild(this.debugEl);
    } else if (!this.debugEnabled && this.debugEl) {
      this.debugEl.remove();
      this.debugEl = null;
    }
  }

  private renderDebug(): void {
    if (!this.debugEl || !this.run || !this.player) return;
    const room = this.run.currentRoom;
    const living = room.enemies.filter((e) => e.alive);
    const nearest = living
      .map((e) => ({ e, dist: Math.hypot(e.x - this.player!.x, e.y - this.player!.y) }))
      .sort((a, b) => a.dist - b.dist)[0];
    this.debugEl.textContent = [
      `FPS: ${this.fps.toFixed(0)}`,
      `Seed: ${this.run.seedLabel}`,
      `Zone: ${this.run.currentZoneDef.name} (${this.run.zoneIndex})`,
      `Room: ${room.key} [${room.type}] locked=${room.locked} doors=${Array.from(room.doors).join('')}`,
      `Player: ${this.player.x.toFixed(0)}, ${this.player.y.toFixed(0)} HP=${this.player.hp.toFixed(0)}/${this.player.stats.maxHp.toFixed(0)}`,
      `Enemies: ${living.length}${nearest ? ` nearest=(${nearest.e.x.toFixed(0)},${nearest.e.y.toFixed(0)},d=${nearest.dist.toFixed(0)})` : ''}`,
      this.boss ? `Boss: hp=${this.boss.hp.toFixed(0)}/${this.boss.maxHp.toFixed(0)} phase=${this.boss.phase} state=${this.boss.bossState} pos=(${this.boss.x.toFixed(0)},${this.boss.y.toFixed(0)})` : '',
      `Particles: ${this.particles.activeCount}`,
      `Projectiles: ${this.combat.projectiles.length} Hazards: ${this.combat.hazards.length}`,
      `Obstacles: ${room.obstacles.map((o) => o.visual + (o.activated ? '*' : '')).join(',')}`,
      room.type === 'sanctum' ? `Rite: active=${room.ritualActive} wave=${room.ritualWave}/${SANCTUM_WAVE_COUNT} cleared=${room.cleared}` : '',
      this.transition ? `Transition: ${this.transition.phase} ${(this.transition.t / this.transition.duration).toFixed(2)}` : '',
      `State: ${this.stateMachine.current}`,
    ].join('\n');
  }
}

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
import { clearRoomTextureCache } from '@/rendering/RoomTexture';
import { spawnChestOpenBurst, spawnDodgeTrail, spawnHealSparkle, spawnLevelUpBurst } from '@/rendering/ParticlePresets';
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
import { Room, OPPOSITE, ROOM_WIDTH, ROOM_HEIGHT, type Direction } from '@/world/Room';
import { populateRoomContent } from '@/world/LevelGenerator';
import { getDifficultyFactors, getCorruptionRatio } from '@/world/Difficulty';
import { resolveAgainstWalls, resolveAgainstObstacles, clampToRoom } from '@/world/Physics';
import { generateShopOffers, makeShopRng, REROLL_COST, HEAL_AMOUNT_RATIO, type ShopOffer } from '@/world/Shop';
import { RunState } from '@/progression/RunState';
import { meta } from '@/progression/MetaProgression';
import { rollUpgradeChoices, pickUpgradeAtLeastRarity } from '@/progression/UpgradePool';
import { applyModifiers } from '@/data/stats';
import { createBaseStats, RARITY_ORDER, RARITY_COLORS, type Rarity, type UpgradeDefinition, type UpgradeIconId, type EventOption } from '@/data/types';
import { ZONES } from '@/data/zones';
import { getSynergy } from '@/data/synergies';
import { WORLD_EVENTS, getWorldEvent } from '@/data/events';
import { Random } from '@/utils/Random';
import { clamp, formatNumber } from '@/utils/MathUtils';
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
  }
}

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

  private lastTime = performance.now();
  private ambientTimer = 0.3;
  private fps = 60;
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
    this.showMainMenu();

    requestAnimationFrame(this.loop);
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
    music.setIntensity(0);

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

    this.syncCombatState();
    this.hud?.refreshMinimap(run);

    if (room.type === 'chest') this.onboarding?.show('chest');
    if (room.type === 'shop') this.onboarding?.show('shop');
    if (room.type === 'boss') this.onboarding?.show('boss');
  }

  private syncCombatState(): void {
    if (!this.stateMachine.is(GameState.EXPLORATION, GameState.COMBAT, GameState.BOSS)) return;
    const room = this.run!.currentRoom;
    if (room.type === 'boss') {
      this.stateMachine.set(GameState.BOSS);
      music.setIntensity(2);
      return;
    }
    const active = room.requiresClearing && !room.cleared && room.enemies.some((e) => e.alive);
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
    if (room.type === 'heart' && room.cleared && centerDist < 110 && !run.isFinalZone()) {
      const nextName = ZONES[run.zoneIndex + 1]?.name ?? 'the next zone';
      return { label: `Descend to ${nextName}`, action: () => this.advanceZone() };
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
      let available = WORLD_EVENTS.filter((e) => !used.has(e.id));
      if (available.length === 0) available = WORLD_EVENTS;
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
    playSfx('doorOpen');
  }

  private grantRoomClearReward(room: Room): void {
    if (room.rewardGranted) return;
    room.rewardGranted = true;
    const player = this.player!;
    const run = this.run!;
    const bonusLuck = room.type === 'elite' || room.type === 'heart' ? 0.15 : 0;
    const luck = clamp(player.stats.rarityLuck + bonusLuck, 0, 1);
    const rng = Random.fromString(`${run.seed}:reward:${room.key}`);
    const owned = new Set(player.upgrades.map((u) => u.def.id));
    const choices = rollUpgradeChoices(rng, 3, luck, meta.getUnlockedGateIds(), owned);
    playSfx('roomCleared');
    if (choices.length === 0) return;
    this.onboarding?.show('upgrade');
    this.modalScreen = new UpgradeSelectUI(this.uiRoot, choices, {
      onChoose: (def) => {
        this.chooseUpgrade(def);
        this.modalScreen = null;
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
    const room = run.currentRoom;

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
    };
    for (const enemy of room.enemies) {
      if (!enemy.alive) {
        enemy.update(dt);
        continue;
      }
      const prevState = enemy.state;
      updateEnemyAI(enemy, aiCtx);
      if (isAttackTriggerFrame(enemy, prevState)) resolveAttackTrigger(enemy, aiCtx);
      enemy.update(dt);
      if (!enemy.alive) this.combat.onEnemyDeath(player, enemy);
      resolveAgainstWalls(enemy, walls);
      resolveAgainstObstacles(enemy, room.obstacles);
    }
    applyEnemySeparation(room.enemies, this.enemyGrid);
    this.combat.resolveContactDamage(player, room.enemies);

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

    if (room.type !== 'boss' && room.requiresClearing && !room.rewardGranted) {
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

    if (this.input.isAttackHeld() && player.canAttack()) this.performAttack();
    if (this.input.wasPressed('dodge') && player.canDodge()) this.performDodge();
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
    });

    if (getCorruptionRatio(run.elapsedMinutes()) > 0.5) this.onboarding?.show('corruption');
  }

  // ------------------------------------------------------------ Rendering
  private registerLights(): void {
    const player = this.player!;
    const room = this.run!.currentRoom;
    this.lighting.add(player.x, player.y, 260, Palette.ember4, 1);
    for (const o of room.obstacles) {
      if (o.lit) this.lighting.add(o.x, o.y - 8, 120, o.visual === 'crystal' ? Palette.soul : Palette.ember4, 0.75);
    }
    for (const e of room.enemies) {
      if (e.alive && (e.def.id === 'flameWisp' || e.def.id === 'emberDevourer' || e.def.id === 'cinderWraith')) {
        this.lighting.add(e.x, e.y, 90, e.def.accentColor, 0.7);
      }
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
    layers.push({
      y: player.y,
      draw: () => {
        const s = this.camera.worldToScreen(player.x, player.y);
        drawPlayer(ctx, player, s.x, s.y);
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
      `Projectiles: ${this.combat.projectiles.length}`,
      `State: ${this.stateMachine.current}`,
    ].join('\n');
  }
}

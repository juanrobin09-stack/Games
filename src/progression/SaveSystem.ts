export const SAVE_VERSION = 1;
const SAVE_KEY = 'emberfall.save.v1';

export interface SaveSettings {
  masterVolume: number;
  musicVolume: number;
  sfxVolume: number;
  muted: boolean;
  screenShake: boolean;
  particleQuality: 'low' | 'medium' | 'high';
  graphicsQuality: 'low' | 'medium' | 'high';
  textScale: number;
  highContrast: boolean;
  reducedMotion: boolean;
}

export interface SaveStats {
  totalRuns: number;
  totalKills: number;
  totalDeaths: number;
  bossesDefeated: number;
  bestTimeSeconds: number | null;
  totalEmbersCollected: number;
  totalSoulAshEarned: number;
}

export interface SaveData {
  version: number;
  soulAsh: number;
  permanentLevels: Record<string, number>;
  unlocked: string[];
  settings: SaveSettings;
  stats: SaveStats;
  tutorialSeen: boolean;
  lastSeed: string | null;
}

function defaultSettings(): SaveSettings {
  return {
    masterVolume: 0.8,
    musicVolume: 0.55,
    sfxVolume: 0.9,
    muted: false,
    screenShake: true,
    particleQuality: 'high',
    graphicsQuality: 'high',
    textScale: 1,
    highContrast: false,
    reducedMotion: false,
  };
}

function defaultStats(): SaveStats {
  return {
    totalRuns: 0,
    totalKills: 0,
    totalDeaths: 0,
    bossesDefeated: 0,
    bestTimeSeconds: null,
    totalEmbersCollected: 0,
    totalSoulAshEarned: 0,
  };
}

export function defaultSave(): SaveData {
  return {
    version: SAVE_VERSION,
    soulAsh: 0,
    permanentLevels: {},
    unlocked: ['emberBlade', 'emberBurst'],
    settings: defaultSettings(),
    stats: defaultStats(),
    tutorialSeen: false,
    lastSeed: null,
  };
}

function num(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function bool(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function sanitizeSettings(raw: unknown): SaveSettings {
  const base = defaultSettings();
  if (typeof raw !== 'object' || raw === null) return base;
  const r = raw as Record<string, unknown>;
  const qualities = ['low', 'medium', 'high'];
  return {
    masterVolume: clamp01(num(r.masterVolume, base.masterVolume)),
    musicVolume: clamp01(num(r.musicVolume, base.musicVolume)),
    sfxVolume: clamp01(num(r.sfxVolume, base.sfxVolume)),
    muted: bool(r.muted, base.muted),
    screenShake: bool(r.screenShake, base.screenShake),
    particleQuality: qualities.includes(r.particleQuality as string) ? (r.particleQuality as SaveSettings['particleQuality']) : base.particleQuality,
    graphicsQuality: qualities.includes(r.graphicsQuality as string) ? (r.graphicsQuality as SaveSettings['graphicsQuality']) : base.graphicsQuality,
    textScale: clampRange(num(r.textScale, base.textScale), 0.85, 1.3),
    highContrast: bool(r.highContrast, base.highContrast),
    reducedMotion: bool(r.reducedMotion, base.reducedMotion),
  };
}

function sanitizeStats(raw: unknown): SaveStats {
  const base = defaultStats();
  if (typeof raw !== 'object' || raw === null) return base;
  const r = raw as Record<string, unknown>;
  return {
    totalRuns: Math.max(0, Math.floor(num(r.totalRuns, base.totalRuns))),
    totalKills: Math.max(0, Math.floor(num(r.totalKills, base.totalKills))),
    totalDeaths: Math.max(0, Math.floor(num(r.totalDeaths, base.totalDeaths))),
    bossesDefeated: Math.max(0, Math.floor(num(r.bossesDefeated, base.bossesDefeated))),
    bestTimeSeconds: typeof r.bestTimeSeconds === 'number' ? r.bestTimeSeconds : null,
    totalEmbersCollected: Math.max(0, Math.floor(num(r.totalEmbersCollected, base.totalEmbersCollected))),
    totalSoulAshEarned: Math.max(0, Math.floor(num(r.totalSoulAshEarned, base.totalSoulAshEarned))),
  };
}

function clamp01(v: number): number {
  return Math.min(1, Math.max(0, v));
}
function clampRange(v: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, v));
}

/** Validates and migrates arbitrary parsed JSON into a safe SaveData, never throwing. */
export function migrateSave(raw: unknown): SaveData {
  const base = defaultSave();
  if (typeof raw !== 'object' || raw === null) return base;
  const r = raw as Record<string, unknown>;
  const permanentLevels: Record<string, number> = {};
  if (typeof r.permanentLevels === 'object' && r.permanentLevels !== null) {
    for (const [key, value] of Object.entries(r.permanentLevels as Record<string, unknown>)) {
      if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
        permanentLevels[key] = Math.floor(value);
      }
    }
  }
  const unlocked = Array.isArray(r.unlocked) ? r.unlocked.filter((x): x is string => typeof x === 'string') : base.unlocked;
  return {
    version: SAVE_VERSION,
    soulAsh: Math.max(0, Math.floor(num(r.soulAsh, base.soulAsh))),
    permanentLevels,
    unlocked: unlocked.length > 0 ? Array.from(new Set([...unlocked, 'emberBlade', 'emberBurst'])) : base.unlocked,
    settings: sanitizeSettings(r.settings),
    stats: sanitizeStats(r.stats),
    tutorialSeen: bool(r.tutorialSeen, base.tutorialSeen),
    lastSeed: typeof r.lastSeed === 'string' ? r.lastSeed : null,
  };
}

export function loadSave(): SaveData {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return defaultSave();
    const parsed = JSON.parse(raw);
    return migrateSave(parsed);
  } catch (err) {
    console.warn('[Save] Save data was corrupted or unreadable — resetting to a fresh save.', err);
    const fresh = defaultSave();
    writeSave(fresh);
    return fresh;
  }
}

export function writeSave(data: SaveData): void {
  try {
    localStorage.setItem(SAVE_KEY, JSON.stringify(data));
  } catch (err) {
    console.warn('[Save] Failed to persist save (storage full or unavailable).', err);
  }
}

import { audio } from '@/audio/AudioEngine';

type OscType = OscillatorType;

interface ToneOpts {
  freq: number;
  freqEnd?: number;
  type?: OscType;
  duration: number;
  attack?: number;
  decay?: number;
  volume?: number;
  delay?: number;
  detune?: number;
}

interface NoiseOpts {
  duration: number;
  filterType?: BiquadFilterType;
  freq: number;
  freqEnd?: number;
  Q?: number;
  volume?: number;
  attack?: number;
  delay?: number;
}

export function tone(dest: AudioNode, opts: ToneOpts): void {
  const ctx = audio.context;
  if (!ctx) return;
  const t0 = ctx.currentTime + (opts.delay ?? 0);
  const osc = ctx.createOscillator();
  osc.type = opts.type ?? 'sine';
  osc.frequency.setValueAtTime(opts.freq, t0);
  if (opts.freqEnd !== undefined) {
    osc.frequency.exponentialRampToValueAtTime(Math.max(1, opts.freqEnd), t0 + opts.duration);
  }
  if (opts.detune) osc.detune.setValueAtTime(opts.detune, t0);
  const gain = ctx.createGain();
  const vol = opts.volume ?? 0.5;
  const attack = opts.attack ?? 0.008;
  const decay = opts.decay ?? opts.duration;
  gain.gain.setValueAtTime(0, t0);
  gain.gain.linearRampToValueAtTime(vol, t0 + attack);
  gain.gain.exponentialRampToValueAtTime(0.0008, t0 + attack + decay);
  osc.connect(gain).connect(dest);
  osc.start(t0);
  osc.stop(t0 + attack + decay + 0.05);
  osc.onended = () => {
    osc.disconnect();
    gain.disconnect();
  };
}

export function noise(dest: AudioNode, opts: NoiseOpts): void {
  const ctx = audio.context;
  const buffer = audio.noiseBuffer;
  if (!ctx || !buffer) return;
  const t0 = ctx.currentTime + (opts.delay ?? 0);
  const src = ctx.createBufferSource();
  src.buffer = buffer;
  const filter = ctx.createBiquadFilter();
  filter.type = opts.filterType ?? 'bandpass';
  filter.frequency.setValueAtTime(opts.freq, t0);
  if (opts.freqEnd !== undefined) {
    filter.frequency.exponentialRampToValueAtTime(Math.max(1, opts.freqEnd), t0 + opts.duration);
  }
  filter.Q.value = opts.Q ?? 1;
  const gain = ctx.createGain();
  const vol = opts.volume ?? 0.4;
  const attack = opts.attack ?? 0.004;
  gain.gain.setValueAtTime(0, t0);
  gain.gain.linearRampToValueAtTime(vol, t0 + attack);
  gain.gain.exponentialRampToValueAtTime(0.0008, t0 + opts.duration);
  src.connect(filter).connect(gain).connect(dest);
  src.start(t0);
  src.stop(t0 + opts.duration + 0.05);
  src.onended = () => {
    src.disconnect();
    filter.disconnect();
    gain.disconnect();
  };
}

function sub(dest: AudioNode, opts: ToneOpts): void {
  tone(dest, { ...opts, type: 'sine' });
}

export type SfxId =
  | 'attackSwing'
  | 'attackSwingHeavy'
  | 'attackRanged'
  | 'impactLight'
  | 'impactCrit'
  | 'dodge'
  | 'perfectDodge'
  | 'abilityEmberBurst'
  | 'abilityStormstep'
  | 'abilityWardingSigil'
  | 'synergyFormed'
  | 'pickupEmber'
  | 'pickupSoulAsh'
  | 'pickupHeart'
  | 'chestOpenCommon'
  | 'chestOpenRare'
  | 'chestOpenEpic'
  | 'chestOpenLegendary'
  | 'uiClick'
  | 'uiHover'
  | 'uiBack'
  | 'upgradeChoose'
  | 'levelUp'
  | 'enemyHit'
  | 'enemyDeath'
  | 'eliteDeath'
  | 'bossHit'
  | 'bossPhase'
  | 'bossDeath'
  | 'bossRoar'
  | 'playerHurt'
  | 'playerDeath'
  | 'shopBuy'
  | 'shopError'
  | 'eventChoice'
  | 'doorOpen'
  | 'shieldBreak'
  | 'shieldUp'
  | 'interact'
  | 'roomCleared'
  | 'stairsDescend'
  | 'zoneArrive'
  | 'sealBreak'
  | 'sporeBurst'
  | 'sporeHiss'
  | 'bloatSwell'
  | 'shieldClang'
  | 'wardenBash'
  | 'shieldShatter'
  | 'ritualCandle'
  | 'ritualComplete';

const players: Record<SfxId, () => void> = {
  attackSwing: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.09, filterType: 'highpass', freq: 2200, freqEnd: 900, volume: 0.18, Q: 0.6 });
    tone(d, { freq: 480, freqEnd: 220, type: 'triangle', duration: 0.08, volume: 0.14 });
  },
  attackSwingHeavy: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.16, filterType: 'highpass', freq: 1400, freqEnd: 500, volume: 0.24, Q: 0.5 });
    sub(d, { freq: 160, freqEnd: 70, duration: 0.18, volume: 0.22 });
  },
  attackRanged: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 900, freqEnd: 1500, type: 'sine', duration: 0.1, volume: 0.16 });
    noise(d, { duration: 0.08, filterType: 'highpass', freq: 3000, volume: 0.08 });
  },
  impactLight: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.07, filterType: 'bandpass', freq: 1600, freqEnd: 600, volume: 0.22, Q: 1.2 });
    sub(d, { freq: 140, freqEnd: 60, duration: 0.1, volume: 0.2 });
  },
  impactCrit: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.12, filterType: 'bandpass', freq: 2400, freqEnd: 500, volume: 0.3, Q: 1 });
    tone(d, { freq: 1200, freqEnd: 300, type: 'square', duration: 0.1, volume: 0.14 });
    sub(d, { freq: 180, freqEnd: 50, duration: 0.16, volume: 0.26 });
  },
  dodge: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.18, filterType: 'bandpass', freq: 1800, freqEnd: 300, volume: 0.16, Q: 0.8 });
    tone(d, { freq: 700, freqEnd: 260, type: 'sine', duration: 0.15, volume: 0.1 });
  },
  perfectDodge: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 900, freqEnd: 1500, type: 'sine', duration: 0.12, volume: 0.14 });
    tone(d, { freq: 1500, freqEnd: 2100, type: 'sine', duration: 0.14, volume: 0.09, delay: 0.04 });
    noise(d, { duration: 0.1, filterType: 'highpass', freq: 3000, volume: 0.08 });
  },
  abilityEmberBurst: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.4, filterType: 'lowpass', freq: 4000, freqEnd: 200, volume: 0.35, Q: 0.7 });
    sub(d, { freq: 90, freqEnd: 40, duration: 0.5, volume: 0.4 });
    tone(d, { freq: 1600, freqEnd: 2600, type: 'sine', duration: 0.25, volume: 0.12, delay: 0.02 });
  },
  abilityStormstep: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 300, freqEnd: 1400, type: 'sawtooth', duration: 0.18, volume: 0.14 });
    noise(d, { duration: 0.2, filterType: 'highpass', freq: 2000, volume: 0.18 });
  },
  abilityWardingSigil: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 220, freqEnd: 440, type: 'sine', duration: 0.5, volume: 0.16 });
    tone(d, { freq: 330, freqEnd: 660, type: 'sine', duration: 0.5, volume: 0.1, delay: 0.05 });
  },
  synergyFormed: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 392, type: 'sine', duration: 0.5, volume: 0.14 });
    tone(d, { freq: 587.33, type: 'sine', duration: 0.55, volume: 0.13, delay: 0.09 });
    tone(d, { freq: 784, type: 'triangle', duration: 0.7, volume: 0.12, delay: 0.18 });
    tone(d, { freq: 1568, type: 'sine', duration: 0.5, volume: 0.06, delay: 0.22 });
  },
  pickupEmber: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 920, type: 'sine', duration: 0.09, volume: 0.16 });
    tone(d, { freq: 1380, type: 'sine', duration: 0.12, volume: 0.1, delay: 0.03 });
  },
  pickupSoulAsh: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 500, freqEnd: 850, type: 'triangle', duration: 0.16, volume: 0.16 });
    tone(d, { freq: 750, freqEnd: 1200, type: 'sine', duration: 0.2, volume: 0.1, delay: 0.04 });
  },
  pickupHeart: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 600, freqEnd: 500, type: 'sine', duration: 0.18, volume: 0.16 });
    tone(d, { freq: 900, freqEnd: 750, type: 'sine', duration: 0.22, volume: 0.1, delay: 0.05 });
  },
  chestOpenCommon: () => chestOpen(1),
  chestOpenRare: () => chestOpen(2),
  chestOpenEpic: () => chestOpen(3),
  chestOpenLegendary: () => chestOpen(4),
  uiClick: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 700, freqEnd: 500, type: 'square', duration: 0.05, volume: 0.08 });
  },
  uiHover: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 900, type: 'sine', duration: 0.04, volume: 0.05 });
  },
  uiBack: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 500, freqEnd: 350, type: 'square', duration: 0.06, volume: 0.07 });
  },
  upgradeChoose: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    [0, 0.06, 0.12].forEach((delay, i) => {
      tone(d, { freq: 520 + i * 180, type: 'triangle', duration: 0.18, volume: 0.13, delay });
    });
  },
  levelUp: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    [0, 0.08, 0.16, 0.26].forEach((delay, i) => {
      tone(d, { freq: 440 * Math.pow(1.2599, i), type: 'triangle', duration: 0.3, volume: 0.15, delay });
    });
  },
  enemyHit: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.06, filterType: 'bandpass', freq: 1200, freqEnd: 400, volume: 0.16, Q: 1 });
  },
  enemyDeath: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 340, freqEnd: 60, type: 'sawtooth', duration: 0.3, volume: 0.14 });
    noise(d, { duration: 0.25, filterType: 'lowpass', freq: 1200, freqEnd: 200, volume: 0.14 });
  },
  eliteDeath: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 260, freqEnd: 40, type: 'sawtooth', duration: 0.55, volume: 0.2 });
    noise(d, { duration: 0.5, filterType: 'lowpass', freq: 1800, freqEnd: 150, volume: 0.22 });
    sub(d, { freq: 100, freqEnd: 35, duration: 0.6, volume: 0.2, delay: 0.05 });
  },
  bossHit: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.16, filterType: 'bandpass', freq: 900, freqEnd: 300, volume: 0.28, Q: 0.9 });
    sub(d, { freq: 130, freqEnd: 45, duration: 0.22, volume: 0.3 });
  },
  bossPhase: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 110, freqEnd: 70, type: 'sawtooth', duration: 1.1, volume: 0.28 });
    tone(d, { freq: 165, freqEnd: 90, type: 'sawtooth', duration: 1.0, volume: 0.18, delay: 0.05 });
    noise(d, { duration: 0.8, filterType: 'lowpass', freq: 2000, freqEnd: 300, volume: 0.2 });
  },
  bossDeath: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 200, freqEnd: 30, type: 'sawtooth', duration: 1.6, volume: 0.3 });
    tone(d, { freq: 300, freqEnd: 40, type: 'sawtooth', duration: 1.4, volume: 0.2, delay: 0.08 });
    noise(d, { duration: 1.5, filterType: 'lowpass', freq: 2500, freqEnd: 100, volume: 0.26 });
  },
  bossRoar: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 90, freqEnd: 130, type: 'sawtooth', duration: 0.6, volume: 0.26 });
    noise(d, { duration: 0.5, filterType: 'bandpass', freq: 500, freqEnd: 900, volume: 0.2, Q: 0.6 });
  },
  playerHurt: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 260, freqEnd: 140, type: 'sawtooth', duration: 0.16, volume: 0.2 });
    noise(d, { duration: 0.12, filterType: 'highpass', freq: 1000, volume: 0.15 });
  },
  playerDeath: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 300, freqEnd: 50, type: 'sine', duration: 1.4, volume: 0.22 });
    tone(d, { freq: 200, freqEnd: 35, type: 'sine', duration: 1.6, volume: 0.16, delay: 0.15 });
  },
  shopBuy: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 1100, type: 'sine', duration: 0.07, volume: 0.14 });
    tone(d, { freq: 1500, type: 'sine', duration: 0.1, volume: 0.1, delay: 0.05 });
  },
  shopError: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 220, type: 'square', duration: 0.12, volume: 0.12 });
  },
  eventChoice: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 500, freqEnd: 700, type: 'sine', duration: 0.3, volume: 0.14 });
  },
  doorOpen: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.4, filterType: 'lowpass', freq: 500, freqEnd: 900, volume: 0.14, Q: 0.5 });
  },
  shieldBreak: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.2, filterType: 'highpass', freq: 3500, freqEnd: 1200, volume: 0.22, Q: 0.9 });
    tone(d, { freq: 1800, freqEnd: 400, type: 'triangle', duration: 0.18, volume: 0.12 });
  },
  shieldUp: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 500, freqEnd: 900, type: 'sine', duration: 0.2, volume: 0.14 });
  },
  interact: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 640, type: 'sine', duration: 0.06, volume: 0.1 });
  },
  roomCleared: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 440, type: 'sine', duration: 0.2, volume: 0.1 });
    tone(d, { freq: 660, type: 'sine', duration: 0.3, volume: 0.12, delay: 0.08 });
  },

  // ---- Hollow Ruins / stairwell
  stairsDescend: () => {
    // Four stone footfalls, each a little lower and further away, under a long cold draft.
    const d = audio.sfxDestination;
    if (!d) return;
    [0, 0.28, 0.56, 0.84].forEach((delay, i) => {
      noise(d, { duration: 0.09, filterType: 'bandpass', freq: 720 - i * 90, freqEnd: 280, volume: 0.17 - i * 0.03, Q: 1.4, delay });
      sub(d, { freq: 118 - i * 12, freqEnd: 58, duration: 0.12, volume: 0.15 - i * 0.025, delay });
    });
    noise(d, { duration: 1.7, filterType: 'lowpass', freq: 420, freqEnd: 130, volume: 0.12, attack: 0.35 });
  },
  zoneArrive: () => {
    // Deep reverberant boom of arriving somewhere vast, then a thin cold hiss.
    const d = audio.sfxDestination;
    if (!d) return;
    sub(d, { freq: 70, freqEnd: 32, duration: 1.5, volume: 0.34 });
    tone(d, { freq: 140, freqEnd: 55, type: 'triangle', duration: 1.2, volume: 0.11, delay: 0.02 });
    noise(d, { duration: 1.9, filterType: 'highpass', freq: 2600, freqEnd: 900, volume: 0.07, attack: 0.5 });
  },
  sealBreak: () => {
    // The stairwell's stone lid grinding aside.
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.95, filterType: 'bandpass', freq: 240, freqEnd: 430, volume: 0.21, Q: 2, attack: 0.05 });
    sub(d, { freq: 55, freqEnd: 38, duration: 0.85, volume: 0.22 });
    tone(d, { freq: 1200, freqEnd: 1900, type: 'sine', duration: 0.5, volume: 0.05, delay: 0.55 });
  },
  sporeBurst: () => {
    // Wet pop, then the hiss of spores settling.
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 320, freqEnd: 90, type: 'sine', duration: 0.16, volume: 0.22 });
    noise(d, { duration: 0.12, filterType: 'lowpass', freq: 1500, freqEnd: 300, volume: 0.22 });
    noise(d, { duration: 0.7, filterType: 'bandpass', freq: 3200, freqEnd: 1800, volume: 0.09, Q: 0.8, attack: 0.05 });
  },
  sporeHiss: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.22, filterType: 'bandpass', freq: 2600, freqEnd: 1400, volume: 0.12, Q: 1.1 });
    tone(d, { freq: 220, freqEnd: 160, type: 'triangle', duration: 0.12, volume: 0.06 });
  },
  bloatSwell: () => {
    // A rising, straining tone under the swell — the "get away" cue.
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 90, freqEnd: 260, type: 'sine', duration: 0.8, volume: 0.12, attack: 0.1 });
    noise(d, { duration: 0.8, filterType: 'bandpass', freq: 600, freqEnd: 1600, volume: 0.06, Q: 1.5, attack: 0.2 });
  },
  shieldClang: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    tone(d, { freq: 1500, freqEnd: 900, type: 'square', duration: 0.07, volume: 0.09 });
    noise(d, { duration: 0.09, filterType: 'bandpass', freq: 2800, freqEnd: 1200, volume: 0.16, Q: 2.2 });
    tone(d, { freq: 420, freqEnd: 300, type: 'triangle', duration: 0.12, volume: 0.08 });
  },
  wardenBash: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.22, filterType: 'lowpass', freq: 1800, freqEnd: 400, volume: 0.2 });
    sub(d, { freq: 110, freqEnd: 45, duration: 0.24, volume: 0.24 });
  },
  shieldShatter: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.5, filterType: 'highpass', freq: 1800, freqEnd: 500, volume: 0.28, Q: 0.8 });
    tone(d, { freq: 900, freqEnd: 180, type: 'square', duration: 0.3, volume: 0.1 });
    sub(d, { freq: 90, freqEnd: 35, duration: 0.6, volume: 0.28 });
    [0.08, 0.16, 0.27].forEach((delay) => {
      noise(d, { duration: 0.06, filterType: 'bandpass', freq: 1400, volume: 0.1, Q: 2, delay });
    });
  },
  ritualCandle: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    noise(d, { duration: 0.25, filterType: 'bandpass', freq: 1200, freqEnd: 2600, volume: 0.1, Q: 1 });
    tone(d, { freq: 660, type: 'sine', duration: 0.6, volume: 0.09, attack: 0.02 });
    tone(d, { freq: 990, type: 'sine', duration: 0.7, volume: 0.05, delay: 0.05 });
  },
  ritualComplete: () => {
    const d = audio.sfxDestination;
    if (!d) return;
    [330, 440, 554.37, 659.25].forEach((freq, i) => {
      tone(d, { freq, type: 'triangle', duration: 0.9, volume: 0.12, delay: i * 0.12 });
    });
    sub(d, { freq: 82, freqEnd: 60, duration: 1.2, volume: 0.18 });
  },
};

function chestOpen(tier: number): void {
  const d = audio.sfxDestination;
  if (!d) return;
  noise(d, { duration: 0.3, filterType: 'lowpass', freq: 700, freqEnd: 1200, volume: 0.16, Q: 0.6 });
  const notes = [523, 659, 784, 988];
  for (let i = 0; i < tier + 1 && i < notes.length; i++) {
    tone(d, { freq: notes[i], type: 'triangle', duration: 0.28, volume: 0.12, delay: i * 0.07 });
  }
}

let lastPlay: Partial<Record<SfxId, number>> = {};

export function playSfx(id: SfxId, opts?: { throttleMs?: number }): void {
  if (!audio.isReady) return;
  const throttle = opts?.throttleMs ?? 25;
  const now = performance.now();
  const last = lastPlay[id] ?? 0;
  if (now - last < throttle) return;
  lastPlay[id] = now;
  try {
    players[id]();
  } catch (err) {
    console.warn('[Audio] failed to play', id, err);
  }
}

export function resetSfxThrottle(): void {
  lastPlay = {};
}

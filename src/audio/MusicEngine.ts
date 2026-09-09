import { audio } from '@/audio/AudioEngine';
import { tone, noise } from '@/audio/SoundFactory';

export type MusicIntensity = 0 | 1 | 2;

interface Chord {
  root: number;
  fifth: number;
}

const CHORDS: Chord[] = [
  { root: 110.0, fifth: 164.81 },
  { root: 87.31, fifth: 130.81 },
  { root: 130.81, fifth: 196.0 },
  { root: 98.0, fifth: 146.83 },
];
/** The Hollow Ruins' set: a semitone down, and one chord carries a lowered
 * fifth (a tritone) so the drone never quite settles — colder, unresolved. */
const RUINS_CHORDS: Chord[] = [
  { root: 103.83, fifth: 155.56 },
  { root: 82.41, fifth: 116.54 },
  { root: 116.54, fifth: 174.61 },
  { root: 92.5, fifth: 138.59 },
];
const CHORD_SETS: Chord[][] = [CHORDS, RUINS_CHORDS, CHORDS];
const CHORD_DURATION = 7;

const PLUCK_SCALE = [220.0, 246.94, 261.63, 293.66, 329.63, 349.23, 392.0, 440.0];
/** G# natural minor for the ruins — same sparse plucks, darker ground. */
const RUINS_PLUCK_SCALE = [207.65, 233.08, 246.94, 277.18, 311.13, 329.63, 369.99, 415.3];
const PLUCK_SCALES: number[][] = [PLUCK_SCALE, RUINS_PLUCK_SCALE, PLUCK_SCALE];

/**
 * Fully procedural, self-looping ambient score. A continuous detuned drone
 * glides between chords; sparse "ember chime" plucks and a low tension pulse
 * layer fade in during combat/boss states. No audio files, no setInterval —
 * advanced purely from the main loop's delta time so it always cleans up
 * with the rest of the game.
 */
export class MusicEngine {
  private started = false;
  private droneOscA: OscillatorNode | null = null;
  private droneOscB: OscillatorNode | null = null;
  private droneSub: OscillatorNode | null = null;
  private droneFilter: BiquadFilterNode | null = null;
  private droneGain: GainNode | null = null;
  private tensionGain: GainNode | null = null;
  private ambienceGain: GainNode | null = null;

  private intensity: MusicIntensity = 0;
  /** Which zone's chord set / pluck scale / ambience is playing (0 = Ashen Woods). */
  private mood = 0;
  private chordTimer = 0;
  private chordIndex = 0;
  private pluckTimer = 2;
  private pulseTimer = 0;
  private dripTimer = 3;
  private lfoPhase = 0;

  start(): void {
    const ctx = audio.context;
    const dest = audio.musicDestination;
    if (!ctx || !dest || this.started) return;
    this.started = true;

    const chord = CHORDS[0];
    this.droneFilter = ctx.createBiquadFilter();
    this.droneFilter.type = 'lowpass';
    this.droneFilter.frequency.value = 900;
    this.droneFilter.Q.value = 0.4;

    this.droneGain = ctx.createGain();
    this.droneGain.gain.value = 0.22;
    this.droneFilter.connect(this.droneGain).connect(dest);

    this.droneOscA = ctx.createOscillator();
    this.droneOscA.type = 'sawtooth';
    this.droneOscA.frequency.value = chord.root;
    this.droneOscA.detune.value = -6;

    this.droneOscB = ctx.createOscillator();
    this.droneOscB.type = 'sawtooth';
    this.droneOscB.frequency.value = chord.fifth;
    this.droneOscB.detune.value = 5;

    this.droneSub = ctx.createOscillator();
    this.droneSub.type = 'sine';
    this.droneSub.frequency.value = chord.root / 2;

    const oscGainA = ctx.createGain();
    oscGainA.gain.value = 0.5;
    const oscGainB = ctx.createGain();
    oscGainB.gain.value = 0.32;
    const oscGainSub = ctx.createGain();
    oscGainSub.gain.value = 0.55;

    this.droneOscA.connect(oscGainA).connect(this.droneFilter);
    this.droneOscB.connect(oscGainB).connect(this.droneFilter);
    this.droneSub.connect(oscGainSub).connect(this.droneFilter);

    this.droneOscA.start();
    this.droneOscB.start();
    this.droneSub.start();

    this.tensionGain = ctx.createGain();
    this.tensionGain.gain.value = 0;
    this.tensionGain.connect(dest);

    // Zone ambience that plays regardless of combat intensity (the ruins' water drips).
    this.ambienceGain = ctx.createGain();
    this.ambienceGain.gain.value = 0.3;
    this.ambienceGain.connect(dest);
  }

  setIntensity(level: MusicIntensity): void {
    this.intensity = level;
  }

  /** Switches the score to a zone's harmonic set. The drone glides to the new
   * set's current chord over a couple of seconds rather than cutting. */
  setMood(zoneIndex: number): void {
    const next = Math.max(0, Math.min(CHORD_SETS.length - 1, zoneIndex));
    if (next === this.mood) return;
    this.mood = next;
    this.chordIndex = 0;
    this.chordTimer = 0;
    const ctx = audio.context;
    if (!ctx || !this.started) return;
    const chord = CHORD_SETS[this.mood][0];
    const t = ctx.currentTime;
    this.droneOscA?.frequency.setTargetAtTime(chord.root, t, 1.6);
    this.droneOscB?.frequency.setTargetAtTime(chord.fifth, t, 1.6);
    this.droneSub?.frequency.setTargetAtTime(chord.root / 2, t, 1.6);
  }

  update(dt: number): void {
    if (!this.started || !audio.context) return;
    const ctx = audio.context;
    const t = ctx.currentTime;
    const chords = CHORD_SETS[this.mood];
    const scale = PLUCK_SCALES[this.mood];

    this.lfoPhase += dt;
    if (this.droneFilter) {
      // The ruins sit under a lower ceiling: the drone is filtered darker there.
      const moodCut = this.mood === 1 ? -140 : 0;
      const targetCut = 700 + moodCut + this.intensity * 350 + Math.sin(this.lfoPhase * 0.15) * 180;
      this.droneFilter.frequency.setTargetAtTime(targetCut, t, 0.6);
    }
    if (this.tensionGain) {
      const targetTension = this.intensity >= 1 ? (this.intensity === 2 ? 0.16 : 0.09) : 0;
      this.tensionGain.gain.setTargetAtTime(targetTension, t, 1.2);
    }

    this.chordTimer += dt;
    if (this.chordTimer >= CHORD_DURATION) {
      this.chordTimer = 0;
      this.chordIndex = (this.chordIndex + 1) % chords.length;
      const chord = chords[this.chordIndex];
      this.droneOscA?.frequency.setTargetAtTime(chord.root, t, 2.2);
      this.droneOscB?.frequency.setTargetAtTime(chord.fifth, t, 2.2);
      this.droneSub?.frequency.setTargetAtTime(chord.root / 2, t, 2.2);
    }

    if (this.mood === 1 && this.ambienceGain) {
      // Water dripping somewhere in the dark: a tiny bright blip at irregular intervals.
      this.dripTimer -= dt;
      if (this.dripTimer <= 0) {
        this.dripTimer = 2.2 + Math.random() * 4.5;
        const freq = 1500 + Math.random() * 900;
        tone(this.ambienceGain, { freq, freqEnd: freq * 0.7, type: 'sine', duration: 0.09, attack: 0.003, volume: 0.35 });
        if (Math.random() < 0.4) {
          tone(this.ambienceGain, { freq: freq * 1.18, freqEnd: freq * 0.8, type: 'sine', duration: 0.07, attack: 0.003, volume: 0.2, delay: 0.16 + Math.random() * 0.2 });
        }
      }
    }

    this.pluckTimer -= dt;
    if (this.pluckTimer <= 0) {
      const baseInterval = this.intensity === 2 ? 1.6 : this.intensity === 1 ? 2.4 : 3.6;
      // Sparser in the ruins — more silence between notes, more room for the drips.
      this.pluckTimer = baseInterval * (this.mood === 1 ? 1.35 : 1) + Math.random() * 2.5;
      if (Math.random() < 0.85 && this.tensionGain) {
        const note = scale[Math.floor(Math.random() * scale.length)];
        tone(this.tensionGain, {
          freq: note,
          type: 'sine',
          duration: 1.4,
          attack: 0.05,
          decay: 1.3,
          volume: 0.5,
        });
      }
    }

    if (this.intensity === 2) {
      this.pulseTimer -= dt;
      if (this.pulseTimer <= 0) {
        this.pulseTimer = 0.85;
        if (this.tensionGain) {
          noise(this.tensionGain, {
            duration: 0.3,
            filterType: 'lowpass',
            freq: 220,
            volume: 0.4,
          });
        }
      }
    }
  }

  stop(): void {
    if (!this.started) return;
    const ctx = audio.context;
    const t = ctx ? ctx.currentTime : 0;
    [this.droneOscA, this.droneOscB, this.droneSub].forEach((osc) => {
      if (!osc) return;
      try {
        osc.stop(t + 0.6);
      } catch {
        /* already stopped */
      }
    });
    this.droneGain?.gain.setTargetAtTime(0, t, 0.2);
    this.tensionGain?.gain.setTargetAtTime(0, t, 0.2);
    this.ambienceGain?.gain.setTargetAtTime(0, t, 0.2);
    this.started = false;
  }
}

export const music = new MusicEngine();

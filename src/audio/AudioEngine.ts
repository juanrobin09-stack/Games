export interface AudioSettings {
  master: number;
  music: number;
  sfx: number;
  muted: boolean;
}

/**
 * Owns the single AudioContext, master/music/sfx buses and the shared noise
 * buffer used by procedural SFX. Everything is synthesized at runtime —
 * there are no audio files anywhere in this project.
 */
export class AudioEngine {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private musicGain: GainNode | null = null;
  private sfxGain: GainNode | null = null;
  private limiter: DynamicsCompressorNode | null = null;
  private _noiseBuffer: AudioBuffer | null = null;
  private unlocked = false;

  settings: AudioSettings = { master: 0.8, music: 0.55, sfx: 0.9, muted: false };

  get context(): AudioContext | null {
    return this.ctx;
  }

  get sfxDestination(): GainNode | null {
    return this.sfxGain;
  }

  get musicDestination(): GainNode | null {
    return this.musicGain;
  }

  get noiseBuffer(): AudioBuffer | null {
    return this._noiseBuffer;
  }

  get now(): number {
    return this.ctx ? this.ctx.currentTime : 0;
  }

  get isReady(): boolean {
    return this.ctx !== null && this.ctx.state === 'running';
  }

  /** Must be called from within a user gesture handler (click/keydown/touch). */
  unlock(): void {
    if (this.unlocked) {
      if (this.ctx && this.ctx.state === 'suspended') void this.ctx.resume();
      return;
    }
    try {
      const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      this.ctx = new Ctx();
      this.masterGain = this.ctx.createGain();
      this.musicGain = this.ctx.createGain();
      this.sfxGain = this.ctx.createGain();
      // Every SFX/music voice shares this bus with no per-voice ducking, so a
      // pile-up of simultaneous hits (multi-target cleave, elite death, boss
      // adds) can sum past 0dB and hard-clip at the destination. A brickwall
      // limiter on the final bus catches that without coloring normal levels.
      this.limiter = this.ctx.createDynamicsCompressor();
      this.limiter.threshold.setValueAtTime(-6, this.ctx.currentTime);
      this.limiter.knee.setValueAtTime(0, this.ctx.currentTime);
      this.limiter.ratio.setValueAtTime(20, this.ctx.currentTime);
      this.limiter.attack.setValueAtTime(0.003, this.ctx.currentTime);
      this.limiter.release.setValueAtTime(0.25, this.ctx.currentTime);
      this.musicGain.connect(this.masterGain);
      this.sfxGain.connect(this.masterGain);
      this.masterGain.connect(this.limiter);
      this.limiter.connect(this.ctx.destination);
      this._noiseBuffer = this.buildNoiseBuffer(this.ctx);
      this.applySettings();
      void this.ctx.resume();
      this.unlocked = true;
    } catch (err) {
      console.warn('[Audio] Web Audio unavailable — will retry on the next user gesture.', err);
    }
  }

  private buildNoiseBuffer(ctx: AudioContext): AudioBuffer {
    const duration = 2;
    const buffer = ctx.createBuffer(1, ctx.sampleRate * duration, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    return buffer;
  }

  createNoiseSource(): AudioBufferSourceNode | null {
    if (!this.ctx || !this._noiseBuffer) return null;
    const src = this.ctx.createBufferSource();
    src.buffer = this._noiseBuffer;
    src.loop = true;
    return src;
  }

  setMaster(v: number): void {
    this.settings.master = v;
    this.applySettings();
  }
  setMusic(v: number): void {
    this.settings.music = v;
    this.applySettings();
  }
  setSfx(v: number): void {
    this.settings.sfx = v;
    this.applySettings();
  }
  setMuted(muted: boolean): void {
    this.settings.muted = muted;
    this.applySettings();
  }

  private applySettings(): void {
    if (!this.masterGain || !this.musicGain || !this.sfxGain || !this.ctx) return;
    const t = this.ctx.currentTime;
    const masterTarget = this.settings.muted ? 0 : this.settings.master;
    this.masterGain.gain.setTargetAtTime(masterTarget, t, 0.05);
    this.musicGain.gain.setTargetAtTime(this.settings.music, t, 0.05);
    this.sfxGain.gain.setTargetAtTime(this.settings.sfx, t, 0.05);
  }
}

export const audio = new AudioEngine();

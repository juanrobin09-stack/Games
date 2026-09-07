/**
 * Brief, real-time-duration slowdown applied to the simulation on high-impact
 * hits (crits, ability casts, boss beats) — the classic "hit-stop"/"hitlag"
 * trick that makes attacks feel weighty without a jarring full freeze.
 * Strength is a fraction of normal speed (e.g. 0.06 = simulation crawls at 6%
 * speed); a longer or stronger request never gets cut short by a smaller one
 * requested while it's still active.
 */
export class HitStopController {
  private timer = 0;
  private strength = 1;
  enabled = true;

  trigger(durationSeconds: number, strength: number): void {
    if (!this.enabled || durationSeconds <= this.timer) return;
    this.timer = durationSeconds;
    this.strength = strength;
  }

  /** Call once per frame with the real (unscaled) delta time; returns the delta to actually simulate with. */
  apply(rawDt: number): number {
    if (this.timer <= 0) return rawDt;
    this.timer -= rawDt;
    return rawDt * this.strength;
  }
}

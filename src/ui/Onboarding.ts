import type { HUD } from '@/ui/HUD';
import type { InputMode } from '@/core/Input';
import { meta } from '@/progression/MetaProgression';

const HINTS_DESKTOP: Record<string, string> = {
  move: 'Use <strong>WASD</strong> to move — aim with your mouse.',
  attack: '<strong>Left Click</strong> to strike with your weapon.',
  ability: '<strong>Right Click</strong> unleashes Ember Burst when charged.',
  dodge: '<strong>Space</strong> to dodge. Briefly invulnerable — time it well.',
  interact: 'Press <strong>E</strong> to open, take, or trigger nearby things.',
};

const HINTS_TOUCH: Record<string, string> = {
  move: 'Drag the left stick to move — your Warden aims where you walk.',
  attack: 'Tap the <strong>blade</strong> button to strike with your weapon.',
  ability: 'Tap the <strong>ember</strong> button to unleash Ember Burst when charged.',
  dodge: 'Tap the <strong>dodge</strong> button. Briefly invulnerable — time it well.',
  interact: 'Tap the <strong>E</strong> button to open, take, or trigger nearby things.',
};

const HINTS_SHARED: Record<string, string> = {
  upgrade: 'Choose one blessing — you can only take one per offer.',
  chest: 'Chests hold a guaranteed upgrade. Rarer chests, better odds.',
  shop: 'Spend Embers here on upgrades, healing, or a reroll.',
  corruption: 'The longer a zone drags on, the stronger the dark grows. Keep moving.',
  boss: 'Watch for the red glow before an attack lands — that is your window to dodge.',
};

/** Shows each contextual hint once, ever, across every run — persisted in the save
 * file so a hint tied to a room type the player hasn't reached yet (chest/shop/boss)
 * still appears the first time they actually encounter it, even in a later run. */
export class Onboarding {
  constructor(private hud: HUD, private mode: InputMode = 'desktop') {}

  show(key: string): void {
    if (meta.hasSeenHint(key)) return;
    meta.markHintSeen(key);
    const modeHints = this.mode === 'touch' ? HINTS_TOUCH : HINTS_DESKTOP;
    const text = modeHints[key] ?? HINTS_SHARED[key];
    if (text) this.hud.showToast(text);
  }
}

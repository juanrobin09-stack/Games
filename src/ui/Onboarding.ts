import type { HUD } from '@/ui/HUD';
import type { InputMode } from '@/core/Input';
import { meta } from '@/progression/MetaProgression';
import { t } from '@/i18n';

function hintsDesktop(): Record<string, string> {
  return {
    move: t('hint.desktop.move', 'Use <strong>WASD</strong> to move — aim with your mouse.'),
    attack: t('hint.desktop.attack', '<strong>Left Click</strong> to strike with your weapon.'),
    ability: t('hint.desktop.ability', '<strong>Right Click</strong> unleashes Ember Burst when charged.'),
    dodge: t('hint.desktop.dodge', '<strong>Space</strong> to dodge. Briefly invulnerable — time it well.'),
    interact: t('hint.desktop.interact', 'Press <strong>E</strong> to open, take, or trigger nearby things.'),
  };
}

function hintsTouch(): Record<string, string> {
  return {
    move: t('hint.touch.move', 'Drag the left stick to move — your Warden aims where you walk.'),
    attack: t('hint.touch.attack', 'Tap the <strong>blade</strong> button to strike with your weapon.'),
    ability: t('hint.touch.ability', 'Tap the <strong>ember</strong> button to unleash Ember Burst when charged.'),
    dodge: t('hint.touch.dodge', 'Tap the <strong>dodge</strong> button. Briefly invulnerable — time it well.'),
    interact: t('hint.touch.interact', 'Tap the <strong>E</strong> button to open, take, or trigger nearby things.'),
  };
}

function hintsShared(): Record<string, string> {
  return {
    upgrade: t('hint.shared.upgrade', 'Choose one blessing — you can only take one per offer.'),
    chest: t('hint.shared.chest', 'Chests hold a guaranteed upgrade. Rarer chests, better odds.'),
    shop: t('hint.shared.shop', 'Spend Embers here on upgrades, healing, or a reroll.'),
    corruption: t('hint.shared.corruption', 'The longer a zone drags on, the stronger the dark grows. Keep moving.'),
    boss: t('hint.shared.boss', 'Watch for the red glow before an attack lands — that is your window to dodge.'),
    stairs: t('hint.shared.stairs', 'The way down is open. There is no way back up.'),
    warden: t('hint.shared.warden', 'A Warden’s shield turns aside blows from the front. Circle it — or strike when its guard drops after a bash.'),
    bloat: t('hint.shared.bloat', 'Blightbloats burst. Back away when one swells, and stay out of the spores it leaves.'),
    sanctum: t('hint.shared.sanctum', 'A rite sleeps here. Kneel at the circle to wake it — the doors will seal until every wave is down.'),
  };
}

/** Shows each contextual hint once, ever, across every run — persisted in the save
 * file so a hint tied to a room type the player hasn't reached yet (chest/shop/boss)
 * still appears the first time they actually encounter it, even in a later run. */
export class Onboarding {
  constructor(private hud: HUD, private mode: InputMode = 'desktop') {}

  show(key: string): void {
    if (meta.hasSeenHint(key)) return;
    meta.markHintSeen(key);
    const modeHints = this.mode === 'touch' ? hintsTouch() : hintsDesktop();
    const text = modeHints[key] ?? hintsShared()[key];
    if (text) this.hud.showToast(text);
  }
}

import { el } from '@/ui/dom';
import { formatTime } from '@/utils/MathUtils';
import type { RunState } from '@/progression/RunState';
import { t, tc } from '@/i18n';

export interface EndScreenCallbacks {
  onPrimary: () => void;
  onSecondary?: () => void;
}

function statTile(value: string | number, label: string): HTMLElement {
  return el('div', { class: 'stat-tile' }, [el('div', { class: 'value' }, [String(value)]), el('div', { class: 'label' }, [label])]);
}

export class VictoryScreen {
  root: HTMLElement;

  constructor(container: HTMLElement, run: RunState, soulAshEarned: number, callbacks: EndScreenCallbacks) {
    const time = formatTime(run.elapsedSeconds());
    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, [t('victory.title', 'The Ember Endures')]),
      el('div', { class: 'screen-subtitle' }, [t('victory.subtitle', 'The Ashen Colossus falls. For now, the dark recedes.')]),
      el('div', { class: 'stat-grid' }, [
        statTile(time, t('stat.time', 'Time')),
        statTile(run.stats.kills, t('stat.kills', 'Kills')),
        statTile(Math.round(run.stats.damageDealt), t('stat.damageDealt', 'Damage Dealt')),
        statTile(run.stats.embersCollected, t('stat.embersCollected', 'Embers Collected')),
        statTile(run.stats.upgradesChosen.length, t('stat.upgradesTaken', 'Upgrades Taken')),
        statTile(soulAshEarned, t('stat.soulAshEarned', 'Soul Ash Earned')),
      ]),
      el('div', { class: 'seed-label' }, [`${t('endScreen.seedLabel', 'Seed')}: ${run.seedLabel}`]),
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: callbacks.onPrimary }, [t('victory.continue', 'Continue')])]),
    ]);
    this.root = el('div', { class: 'screen-overlay fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

export class DefeatScreen {
  root: HTMLElement;

  constructor(container: HTMLElement, run: RunState, soulAshEarned: number, callbacks: EndScreenCallbacks) {
    const time = formatTime(run.elapsedSeconds());
    const zoneName = tc(run.currentZoneDef.id, 'name', run.currentZoneDef.name);
    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, [t('defeat.title', 'The Light Gutters Out')]),
      el('div', { class: 'screen-subtitle' }, [t('defeat.subtitleFormat', 'Fallen in {zone}. The Ember dims, but does not die.').replace('{zone}', zoneName)]),
      el('div', { class: 'stat-grid' }, [
        statTile(time, t('stat.timeSurvived', 'Time Survived')),
        statTile(run.stats.kills, t('stat.kills', 'Kills')),
        statTile(Math.round(run.stats.damageDealt), t('stat.damageDealt', 'Damage Dealt')),
        statTile(run.stats.embersCollected, t('stat.embersCollected', 'Embers Collected')),
        statTile(run.stats.upgradesChosen.length, t('stat.upgradesTaken', 'Upgrades Taken')),
        statTile(soulAshEarned, t('stat.soulAshEarned', 'Soul Ash Earned')),
      ]),
      el('div', { class: 'seed-label' }, [`${t('endScreen.seedLabel', 'Seed')}: ${run.seedLabel}`]),
      el('div', { class: 'button-row' }, [
        el('button', { class: 'btn primary', onClick: callbacks.onPrimary }, [t('defeat.tryAgain', 'Try Again')]),
        el('button', { class: 'btn ghost', onClick: callbacks.onSecondary }, [t('defeat.mainMenu', 'Main Menu')]),
      ]),
    ]);
    this.root = el('div', { class: 'screen-overlay fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

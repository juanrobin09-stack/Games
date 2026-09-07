import { el } from '@/ui/dom';
import { formatTime } from '@/utils/MathUtils';
import type { RunState } from '@/progression/RunState';

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
      el('div', { class: 'screen-title' }, ['The Ember Endures']),
      el('div', { class: 'screen-subtitle' }, ['The Ashen Colossus falls. For now, the dark recedes.']),
      el('div', { class: 'stat-grid' }, [
        statTile(time, 'Time'),
        statTile(run.stats.kills, 'Kills'),
        statTile(Math.round(run.stats.damageDealt), 'Damage Dealt'),
        statTile(run.stats.embersCollected, 'Embers Collected'),
        statTile(run.stats.upgradesChosen.length, 'Upgrades Taken'),
        statTile(soulAshEarned, 'Soul Ash Earned'),
      ]),
      el('div', { class: 'seed-label' }, [`Seed: ${run.seedLabel}`]),
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: callbacks.onPrimary }, ['Continue'])]),
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
    const zoneName = run.currentZoneDef.name;
    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, ['The Light Gutters Out']),
      el('div', { class: 'screen-subtitle' }, [`Fallen in ${zoneName}. The Ember dims, but does not die.`]),
      el('div', { class: 'stat-grid' }, [
        statTile(time, 'Time Survived'),
        statTile(run.stats.kills, 'Kills'),
        statTile(Math.round(run.stats.damageDealt), 'Damage Dealt'),
        statTile(run.stats.embersCollected, 'Embers Collected'),
        statTile(run.stats.upgradesChosen.length, 'Upgrades Taken'),
        statTile(soulAshEarned, 'Soul Ash Earned'),
      ]),
      el('div', { class: 'seed-label' }, [`Seed: ${run.seedLabel}`]),
      el('div', { class: 'button-row' }, [
        el('button', { class: 'btn primary', onClick: callbacks.onPrimary }, ['Try Again']),
        el('button', { class: 'btn ghost', onClick: callbacks.onSecondary }, ['Main Menu']),
      ]),
    ]);
    this.root = el('div', { class: 'screen-overlay fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

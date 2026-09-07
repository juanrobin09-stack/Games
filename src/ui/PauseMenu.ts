import { el } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import { SettingsMenu } from '@/ui/SettingsMenu';
import type { SaveSettings } from '@/progression/SaveSystem';
import type { Player } from '@/entities/Player';
import { SYNERGIES } from '@/data/synergies';

export interface PauseMenuCallbacks {
  onResume: () => void;
  onAbandon: () => void;
  onSettingsChange: (settings: SaveSettings) => void;
}

export class PauseMenu {
  root: HTMLElement;
  private settingsPanel: SettingsMenu | null = null;

  constructor(private container: HTMLElement, private player: Player, private settings: SaveSettings, private callbacks: PauseMenuCallbacks) {
    this.root = el('div', { class: 'screen-overlay modal-backdrop fade-screen' });
    container.appendChild(this.root);
    this.renderMain();
  }

  private renderMain(): void {
    this.root.innerHTML = '';
    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, ['Paused']),
      el('div', { class: 'button-column' }, [
        el('button', { class: 'btn primary', onClick: this.callbacks.onResume }, ['Resume']),
        el('button', {
          class: 'btn',
          onClick: () => this.renderBuild(),
        }, ['Your Build']),
        el('button', {
          class: 'btn',
          onClick: () => this.showSettings(),
        }, ['Settings']),
        el('button', {
          class: 'btn danger',
          onClick: () => this.renderConfirmAbandon(),
        }, ['Abandon Run']),
      ]),
    ]);
    this.root.appendChild(panel);
  }

  private renderBuild(): void {
    this.root.innerHTML = '';
    const upgradeCards = this.player.upgrades.map((owned) =>
      el('div', { class: `upgrade-card rarity-${owned.def.rarity}` }, [
        el('div', { class: 'icon-badge', html: iconSvg(owned.def.icon, 20) }),
        el('div', { class: `card-name rarity-${owned.def.rarity}` }, [owned.def.name + (owned.stacks > 1 ? ` ×${owned.stacks}` : '')]),
        el('div', { class: 'card-desc' }, [owned.def.description]),
      ])
    );
    const activeSynergies = SYNERGIES.filter((s) => this.player.hasSynergy(s.id));
    const synergyRows = activeSynergies.map((s) =>
      el('div', { class: 'meta-node' }, [
        el('div', { class: 'icon-badge', html: iconSvg(s.icon, 20) }),
        el('div', { class: 'meta-info' }, [
          el('div', { class: 'meta-name', style: 'color:var(--c-soul-bright);' }, [s.name]),
          el('div', { class: 'meta-desc' }, [s.description]),
        ]),
      ])
    );

    const panel = el('div', { class: 'screen-panel wide panel pop-in' }, [
      el('div', { class: 'screen-title' }, ['Your Build']),
      el('div', { class: 'screen-subtitle' }, [
        activeSynergies.length > 0 ? 'Active synergies' : 'No synergies active yet — some upgrade pairs unlock a bonus effect.',
      ]),
      synergyRows.length > 0 ? el('div', { class: 'button-column' }, synergyRows) : null,
      el('hr', { class: 'divider' }),
      el('div', { class: 'screen-subtitle' }, [`${this.player.upgrades.length} upgrade${this.player.upgrades.length === 1 ? '' : 's'} collected this run`]),
      upgradeCards.length > 0
        ? el('div', { class: 'card-grid' }, upgradeCards)
        : el('div', { class: 'screen-body-text' }, ['No upgrades yet — clear a room, open a chest, or visit a shop.']),
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: () => this.renderMain() }, ['Back'])]),
    ]);
    this.root.appendChild(panel);
  }

  private renderConfirmAbandon(): void {
    this.root.innerHTML = '';
    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, ['Abandon this run?']),
      el('div', { class: 'screen-body-text' }, ['The Ember will fall dark here. All progress from this run will be lost — only Soul Ash already banked remains.']),
      el('div', { class: 'button-row' }, [
        el('button', { class: 'btn ghost', onClick: () => this.renderMain() }, ['Keep Going']),
        el('button', { class: 'btn danger', onClick: this.callbacks.onAbandon }, ['Abandon']),
      ]),
    ]);
    this.root.appendChild(panel);
  }

  private showSettings(): void {
    this.root.innerHTML = '';
    this.settingsPanel = new SettingsMenu(this.root, this.settings, {
      onClose: () => {
        this.settingsPanel?.destroy();
        this.settingsPanel = null;
        this.renderMain();
      },
      onChange: this.callbacks.onSettingsChange,
    }, true);
  }

  destroy(): void {
    this.settingsPanel?.destroy();
    this.root.remove();
  }
}

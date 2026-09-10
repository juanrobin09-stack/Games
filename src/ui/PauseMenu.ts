import { el } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import { SettingsMenu } from '@/ui/SettingsMenu';
import type { SaveSettings } from '@/progression/SaveSystem';
import type { Player } from '@/entities/Player';
import { SYNERGIES } from '@/data/synergies';
import { t, tc } from '@/i18n';

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
      el('div', { class: 'screen-title' }, [t('pause.title', 'Paused')]),
      el('div', { class: 'button-column' }, [
        el('button', { class: 'btn primary', onClick: this.callbacks.onResume }, [t('pause.resume', 'Resume')]),
        el('button', {
          class: 'btn',
          onClick: () => this.renderBuild(),
        }, [t('pause.yourBuild', 'Your Build')]),
        el('button', {
          class: 'btn',
          onClick: () => this.showSettings(),
        }, [t('menu.settings', 'Settings')]),
        el('button', {
          class: 'btn danger',
          onClick: () => this.renderConfirmAbandon(),
        }, [t('pause.abandonRun', 'Abandon Run')]),
      ]),
    ]);
    this.root.appendChild(panel);
  }

  private renderBuild(): void {
    this.root.innerHTML = '';
    const upgradeCards = this.player.upgrades.map((owned) =>
      el('div', { class: `upgrade-card rarity-${owned.def.rarity}` }, [
        el('div', { class: 'icon-badge', html: iconSvg(owned.def.icon, 20) }),
        el('div', { class: `card-name rarity-${owned.def.rarity}` }, [tc(owned.def.id, 'name', owned.def.name) + (owned.stacks > 1 ? ` ×${owned.stacks}` : '')]),
        el('div', { class: 'card-desc' }, [tc(owned.def.id, 'description', owned.def.description)]),
      ])
    );
    const activeSynergies = SYNERGIES.filter((s) => this.player.hasSynergy(s.id));
    const synergyRows = activeSynergies.map((s) =>
      el('div', { class: 'meta-node' }, [
        el('div', { class: 'icon-badge', html: iconSvg(s.icon, 20) }),
        el('div', { class: 'meta-info' }, [
          el('div', { class: 'meta-name', style: 'color:var(--c-soul-bright);' }, [tc(s.id, 'name', s.name)]),
          el('div', { class: 'meta-desc' }, [tc(s.id, 'description', s.description)]),
        ]),
      ])
    );

    const upgradeCountLabel = this.player.upgrades.length === 1
      ? t('pause.upgradeCountOne', '{count} upgrade collected this run')
      : t('pause.upgradeCountMany', '{count} upgrades collected this run');

    const panel = el('div', { class: 'screen-panel wide panel pop-in' }, [
      el('div', { class: 'screen-title' }, [t('pause.yourBuild', 'Your Build')]),
      el('div', { class: 'screen-subtitle' }, [
        activeSynergies.length > 0 ? t('pause.activeSynergies', 'Active synergies') : t('pause.noSynergies', 'No synergies active yet — some upgrade pairs unlock a bonus effect.'),
      ]),
      synergyRows.length > 0 ? el('div', { class: 'button-column' }, synergyRows) : null,
      el('hr', { class: 'divider' }),
      el('div', { class: 'screen-subtitle' }, [upgradeCountLabel.replace('{count}', String(this.player.upgrades.length))]),
      upgradeCards.length > 0
        ? el('div', { class: 'card-grid' }, upgradeCards)
        : el('div', { class: 'screen-body-text' }, [t('pause.noUpgrades', 'No upgrades yet — clear a room, open a chest, or visit a shop.')]),
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: () => this.renderMain() }, [t('pause.back', 'Back')])]),
    ]);
    this.root.appendChild(panel);
  }

  private renderConfirmAbandon(): void {
    this.root.innerHTML = '';
    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, [t('pause.abandonConfirmTitle', 'Abandon this run?')]),
      el('div', { class: 'screen-body-text' }, [t('pause.abandonConfirmBody', 'The Ember will fall dark here. All progress from this run will be lost — only Soul Ash already banked remains.')]),
      el('div', { class: 'button-row' }, [
        el('button', { class: 'btn ghost', onClick: () => this.renderMain() }, [t('pause.keepGoing', 'Keep Going')]),
        el('button', { class: 'btn danger', onClick: this.callbacks.onAbandon }, [t('pause.abandonConfirm', 'Abandon')]),
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

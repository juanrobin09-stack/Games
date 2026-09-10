import { el } from '@/ui/dom';
import { SettingsMenu } from '@/ui/SettingsMenu';
import type { SaveSettings } from '@/progression/SaveSystem';
import { t } from '@/i18n';

export interface PauseMenuCallbacks {
  onResume: () => void;
  onAbandon: () => void;
  onSettingsChange: (settings: SaveSettings) => void;
  /** Closes the pause menu and opens the character/build screen (InventoryUI). */
  onOpenInventory: () => void;
}

export class PauseMenu {
  root: HTMLElement;
  private settingsPanel: SettingsMenu | null = null;

  constructor(private container: HTMLElement, private settings: SaveSettings, private callbacks: PauseMenuCallbacks) {
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
          onClick: this.callbacks.onOpenInventory,
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

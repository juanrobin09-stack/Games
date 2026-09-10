import { el } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import type { UpgradeDefinition } from '@/data/types';
import { playSfx } from '@/audio/SoundFactory';
import { t, tc } from '@/i18n';

export interface UpgradeSelectCallbacks {
  onChoose: (upgrade: UpgradeDefinition) => void;
}

export class UpgradeSelectUI {
  root: HTMLElement;

  constructor(container: HTMLElement, choices: UpgradeDefinition[], callbacks: UpgradeSelectCallbacks) {
    const cards = choices.map((def) => {
      const button = el(
        'button',
        {
          class: `upgrade-card rarity-${def.rarity} slide-up`,
          onClick: () => {
            if (button.disabled) return;
            cards.forEach((c) => (c.disabled = true));
            playSfx('upgradeChoose');
            this.destroy();
            callbacks.onChoose(def);
          },
        },
        [
          el('div', { class: 'icon-badge', html: iconSvg(def.icon, 22) }),
          el('div', { class: `card-name rarity-${def.rarity}` }, [tc(def.id, 'name', def.name)]),
          el('div', { class: 'card-desc' }, [tc(def.id, 'description', def.description)]),
          el('div', { class: 'card-tags' }, [el('span', { class: `tag rarity-${def.rarity}` }, [t(`rarity.${def.rarity}`, def.rarity)])]),
        ]
      );
      return button;
    });

    const panel = el('div', { class: 'screen-panel wide panel pop-in' }, [
      el('div', { class: 'screen-title' }, [t('upgradeSelect.title', 'A Blessing Awaits')]),
      el('div', { class: 'screen-subtitle' }, [t('upgradeSelect.subtitle', 'Choose one. The Ember remembers every choice.')]),
      el('div', { class: 'card-grid' }, cards),
    ]);

    this.root = el('div', { class: 'screen-overlay modal-backdrop fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

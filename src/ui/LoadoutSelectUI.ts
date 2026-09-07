import { el, clear } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import { WEAPONS } from '@/data/weapons';
import { ABILITIES } from '@/data/abilities';

export interface LoadoutCallbacks {
  onConfirm: (weaponId: string, abilityId: string) => void;
}

export class LoadoutSelectUI {
  root: HTMLElement;
  private weaponId: string;
  private abilityId: string;
  private weaponRow!: HTMLElement;
  private abilityRow!: HTMLElement;
  private confirmBtn!: HTMLButtonElement;

  constructor(container: HTMLElement, unlockedWeapons: string[], unlockedAbilities: string[], callbacks: LoadoutCallbacks) {
    this.weaponId = unlockedWeapons[0] ?? 'emberBlade';
    this.abilityId = unlockedAbilities[0] ?? 'emberBurst';

    this.weaponRow = el('div', { class: 'card-grid' });
    this.abilityRow = el('div', { class: 'card-grid' });
    this.confirmBtn = el('button', { class: 'btn primary', onClick: () => callbacks.onConfirm(this.weaponId, this.abilityId) }, ['Begin']) as HTMLButtonElement;

    const panel = el('div', { class: 'screen-panel wide panel pop-in' }, [
      el('div', { class: 'screen-title' }, ['Choose Your Loadout']),
      el('div', { class: 'screen-subtitle' }, ['Weapon']),
      this.weaponRow,
      el('div', { class: 'screen-subtitle' }, ['Ability']),
      this.abilityRow,
      el('div', { class: 'button-row' }, [this.confirmBtn]),
    ]);

    this.root = el('div', { class: 'screen-overlay fade-screen' }, [panel]);
    container.appendChild(this.root);

    this.renderWeapons(unlockedWeapons);
    this.renderAbilities(unlockedAbilities);
  }

  private renderWeapons(unlocked: string[]): void {
    clear(this.weaponRow);
    for (const id of unlocked) {
      const def = WEAPONS[id];
      const card = el(
        'button',
        {
          class: `upgrade-card${this.weaponId === id ? ' rarity-legendary' : ''}`,
          onClick: () => {
            this.weaponId = id;
            this.renderWeapons(unlocked);
          },
        },
        [
          el('div', { class: 'icon-badge', html: iconSvg('blade', 22) }),
          el('div', { class: 'card-name' }, [def.name]),
          el('div', { class: 'card-desc' }, [def.description]),
        ]
      );
      this.weaponRow.appendChild(card);
    }
  }

  private renderAbilities(unlocked: string[]): void {
    clear(this.abilityRow);
    for (const id of unlocked) {
      const def = ABILITIES[id];
      const card = el(
        'button',
        {
          class: `upgrade-card${this.abilityId === id ? ' rarity-legendary' : ''}`,
          onClick: () => {
            this.abilityId = id;
            this.renderAbilities(unlocked);
          },
        },
        [
          el('div', { class: 'icon-badge', html: iconSvg('ability', 22) }),
          el('div', { class: 'card-name' }, [def.name]),
          el('div', { class: 'card-desc' }, [def.description]),
        ]
      );
      this.abilityRow.appendChild(card);
    }
  }

  destroy(): void {
    this.root.remove();
  }
}

import { el } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import type { UpgradeDefinition } from '@/data/types';
import { tc } from '@/i18n';

/** Brief auto-dismissing reveal for a granted upgrade (chest rewards, event boons). */
export class RewardPopup {
  root: HTMLElement;
  private timeout: number;

  constructor(container: HTMLElement, def: UpgradeDefinition, sourceLabel: string) {
    const card = el('div', { class: `upgrade-card rarity-${def.rarity} pop-in`, style: 'pointer-events:none;' }, [
      el('div', { class: 'tag' }, [sourceLabel]),
      el('div', { class: 'icon-badge', html: iconSvg(def.icon, 22) }),
      el('div', { class: `card-name rarity-${def.rarity}` }, [tc(def.id, 'name', def.name)]),
      el('div', { class: 'card-desc' }, [tc(def.id, 'description', def.description)]),
    ]);
    this.root = el('div', { class: 'screen-overlay', style: 'background:transparent;pointer-events:none;align-items:flex-start;padding-top:16vh;' }, [card]);
    container.appendChild(this.root);
    this.timeout = window.setTimeout(() => this.destroy(), 2800);
  }

  destroy(): void {
    clearTimeout(this.timeout);
    this.root.remove();
  }
}

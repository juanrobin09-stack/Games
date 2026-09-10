import { el, clear } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import { meta } from '@/progression/MetaProgression';
import { PERMANENT_UPGRADES } from '@/data/permanentUpgrades';
import { UNLOCKS } from '@/data/unlocks';
import { getWeaponDefinition } from '@/data/weapons';
import { getAbilityDefinition } from '@/data/abilities';
import { playSfx } from '@/audio/SoundFactory';
import type { UnlockDefinition, UpgradeIconId } from '@/data/types';
import { t, tc } from '@/i18n';

export type MetaMenuMode = 'upgrades' | 'armory';

export interface MetaMenuCallbacks {
  onClose: () => void;
}

const UNLOCK_ICON: Record<UnlockDefinition['kind'], UpgradeIconId> = {
  weapon: 'blade',
  ability: 'ability',
  enemy: 'burn',
  upgradeTier: 'luck',
};

export class MetaProgressionMenu {
  root: HTMLElement;
  private mode: MetaMenuMode;
  private balanceEl!: HTMLElement;
  private listEl!: HTMLElement;

  constructor(container: HTMLElement, mode: MetaMenuMode, private callbacks: MetaMenuCallbacks) {
    this.mode = mode;
    this.root = el('div', { class: 'screen-overlay fade-screen' });
    container.appendChild(this.root);
    this.render();
  }

  private render(): void {
    clear(this.root);
    this.balanceEl = el('div', { class: 'soul-ash-balance' }, [el('span', { html: iconSvg('luck', 18) }), `${meta.soulAsh} ${t('currency.soulAsh', 'Soul Ash')}`]);
    this.listEl = el('div', { class: 'button-column' });

    const tabRow = el('div', { class: 'tab-row' }, [
      el('button', { class: this.mode === 'upgrades' ? 'active' : '', onClick: () => this.switchMode('upgrades') }, [t('menu.upgrades', 'Upgrades')]),
      el('button', { class: this.mode === 'armory' ? 'active' : '', onClick: () => this.switchMode('armory') }, [t('menu.armory', 'Armory')]),
    ]);

    const panel = el('div', { class: 'screen-panel wide panel pop-in' }, [
      el('div', { class: 'screen-title' }, [this.mode === 'upgrades' ? t('meta.permanentUpgrades', 'Permanent Upgrades') : t('menu.armory', 'Armory')]),
      el('div', { class: 'screen-subtitle' }, [
        this.mode === 'upgrades'
          ? t('meta.upgradesSubtitle', 'Spend Soul Ash gathered across fallen runs to strengthen every Warden to come.')
          : t('meta.armorySubtitle', 'Unlock new weapons, abilities, and threats that persist across every run.'),
      ]),
      this.balanceEl,
      tabRow,
      this.listEl,
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: this.callbacks.onClose }, [t('pause.back', 'Back')])]),
    ]);
    this.root.appendChild(panel);
    this.renderList();
  }

  private switchMode(mode: MetaMenuMode): void {
    if (this.mode === mode) return;
    this.mode = mode;
    playSfx('uiClick');
    this.render();
  }

  private renderList(): void {
    clear(this.listEl);
    if (this.mode === 'upgrades') {
      for (const def of PERMANENT_UPGRADES) {
        const level = meta.getPermanentLevel(def.id);
        const cost = meta.getPermanentCost(def.id);
        const locked = !!def.requires && meta.getPermanentLevel(def.requires) === 0;
        const pips = Array.from({ length: def.maxLevel }, (_, i) =>
          el('div', { class: 'pip' + (i < level ? ' filled' : '') })
        );
        const buyLabel = locked ? t('meta.locked', 'Locked') : cost === null ? t('meta.max', 'Max') : `${cost}`;
        const canBuy = !locked && meta.canPurchasePermanent(def.id);
        const requiredDef = PERMANENT_UPGRADES.find((p) => p.id === def.requires);
        this.listEl.appendChild(
          el('div', { class: 'meta-node' }, [
            el('div', { class: 'icon-badge', html: iconSvg(def.icon, 20) }),
            el('div', { class: 'meta-info' }, [
              el('div', { class: 'meta-name' }, [tc(def.id, 'name', def.name)]),
              el('div', { class: 'meta-desc' }, [
                locked && requiredDef
                  ? t('meta.requiresFormat', 'Requires {name}').replace('{name}', tc(requiredDef.id, 'name', requiredDef.name))
                  : tc(def.id, 'description', def.description),
              ]),
              el('div', { class: 'meta-levels' }, pips),
            ]),
            el('button', {
              class: 'btn small buy-btn',
              disabled: !canBuy,
              onClick: () => {
                if (meta.purchasePermanent(def.id)) {
                  playSfx('shopBuy');
                  this.render();
                } else {
                  playSfx('shopError');
                }
              },
            }, [buyLabel]),
          ])
        );
      }
    } else {
      for (const def of UNLOCKS) {
        const unlocked = meta.isUnlocked(def.id);
        const canBuy = meta.canPurchaseUnlock(def.id);
        let detail = tc(def.id, 'description', def.description);
        if (def.kind === 'weapon') {
          const weaponDef = getWeaponDefinition(def.refId);
          detail = tc(weaponDef.id, 'description', weaponDef.description);
        }
        if (def.kind === 'ability') {
          const abilityDef = getAbilityDefinition(def.refId);
          detail = tc(abilityDef.id, 'description', abilityDef.description);
        }
        this.listEl.appendChild(
          el('div', { class: 'meta-node' }, [
            el('div', { class: 'icon-badge', html: iconSvg(UNLOCK_ICON[def.kind], 20) }),
            el('div', { class: 'meta-info' }, [
              el('div', { class: 'meta-name' }, [tc(def.id, 'name', def.name)]),
              el('div', { class: 'meta-desc' }, [detail]),
            ]),
            el('button', {
              class: 'btn small buy-btn',
              disabled: unlocked || !canBuy,
              onClick: () => {
                if (meta.purchaseUnlock(def.id)) {
                  playSfx('shopBuy');
                  this.render();
                } else {
                  playSfx('shopError');
                }
              },
            }, [unlocked ? t('meta.unlocked', 'Unlocked') : `${def.cost}`]),
          ])
        );
      }
    }
  }

  destroy(): void {
    this.root.remove();
  }
}

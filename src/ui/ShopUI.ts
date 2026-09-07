import { el, clear } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import type { ShopOffer } from '@/world/Shop';
import { REROLL_COST } from '@/world/Shop';
import { playSfx } from '@/audio/SoundFactory';

export interface ShopCallbacks {
  getEmbers: () => number;
  onBuyUpgrade: (offer: ShopOffer) => boolean;
  onBuyHeal: (offer: ShopOffer) => boolean;
  onReroll: () => ShopOffer[];
  onClose: () => void;
}

export class ShopUI {
  root: HTMLElement;
  private listEl!: HTMLElement;
  private embersEl!: HTMLElement;
  private rerollBtn!: HTMLButtonElement;

  constructor(container: HTMLElement, private offers: ShopOffer[], private callbacks: ShopCallbacks) {
    this.root = el('div', { class: 'screen-overlay modal-backdrop fade-screen' });
    container.appendChild(this.root);
    this.render();
  }

  private render(): void {
    clear(this.root);
    this.embersEl = el('div', { class: 'hud-embers', style: 'justify-content:center;margin:0 auto;' }, [
      el('span', { html: iconSvg('ember', 16) }),
      `${this.callbacks.getEmbers()}`,
    ]);
    this.listEl = el('div', { class: 'button-column' });
    this.rerollBtn = el('button', { class: 'btn small', onClick: () => this.reroll() }, [`Reroll (${REROLL_COST})`]) as HTMLButtonElement;

    const panel = el('div', { class: 'screen-panel wide panel pop-in' }, [
      el('div', { class: 'screen-title' }, ['The Forgotten Merchant']),
      el('div', { class: 'screen-subtitle' }, ['"Everything has a price, Warden. Choose wisely."']),
      this.embersEl,
      this.listEl,
      el('div', { class: 'button-row' }, [this.rerollBtn, el('button', { class: 'btn primary', onClick: () => this.leave() }, ['Leave'])]),
    ]);
    this.root.appendChild(panel);
    this.renderList();
  }

  private renderList(): void {
    clear(this.listEl);
    const embers = this.callbacks.getEmbers();
    for (const offer of this.offers) {
      const isUpgrade = offer.kind === 'upgrade' && offer.upgrade;
      const name = isUpgrade ? offer.upgrade!.name : 'Mend Your Wounds';
      const desc = isUpgrade ? offer.upgrade!.description : 'Restore a portion of your health.';
      const icon = isUpgrade ? offer.upgrade!.icon : 'heart';
      const affordable = embers >= offer.cost && !offer.purchased;
      this.listEl.appendChild(
        el('div', { class: 'shop-item' }, [
          el('div', { class: `icon-badge${isUpgrade ? ' rarity-' + offer.upgrade!.rarity : ''}`, html: iconSvg(icon, 20) }),
          el('div', { class: 'shop-info' }, [
            el('div', { class: `shop-name${isUpgrade ? ' rarity-' + offer.upgrade!.rarity : ''}` }, [name]),
            el('div', { class: 'shop-desc' }, [desc]),
          ]),
          el('div', { class: 'shop-cost' }, [`${offer.cost}`]),
          el('button', {
            class: 'btn small',
            disabled: !affordable,
            onClick: () => this.buy(offer),
          }, [offer.purchased ? 'Sold' : 'Buy']),
        ])
      );
    }
    this.embersEl.textContent = '';
    this.embersEl.appendChild(el('span', { html: iconSvg('ember', 16) }));
    this.embersEl.appendChild(document.createTextNode(` ${embers}`));
    this.rerollBtn.disabled = embers < REROLL_COST;
  }

  private buy(offer: ShopOffer): void {
    const success = offer.kind === 'upgrade' ? this.callbacks.onBuyUpgrade(offer) : this.callbacks.onBuyHeal(offer);
    if (success) {
      offer.purchased = true;
      playSfx('shopBuy');
    } else {
      playSfx('shopError');
    }
    this.renderList();
  }

  private leave(): void {
    this.destroy();
    this.callbacks.onClose();
  }

  private reroll(): void {
    const fresh = this.callbacks.onReroll();
    if (fresh.length === 0) {
      playSfx('shopError');
      return;
    }
    this.offers = fresh;
    playSfx('uiClick');
    this.renderList();
  }

  destroy(): void {
    this.root.remove();
  }
}

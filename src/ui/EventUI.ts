import { el } from '@/ui/dom';
import type { WorldEventDefinition, EventOption } from '@/data/types';
import { playSfx } from '@/audio/SoundFactory';

export interface EventCallbacks {
  getEmbers: () => number;
  onChoose: (option: EventOption) => void;
}

export class EventUI {
  root: HTMLElement;

  constructor(container: HTMLElement, def: WorldEventDefinition, callbacks: EventCallbacks) {
    const embers = callbacks.getEmbers();
    const buttons = def.options.map((opt) => {
      const affordable = !opt.cost || embers >= opt.cost;
      const button = el(
        'button',
        {
          class: 'event-option',
          disabled: !affordable,
          onClick: () => {
            if (button.disabled) return;
            buttons.forEach((b) => (b.disabled = true));
            playSfx('eventChoice');
            this.destroy();
            callbacks.onChoose(opt);
          },
        },
        [
          el('div', { class: 'opt-label' }, [opt.label]),
          el('div', { class: 'opt-detail' }, [opt.detail]),
          opt.cost ? el('div', { class: 'opt-cost' }, [`Costs ${opt.cost} Embers`]) : null,
        ]
      );
      return button;
    });

    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, [def.title]),
      el('div', { class: 'screen-body-text' }, [def.description]),
      el('div', { class: 'button-column' }, buttons),
    ]);

    this.root = el('div', { class: 'screen-overlay modal-backdrop fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

import { el } from '@/ui/dom';

export class CreditsScreen {
  root: HTMLElement;

  constructor(container: HTMLElement, onClose: () => void) {
    const panel = el('div', { class: 'screen-panel panel pop-in' }, [
      el('div', { class: 'screen-title' }, ['Credits']),
      el('div', { class: 'screen-body-text' }, [
        el('p', {}, ['EMBERFALL: LAST LIGHT']),
        el('p', {}, ['A self-contained dark fantasy action roguelite. Every sprite, particle, and sound in this game is generated procedurally at runtime — no external art or audio files.']),
        el('p', {}, ['Built with TypeScript, Vite, Canvas 2D, and the Web Audio API.']),
        el('p', {}, ['Thank you for guarding the last light.']),
      ]),
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: onClose }, ['Back'])]),
    ]);
    this.root = el('div', { class: 'screen-overlay fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

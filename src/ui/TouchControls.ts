import { el } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import type { InputManager } from '@/core/Input';
import { Vector2 } from '@/utils/Vector2';

export interface TouchControlsCallbacks {
  onPause: () => void;
}

export class TouchControls {
  root: HTMLElement;
  private stickZone: HTMLElement;
  private stickNub: HTMLElement;
  private stickActive = false;
  private stickPointerId: number | null = null;
  private stickOrigin = { x: 0, y: 0 };
  private readonly stickRadius = 52;

  constructor(container: HTMLElement, private input: InputManager, callbacks: TouchControlsCallbacks) {
    this.stickNub = el('div', { class: 'touch-stick-nub' });
    this.stickZone = el('div', { class: 'touch-stick-zone' }, [this.stickNub]);

    this.stickZone.addEventListener('pointerdown', this.onStickDown);
    window.addEventListener('pointermove', this.onStickMove);
    window.addEventListener('pointerup', this.onStickUp);
    window.addEventListener('pointercancel', this.onStickUp);

    const attackBtn = el('div', { class: 'touch-action-btn attack', html: iconSvg('blade', 26) });
    attackBtn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      this.input.setTouchAttackHeld(true);
    });
    attackBtn.addEventListener('pointerup', () => this.input.setTouchAttackHeld(false));
    attackBtn.addEventListener('pointercancel', () => this.input.setTouchAttackHeld(false));

    const dodgeBtn = el('div', { class: 'touch-action-btn dodge', html: iconSvg('dodge', 20) });
    dodgeBtn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      this.input.triggerTouchDodge();
    });

    const abilityBtn = el('div', { class: 'touch-action-btn ability', html: iconSvg('ember', 24) });
    abilityBtn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      this.input.triggerTouchAbility();
    });

    const interactBtn = el('div', { class: 'touch-action-btn interact', html: '<span style="font-size:13px;font-weight:700;">E</span>' });
    interactBtn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      this.input.triggerTouchInteract();
    });

    const pauseBtn = el('button', { class: 'touch-pause-btn', onClick: callbacks.onPause, html: '<span style="font-size:16px;">II</span>' });

    this.root = el('div', { class: 'touch-controls' }, [this.stickZone, attackBtn, dodgeBtn, abilityBtn, interactBtn, pauseBtn]);
    container.appendChild(this.root);
  }

  private onStickDown = (e: PointerEvent): void => {
    e.preventDefault();
    this.stickActive = true;
    this.stickPointerId = e.pointerId;
    const rect = this.stickZone.getBoundingClientRect();
    this.stickOrigin = { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
    this.updateStick(e.clientX, e.clientY);
  };

  private onStickMove = (e: PointerEvent): void => {
    if (!this.stickActive || e.pointerId !== this.stickPointerId) return;
    this.updateStick(e.clientX, e.clientY);
  };

  private onStickUp = (e: PointerEvent): void => {
    if (e.pointerId !== this.stickPointerId) return;
    this.stickActive = false;
    this.stickPointerId = null;
    this.stickNub.style.transform = `translate(0px, 0px)`;
    this.input.setTouchMove(new Vector2(0, 0));
  };

  private updateStick(clientX: number, clientY: number): void {
    let dx = clientX - this.stickOrigin.x;
    let dy = clientY - this.stickOrigin.y;
    const dist = Math.hypot(dx, dy);
    if (dist > this.stickRadius) {
      dx = (dx / dist) * this.stickRadius;
      dy = (dy / dist) * this.stickRadius;
    }
    this.stickNub.style.transform = `translate(${dx}px, ${dy}px)`;
    const normalized = new Vector2(dx / this.stickRadius, dy / this.stickRadius);
    this.input.setTouchMove(normalized);
  }

  destroy(): void {
    window.removeEventListener('pointermove', this.onStickMove);
    window.removeEventListener('pointerup', this.onStickUp);
    window.removeEventListener('pointercancel', this.onStickUp);
    this.root.remove();
  }
}

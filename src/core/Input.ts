import { Vector2 } from '@/utils/Vector2';

export type InputMode = 'desktop' | 'touch';

export type InputAction = 'dodge' | 'ability' | 'interact' | 'pause' | 'attack' | 'confirm';

const KEY_ACTIONS: Record<string, InputAction> = {
  Space: 'dodge',
  ShiftLeft: 'dodge',
  ShiftRight: 'dodge',
  KeyE: 'interact',
  Escape: 'pause',
  Enter: 'confirm',
};

/**
 * Unifies keyboard/mouse and touch input into one action-based interface the
 * rest of the game queries. Touch input arrives via the setters below, fed by
 * the on-screen TouchControls DOM overlay (see ui/TouchControls.ts).
 */
export class InputManager {
  mode: InputMode;

  private keysDown = new Set<string>();
  private framePressed = new Set<InputAction>();
  private frameReleased = new Set<InputAction>();

  private mouseScreen = new Vector2();
  private mouseDown = false;
  private mouseRightPending = false;

  private touchMove = new Vector2();
  private touchAim: number | null = null;
  private touchAttackHeld = false;
  private touchAbilityPending = false;
  private touchDodgePending = false;
  private touchInteractPending = false;

  private listeners: Array<() => void> = [];

  constructor(private target: HTMLElement) {
    this.mode = window.matchMedia('(pointer: coarse)').matches ? 'touch' : 'desktop';
    this.attach();
  }

  private attach(): void {
    const onKeyDown = (e: KeyboardEvent) => {
      this.setDesktopMode();
      if (e.repeat) return;
      this.keysDown.add(e.code);
      const action = KEY_ACTIONS[e.code];
      if (action) this.framePressed.add(action);
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) {
        e.preventDefault();
      }
    };
    const onKeyUp = (e: KeyboardEvent) => {
      this.keysDown.delete(e.code);
      const action = KEY_ACTIONS[e.code];
      if (action) this.frameReleased.add(action);
    };
    const onMouseMove = (e: MouseEvent) => {
      this.setDesktopMode();
      const rect = this.target.getBoundingClientRect();
      this.mouseScreen.set(e.clientX - rect.left, e.clientY - rect.top);
    };
    const onMouseDown = (e: MouseEvent) => {
      this.setDesktopMode();
      if (e.button === 0) {
        this.mouseDown = true;
        this.framePressed.add('attack');
      } else if (e.button === 2) {
        this.mouseRightPending = true;
        this.framePressed.add('ability');
      }
    };
    const onMouseUp = (e: MouseEvent) => {
      if (e.button === 0) {
        this.mouseDown = false;
        this.frameReleased.add('attack');
      }
    };
    const onContextMenu = (e: Event) => e.preventDefault();
    const onBlur = () => {
      this.keysDown.clear();
      this.mouseDown = false;
    };

    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    this.target.addEventListener('mousemove', onMouseMove);
    this.target.addEventListener('mousedown', onMouseDown);
    window.addEventListener('mouseup', onMouseUp);
    this.target.addEventListener('contextmenu', onContextMenu);
    window.addEventListener('blur', onBlur);
    this.target.addEventListener(
      'touchstart',
      () => {
        this.mode = 'touch';
      },
      { passive: true }
    );

    this.listeners.push(
      () => window.removeEventListener('keydown', onKeyDown),
      () => window.removeEventListener('keyup', onKeyUp),
      () => this.target.removeEventListener('mousemove', onMouseMove),
      () => this.target.removeEventListener('mousedown', onMouseDown),
      () => window.removeEventListener('mouseup', onMouseUp),
      () => this.target.removeEventListener('contextmenu', onContextMenu),
      () => window.removeEventListener('blur', onBlur)
    );
  }

  private setDesktopMode(): void {
    this.mode = 'desktop';
  }

  destroy(): void {
    this.listeners.forEach((fn) => fn());
  }

  /** Call once per frame after gameplay has consumed this frame's input. */
  endFrame(): void {
    this.framePressed.clear();
    this.frameReleased.clear();
    this.touchAbilityPending = false;
    this.touchDodgePending = false;
    this.touchInteractPending = false;
    this.mouseRightPending = false;
  }

  getMoveVector(): Vector2 {
    if (this.mode === 'touch') return this.touchMove.clone();
    let x = 0;
    let y = 0;
    if (this.keysDown.has('KeyW') || this.keysDown.has('ArrowUp')) y -= 1;
    if (this.keysDown.has('KeyS') || this.keysDown.has('ArrowDown')) y += 1;
    if (this.keysDown.has('KeyA') || this.keysDown.has('ArrowLeft')) x -= 1;
    if (this.keysDown.has('KeyD') || this.keysDown.has('ArrowRight')) x += 1;
    const v = new Vector2(x, y);
    if (v.lengthSq() > 1) v.normalize();
    return v;
  }

  getAimAngle(originScreenX: number, originScreenY: number, facingFallback: number): number {
    if (this.mode === 'touch') {
      if (this.touchAim !== null) return this.touchAim;
      const mv = this.touchMove;
      if (mv.lengthSq() > 0.02) return Math.atan2(mv.y, mv.x);
      return facingFallback;
    }
    return Math.atan2(this.mouseScreen.y - originScreenY, this.mouseScreen.x - originScreenX);
  }

  isAttackHeld(): boolean {
    return this.mode === 'touch' ? this.touchAttackHeld : this.mouseDown;
  }

  wasPressed(action: InputAction): boolean {
    if (this.mode === 'touch') {
      if (action === 'ability' && this.touchAbilityPending) return true;
      if (action === 'dodge' && this.touchDodgePending) return true;
      if (action === 'interact' && this.touchInteractPending) return true;
    }
    return this.framePressed.has(action);
  }

  wasReleased(action: InputAction): boolean {
    return this.frameReleased.has(action);
  }

  isKeyDown(code: string): boolean {
    return this.keysDown.has(code);
  }

  // --- Touch overlay bridge -------------------------------------------------
  setTouchMove(v: Vector2): void {
    this.touchMove.copy(v);
  }
  setTouchAim(angle: number | null): void {
    this.touchAim = angle;
  }
  setTouchAttackHeld(held: boolean): void {
    this.touchAttackHeld = held;
    if (held) this.framePressed.add('attack');
  }
  triggerTouchAbility(): void {
    this.touchAbilityPending = true;
  }
  triggerTouchDodge(): void {
    this.touchDodgePending = true;
  }
  triggerTouchInteract(): void {
    this.touchInteractPending = true;
  }
  triggerPause(): void {
    this.framePressed.add('pause');
  }
}

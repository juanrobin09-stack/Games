export enum GameState {
  BOOT = 'BOOT',
  MAIN_MENU = 'MAIN_MENU',
  RUN_START = 'RUN_START',
  EXPLORATION = 'EXPLORATION',
  COMBAT = 'COMBAT',
  EVENT = 'EVENT',
  SHOP = 'SHOP',
  BOSS = 'BOSS',
  VICTORY = 'VICTORY',
  DEFEAT = 'DEFEAT',
  PAUSED = 'PAUSED',
}

/**
 * Single authority for "what state is the game in". Every system (input
 * routing, rendering, HUD visibility, music) reads `current` rather than
 * maintaining its own notion of state, so nothing fights for control.
 */
export class GameStateMachine {
  private stack: GameState[] = [GameState.BOOT];
  private listeners: Array<(state: GameState, previous: GameState) => void> = [];

  get current(): GameState {
    return this.stack[this.stack.length - 1];
  }

  is(...states: GameState[]): boolean {
    return states.includes(this.current);
  }

  /** Replaces the whole stack (normal transition). */
  set(state: GameState): void {
    const previous = this.current;
    if (previous === state) return;
    this.stack = [state];
    this.notify(state, previous);
  }

  /** Pushes on top (e.g. PAUSED over EXPLORATION) so popping restores prior state. */
  push(state: GameState): void {
    const previous = this.current;
    this.stack.push(state);
    this.notify(state, previous);
  }

  pop(): void {
    if (this.stack.length <= 1) return;
    const previous = this.current;
    this.stack.pop();
    this.notify(this.current, previous);
  }

  onChange(fn: (state: GameState, previous: GameState) => void): () => void {
    this.listeners.push(fn);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== fn);
    };
  }

  private notify(state: GameState, previous: GameState): void {
    for (const l of this.listeners) l(state, previous);
  }
}

type Handler<T> = (payload: T) => void;

/**
 * Minimal typed pub/sub bus. Used to decouple gameplay systems from audio/VFX/UI
 * reactions (e.g. "enemyKilled" triggers loot + sound + stats without those
 * systems knowing about each other). Conceptually maps to Godot's signals.
 */
export class EventBus<Events extends Record<string, unknown>> {
  private handlers = new Map<keyof Events, Set<Handler<any>>>();

  on<K extends keyof Events>(event: K, handler: Handler<Events[K]>): () => void {
    let set = this.handlers.get(event);
    if (!set) {
      set = new Set();
      this.handlers.set(event, set);
    }
    set.add(handler);
    return () => this.off(event, handler);
  }

  off<K extends keyof Events>(event: K, handler: Handler<Events[K]>): void {
    this.handlers.get(event)?.delete(handler);
  }

  emit<K extends keyof Events>(event: K, payload: Events[K]): void {
    const set = this.handlers.get(event);
    if (!set) return;
    for (const handler of Array.from(set)) {
      handler(payload);
    }
  }

  clear(): void {
    this.handlers.clear();
  }
}

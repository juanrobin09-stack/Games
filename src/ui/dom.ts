type Child = Node | string | null | undefined | false;

export type ElProps = {
  [key: string]: unknown;
} & {
  class?: string;
  onClick?: (e: MouseEvent) => void;
  onInput?: (e: Event) => void;
  onChange?: (e: Event) => void;
  onPointerDown?: (e: PointerEvent) => void;
  onPointerUp?: (e: PointerEvent) => void;
  onPointerMove?: (e: PointerEvent) => void;
  html?: string;
};

const EVENT_MAP: Record<string, string> = {
  onClick: 'click',
  onInput: 'input',
  onChange: 'change',
  onPointerDown: 'pointerdown',
  onPointerUp: 'pointerup',
  onPointerMove: 'pointermove',
  onPointerCancel: 'pointercancel',
  onPointerLeave: 'pointerleave',
};

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  props: ElProps = {},
  children: Child[] = []
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') {
      node.className = value as string;
    } else if (key === 'html') {
      node.innerHTML = value as string;
    } else if (EVENT_MAP[key]) {
      node.addEventListener(EVENT_MAP[key], value as EventListener);
    } else if (key.startsWith('data-')) {
      node.setAttribute(key, String(value));
    } else if (key in node) {
      (node as unknown as Record<string, unknown>)[key] = value;
    } else {
      node.setAttribute(key, String(value));
    }
  }
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

export function clear(node: Element): void {
  node.innerHTML = '';
}

export function fragment(children: Child[]): DocumentFragment {
  const frag = document.createDocumentFragment();
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    frag.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return frag;
}

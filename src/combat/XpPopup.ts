/** Floating "+N XP" feedback spawned at the exact spot an enemy died — kept
 * deliberately separate from DamageNumber (a different concept: passive XP
 * feedback, not a combat hit), but mirrors its structure/rendering approach
 * for visual consistency. Slower and longer-lived than a hit number, with a
 * gentle constant drift rather than a gravity arc — this is a reward beat,
 * not an impact. */
export interface XpPopup {
  x: number;
  y: number;
  vy: number;
  text: string;
  age: number;
  life: number;
}

export function createXpPopup(x: number, y: number, amount: number): XpPopup {
  return {
    x: x + (Math.random() * 24 - 12),
    y: y + 4 + Math.random() * 6,
    vy: -19,
    text: `+${amount} XP`,
    age: 0,
    life: 1.7,
  };
}

export function updateXpPopups(list: XpPopup[], dt: number): void {
  for (let i = list.length - 1; i >= 0; i--) {
    const p = list[i];
    p.age += dt;
    p.y += p.vy * dt;
    if (p.age >= p.life) list.splice(i, 1);
  }
}

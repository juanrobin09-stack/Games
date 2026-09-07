export interface DamageNumber {
  x: number;
  y: number;
  vy: number;
  text: string;
  color: string;
  size: number;
  age: number;
  life: number;
}

export function createDamageNumber(x: number, y: number, text: string, color: string, size = 15): DamageNumber {
  return {
    x: x + (Math.random() * 14 - 7),
    y,
    vy: -48,
    text,
    color,
    size,
    age: 0,
    life: 0.75,
  };
}

export function updateDamageNumbers(list: DamageNumber[], dt: number): void {
  for (let i = list.length - 1; i >= 0; i--) {
    const n = list[i];
    n.age += dt;
    n.y += n.vy * dt;
    n.vy += 90 * dt;
    if (n.age >= n.life) list.splice(i, 1);
  }
}

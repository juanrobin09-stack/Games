let counter = 1;

export function nextEntityId(): number {
  return counter++;
}

export function resetEntityIdCounter(): void {
  counter = 1;
}

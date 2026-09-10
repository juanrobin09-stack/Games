import { FR_CONTENT, FR_UI } from '@/i18n/fr';

export type LocaleId = 'en' | 'fr';

/**
 * Not React-style reactive: text is baked into DOM nodes at construction
 * time throughout this codebase (see `el()` in ui/dom.ts), so changing the
 * locale mid-session doesn't retroactively re-render whatever's already on
 * screen. SettingsMenu reloads the page after a language change specifically
 * so every screen is rebuilt from scratch in the new language, rather than
 * trying to make every call site reactive for a switch a player makes once,
 * rarely, from a menu.
 */
let currentLocale: LocaleId = 'fr';

export function getLocale(): LocaleId {
  return currentLocale;
}

export function setLocale(id: LocaleId): void {
  currentLocale = id;
}

/** UI-chrome text: flat semantic key -> translated string, falling back to
 * the English text passed at the call site (which also doubles as inline
 * documentation of what the key means). */
export function t(key: string, fallbackEn: string): string {
  if (currentLocale === 'en') return fallbackEn;
  return FR_UI[key] ?? fallbackEn;
}

/** Data-driven content (enemies/weapons/abilities/upgrades/permanent
 * upgrades/zones/unlocks/synergies/world events & their options) — looked up
 * by the object's own stable `id` plus a field name (`'name'`,
 * `'description'`, `'subtitle'`, `'title'`, `'label'`, `'detail'`...),
 * falling back to the English value already sitting in the data file. */
export function tc(id: string, field: string, fallbackEn: string): string {
  if (currentLocale === 'en') return fallbackEn;
  return FR_CONTENT[id]?.[field] ?? fallbackEn;
}

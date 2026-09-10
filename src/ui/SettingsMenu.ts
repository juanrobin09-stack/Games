import { el } from '@/ui/dom';
import type { SaveSettings } from '@/progression/SaveSystem';
import { t } from '@/i18n';

export interface SettingsCallbacks {
  onClose: () => void;
  onChange: (settings: SaveSettings) => void;
}

export class SettingsMenu {
  root: HTMLElement;

  constructor(container: HTMLElement, settings: SaveSettings, callbacks: SettingsCallbacks, embedded = false) {
    const current = { ...settings };
    const emit = () => callbacks.onChange({ ...current });

    const slider = (label: string, value: number, min: number, max: number, step: number, onInput: (v: number) => void) => {
      const valueLabel = el('span', {}, [Math.round(value * 100) / 100 + '']);
      const input = el('input', {
        type: 'range',
        min: String(min),
        max: String(max),
        step: String(step),
        value: String(value),
        onInput: (e: Event) => {
          const v = parseFloat((e.target as HTMLInputElement).value);
          onInput(v);
          valueLabel.textContent = String(Math.round(v * 100) / 100);
          emit();
        },
      });
      return el('div', { class: 'settings-row' }, [
        el('label', {}, [label]),
        el('div', { class: 'settings-control' }, [input, valueLabel]),
      ]);
    };

    const toggle = (label: string, hint: string, value: boolean, onToggle: (v: boolean) => void) => {
      const sw = el('div', { class: 'toggle-switch' + (value ? ' on' : '') });
      sw.addEventListener('click', () => {
        const next = !sw.classList.contains('on');
        sw.classList.toggle('on', next);
        onToggle(next);
        emit();
      });
      return el('div', { class: 'settings-row' }, [
        el('div', {}, [el('label', {}, [label]), el('span', { class: 'hint' }, [hint])]),
        el('div', { class: 'settings-control' }, [sw]),
      ]);
    };

    const segmented = (label: string, options: { value: string; text: string }[], value: string, onPick: (v: string) => void) => {
      const buttons = options.map((opt) =>
        el('button', {
          class: opt.value === value ? 'active' : '',
          onClick: (e: MouseEvent) => {
            onPick(opt.value);
            emit();
            const parent = (e.target as HTMLElement).parentElement!;
            parent.querySelectorAll('button').forEach((b) => b.classList.remove('active'));
            (e.target as HTMLElement).classList.add('active');
          },
        }, [opt.text])
      );
      return el('div', { class: 'settings-row' }, [
        el('label', {}, [label]),
        el('div', { class: 'segmented' }, buttons),
      ]);
    };

    const languageRow = (() => {
      const langButton = (code: 'en' | 'fr', label: string) =>
        el('button', {
          class: current.language === code ? 'active' : '',
          onClick: (e: MouseEvent) => {
            if (current.language === code) return;
            current.language = code;
            emit();
            (e.target as HTMLElement).parentElement!.querySelectorAll('button').forEach((b) => b.classList.remove('active'));
            (e.target as HTMLElement).classList.add('active');
            // Text is baked into DOM nodes at construction time throughout the
            // UI, so a locale switch needs a fresh load to actually apply
            // everywhere rather than just in this menu — the setting is
            // already persisted by emit() above, synchronously, before this fires.
            window.setTimeout(() => window.location.reload(), 150);
          },
        }, [label]);
      return el('div', { class: 'settings-row' }, [
        el('div', {}, [
          el('label', {}, [t('settings.language', 'Language')]),
          el('span', { class: 'hint' }, [t('settings.languageHint', 'Reloads the game to apply')]),
        ]),
        el('div', { class: 'segmented' }, [langButton('en', 'English'), langButton('fr', 'Français')]),
      ]);
    })();

    const qualityOptions = (['low', 'medium', 'high'] as const).map((v) => ({ value: v, text: t(`settings.quality.${v}`, v) }));

    const body = el('div', { class: 'button-column' }, [
      languageRow,
      slider(t('settings.masterVolume', 'Master Volume'), current.masterVolume, 0, 1, 0.01, (v) => (current.masterVolume = v)),
      slider(t('settings.musicVolume', 'Music Volume'), current.musicVolume, 0, 1, 0.01, (v) => (current.musicVolume = v)),
      slider(t('settings.sfxVolume', 'SFX Volume'), current.sfxVolume, 0, 1, 0.01, (v) => (current.sfxVolume = v)),
      toggle(t('settings.muteAll', 'Mute All'), t('settings.muteAllHint', 'Silence all audio output'), current.muted, (v) => (current.muted = v)),
      toggle(t('settings.screenShake', 'Screen Shake'), t('settings.screenShakeHint', 'Camera shake on heavy impacts'), current.screenShake, (v) => (current.screenShake = v)),
      segmented(t('settings.particles', 'Particles'), qualityOptions, current.particleQuality, (v) => (current.particleQuality = v as SaveSettings['particleQuality'])),
      segmented(t('settings.graphicsQuality', 'Graphics Quality'), qualityOptions, current.graphicsQuality, (v) => (current.graphicsQuality = v as SaveSettings['graphicsQuality'])),
      slider(t('settings.textSize', 'Text Size'), current.textScale, 0.85, 1.3, 0.05, (v) => (current.textScale = v)),
      toggle(t('settings.highContrast', 'High Contrast'), t('settings.highContrastHint', 'Increase text and UI contrast'), current.highContrast, (v) => (current.highContrast = v)),
      toggle(t('settings.reducedMotion', 'Reduced Motion'), t('settings.reducedMotionHint', 'Minimize UI animation'), current.reducedMotion, (v) => (current.reducedMotion = v)),
      el('div', { class: 'settings-row' }, [
        el('label', {}, [t('settings.fullscreen', 'Fullscreen')]),
        el('button', {
          class: 'btn small',
          onClick: () => {
            if (document.fullscreenElement) document.exitFullscreen();
            else document.documentElement.requestFullscreen().catch(() => undefined);
          },
        }, [t('settings.toggle', 'Toggle')]),
      ]),
    ]);

    const panel = el('div', { class: `screen-panel${embedded ? '' : ' panel pop-in'}` }, [
      el('div', { class: 'screen-title' }, [t('menu.settings', 'Settings')]),
      body,
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: callbacks.onClose }, [t('settings.done', 'Done')])]),
    ]);

    this.root = embedded ? panel : el('div', { class: 'screen-overlay modal-backdrop fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

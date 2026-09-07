import { el } from '@/ui/dom';
import type { SaveSettings } from '@/progression/SaveSystem';

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

    const segmented = (label: string, options: string[], value: string, onPick: (v: string) => void) => {
      const buttons = options.map((opt) =>
        el('button', {
          class: opt === value ? 'active' : '',
          onClick: (e: MouseEvent) => {
            onPick(opt);
            emit();
            const parent = (e.target as HTMLElement).parentElement!;
            parent.querySelectorAll('button').forEach((b) => b.classList.remove('active'));
            (e.target as HTMLElement).classList.add('active');
          },
        }, [opt])
      );
      return el('div', { class: 'settings-row' }, [
        el('label', {}, [label]),
        el('div', { class: 'segmented' }, buttons),
      ]);
    };

    const body = el('div', { class: 'button-column' }, [
      slider('Master Volume', current.masterVolume, 0, 1, 0.01, (v) => (current.masterVolume = v)),
      slider('Music Volume', current.musicVolume, 0, 1, 0.01, (v) => (current.musicVolume = v)),
      slider('SFX Volume', current.sfxVolume, 0, 1, 0.01, (v) => (current.sfxVolume = v)),
      toggle('Mute All', 'Silence all audio output', current.muted, (v) => (current.muted = v)),
      toggle('Screen Shake', 'Camera shake on heavy impacts', current.screenShake, (v) => (current.screenShake = v)),
      segmented('Particles', ['low', 'medium', 'high'], current.particleQuality, (v) => (current.particleQuality = v as SaveSettings['particleQuality'])),
      segmented('Graphics Quality', ['low', 'medium', 'high'], current.graphicsQuality, (v) => (current.graphicsQuality = v as SaveSettings['graphicsQuality'])),
      slider('Text Size', current.textScale, 0.85, 1.3, 0.05, (v) => (current.textScale = v)),
      toggle('High Contrast', 'Increase text and UI contrast', current.highContrast, (v) => (current.highContrast = v)),
      toggle('Reduced Motion', 'Minimize UI animation', current.reducedMotion, (v) => (current.reducedMotion = v)),
      el('div', { class: 'settings-row' }, [
        el('label', {}, ['Fullscreen']),
        el('button', {
          class: 'btn small',
          onClick: () => {
            if (document.fullscreenElement) document.exitFullscreen();
            else document.documentElement.requestFullscreen().catch(() => undefined);
          },
        }, ['Toggle']),
      ]),
    ]);

    const panel = el('div', { class: `screen-panel${embedded ? '' : ' panel pop-in'}` }, [
      el('div', { class: 'screen-title' }, ['Settings']),
      body,
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: callbacks.onClose }, ['Done'])]),
    ]);

    this.root = embedded ? panel : el('div', { class: 'screen-overlay modal-backdrop fade-screen' }, [panel]);
    container.appendChild(this.root);
  }

  destroy(): void {
    this.root.remove();
  }
}

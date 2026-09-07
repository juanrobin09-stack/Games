import { el } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import type { Player } from '@/entities/Player';
import type { RunState } from '@/progression/RunState';
import { formatNumber, formatTime, clamp } from '@/utils/MathUtils';
import type { UpgradeIconId } from '@/data/types';

export interface BossHudInfo {
  name: string;
  hpRatio: number;
  phase: number;
  maxPhase: number;
  invulnerable: boolean;
}

export interface HudFrameData {
  player: Player;
  embers: number;
  zoneName: string;
  roomLabel: string;
  corruption: number;
  weaponName: string;
  abilityName: string;
  abilityIcon: UpgradeIconId;
  interactPrompt: string | null;
  boss: BossHudInfo | null;
  elapsedSeconds: number;
}

export class HUD {
  private root: HTMLElement;
  private hpFill!: HTMLElement;
  private hpLabel!: HTMLElement;
  private shieldRow!: HTMLElement;
  private buffRow!: HTMLElement;
  private energyFill!: HTMLElement;
  private energyLabel!: HTMLElement;
  private embersText!: HTMLElement;
  private zoneLabel!: HTMLElement;
  private corruptionFill!: HTMLElement;
  private minimapEl!: HTMLElement;
  private abilitySweep!: HTMLElement;
  private abilityIconEl!: HTMLElement;
  private weaponNameEl!: HTMLElement;
  private abilityNameEl!: HTMLElement;
  private interactPromptEl!: HTMLElement;
  private bossBar!: HTMLElement;
  private bossFill!: HTMLElement;
  private bossName!: HTMLElement;
  private bossDots!: HTMLElement;
  private toastArea!: HTMLElement;
  private phaseBanner!: HTMLElement;
  private synergyBanner!: HTMLElement;
  private timerLabel!: HTMLElement;
  private toastTimers: number[] = [];

  constructor(container: HTMLElement) {
    this.root = this.build();
    container.appendChild(this.root);
  }

  private build(): HTMLElement {
    this.hpFill = el('div', { class: 'hud-bar-fill hp' });
    this.hpLabel = el('div', { class: 'hud-bar-label' });
    this.shieldRow = el('div', { class: 'hud-shields' });
    this.buffRow = el('div', { class: 'hud-buffs' });
    this.energyFill = el('div', { class: 'hud-bar-fill energy' });
    this.energyLabel = el('div', { class: 'hud-bar-label' });
    this.embersText = el('span', {}, ['0']);
    this.zoneLabel = el('div', { class: 'hud-zone-label' }, ['—']);
    this.corruptionFill = el('div', { class: 'hud-corruption-fill' });
    this.minimapEl = el('div', { class: 'hud-minimap' });
    this.abilitySweep = el('div', { class: 'cooldown-sweep' });
    this.abilityIconEl = el('div', { html: iconSvg('ability', 22) });
    this.weaponNameEl = el('span', { class: 'name' }, ['Ember Blade']);
    this.abilityNameEl = el('span', { class: 'name' }, ['Ember Burst']);
    this.interactPromptEl = el('div', { class: 'hud-interact-prompt' });
    this.bossFill = el('div', { class: 'hud-bar-fill boss' });
    this.bossName = el('div', { class: 'hud-boss-name' }, ['???']);
    this.bossDots = el('div', { class: 'hud-boss-phase-dots' });
    this.toastArea = el('div', { class: 'hud-toast-area' });
    this.phaseBanner = el('div', { class: 'hud-phase-banner' });
    this.synergyBanner = el('div', { class: 'hud-synergy-banner' });
    this.timerLabel = el('span', {}, ['0:00']);

    this.bossBar = el('div', { class: 'hud-boss-bar' }, [
      this.bossName,
      el('div', { class: 'hud-bar-track' }, [this.bossFill]),
      this.bossDots,
    ]);

    const topLeft = el('div', { class: 'hud-top-left' }, [
      el('div', { class: 'hud-bar-row' }, [
        el('div', { class: 'hud-bar-icon', html: iconSvg('heart', 16) }),
        el('div', { class: 'hud-bar-track' }, [this.hpFill, this.hpLabel]),
        this.shieldRow,
      ]),
      el('div', { class: 'hud-bar-row' }, [
        el('div', { class: 'hud-bar-icon', html: iconSvg('ability', 16) }),
        el('div', { class: 'hud-bar-track' }, [this.energyFill, this.energyLabel]),
      ]),
      this.buffRow,
    ]);

    const topRight = el('div', { class: 'hud-top-right' }, [
      el('div', { class: 'hud-embers' }, [el('span', { html: iconSvg('ember', 16) }), this.embersText]),
      el('div', { class: 'hud-zone-label' }, [this.timerLabel]),
      this.zoneLabel,
      el('div', { class: 'hud-corruption' }, [this.corruptionFill]),
      this.minimapEl,
    ]);

    const bottomLeft = el('div', { class: 'hud-bottom-left' }, [
      el('div', { class: 'hud-ability-slot' }, [this.abilityIconEl, this.abilitySweep, el('span', { class: 'key-hint' }, ['RMB'])]),
      el('div', { class: 'button-column', style: 'gap:4px;' }, [
        el('div', { class: 'hud-weapon-slot' }, [el('span', { html: iconSvg('blade', 14) }), this.weaponNameEl]),
        el('div', { class: 'hud-weapon-slot' }, [el('span', { html: iconSvg('ember', 14) }), this.abilityNameEl]),
      ]),
    ]);

    return el('div', { class: 'hud' }, [
      topLeft,
      topRight,
      bottomLeft,
      this.interactPromptEl,
      this.bossBar,
      this.toastArea,
      this.phaseBanner,
      this.synergyBanner,
    ]);
  }

  refreshMinimap(runState: RunState): void {
    const layout = runState.currentLayout;
    const rooms = Array.from(layout.rooms.values());
    let minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (const r of rooms) {
      minX = Math.min(minX, r.gridX);
      maxX = Math.max(maxX, r.gridX);
      minY = Math.min(minY, r.gridY);
      maxY = Math.max(maxY, r.gridY);
    }
    const cols = maxX - minX + 1;
    const rows = maxY - minY + 1;
    this.minimapEl.style.gridTemplateColumns = `repeat(${cols}, 12px)`;
    this.minimapEl.style.gridTemplateRows = `repeat(${rows}, 12px)`;
    this.minimapEl.innerHTML = '';
    const byPos = new Map<string, (typeof rooms)[number]>();
    for (const r of rooms) byPos.set(`${r.gridX - minX},${r.gridY - minY}`, r);
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        const room = byPos.get(`${x},${y}`);
        if (!room) {
          this.minimapEl.appendChild(el('div', { class: 'hud-minimap-cell empty' }));
          continue;
        }
        const isCurrent = room.key === runState.currentRoomKey;
        const cls = ['hud-minimap-cell'];
        if (room.visited) cls.push('visited');
        if (isCurrent) cls.push('current');
        const cell = el('div', { class: cls.join(' ') });
        if (room.visited || isCurrent) {
          const tint: Record<string, string> = {
            chest: '#f2b53d',
            shop: '#6fc3d9',
            elite: '#e74c3c',
            heart: '#9b7ed9',
            boss: '#c0392b',
            event: '#7dd35a',
            rest: '#ffab54',
          };
          if (tint[room.type]) cell.style.background = tint[room.type];
        }
        this.minimapEl.appendChild(cell);
      }
    }
  }

  showToast(text: string, durationMs = 4200): void {
    const toast = el('div', { class: 'hud-toast', html: text });
    this.toastArea.appendChild(toast);
    const fadeTimer = window.setTimeout(() => {
      toast.style.transition = 'opacity 0.4s ease';
      toast.style.opacity = '0';
      const removeTimer = window.setTimeout(() => toast.remove(), 420);
      this.toastTimers.push(removeTimer);
    }, durationMs);
    this.toastTimers.push(fadeTimer);
  }

  showPhaseBanner(text: string): void {
    this.phaseBanner.textContent = text;
    this.phaseBanner.classList.remove('showing');
    void this.phaseBanner.offsetWidth;
    this.phaseBanner.classList.add('showing');
  }

  showSynergyBanner(name: string, description: string): void {
    this.synergyBanner.innerHTML = '';
    this.synergyBanner.appendChild(el('div', { class: 'synergy-label' }, ['Synergy Formed']));
    this.synergyBanner.appendChild(el('div', { class: 'synergy-name' }, [name]));
    this.synergyBanner.appendChild(el('div', { class: 'synergy-desc' }, [description]));
    this.synergyBanner.classList.remove('showing');
    void this.synergyBanner.offsetWidth;
    this.synergyBanner.classList.add('showing');
  }

  update(data: HudFrameData): void {
    const hpRatio = clamp(data.player.hp / Math.max(1, data.player.stats.maxHp), 0, 1);
    this.hpFill.style.transform = `scaleX(${hpRatio})`;
    this.hpLabel.textContent = `${Math.ceil(data.player.hp)} / ${Math.ceil(data.player.stats.maxHp)}`;

    this.shieldRow.innerHTML = '';
    for (let i = 0; i < data.player.shieldCharges; i++) {
      this.shieldRow.appendChild(el('div', { class: 'hud-shield-pip' }));
    }

    const energyRatio = clamp(data.player.energy / Math.max(1, data.player.stats.energyMax), 0, 1);
    this.energyFill.style.transform = `scaleX(${energyRatio})`;
    this.energyLabel.textContent = `${Math.floor(data.player.energy)}`;

    this.buffRow.innerHTML = '';
    if (data.player.perfectDodgeTimer > 0) this.buffRow.appendChild(this.buffIcon('dodge'));
    if (data.player.hasSynergy('wrath') && data.player.hp / data.player.stats.maxHp < 0.4) this.buffRow.appendChild(this.buffIcon('critDamage'));
    if (data.player.wardingSigilActive) this.buffRow.appendChild(this.buffIcon('shield'));

    this.embersText.textContent = formatNumber(data.embers);
    this.zoneLabel.textContent = `${data.zoneName} · ${data.roomLabel}`;
    this.timerLabel.textContent = formatTime(data.elapsedSeconds);
    this.corruptionFill.style.width = `${Math.round(data.corruption * 100)}%`;

    const abilityCooldownRatio =
      data.player.ability.cooldown > 0 ? clamp(data.player.abilityCooldownTimer / data.player.ability.cooldown, 0, 1) : 0;
    this.abilitySweep.style.transform = `scaleY(${abilityCooldownRatio})`;
    if (this.abilityIconEl.dataset.icon !== data.abilityIcon) {
      this.abilityIconEl.innerHTML = iconSvg(data.abilityIcon, 22);
      this.abilityIconEl.dataset.icon = data.abilityIcon;
    }
    this.weaponNameEl.textContent = data.weaponName;
    this.abilityNameEl.textContent = data.abilityName;

    if (data.interactPrompt) {
      this.interactPromptEl.innerHTML = `<kbd>E</kbd>${data.interactPrompt}`;
      this.interactPromptEl.classList.add('visible');
    } else {
      this.interactPromptEl.classList.remove('visible');
    }

    if (data.boss) {
      this.bossBar.classList.add('visible');
      this.bossName.textContent = data.boss.name;
      this.bossFill.style.transform = `scaleX(${clamp(data.boss.hpRatio, 0, 1)})`;
      this.bossDots.innerHTML = '';
      for (let i = 0; i < data.boss.maxPhase; i++) {
        const dot = el('div', { class: 'dot' + (i < data.boss.maxPhase - data.boss.phase + 1 ? ' active' : '') });
        this.bossDots.appendChild(dot);
      }
    } else {
      this.bossBar.classList.remove('visible');
    }
  }

  private buffIcon(icon: UpgradeIconId): HTMLElement {
    return el('div', { class: 'hud-buff-icon', html: iconSvg(icon, 13) });
  }

  setVisible(visible: boolean): void {
    this.root.style.display = visible ? '' : 'none';
  }

  destroy(): void {
    this.toastTimers.forEach((id) => window.clearTimeout(id));
    this.toastTimers.length = 0;
    this.root.remove();
  }
}

import { el, clear } from '@/ui/dom';
import { iconSvg } from '@/ui/icons';
import type { RunState } from '@/progression/RunState';
import type { Player } from '@/entities/Player';
import { PLAYER_STATS, type PlayerStatId } from '@/data/playerProgression';
import { SYNERGIES } from '@/data/synergies';
import { playSfx } from '@/audio/SoundFactory';
import { t, tc } from '@/i18n';

export type InventoryTab = 'character' | 'build';

export interface InventoryCallbacks {
  /** Attempts to spend one point on `statId`; returns whether it succeeded. */
  onSpend: (statId: PlayerStatId) => boolean;
  onClose: () => void;
}

/**
 * The character sheet: Player Level/XP and the 7 stat-point rows (opened
 * directly with the I key), plus the upgrades-collected-this-run view that
 * used to live in PauseMenu's "Your Build" — one screen, reached from either
 * entry point, so there's a single place that ever renders this data.
 */
export class InventoryUI {
  root: HTMLElement;
  private tab: InventoryTab;

  constructor(container: HTMLElement, private run: RunState, private player: Player, private callbacks: InventoryCallbacks, initialTab: InventoryTab = 'character') {
    this.tab = initialTab;
    this.root = el('div', { class: 'screen-overlay modal-backdrop fade-screen' });
    container.appendChild(this.root);
    this.render();
  }

  private switchTab(tab: InventoryTab): void {
    if (this.tab === tab) return;
    this.tab = tab;
    playSfx('uiClick');
    this.render();
  }

  private render(): void {
    clear(this.root);
    const tabRow = el('div', { class: 'tab-row' }, [
      el('button', { class: this.tab === 'character' ? 'active' : '', onClick: () => this.switchTab('character') }, [t('inventory.tabCharacter', 'Character')]),
      el('button', { class: this.tab === 'build' ? 'active' : '', onClick: () => this.switchTab('build') }, [t('inventory.tabBuild', 'Build')]),
    ]);

    const panel = el('div', { class: 'screen-panel wide panel pop-in' }, [
      el('div', { class: 'screen-title' }, [t('inventory.title', 'Character')]),
      tabRow,
      this.tab === 'character' ? this.renderCharacterTab() : this.renderBuildTab(),
      el('div', { class: 'button-row' }, [el('button', { class: 'btn primary', onClick: () => this.close() }, [t('pause.back', 'Back')])]),
    ]);
    this.root.appendChild(panel);
  }

  private renderCharacterTab(): HTMLElement {
    const run = this.run;
    const xpNeeded = run.xpToNextLevel();
    const xpRatio = Math.max(0, Math.min(1, run.xp / Math.max(1, xpNeeded)));

    const header = el('div', { class: 'inventory-header' }, [
      el('div', { class: 'inventory-level' }, [`${t('inventory.player', 'PLAYER')} — ${t('inventory.levelFormat', 'Level {n}').replace('{n}', String(run.playerLevel))}`]),
      el('div', { class: 'hud-bar-track', style: 'height:14px;max-width:360px;margin:6px auto 2px;' }, [
        el('div', { class: 'hud-bar-fill xp', style: `transform:scaleX(${xpRatio});` }),
        el('div', { class: 'hud-bar-label' }, [`${Math.floor(run.xp)} / ${xpNeeded} XP`]),
      ]),
      run.statPoints > 0
        ? el('div', { class: 'inventory-points-available' }, [t('inventory.pointsAvailableFormat', '{count} stat point(s) available').replace('{count}', String(run.statPoints))])
        : null,
    ]);

    const rows = PLAYER_STATS.map((def) => {
      const level = run.statLevels[def.id];
      const perLevelText =
        def.mode === 'flat' ? `+${def.valuePerLevel} ${t(`stat.unit.${def.id}`, '')}`.trim() : `+${Math.round(def.valuePerLevel * 100)}%`;
      const canSpend = run.statPoints > 0;
      const plusBtn = el(
        'button',
        {
          class: 'btn small buy-btn',
          disabled: !canSpend,
          onClick: () => {
            if (this.callbacks.onSpend(def.id)) {
              playSfx('shopBuy');
              this.render();
            }
          },
        },
        ['+']
      );
      return el('div', { class: 'meta-node' }, [
        el('div', { class: 'icon-badge', html: iconSvg(def.icon, 20) }),
        el('div', { class: 'meta-info' }, [
          el('div', { class: 'meta-name' }, [`${t(`stat.${def.id}`, def.id)} — ${t('upgrade.level', 'Level')} ${level}`]),
          el('div', { class: 'meta-desc' }, [t('inventory.perLevelFormat', '{value} per level').replace('{value}', perLevelText)]),
        ]),
        plusBtn,
      ]);
    });

    return el('div', {}, [header, el('div', { class: 'button-column' }, rows)]);
  }

  private renderBuildTab(): HTMLElement {
    const upgradeCards = this.player.upgrades.map((owned) =>
      el('div', { class: `upgrade-card rarity-${owned.def.rarity}` }, [
        el('div', { class: 'icon-badge', html: iconSvg(owned.def.icon, 20) }),
        el('div', { class: `card-name rarity-${owned.def.rarity}` }, [`${tc(owned.def.id, 'name', owned.def.name)} — ${t('upgrade.level', 'Level')} ${owned.stacks}`]),
        el('div', { class: 'card-desc' }, [tc(owned.def.id, 'description', owned.def.description)]),
      ])
    );
    const activeSynergies = SYNERGIES.filter((s) => this.player.hasSynergy(s.id));
    const synergyRows = activeSynergies.map((s) =>
      el('div', { class: 'meta-node' }, [
        el('div', { class: 'icon-badge', html: iconSvg(s.icon, 20) }),
        el('div', { class: 'meta-info' }, [
          el('div', { class: 'meta-name', style: 'color:var(--c-soul-bright);' }, [tc(s.id, 'name', s.name)]),
          el('div', { class: 'meta-desc' }, [tc(s.id, 'description', s.description)]),
        ]),
      ])
    );
    const upgradeCountLabel = this.player.upgrades.length === 1
      ? t('pause.upgradeCountOne', '{count} upgrade collected this run')
      : t('pause.upgradeCountMany', '{count} upgrades collected this run');

    return el('div', {}, [
      el('div', { class: 'screen-subtitle' }, [
        activeSynergies.length > 0 ? t('pause.activeSynergies', 'Active synergies') : t('pause.noSynergies', 'No synergies active yet — some upgrade pairs unlock a bonus effect.'),
      ]),
      synergyRows.length > 0 ? el('div', { class: 'button-column' }, synergyRows) : null,
      el('hr', { class: 'divider' }),
      el('div', { class: 'screen-subtitle' }, [upgradeCountLabel.replace('{count}', String(this.player.upgrades.length))]),
      upgradeCards.length > 0
        ? el('div', { class: 'card-grid' }, upgradeCards)
        : el('div', { class: 'screen-body-text' }, [t('pause.noUpgrades', 'No upgrades yet — clear a room, open a chest, or visit a shop.')]),
    ]);
  }

  private close(): void {
    this.destroy();
    this.callbacks.onClose();
  }

  destroy(): void {
    this.root.remove();
  }
}

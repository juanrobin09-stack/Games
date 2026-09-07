import type { WorldEventDefinition } from '@/data/types';

export const WORLD_EVENTS: WorldEventDefinition[] = [
  {
    id: 'oldShrine',
    title: 'The Old Shrine',
    description: 'A blackened altar hums with what light remains. It offers a single blessing.',
    options: [
      {
        id: 'blessing-embers',
        label: "Ember's Bounty",
        detail: 'Gain a generous handful of Embers.',
        apply: 'gainEmbers',
        value: 45,
      },
      {
        id: 'blessing-hp',
        label: "Light's Mercy",
        detail: 'Mend your wounds completely.',
        apply: 'gainHp',
        value: 9999,
      },
    ],
  },
  {
    id: 'forgottenMerchant',
    title: 'The Forgotten Merchant',
    description: 'A hooded figure trades in things better left buried. "Everything has a price, Warden."',
    options: [
      {
        id: 'buy-upgrade-cheap',
        label: 'A Modest Charm',
        detail: 'Guaranteed upgrade, common odds. 30 Embers.',
        apply: 'gainRandomUpgrade',
        value: 0,
        cost: 30,
      },
      {
        id: 'buy-upgrade-rare',
        label: 'A Rare Relic',
        detail: 'Guaranteed rare-or-better upgrade. 70 Embers.',
        apply: 'gainRandomUpgrade',
        value: 2,
        cost: 70,
      },
      {
        id: 'leave-merchant',
        label: 'Refuse',
        detail: 'Some prices are not worth paying.',
        apply: 'nothing',
      },
    ],
  },
  {
    id: 'dyingFlame',
    title: 'The Dying Flame',
    description: 'A guttering flame offers you strength, but flame demands fuel — and you are the only fuel here.',
    options: [
      {
        id: 'sacrifice-hp',
        label: 'Offer Your Blood',
        detail: 'Lose 25% of your current HP for a rare-or-better upgrade.',
        apply: 'loseHpForRareUpgrade',
        value: 0.25,
      },
      {
        id: 'refuse-flame',
        label: 'Walk Away',
        detail: 'The flame gutters and dims. Nothing ventured.',
        apply: 'nothing',
      },
    ],
  },
  {
    id: 'theWhisper',
    title: 'The Whisper',
    description: 'Something in the dark speaks your name. It knows what you carry. It wants to play a game.',
    options: [
      {
        id: 'gamble-embers',
        label: 'Wager Your Embers',
        detail: 'Coin flip: double your Embers, or lose half.',
        apply: 'gambleEmbers',
      },
      {
        id: 'ignore-whisper',
        label: 'Ignore It',
        detail: 'Some voices are best left unanswered. Small Ember gain.',
        apply: 'gainEmbers',
        value: 15,
      },
    ],
  },
  {
    id: 'emberWell',
    title: 'The Ember Well',
    description: 'A well sunk deep into the dark, glowing faintly. Embers dropped here do not return — but the well remembers.',
    options: [
      {
        id: 'feed-well',
        label: 'Feed the Well',
        detail: 'Spend 40 Embers to draw a measure of Soul Ash, kept even if you fall.',
        apply: 'gainSoulAshNow',
        value: 18,
        cost: 40,
      },
      {
        id: 'leave-well',
        label: 'Leave It Be',
        detail: 'The well can wait. So can you.',
        apply: 'nothing',
      },
    ],
  },
];

export function getWorldEvent(id: string): WorldEventDefinition {
  const def = WORLD_EVENTS.find((e) => e.id === id);
  if (!def) throw new Error(`Unknown event: ${id}`);
  return def;
}

import type { KeyboardEvent } from 'react';

function cardsIn(row: Element) {
  return Array.from(row.querySelectorAll<HTMLElement>('[data-card]'));
}

function focusCard(card: HTMLElement) {
  card.focus({ preventScroll: true });
  card.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
}

/** The card whose centre is closest to `x`, among those in this row. */
function nearestCard(cards: HTMLElement[], x: number) {
  let best: HTMLElement | undefined;
  let bestDistance = Infinity;
  for (const card of cards) {
    const rect = card.getBoundingClientRect();
    const distance = Math.abs(rect.left + rect.width / 2 - x);
    if (distance < bestDistance) {
      best = card;
      bestDistance = distance;
    }
  }
  return best;
}

/**
 * Arrow keys for a row marked `data-card-row`: left and right within it, up and down
 * to the nearest card of the neighbouring row. Return is handled by the card itself.
 */
export function handleRowKeyDown(event: KeyboardEvent<HTMLElement>) {
  if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) return;
  const current = (event.target as HTMLElement).closest<HTMLElement>('[data-card]');
  if (!current) return;
  const row = event.currentTarget;

  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    const cards = cardsIn(row);
    const next = cards[cards.indexOf(current) + (event.key === 'ArrowRight' ? 1 : -1)];
    if (next) {
      event.preventDefault();
      focusCard(next);
    }
    return;
  }

  const rows = Array.from(document.querySelectorAll('[data-card-row]'));
  const target = rows[rows.indexOf(row) + (event.key === 'ArrowDown' ? 1 : -1)];
  if (!target) return;
  const rect = current.getBoundingClientRect();
  const next = nearestCard(cardsIn(target), rect.left + rect.width / 2);
  if (next) {
    event.preventDefault();
    focusCard(next);
  }
}

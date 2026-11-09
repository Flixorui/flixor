import { Dimensions } from 'react-native';

const NOTIFY_STEP = 64;
/** Rows start loading this far below the fold. */
const PREBUFFER_SCREENS = 0.5;

/** Home's scroll position, watched by rows that load themselves when they come near. */
export class HomeViewport {
  private offset = 0;
  private lastNotified = 0;
  /** Where the row list starts inside the scroll content. */
  private contentY = 0;
  private listeners = new Set<() => void>();

  setOffset(offset: number): void {
    this.offset = offset;
    if (Math.abs(offset - this.lastNotified) < NOTIFY_STEP) return;
    this.lastNotified = offset;
    this.notify();
  }

  setContentY(y: number): void {
    this.contentY = y;
    this.notify();
  }

  /** `rowY` is relative to the row list. */
  isNear(rowY: number): boolean {
    const height = Dimensions.get('window').height;
    return this.contentY + rowY <= this.offset + height * (1 + PREBUFFER_SCREENS);
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private notify(): void {
    this.listeners.forEach((listener) => listener());
  }
}

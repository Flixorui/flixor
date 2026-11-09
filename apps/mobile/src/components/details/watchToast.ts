import { showToast } from '../Toast';
import type { WatchStateResult } from '../../core/WatchState';

export function didFail(result: WatchStateResult): boolean {
  return !result.noChanges && !result.isSuccess && !result.isPartialSuccess;
}

export function showWatchToast(result: WatchStateResult): void {
  showToast(result.message, {
    kind: result.isSuccess ? 'success' : result.isPartialSuccess || result.noChanges ? 'info' : 'error',
  });
}

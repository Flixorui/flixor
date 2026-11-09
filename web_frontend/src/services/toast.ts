export type ToastType = 'success' | 'error' | 'info';

export type ToastDetail = {
  message: string;
  type?: ToastType;
  /** Milliseconds before the toast closes. Defaults to 3000. */
  duration?: number;
};

/** Shows an app-wide toast. Rendered by components/GlobalToast. */
export function showToast(message: string, type: ToastType = 'info', duration?: number) {
  window.dispatchEvent(new CustomEvent<ToastDetail>('app-toast', { detail: { message, type, duration } }));
}

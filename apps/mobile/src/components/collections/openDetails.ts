/**
 * Opens Details from a screen that can sit in more than one stack. The Settings stack
 * has no Details route, so from there it opens on the Home tab.
 */
export function openDetails(nav: any, params: Record<string, unknown>): void {
  const routeNames: string[] = nav.getState?.()?.routeNames ?? [];
  if (routeNames.includes('Details')) {
    nav.navigate('Details', params);
  } else {
    nav.navigate('HomeTab', { screen: 'Details', params });
  }
}

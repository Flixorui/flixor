/**
 * Runs a user's include pattern off the main thread. JavaScript regexes cannot be
 * interrupted, so the only way to stop a runaway pattern is to terminate this worker.
 */
self.onmessage = (event: MessageEvent<{ pattern: string; texts: string[] }>) => {
  const { pattern, texts } = event.data;
  const regex = new RegExp(pattern, 'i');
  self.postMessage(texts.map((text) => regex.test(text)));
};

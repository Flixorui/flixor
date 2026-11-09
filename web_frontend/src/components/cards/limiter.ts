/** Runs at most `concurrency` of the given tasks at once. */
export function createLimiter(concurrency: number) {
  let active = 0;
  const queue: Array<() => void> = [];

  const release = () => {
    active -= 1;
    queue.shift()?.();
  };

  return function limit<T>(task: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const start = () => {
        active += 1;
        task().then(resolve, reject).finally(release);
      };
      if (active < concurrency) start();
      else queue.push(start);
    });
  };
}

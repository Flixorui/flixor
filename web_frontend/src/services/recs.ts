// Simple deterministic re-ranker placeholder combining metadata scores.
export type Candidate = { id: string; title: string; genres?: string[]; cast?: string[]; popularity?: number };
export type Context = { likedGenres?: string[]; likedCast?: string[] };

export function rerank(candidates: Candidate[], ctx: Context): Candidate[] {
  const likedGenres = new Set(ctx.likedGenres || []);
  const likedCast = new Set(ctx.likedCast || []);
  return candidates
    .map((c) => {
      const genreScore = (c.genres || []).reduce((s, g) => s + (likedGenres.has(g) ? 1 : 0), 0);
      const castScore = (c.cast || []).reduce((s, p) => s + (likedCast.has(p) ? 1 : 0), 0);
      const pop = c.popularity || 0;
      const score = genreScore * 2 + castScore * 3 + pop * 0.1;
      return { ...c, score } as Candidate & { score: number };
    })
    .sort((a, b) => (b as any).score - (a as any).score)
    .map(({ score, ...rest }) => rest);
}


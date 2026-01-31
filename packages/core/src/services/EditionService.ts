/**
 * Edition title extraction (top-level or Media[0]).
 * Matches FlixorKit EditionService logic.
 */

export class EditionService {
  static extractEditionTitle(
    topLevelEdition: string | undefined,
    media: { editionTitle?: string }[] | undefined
  ): string | undefined {
    if (topLevelEdition?.trim()) {
      return topLevelEdition;
    }
    const firstMediaEdition = media?.[0]?.editionTitle;
    if (firstMediaEdition?.trim()) {
      return firstMediaEdition;
    }
    return undefined;
  }
}

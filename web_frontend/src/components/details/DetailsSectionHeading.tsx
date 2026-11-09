import type { ReactNode } from 'react';

/** Left edge of every heading and row. Matches the hero through `--page-gutter`. */
export const DETAILS_SECTION_INSET = 'page-gutter';

/** One heading style for every section of the details page. */
export default function DetailsSectionHeading({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <h2 className={`text-[22px] leading-7 font-bold text-white truncate ${className}`}>{children}</h2>;
}

/** Horizontal row that starts on the section's left edge and scrolls out to the page edges. */
export function DetailsHorizontalRow({ children, gapClass = 'gap-3' }: { children: ReactNode; gapClass?: string }) {
  return (
    <div className="row-edge overflow-x-auto no-scrollbar">
      <div className={`flex w-max ${gapClass}`}>{children}</div>
    </div>
  );
}

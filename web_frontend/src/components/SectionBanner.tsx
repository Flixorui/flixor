import { Link } from 'react-router-dom';

export default function SectionBanner({ title, message, cta, to }: { title?: string; message: string; cta: string; to: string }) {
  return (
    <section className="py-2 my-5">
      <div className="row-band bleed">
        <div className="page-gutter py-6 flex items-center justify-between gap-4">
          <div>
            {title && <h3 className="text-neutral-200 font-semibold mb-1">{title}</h3>}
            <p className="text-neutral-300">{message}</p>
          </div>
          <Link to={to} className="px-4 py-2 rounded-md bg-white text-black font-semibold shadow hover:bg-neutral-100">{cta}</Link>
        </div>
      </div>
    </section>
  );
}


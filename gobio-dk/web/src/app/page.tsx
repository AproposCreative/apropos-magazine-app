import Link from "next/link";

const DANISH_CITIES = [
  "København",
  "Aarhus",
  "Odense",
  "Aalborg",
  "Esbjerg",
  "Randers",
  "Kolding",
  "Horsens",
  "Vejle",
  "Roskilde",
  "Herning",
  "Silkeborg",
  "Næstved",
  "Fredericia",
];

export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-50 border-b border-white/10 bg-surface/80 backdrop-blur-lg">
        <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4">
          <Link href="/" className="text-2xl font-bold text-primary-light">
            gobio<span className="text-accent">.dk</span>
          </Link>

          <nav className="hidden items-center gap-6 md:flex">
            <Link
              href="/movies"
              className="text-text-secondary transition-colors hover:text-text-primary"
            >
              Film
            </Link>
            <Link
              href="/cinemas"
              className="text-text-secondary transition-colors hover:text-text-primary"
            >
              Biografer
            </Link>
            <Link
              href="/login"
              className="rounded-lg bg-primary px-4 py-2 font-medium text-white transition-colors hover:bg-primary-dark"
            >
              Log ind
            </Link>
          </nav>
        </div>
      </header>

      <section className="flex flex-1 flex-col items-center justify-center px-4 py-20 text-center">
        <h1 className="mb-4 text-5xl font-extrabold leading-tight tracking-tight md:text-7xl">
          Alle biografer.
          <br />
          <span className="text-primary-light">Ét sted.</span>
        </h1>

        <p className="mb-8 max-w-2xl text-lg text-text-secondary md:text-xl">
          Se spilletider fra Nordisk Film, Vue og alle danske biografer samlet
          ét sted. Find din film, se traileren og bestil billetter direkte hos
          biografen.
        </p>

        <div className="mb-12 flex flex-col gap-4 sm:flex-row">
          <Link
            href="/movies"
            className="rounded-xl bg-primary px-8 py-4 text-lg font-semibold text-white shadow-lg shadow-primary/25 transition-all hover:bg-primary-dark hover:shadow-xl hover:shadow-primary/30"
          >
            Se aktuelle film
          </Link>
          <Link
            href="/movies?tab=upcoming"
            className="rounded-xl border border-white/20 px-8 py-4 text-lg font-semibold text-text-primary transition-all hover:bg-white/5"
          >
            Kommer snart
          </Link>
        </div>

        <div className="flex flex-wrap justify-center gap-2">
          {DANISH_CITIES.slice(0, 8).map((city) => (
            <span
              key={city}
              className="rounded-full bg-white/5 px-3 py-1 text-sm text-text-muted"
            >
              {city}
            </span>
          ))}
        </div>
      </section>

      <section className="border-t border-white/10 bg-surface-light py-20">
        <div className="mx-auto max-w-7xl px-4">
          <h2 className="mb-12 text-center text-3xl font-bold">
            Hvordan virker det?
          </h2>

          <div className="grid gap-8 md:grid-cols-3">
            <div className="rounded-2xl bg-surface-card/50 p-8 text-center">
              <div className="mb-4 text-4xl">🔍</div>
              <h3 className="mb-2 text-xl font-semibold">Find din film</h3>
              <p className="text-text-secondary">
                Søg eller browse i aktuelle og kommende biograffilm med
                trailers og anmeldelser.
              </p>
            </div>

            <div className="rounded-2xl bg-surface-card/50 p-8 text-center">
              <div className="mb-4 text-4xl">🎬</div>
              <h3 className="mb-2 text-xl font-semibold">
                Se alle spilletider
              </h3>
              <p className="text-text-secondary">
                Sammenlign spilletider fra alle biografer i din by - Nordisk
                Film, Vue og mange flere.
              </p>
            </div>

            <div className="rounded-2xl bg-surface-card/50 p-8 text-center">
              <div className="mb-4 text-4xl">🎟️</div>
              <h3 className="mb-2 text-xl font-semibold">Bestil billetter</h3>
              <p className="text-text-secondary">
                Tryk bestil og bliv sendt direkte til biografens hjemmeside.
                Nemt og hurtigt.
              </p>
            </div>
          </div>
        </div>
      </section>

      <footer className="border-t border-white/10 py-8">
        <div className="mx-auto max-w-7xl px-4 text-center text-sm text-text-muted">
          <p>
            &copy; {new Date().getFullYear()} Gobio.dk - Din danske
            biografguide
          </p>
          <p className="mt-1">
            This product uses the TMDB API but is not endorsed or certified by
            TMDB.
          </p>
        </div>
      </footer>
    </main>
  );
}

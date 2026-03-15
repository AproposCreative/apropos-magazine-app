/**
 * Nordisk Film Biografer (nfbio.dk) scraper
 *
 * Scrapes showtime data from Denmark's largest cinema chain.
 * The site uses dynamic rendering, so we use Playwright for scraping.
 *
 * Target URLs:
 * - https://www.nfbio.dk/se-alle-aktuelle-film-her?city={city}
 * - https://www.nfbio.dk/film/{film-slug}
 * - https://new.nfbio.dk/ (newer version of the site)
 *
 * Strategy:
 * 1. Load the "all movies" page for each city
 * 2. Extract film list with showtime links
 * 3. For each film, extract showtime data per cinema
 * 4. Build booking URLs for redirect
 */

export interface ScrapedShowtime {
  movieTitle: string;
  cinemaName: string;
  city: string;
  startsAt: string;
  format: string | null;
  language: string | null;
  subtitles: string | null;
  is3d: boolean;
  isImax: boolean;
  bookingUrl: string;
  source: "nfbio";
}

const NFBIO_CITIES = [
  "storkobenhavn",
  "aalborg",
  "aarhus",
  "esbjerg",
  "herning",
  "holstebro",
  "horsens",
  "kolding",
  "naestved",
  "odense",
  "randers",
  "roskilde",
  "silkeborg",
  "viborg",
];

export async function scrapeNordiskFilm(): Promise<number> {
  // TODO: Implement actual scraping with Playwright
  // This is a placeholder that outlines the scraping strategy

  console.log("  NFBio scraper: Not yet implemented (placeholder)");
  console.log(`  Would scrape ${NFBIO_CITIES.length} cities from nfbio.dk`);

  /*
  Implementation plan:

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();

  for (const city of NFBIO_CITIES) {
    const page = await context.newPage();
    await page.goto(`https://www.nfbio.dk/se-alle-aktuelle-film-her?city=${city}`);
    await page.waitForSelector('.film-card');

    const films = await page.$$eval('.film-card', cards => {
      return cards.map(card => ({
        title: card.querySelector('.film-title')?.textContent,
        href: card.querySelector('a')?.href,
      }));
    });

    for (const film of films) {
      // Navigate to film page and extract showtimes
      // Parse cinema name, times, formats from the showtime grid
    }
  }

  await browser.close();
  */

  return 0;
}

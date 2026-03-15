/**
 * Gobio.dk Showtime Scraper
 *
 * This is the entry point for the scraping pipeline that collects
 * showtime data from Danish cinema websites.
 *
 * The scraper runs on a schedule (cron) and updates the database
 * with the latest showtimes.
 *
 * Data flow:
 * 1. Scrape showtime data from cinema websites
 * 2. Match movies with TMDB data
 * 3. Upsert showtimes into database
 * 4. Clean up expired showtimes
 */

import { scrapeNordiskFilm } from "./sources/nfbio.js";
import { scrapeVue } from "./sources/vue.js";

interface ScraperResult {
  source: string;
  showtimesCount: number;
  errors: string[];
  duration: number;
}

async function runAllScrapers(): Promise<ScraperResult[]> {
  console.log("Starting Gobio.dk scraper pipeline...");
  const startTime = Date.now();

  const results: ScraperResult[] = [];

  const scrapers = [
    { name: "Nordisk Film Biografer", fn: scrapeNordiskFilm },
    { name: "Vue", fn: scrapeVue },
  ];

  for (const scraper of scrapers) {
    const scraperStart = Date.now();
    try {
      console.log(`\nScraping ${scraper.name}...`);
      const count = await scraper.fn();
      results.push({
        source: scraper.name,
        showtimesCount: count,
        errors: [],
        duration: Date.now() - scraperStart,
      });
      console.log(`  ${scraper.name}: ${count} showtimes in ${Date.now() - scraperStart}ms`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      results.push({
        source: scraper.name,
        showtimesCount: 0,
        errors: [message],
        duration: Date.now() - scraperStart,
      });
      console.error(`  ${scraper.name} failed: ${message}`);
    }
  }

  const totalDuration = Date.now() - startTime;
  const totalShowtimes = results.reduce((sum, r) => sum + r.showtimesCount, 0);

  console.log(`\nScraping complete: ${totalShowtimes} total showtimes in ${totalDuration}ms`);
  return results;
}

runAllScrapers().catch(console.error);

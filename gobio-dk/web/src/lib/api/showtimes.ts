/**
 * International Showtimes API client.
 * Docs: https://api.internationalshowtimes.com
 *
 * This module is a placeholder for the showtimes data integration.
 * In production, it will connect to the International Showtimes API
 * or use data from our scraping pipeline.
 */

const SHOWTIMES_API_BASE = "https://api.internationalshowtimes.com/v4";

function getApiKey(): string {
  const key = process.env.SHOWTIMES_API_KEY;
  if (!key) throw new Error("SHOWTIMES_API_KEY environment variable is required");
  return key;
}

async function showtimesFetch<T>(path: string, params?: Record<string, string>): Promise<T> {
  const url = new URL(`${SHOWTIMES_API_BASE}${path}`);
  url.searchParams.set("countries", "DK");
  if (params) {
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));
  }

  const response = await fetch(url.toString(), {
    headers: {
      "X-API-Key": getApiKey(),
    },
    next: { revalidate: 7200 },
  });

  if (!response.ok) {
    throw new Error(`Showtimes API error: ${response.status} ${response.statusText}`);
  }

  return response.json();
}

export interface ShowtimesApiCinema {
  id: string;
  name: string;
  city: { name: string };
  chain?: { name: string };
  location: { lat: number; lon: number; address: { display_text: string } };
  website?: string;
  telephone?: string;
}

export interface ShowtimesApiShowtime {
  id: string;
  cinema_id: string;
  movie_id: string;
  start_at: string;
  language?: string;
  subtitle_language?: string;
  auditorium?: string;
  is_3d: boolean;
  is_imax: boolean;
  booking_link?: string;
}

export async function getCinemas(city?: string): Promise<{ cinemas: ShowtimesApiCinema[] }> {
  const params: Record<string, string> = {};
  if (city) params.search_query = city;
  return showtimesFetch("/cinemas", params);
}

export async function getShowtimesByMovie(
  movieId: string,
  city?: string,
  date?: string
): Promise<{ showtimes: ShowtimesApiShowtime[] }> {
  const params: Record<string, string> = { movie_id: movieId };
  if (city) params.search_query = city;
  if (date) params.time_from = date;
  return showtimesFetch("/showtimes", params);
}

export async function getShowtimesByCinema(
  cinemaId: string,
  date?: string
): Promise<{ showtimes: ShowtimesApiShowtime[] }> {
  const params: Record<string, string> = { cinema_id: cinemaId };
  if (date) params.time_from = date;
  return showtimesFetch("/showtimes", params);
}

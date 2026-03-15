const TMDB_BASE_URL = "https://api.themoviedb.org/3";
const TMDB_IMAGE_BASE = "https://image.tmdb.org/t/p";

function getApiKey(): string {
  const key = process.env.TMDB_API_KEY;
  if (!key) throw new Error("TMDB_API_KEY environment variable is required");
  return key;
}

function headers(): HeadersInit {
  return {
    Authorization: `Bearer ${getApiKey()}`,
    "Content-Type": "application/json",
  };
}

async function tmdbFetch<T>(path: string, params?: Record<string, string>): Promise<T> {
  const url = new URL(`${TMDB_BASE_URL}${path}`);
  if (params) {
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));
  }

  const response = await fetch(url.toString(), {
    headers: headers(),
    next: { revalidate: 3600 },
  });

  if (!response.ok) {
    throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
  }

  return response.json();
}

export interface TmdbMovie {
  id: number;
  title: string;
  original_title: string;
  overview: string;
  poster_path: string | null;
  backdrop_path: string | null;
  release_date: string;
  runtime: number | null;
  vote_average: number;
  genre_ids?: number[];
  genres?: { id: number; name: string }[];
}

export interface TmdbMovieList {
  page: number;
  results: TmdbMovie[];
  total_pages: number;
  total_results: number;
}

export interface TmdbVideo {
  key: string;
  site: string;
  type: string;
  name: string;
  official: boolean;
}

export interface TmdbCredits {
  cast: { name: string; character: string; profile_path: string | null }[];
  crew: { name: string; job: string }[];
}

export function posterUrl(path: string | null, size: "w185" | "w342" | "w500" | "w780" | "original" = "w500"): string | null {
  return path ? `${TMDB_IMAGE_BASE}/${size}${path}` : null;
}

export function backdropUrl(path: string | null, size: "w780" | "w1280" | "original" = "w1280"): string | null {
  return path ? `${TMDB_IMAGE_BASE}/${size}${path}` : null;
}

export async function getNowPlaying(page = 1): Promise<TmdbMovieList> {
  return tmdbFetch("/movie/now_playing", {
    language: "da-DK",
    region: "DK",
    page: String(page),
  });
}

export async function getUpcoming(page = 1): Promise<TmdbMovieList> {
  return tmdbFetch("/movie/upcoming", {
    language: "da-DK",
    region: "DK",
    page: String(page),
  });
}

export async function getPopular(page = 1): Promise<TmdbMovieList> {
  return tmdbFetch("/movie/popular", {
    language: "da-DK",
    region: "DK",
    page: String(page),
  });
}

export async function getMovieDetails(tmdbId: number): Promise<TmdbMovie> {
  return tmdbFetch(`/movie/${tmdbId}`, { language: "da-DK" });
}

export async function getMovieVideos(tmdbId: number): Promise<{ results: TmdbVideo[] }> {
  return tmdbFetch(`/movie/${tmdbId}/videos`, { language: "da-DK" });
}

export async function getMovieCredits(tmdbId: number): Promise<TmdbCredits> {
  return tmdbFetch(`/movie/${tmdbId}/credits`, { language: "da-DK" });
}

export async function searchMovies(query: string, page = 1): Promise<TmdbMovieList> {
  return tmdbFetch("/search/movie", {
    query,
    language: "da-DK",
    region: "DK",
    page: String(page),
  });
}

export function findTrailer(videos: TmdbVideo[]): TmdbVideo | null {
  return (
    videos.find((v) => v.site === "YouTube" && v.type === "Trailer" && v.official) ??
    videos.find((v) => v.site === "YouTube" && v.type === "Trailer") ??
    videos.find((v) => v.site === "YouTube") ??
    null
  );
}

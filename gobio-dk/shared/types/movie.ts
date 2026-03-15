export interface Movie {
  id: number;
  tmdbId: number;
  title: string;
  originalTitle: string;
  danishTitle: string | null;
  overview: string;
  posterUrl: string | null;
  backdropUrl: string | null;
  trailerYoutubeKey: string | null;
  releaseDate: string;
  runtimeMinutes: number | null;
  genres: string[];
  castList: CastMember[];
  director: string | null;
  tmdbRating: number | null;
  isUpcoming: boolean;
}

export interface CastMember {
  name: string;
  character: string;
  profileUrl: string | null;
}

export interface MovieListItem {
  id: number;
  tmdbId: number;
  title: string;
  danishTitle: string | null;
  posterUrl: string | null;
  releaseDate: string;
  genres: string[];
  tmdbRating: number | null;
  isUpcoming: boolean;
}

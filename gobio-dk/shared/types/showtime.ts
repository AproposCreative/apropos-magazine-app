export interface Showtime {
  id: number;
  movieId: number;
  cinema: ShowtimeCinema;
  startsAt: string;
  format: string | null;
  language: string | null;
  subtitles: string | null;
  is3d: boolean;
  isImax: boolean;
  bookingUrl: string | null;
  hallName: string | null;
}

export interface ShowtimeCinema {
  id: number;
  name: string;
  chainName: string;
  chainSlug: string;
  city: string;
}

export interface ShowtimeGroup {
  cinema: ShowtimeCinema;
  showtimes: Showtime[];
}

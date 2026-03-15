import { NextRequest, NextResponse } from "next/server";
import {
  getMovieDetails,
  getMovieVideos,
  getMovieCredits,
  posterUrl,
  backdropUrl,
  findTrailer,
} from "@/lib/api/tmdb";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const tmdbId = parseInt(id, 10);

  if (isNaN(tmdbId)) {
    return NextResponse.json(
      { success: false, error: "Invalid movie ID" },
      { status: 400 }
    );
  }

  try {
    const [movie, videos, credits] = await Promise.all([
      getMovieDetails(tmdbId),
      getMovieVideos(tmdbId),
      getMovieCredits(tmdbId),
    ]);

    const trailer = findTrailer(videos.results);
    const director = credits.crew.find((c) => c.job === "Director");

    return NextResponse.json({
      success: true,
      data: {
        movie: {
          tmdbId: movie.id,
          title: movie.title,
          originalTitle: movie.original_title,
          overview: movie.overview,
          posterUrl: posterUrl(movie.poster_path),
          backdropUrl: backdropUrl(movie.backdrop_path),
          trailerYoutubeKey: trailer?.key ?? null,
          releaseDate: movie.release_date,
          runtimeMinutes: movie.runtime,
          genres: movie.genres?.map((g) => g.name) ?? [],
          cast: credits.cast.slice(0, 10).map((c) => ({
            name: c.name,
            character: c.character,
            profileUrl: c.profile_path
              ? `https://image.tmdb.org/t/p/w185${c.profile_path}`
              : null,
          })),
          director: director?.name ?? null,
          tmdbRating: movie.vote_average,
        },
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return NextResponse.json(
      { success: false, error: message },
      { status: 500 }
    );
  }
}

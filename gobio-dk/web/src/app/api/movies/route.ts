import { NextRequest, NextResponse } from "next/server";
import { getNowPlaying, getUpcoming, getPopular, posterUrl } from "@/lib/api/tmdb";

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const tab = searchParams.get("tab") ?? "now_playing";
  const page = parseInt(searchParams.get("page") ?? "1", 10);

  try {
    let result;
    switch (tab) {
      case "upcoming":
        result = await getUpcoming(page);
        break;
      case "popular":
        result = await getPopular(page);
        break;
      default:
        result = await getNowPlaying(page);
    }

    const movies = result.results.map((movie) => ({
      tmdbId: movie.id,
      title: movie.title,
      originalTitle: movie.original_title,
      overview: movie.overview,
      posterUrl: posterUrl(movie.poster_path),
      releaseDate: movie.release_date,
      genres: movie.genre_ids ?? [],
      tmdbRating: movie.vote_average,
      isUpcoming: tab === "upcoming",
    }));

    return NextResponse.json({
      success: true,
      data: { movies },
      meta: {
        page: result.page,
        totalPages: result.total_pages,
        total: result.total_results,
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

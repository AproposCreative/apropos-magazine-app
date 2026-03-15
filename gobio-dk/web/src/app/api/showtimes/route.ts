import { NextRequest, NextResponse } from "next/server";

/**
 * GET /api/showtimes
 *
 * Returns showtimes filtered by city, date, movie, or cinema.
 * In production, this queries our database which is populated
 * by the scraper pipeline and/or the International Showtimes API.
 */
export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const _city = searchParams.get("city");
  const _date = searchParams.get("date");
  const _movieId = searchParams.get("movie_id");
  const _cinemaId = searchParams.get("cinema_id");

  // TODO: Query database for showtimes
  // For now, return placeholder data

  return NextResponse.json({
    success: true,
    data: {
      showtimes: [],
      message:
        "Showtime data will be available once the scraper pipeline is running and/or the International Showtimes API is configured.",
    },
  });
}

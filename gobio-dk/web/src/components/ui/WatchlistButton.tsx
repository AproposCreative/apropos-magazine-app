"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

interface WatchlistButtonProps {
  movieId: number;
  initialIsInWatchlist?: boolean;
  className?: string;
}

export function WatchlistButton({
  movieId,
  initialIsInWatchlist = false,
  className,
}: WatchlistButtonProps) {
  const [isInWatchlist, setIsInWatchlist] = useState(initialIsInWatchlist);
  const [isLoading, setIsLoading] = useState(false);

  async function toggleWatchlist() {
    setIsLoading(true);
    try {
      const method = isInWatchlist ? "DELETE" : "POST";
      const response = await fetch(`/api/watchlist/${movieId}`, { method });

      if (response.ok) {
        setIsInWatchlist(!isInWatchlist);
      }
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <button
      onClick={toggleWatchlist}
      disabled={isLoading}
      className={cn(
        "flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-all",
        isInWatchlist
          ? "bg-accent/20 text-accent hover:bg-accent/30"
          : "border border-white/20 text-text-secondary hover:border-accent/50 hover:text-accent",
        isLoading && "cursor-not-allowed opacity-50",
        className
      )}
      aria-label={isInWatchlist ? "Fjern fra watchlist" : "Tilføj til watchlist"}
    >
      <svg
        className="h-5 w-5"
        fill={isInWatchlist ? "currentColor" : "none"}
        viewBox="0 0 24 24"
        stroke="currentColor"
        strokeWidth={2}
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
        />
      </svg>
      {isInWatchlist ? "I din watchlist" : "Tilføj til watchlist"}
    </button>
  );
}

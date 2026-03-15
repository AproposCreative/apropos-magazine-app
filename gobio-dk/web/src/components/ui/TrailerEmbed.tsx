"use client";

import { useState } from "react";

interface TrailerEmbedProps {
  youtubeKey: string;
  title: string;
}

export function TrailerEmbed({ youtubeKey, title }: TrailerEmbedProps) {
  const [loaded, setLoaded] = useState(false);
  const thumbnailUrl = `https://img.youtube.com/vi/${youtubeKey}/maxresdefault.jpg`;

  if (!loaded) {
    return (
      <button
        onClick={() => setLoaded(true)}
        className="group relative aspect-video w-full overflow-hidden rounded-xl"
        aria-label={`Afspil trailer for ${title}`}
      >
        <img
          src={thumbnailUrl}
          alt={`Trailer for ${title}`}
          className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
        />
        <div className="absolute inset-0 flex items-center justify-center bg-black/30 transition-colors group-hover:bg-black/40">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-primary/90 shadow-xl transition-transform group-hover:scale-110">
            <svg
              className="ml-1 h-8 w-8 text-white"
              fill="currentColor"
              viewBox="0 0 24 24"
            >
              <path d="M8 5v14l11-7z" />
            </svg>
          </div>
        </div>
        <span className="absolute bottom-3 left-3 rounded bg-black/70 px-2 py-1 text-sm text-white">
          Se trailer
        </span>
      </button>
    );
  }

  return (
    <div className="aspect-video w-full overflow-hidden rounded-xl">
      <iframe
        src={`https://www.youtube.com/embed/${youtubeKey}?autoplay=1&rel=0`}
        title={`Trailer: ${title}`}
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
        allowFullScreen
        className="h-full w-full"
      />
    </div>
  );
}

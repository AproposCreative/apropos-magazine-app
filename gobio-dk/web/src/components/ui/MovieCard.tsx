import Image from "next/image";
import Link from "next/link";
import { cn, formatDate } from "@/lib/utils";

interface MovieCardProps {
  id: number;
  title: string;
  posterUrl: string | null;
  releaseDate: string;
  genres: string[];
  rating: number | null;
  isUpcoming?: boolean;
  className?: string;
}

export function MovieCard({
  id,
  title,
  posterUrl,
  releaseDate,
  genres,
  rating,
  isUpcoming,
  className,
}: MovieCardProps) {
  return (
    <Link
      href={`/movies/${id}`}
      className={cn(
        "group relative overflow-hidden rounded-xl bg-surface-card/50 transition-all hover:scale-[1.02] hover:shadow-xl hover:shadow-primary/10",
        className
      )}
    >
      <div className="relative aspect-[2/3] w-full overflow-hidden">
        {posterUrl ? (
          <Image
            src={posterUrl}
            alt={title}
            fill
            sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 20vw"
            className="object-cover transition-transform duration-300 group-hover:scale-105"
          />
        ) : (
          <div className="flex h-full items-center justify-center bg-surface-light text-text-muted">
            Ingen poster
          </div>
        )}

        {isUpcoming && (
          <span className="absolute left-2 top-2 rounded-full bg-accent px-2 py-0.5 text-xs font-semibold text-black">
            Kommer snart
          </span>
        )}

        {rating !== null && rating > 0 && (
          <span className="absolute right-2 top-2 rounded-full bg-black/70 px-2 py-0.5 text-xs font-semibold text-accent">
            ★ {rating.toFixed(1)}
          </span>
        )}
      </div>

      <div className="p-3">
        <h3 className="line-clamp-2 text-sm font-semibold leading-tight text-text-primary">
          {title}
        </h3>
        <p className="mt-1 text-xs text-text-muted">
          {formatDate(releaseDate)}
        </p>
        {genres.length > 0 && (
          <div className="mt-1.5 flex flex-wrap gap-1">
            {genres.slice(0, 2).map((genre) => (
              <span
                key={genre}
                className="rounded bg-white/5 px-1.5 py-0.5 text-[10px] text-text-secondary"
              >
                {genre}
              </span>
            ))}
          </div>
        )}
      </div>
    </Link>
  );
}

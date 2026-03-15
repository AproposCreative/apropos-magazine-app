"use client";

import { cn, formatTime } from "@/lib/utils";

interface ShowtimeButtonProps {
  time: string;
  bookingUrl: string | null;
  format?: string | null;
  is3d?: boolean;
  isImax?: boolean;
  className?: string;
}

export function ShowtimeButton({
  time,
  bookingUrl,
  format,
  is3d,
  isImax,
  className,
}: ShowtimeButtonProps) {
  const formattedTime = formatTime(time);

  const badges: string[] = [];
  if (isImax) badges.push("IMAX");
  if (is3d) badges.push("3D");
  if (format && !is3d && !isImax) badges.push(format);

  return (
    <a
      href={bookingUrl ?? "#"}
      target="_blank"
      rel="noopener noreferrer"
      className={cn(
        "inline-flex items-center gap-1.5 rounded-lg border border-primary/30 bg-primary/10 px-3 py-2 text-sm font-medium text-primary-light transition-all hover:border-primary hover:bg-primary/20",
        className
      )}
    >
      <span>{formattedTime}</span>
      {badges.map((badge) => (
        <span
          key={badge}
          className="rounded bg-accent/20 px-1 py-0.5 text-[10px] font-bold text-accent"
        >
          {badge}
        </span>
      ))}
    </a>
  );
}

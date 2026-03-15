"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

const CITIES = [
  "København",
  "Aarhus",
  "Odense",
  "Aalborg",
  "Esbjerg",
  "Randers",
  "Kolding",
  "Horsens",
  "Vejle",
  "Roskilde",
  "Herning",
  "Silkeborg",
  "Næstved",
  "Fredericia",
  "Viborg",
  "Holstebro",
  "Sønderborg",
] as const;

interface CitySelectorProps {
  selectedCity: string;
  onCityChange: (city: string) => void;
  className?: string;
}

export function CitySelector({
  selectedCity,
  onCityChange,
  className,
}: CitySelectorProps) {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className={cn("relative", className)}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 rounded-lg border border-white/10 bg-surface-light px-4 py-2 text-sm font-medium text-text-primary transition-colors hover:border-white/20"
      >
        <svg className="h-4 w-4 text-primary-light" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
        {selectedCity}
        <svg className={cn("h-4 w-4 transition-transform", isOpen && "rotate-180")} fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setIsOpen(false)} />
          <div className="absolute top-full z-50 mt-1 max-h-64 w-48 overflow-auto rounded-lg border border-white/10 bg-surface-light shadow-xl">
            {CITIES.map((city) => (
              <button
                key={city}
                onClick={() => {
                  onCityChange(city);
                  setIsOpen(false);
                }}
                className={cn(
                  "block w-full px-4 py-2 text-left text-sm transition-colors hover:bg-white/5",
                  city === selectedCity
                    ? "bg-primary/10 text-primary-light"
                    : "text-text-secondary"
                )}
              >
                {city}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

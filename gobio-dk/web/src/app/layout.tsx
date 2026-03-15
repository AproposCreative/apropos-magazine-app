import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Gobio.dk - Din danske biografguide",
  description:
    "Se spilletider for biograffilm på tværs af alle danske biografer. Nordisk Film, Vue og mange flere - alt samlet ét sted.",
  keywords: [
    "biograf",
    "spilletider",
    "film",
    "Danmark",
    "biografbilletter",
    "Nordisk Film",
    "Vue",
  ],
  openGraph: {
    title: "Gobio.dk - Din danske biografguide",
    description:
      "Se spilletider for biograffilm på tværs af alle danske biografer.",
    url: "https://gobio.dk",
    siteName: "Gobio.dk",
    locale: "da_DK",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="da">
      <body className="min-h-screen bg-surface font-sans antialiased">
        {children}
      </body>
    </html>
  );
}

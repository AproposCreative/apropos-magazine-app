export interface User {
  id: string;
  email: string;
  displayName: string | null;
  avatarUrl: string | null;
  preferredCity: string;
  notificationPreferences: NotificationPreferences;
}

export interface NotificationPreferences {
  push: boolean;
  email: boolean;
}

export interface WatchlistItem {
  id: number;
  movieId: number;
  movie: {
    id: number;
    title: string;
    posterUrl: string | null;
    releaseDate: string;
    isUpcoming: boolean;
  };
  notifyOnPremiere: boolean;
  addedAt: string;
}

export interface Notification {
  id: number;
  movieId: number | null;
  type: "premiere" | "watchlist" | "system";
  title: string;
  body: string | null;
  isRead: boolean;
  sentAt: string;
}

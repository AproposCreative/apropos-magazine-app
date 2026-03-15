-- Gobio.dk Initial Database Schema
-- Run this migration on your Supabase project

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- Users (extends Supabase Auth)
-- ============================================================
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    avatar_url TEXT,
    preferred_city VARCHAR(100) DEFAULT 'København',
    notification_preferences JSONB DEFAULT '{"push": true, "email": true}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, display_name)
    VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- Movies (cached from TMDB)
-- ============================================================
CREATE TABLE public.movies (
    id SERIAL PRIMARY KEY,
    tmdb_id INTEGER UNIQUE NOT NULL,
    title VARCHAR(500) NOT NULL,
    original_title VARCHAR(500),
    overview TEXT,
    poster_path TEXT,
    backdrop_path TEXT,
    trailer_youtube_key VARCHAR(20),
    release_date DATE,
    runtime_minutes INTEGER,
    genres JSONB DEFAULT '[]'::jsonb,
    cast_list JSONB DEFAULT '[]'::jsonb,
    director VARCHAR(255),
    tmdb_rating DECIMAL(3,1),
    danish_title VARCHAR(500),
    is_upcoming BOOLEAN DEFAULT FALSE,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_movies_tmdb ON public.movies(tmdb_id);
CREATE INDEX idx_movies_release ON public.movies(release_date);
CREATE INDEX idx_movies_upcoming ON public.movies(is_upcoming) WHERE is_upcoming = TRUE;

ALTER TABLE public.movies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Movies are viewable by everyone"
    ON public.movies FOR SELECT TO authenticated, anon
    USING (true);

-- ============================================================
-- Cinema Chains
-- ============================================================
CREATE TABLE public.cinema_chains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    logo_url TEXT,
    website_url TEXT NOT NULL,
    booking_base_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.cinema_chains ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Cinema chains are viewable by everyone"
    ON public.cinema_chains FOR SELECT TO authenticated, anon
    USING (true);

-- ============================================================
-- Cinemas
-- ============================================================
CREATE TABLE public.cinemas (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER REFERENCES public.cinema_chains(id),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    address TEXT,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    phone VARCHAR(20),
    website_url TEXT,
    facilities JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(chain_id, slug)
);

CREATE INDEX idx_cinemas_city ON public.cinemas(city);
CREATE INDEX idx_cinemas_chain ON public.cinemas(chain_id);

ALTER TABLE public.cinemas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Cinemas are viewable by everyone"
    ON public.cinemas FOR SELECT TO authenticated, anon
    USING (true);

-- ============================================================
-- Showtimes
-- ============================================================
CREATE TABLE public.showtimes (
    id SERIAL PRIMARY KEY,
    movie_id INTEGER REFERENCES public.movies(id) ON DELETE CASCADE,
    cinema_id INTEGER REFERENCES public.cinemas(id) ON DELETE CASCADE,
    starts_at TIMESTAMPTZ NOT NULL,
    format VARCHAR(50),
    language VARCHAR(50),
    subtitles VARCHAR(50),
    is_3d BOOLEAN DEFAULT FALSE,
    is_imax BOOLEAN DEFAULT FALSE,
    booking_url TEXT,
    hall_name VARCHAR(100),
    source VARCHAR(50) NOT NULL DEFAULT 'api',
    external_id VARCHAR(255),
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(cinema_id, movie_id, starts_at)
);

CREATE INDEX idx_showtimes_movie ON public.showtimes(movie_id);
CREATE INDEX idx_showtimes_cinema ON public.showtimes(cinema_id);
CREATE INDEX idx_showtimes_starts_at ON public.showtimes(starts_at);
CREATE INDEX idx_showtimes_lookup ON public.showtimes(movie_id, cinema_id, starts_at);

ALTER TABLE public.showtimes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Showtimes are viewable by everyone"
    ON public.showtimes FOR SELECT TO authenticated, anon
    USING (true);

-- ============================================================
-- Watchlist
-- ============================================================
CREATE TABLE public.watchlist_items (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    movie_id INTEGER REFERENCES public.movies(id) ON DELETE CASCADE,
    notify_on_premiere BOOLEAN DEFAULT TRUE,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, movie_id)
);

CREATE INDEX idx_watchlist_user ON public.watchlist_items(user_id);
CREATE INDEX idx_watchlist_movie ON public.watchlist_items(movie_id);

ALTER TABLE public.watchlist_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own watchlist"
    ON public.watchlist_items FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can add to own watchlist"
    ON public.watchlist_items FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove from own watchlist"
    ON public.watchlist_items FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================
-- Notifications
-- ============================================================
CREATE TABLE public.notifications (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    movie_id INTEGER REFERENCES public.movies(id),
    type VARCHAR(50) NOT NULL DEFAULT 'system',
    title VARCHAR(255) NOT NULL,
    body TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

CREATE INDEX idx_notifications_user ON public.notifications(user_id, is_read);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own notifications"
    ON public.notifications FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can mark own notifications as read"
    ON public.notifications FOR UPDATE
    USING (auth.uid() = user_id);

-- ============================================================
-- Push Tokens (for mobile app)
-- ============================================================
CREATE TABLE public.push_tokens (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own push tokens"
    ON public.push_tokens FOR ALL
    USING (auth.uid() = user_id);

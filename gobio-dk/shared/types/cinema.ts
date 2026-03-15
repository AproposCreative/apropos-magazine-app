export interface CinemaChain {
  id: number;
  name: string;
  slug: string;
  logoUrl: string | null;
  websiteUrl: string;
}

export interface Cinema {
  id: number;
  chain: CinemaChain | null;
  name: string;
  slug: string;
  city: string;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  phone: string | null;
  websiteUrl: string | null;
  facilities: string[];
}

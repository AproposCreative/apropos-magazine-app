-- Seed Danish cinema chains
INSERT INTO public.cinema_chains (name, slug, website_url, booking_base_url) VALUES
('Nordisk Film Biografer', 'nordisk-film', 'https://www.nfbio.dk', 'https://www.nfbio.dk/film/'),
('Vue', 'vue', 'https://www.cinemaxx.dk', 'https://www.cinemaxx.dk/film/'),
('Grand Teatret', 'grand-teatret', 'https://www.grandteatret.dk', 'https://www.grandteatret.dk/film/'),
('Cinemateket', 'cinemateket', 'https://www.dfi.dk/cinemateket', 'https://www.dfi.dk/cinemateket/film/'),
('BIG BIO', 'big-bio', 'https://www.bigbio.dk', 'https://www.bigbio.dk/'),
('Øst for Paradis', 'oest-for-paradis', 'https://www.paradisbio.dk', 'https://www.paradisbio.dk/'),
('Fotorama', 'fotorama', 'https://www.fotorama.dk', 'https://www.fotorama.dk/'),
('Bibliografen', 'bibliografen', 'https://www.bibliografen.dk', 'https://www.bibliografen.dk/'),
('Atlas Biograferne', 'atlas-biograferne', 'https://www.atlas-bio.dk', 'https://www.atlas-bio.dk/')
ON CONFLICT (slug) DO NOTHING;

-- Seed some cinemas for each chain
INSERT INTO public.cinemas (chain_id, name, slug, city, address) VALUES
-- Nordisk Film Biografer
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Imperial', 'imperial', 'København', 'Ved Vesterport 4, 1612 København V'),
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Palads', 'palads', 'København', 'Axeltorv 9, 1609 København V'),
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Dagmar', 'dagmar', 'København', 'Jernbanegade 2, 1608 København V'),
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Aarhus C', 'aarhus-c', 'Aarhus', 'Søndergade 28, 8000 Aarhus C'),
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Aalborg City Syd', 'aalborg-city-syd', 'Aalborg', 'Hobrovej 452, 9200 Aalborg SV'),
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Odense', 'odense', 'Odense', 'Ørbækvej 75-77, 5220 Odense SØ'),
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Herning', 'herning', 'Herning', 'Østergade 30, 7400 Herning'),
((SELECT id FROM public.cinema_chains WHERE slug = 'nordisk-film'), 'Esbjerg', 'esbjerg', 'Esbjerg', 'Skolegade 115, 6700 Esbjerg'),

-- Vue (CinemaxX)
((SELECT id FROM public.cinema_chains WHERE slug = 'vue'), 'Vue København', 'vue-koebenhavn', 'København', 'Fisketorvet, Kalvebod Brygge 59, 1560 København V'),
((SELECT id FROM public.cinema_chains WHERE slug = 'vue'), 'Vue Aarhus', 'vue-aarhus', 'Aarhus', 'Bruuns Galleri, M.P. Bruuns Gade 25, 8000 Aarhus C'),
((SELECT id FROM public.cinema_chains WHERE slug = 'vue'), 'Vue Odense', 'vue-odense', 'Odense', 'Rosengårdcentret, Ørbækvej 75, 5220 Odense SØ'),
((SELECT id FROM public.cinema_chains WHERE slug = 'vue'), 'Vue Aalborg', 'vue-aalborg', 'Aalborg', 'Aalborg Storcenter, Hobrovej 452, 9200 Aalborg SV'),

-- Uafhængige biografer
((SELECT id FROM public.cinema_chains WHERE slug = 'grand-teatret'), 'Grand Teatret', 'grand-teatret', 'København', 'Mikkel Bryggers Gade 8, 1460 København K'),
((SELECT id FROM public.cinema_chains WHERE slug = 'cinemateket'), 'Cinemateket', 'cinemateket', 'København', 'Gothersgade 55, 1123 København K'),
((SELECT id FROM public.cinema_chains WHERE slug = 'big-bio'), 'BIG BIO Herlev', 'big-bio-herlev', 'Herlev', 'Herlev Hovedgade 17, 2730 Herlev'),
((SELECT id FROM public.cinema_chains WHERE slug = 'big-bio'), 'BIG BIO Nordhavn', 'big-bio-nordhavn', 'København', 'Århusgade 88, 2150 Nordhavn'),
((SELECT id FROM public.cinema_chains WHERE slug = 'oest-for-paradis'), 'Øst for Paradis', 'oest-for-paradis', 'Aarhus', 'Paradisgade 7-9, 8000 Aarhus C'),
((SELECT id FROM public.cinema_chains WHERE slug = 'fotorama'), 'Fotorama Aarhus', 'fotorama-aarhus', 'Aarhus', 'Vesterbro Torv 3, 8000 Aarhus C')
ON CONFLICT DO NOTHING;

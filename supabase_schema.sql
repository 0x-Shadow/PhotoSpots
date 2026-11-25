-- Run this in your Supabase SQL editor.
-- PhotoSpot database schema (free tier).

-- Profiles (extends Supabase auth.users)
create table profiles (
  id uuid references auth.users on delete cascade primary key,
  display_name text,
  avatar_url text,
  bio text,
  created_at timestamptz default now()
);

alter table profiles enable row level security;

create policy "Public profiles are viewable by everyone"
  on profiles for select using ( true );

create policy "Users can insert their own profile"
  on profiles for insert with check ( auth.uid() = id );

create policy "Users can update own profile"
  on profiles for update using ( auth.uid() = id );

-- Spots
create table spots (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  description text,
  city text not null,
  latitude double precision not null,
  longitude double precision not null,
  tags text[] default '{}',
  best_time text,
  rating double precision default 4.5,
  review_count integer default 0,
  save_count integer default 0,
  view_count integer default 0,
  created_at timestamptz default now(),
  submitted_by uuid references profiles(id)
);

alter table spots enable row level security;

create policy "Spots are viewable by everyone"
  on spots for select using ( true );

create policy "Authenticated users can insert spots"
  on spots for insert with check ( auth.uid() = submitted_by );

create policy "Users can update own spots"
  on spots for update using ( auth.uid() = submitted_by );

-- Photos
create table photos (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade not null,
  uploader uuid references profiles(id),
  image_url text not null,
  caption text,
  taken_at timestamptz,
  created_at timestamptz default now()
);

alter table photos enable row level security;

create policy "Photos are viewable by everyone"
  on photos for select using ( true );

create policy "Authenticated users can insert photos"
  on photos for insert with check ( auth.uid() = uploader );

-- Saves
create table saves (
  user_id uuid references profiles(id) on delete cascade,
  spot_id uuid references spots(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, spot_id)
);

alter table saves enable row level security;

create policy "Users can view own saves"
  on saves for select using ( auth.uid() = user_id );

create policy "Users can insert own saves"
  on saves for insert with check ( auth.uid() = user_id );

create policy "Users can delete own saves"
  on saves for delete using ( auth.uid() = user_id );

-- Spot views (for ranking)
create table spot_views (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade,
  viewer uuid references profiles(id),
  viewed_at timestamptz default now()
);

alter table spot_views enable row level security;

create policy "Anyone can insert spot views"
  on spot_views for insert with check ( true );

create policy "Anyone can view spot views"
  on spot_views for select using ( true );

-- Storage bucket for photos (create manually in Supabase dashboard: "photos", public)
-- Insert into storage.buckets (id, name, public) values ('photos', 'photos', true);

-- Seed: real Lisbon photo spots
insert into spots (title, description, city, latitude, longitude, tags, best_time, rating, review_count, save_count, view_count) values
('Miradouro da Senhora do Monte', 'Highest viewpoint in Alfama. The whole city falls away toward the river — arrive 45 min before sunset.', 'Lisbon', 38.7223, -9.1335, ARRAY['skyline','sunset'], 'Golden hour', 4.9, 12500, 214, 1890),
('Miradouro de Santa Luzia', 'Blue-and-white azulejo wall framed by bougainvillea. Best in soft morning light before the tour groups arrive.', 'Lisbon', 38.7121, -9.1305, ARRAY['tiles','street'], 'Morning light', 4.8, 8400, 168, 1420),
('Praça do Comércio', 'Symmetrical arch and riverside square. Stand under Rua Augusta Arch to frame the whole plaza.', 'Lisbon', 38.7077, -9.1365, ARRAY['architecture','symmetry'], 'Blue hour', 4.9, 21000, 192, 1675),
('Belém Tower', 'Shoot from the far side of the water for the full silhouette. Low tide exposes reflective sand.', 'Lisbon', 38.6916, -9.2160, ARRAY['landmark','water'], 'Sunset', 4.7, 15600, 143, 1210),
('LX Factory', 'Industrial chic under the 25 de Abril bridge — murals, neon signs, gritty textures.', 'Lisbon', 38.7033, -9.1786, ARRAY['street','industrial'], 'Afternoon', 4.6, 5200, 97, 860),
('Tram 28 at Graça', 'The classic yellow tram shot. Stand on the pavement bend and wait for the tram to crest the hill.', 'Lisbon', 38.7169, -9.1332, ARRAY['street','tram'], 'Golden hour', 4.8, 9800, 176, 1530),
('Castelo de São Jorge', 'Ramparts look straight down over the red rooftops. Golden hour hits the castle walls first.', 'Lisbon', 38.7139, -9.1335, ARRAY['skyline','landmark'], 'Sunset', 4.7, 13400, 131, 1105),
('Pink Street', 'Pink cobbles and yellow umbrellas. Empty at dawn, buzzing with neon after dark.', 'Lisbon', 38.7075, -9.1458, ARRAY['street','nightlife'], 'Night', 4.5, 7300, 120, 1015),
('Graça Rooftop Ledge', 'A quiet residential ledge most tourists walk past. Full river view with no one behind you.', 'Lisbon', 38.7185, -9.1347, ARRAY['skyline','hidden gem'], 'Golden hour', 4.9, 1200, 58, 430),
('Cais das Colunas', 'Two marble columns walking into the Tagus. Reflections pool around your feet at high tide.', 'Lisbon', 38.7066, -9.1440, ARRAY['water','reflection'], 'Blue hour', 4.7, 3800, 102, 895);

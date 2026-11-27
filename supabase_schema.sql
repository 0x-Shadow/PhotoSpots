-- Run this in your Supabase SQL editor.
-- PhotoSpot database schema (free tier).
--
-- Apply in this order, and re-run any of them whenever you like:
--   1. supabase_schema.sql      (this file)
--   2. supabase_engagement.sql  (likes, comments)
--   3. supabase_fix.sql         (de-duplication repair, storage policies)
-- Every statement is idempotent and every policy is written in its hardened
-- form here, so re-running a script can never widen a policy that a later
-- script tightened.
--
-- After running it:
--   1. Authentication → Providers → enable "Anonymous sign-ins" so the app can
--      save, view, and publish without a login screen.
--   2. Create a public Storage bucket named "photos".
--   3. Build with SUPABASE_URL and SUPABASE_ANON_KEY dart-defines.

-- ---------------------------------------------------------------------------
-- Profiles (extends Supabase auth.users)
-- ---------------------------------------------------------------------------
create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  display_name text,
  avatar_url text,
  bio text,
  created_at timestamptz default now()
);

alter table profiles enable row level security;

drop policy if exists "Public profiles are viewable by everyone" on profiles;
create policy "Public profiles are viewable by everyone"
  on profiles for select using ( true );

drop policy if exists "Users can insert their own profile" on profiles;
create policy "Users can insert their own profile"
  on profiles for insert with check ( auth.uid() = id );

drop policy if exists "Users can update own profile" on profiles;
create policy "Users can update own profile"
  on profiles for update using ( auth.uid() = id );

drop policy if exists "Users can delete own profile" on profiles;
create policy "Users can delete own profile"
  on profiles for delete using ( auth.uid() = id );

-- Every new auth user (including anonymous sessions) gets a profile row, so
-- spots.submitted_by and photos.uploader foreign keys always resolve.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', 'Explorer')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Spots
-- ---------------------------------------------------------------------------
create table if not exists spots (
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

-- Values a client cannot talk its way out of. `not valid` keeps the migration
-- runnable over historical rows while still rejecting new bad writes.
alter table spots drop constraint if exists spots_title_len;
alter table spots add constraint spots_title_len
  check (char_length(btrim(title)) between 1 and 120) not valid;
alter table spots drop constraint if exists spots_city_len;
alter table spots add constraint spots_city_len
  check (char_length(btrim(city)) between 1 and 80) not valid;
alter table spots drop constraint if exists spots_latitude_range;
alter table spots add constraint spots_latitude_range
  check (latitude between -90 and 90) not valid;
alter table spots drop constraint if exists spots_longitude_range;
alter table spots add constraint spots_longitude_range
  check (longitude between -180 and 180) not valid;
alter table spots drop constraint if exists spots_rating_range;
alter table spots add constraint spots_rating_range
  check (rating between 0 and 5) not valid;
alter table spots drop constraint if exists spots_counts_nonnegative;
alter table spots add constraint spots_counts_nonnegative
  check (save_count >= 0 and view_count >= 0) not valid;

drop policy if exists "Spots are viewable by everyone" on spots;
create policy "Spots are viewable by everyone"
  on spots for select using ( true );

drop policy if exists "Authenticated users can insert spots" on spots;
create policy "Authenticated users can insert spots"
  on spots for insert with check ( auth.uid() = submitted_by );

drop policy if exists "Users can update own spots" on spots;
create policy "Users can update own spots"
  on spots for update using ( auth.uid() = submitted_by );

drop policy if exists "Users can delete own spots" on spots;
create policy "Users can delete own spots"
  on spots for delete using ( auth.uid() = submitted_by );

-- Column-level privileges are the only way to stop a crafted request from
-- writing rating or the engagement counters: the RLS policy only says *which
-- row*, never *which columns*. Table-wide INSERT/UPDATE is revoked and then
-- granted back for exactly the fields a person may set.
revoke insert, update on spots from anon, authenticated;
grant insert (
  title, description, city, latitude, longitude, tags, best_time, submitted_by
) on spots to anon, authenticated;
grant update (
  title, description, city, latitude, longitude, tags, best_time
) on spots to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Photos
-- ---------------------------------------------------------------------------
create table if not exists photos (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade not null,
  uploader uuid references profiles(id),
  image_url text not null,
  caption text,
  taken_at timestamptz,
  created_at timestamptz default now()
);

alter table photos enable row level security;

drop policy if exists "Photos are viewable by everyone" on photos;
create policy "Photos are viewable by everyone"
  on photos for select using ( true );

drop policy if exists "Authenticated users can insert photos" on photos;
create policy "Authenticated users can insert photos"
  on photos for insert with check ( auth.uid() = uploader );

drop policy if exists "Photo owners can delete rows" on photos;
create policy "Photo owners can delete rows"
  on photos for delete using ( auth.uid() = uploader );

-- ---------------------------------------------------------------------------
-- Saves
-- ---------------------------------------------------------------------------
create table if not exists saves (
  user_id uuid references profiles(id) on delete cascade,
  spot_id uuid references spots(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, spot_id)
);

alter table saves enable row level security;

drop policy if exists "Users can view own saves" on saves;
create policy "Users can view own saves"
  on saves for select using ( auth.uid() = user_id );

drop policy if exists "Users can insert own saves" on saves;
create policy "Users can insert own saves"
  on saves for insert with check ( auth.uid() = user_id );

drop policy if exists "Users can delete own saves" on saves;
create policy "Users can delete own saves"
  on saves for delete using ( auth.uid() = user_id );

-- ---------------------------------------------------------------------------
-- Spot views (for ranking)
-- ---------------------------------------------------------------------------
create table if not exists spot_views (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade,
  viewer uuid references profiles(id),
  viewed_at timestamptz default now()
);

alter table spot_views enable row level security;

-- One view per person per spot. Views feed the ranking, so unauthenticated or
-- repeated inserts used to be an unbounded way to inflate a spot. Existing
-- spam and duplicates are cleared before the constraint is added.
delete from spot_views where viewer is null;
delete from spot_views a using spot_views b
 where a.viewer = b.viewer
   and a.spot_id = b.spot_id
   and a.id > b.id;
create unique index if not exists spot_views_spot_viewer_key
  on spot_views (spot_id, viewer);
alter table spot_views alter column viewer set default auth.uid();
alter table spot_views alter column viewer set not null;

drop policy if exists "Anyone can insert spot views" on spot_views;
drop policy if exists "Users can insert own spot views" on spot_views;
create policy "Users can insert own spot views"
  on spot_views for insert with check ( auth.uid() = viewer );

drop policy if exists "Anyone can view spot views" on spot_views;
drop policy if exists "Users can view own spot views" on spot_views;
create policy "Users can view own spot views"
  on spot_views for select using ( auth.uid() = viewer );

-- ---------------------------------------------------------------------------
-- Server-owned counters
-- ---------------------------------------------------------------------------
-- Counters are maintained here rather than by the client, so concurrent saves
-- and views cannot overwrite each other.
create or replace function public.bump_save_count()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update spots set save_count = save_count + 1 where id = new.spot_id;
  elsif tg_op = 'DELETE' then
    update spots
      set save_count = greatest(save_count - 1, 0)
      where id = old.spot_id;
  end if;
  return null;
end;
$$;

drop trigger if exists on_save_change on saves;
create trigger on_save_change
  after insert or delete on saves
  for each row execute function public.bump_save_count();

create or replace function public.bump_view_count()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update spots set view_count = view_count + 1 where id = new.spot_id;
  return null;
end;
$$;

drop trigger if exists on_view_insert on spot_views;
create trigger on_view_insert
  after insert on spot_views
  for each row execute function public.bump_view_count();

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
-- One row per place, so re-running the seed below cannot duplicate spots.
create unique index if not exists spots_title_city_key on spots (title, city);
create index if not exists spots_tags_idx on spots using gin (tags);
create index if not exists spots_created_at_idx on spots (created_at desc);
create index if not exists photos_spot_id_idx on photos (spot_id);
create index if not exists photos_uploader_idx on photos (uploader);
create index if not exists spot_views_spot_id_idx on spot_views (spot_id);
create index if not exists spot_views_viewer_idx on spot_views (viewer);
create index if not exists saves_spot_id_idx on saves (spot_id);
create index if not exists spots_submitted_by_idx on spots (submitted_by);
create index if not exists spots_city_idx on spots (city);
create index if not exists spots_location_idx on spots (latitude, longitude);

-- ---------------------------------------------------------------------------
-- Storage policies for the public "photos" bucket
-- ---------------------------------------------------------------------------
-- Create the bucket first in Storage (name: photos, public).
drop policy if exists "Public photo reads" on storage.objects;
create policy "Public photo reads"
  on storage.objects for select
  using ( bucket_id = 'photos' );

drop policy if exists "Authenticated photo uploads" on storage.objects;
create policy "Authenticated photo uploads"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and lower(storage.extension(name)) in ('jpg','jpeg','png','webp','heic','heif')
  );

drop policy if exists "Photo owners can update" on storage.objects;
create policy "Photo owners can update"
  on storage.objects for update to authenticated
  using ( bucket_id = 'photos' and owner = auth.uid() );

drop policy if exists "Photo owners can delete" on storage.objects;
create policy "Photo owners can delete"
  on storage.objects for delete to authenticated
  using ( bucket_id = 'photos' and owner = auth.uid() );

-- ---------------------------------------------------------------------------
-- Seed: Lisbon photo spots
-- ---------------------------------------------------------------------------
insert into spots
  (title, description, city, latitude, longitude, tags, best_time,
   rating, review_count, save_count, view_count)
values
  ('Miradouro da Senhora do Monte', 'Highest viewpoint in Alfama. The whole city falls away toward the river — arrive 45 min before sunset.', 'Lisbon', 38.7223, -9.1335, ARRAY['skyline','sunset','date'], 'Golden hour', 4.9, 12500, 214, 1890),
  ('Miradouro de Santa Luzia', 'Blue-and-white azulejo wall framed by bougainvillea. Best in soft morning light before the tour groups arrive.', 'Lisbon', 38.7121, -9.1305, ARRAY['tiles','street','friends','date'], 'Morning light', 4.8, 8400, 168, 1420),
  ('Praça do Comércio', 'Symmetrical arch and riverside square. Stand under Rua Augusta Arch to frame the whole plaza.', 'Lisbon', 38.7077, -9.1365, ARRAY['architecture','symmetry','date','friends'], 'Blue hour', 4.9, 21000, 192, 1675),
  ('Belém Tower', 'Shoot from the far side of the water for the full silhouette. Low tide exposes reflective sand.', 'Lisbon', 38.6916, -9.2160, ARRAY['landmark','water','date'], 'Sunset', 4.7, 15600, 143, 1210),
  ('LX Factory', 'Industrial chic under the 25 de Abril bridge — murals, neon signs, gritty textures.', 'Lisbon', 38.7033, -9.1786, ARRAY['street','industrial','friends'], 'Afternoon', 4.6, 5200, 97, 860),
  ('Tram 28 at Graça', 'The classic yellow tram shot. Stand on the pavement bend and wait for the tram to crest the hill.', 'Lisbon', 38.7169, -9.1332, ARRAY['street','tram','friends'], 'Golden hour', 4.8, 9800, 176, 1530),
  ('Castelo de São Jorge', 'Ramparts look straight down over the red rooftops. Golden hour hits the castle walls first.', 'Lisbon', 38.7139, -9.1335, ARRAY['skyline','landmark','date'], 'Sunset', 4.7, 13400, 131, 1105),
  ('Pink Street', 'Pink cobbles and yellow umbrellas. Empty at dawn, buzzing with neon after dark.', 'Lisbon', 38.7075, -9.1458, ARRAY['street','nightlife','friends'], 'Night', 4.5, 7300, 120, 1015),
  ('Rua Augusta Arch', 'Perfect one-point perspective down Rua Augusta. Tripod recommended after dark.', 'Lisbon', 38.7101, -9.1394, ARRAY['architecture','symmetry','date'], 'Blue hour', 4.6, 6100, 88, 790),
  ('Elevador de Santa Justa', 'Gothic iron lift against the rooftops. Shoot from the upper terrace, not the street below.', 'Lisbon', 38.7121, -9.1390, ARRAY['architecture','iron','friends'], 'Blue hour', 4.4, 4900, 74, 640),
  ('Graça Rooftop Ledge', 'A quiet residential ledge most tourists walk past. Full river view with no one behind you.', 'Lisbon', 38.7185, -9.1347, ARRAY['skyline','hidden gem','date'], 'Golden hour', 4.9, 1200, 58, 430),
  ('Cais das Colunas', 'Two marble columns walking into the Tagus. Reflections pool around your feet at high tide.', 'Lisbon', 38.7066, -9.1440, ARRAY['water','reflection','date'], 'Blue hour', 4.7, 3800, 102, 895)
on conflict (title, city) do nothing;

-- Seed photography, so cards are not empty on a fresh project. The files live
-- in the public "photos" bucket under seed/.
insert into photos (spot_id, image_url)
select s.id,
       'https://gurlwhjcqcdntuxgfvlk.supabase.co/storage/v1/object/public/photos/seed/'
         || v.slug || '.jpg'
from (values
  ('Miradouro da Senhora do Monte', 'senhora-do-monte'),
  ('Miradouro de Santa Luzia',      'santa-luzia'),
  ('Praça do Comércio',             'praca-do-comercio'),
  ('Belém Tower',                   'belem-tower'),
  ('LX Factory',                    'lx-factory'),
  ('Tram 28 at Graça',              'tram-28'),
  ('Castelo de São Jorge',          'castelo-sao-jorge'),
  ('Pink Street',                   'pink-street'),
  ('Rua Augusta Arch',              'rua-augusta'),
  ('Elevador de Santa Justa',       'santa-justa')
) as v(title, slug)
join spots s on s.title = v.title
where not exists (
  select 1 from photos p where p.spot_id = s.id and p.image_url like '%/seed/%'
);

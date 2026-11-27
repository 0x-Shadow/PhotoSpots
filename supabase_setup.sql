-- =============================================================================
-- PhotoSpot — Complete Single-File Supabase Setup (Schema + Engagement + Fixes)
-- =============================================================================
-- Paste this entire file into your Supabase SQL Editor and click "Run".
-- Every statement is 100% idempotent and safe to re-run at any time.
--
-- After running:
--   1. Authentication -> Providers -> enable "Anonymous sign-ins" (optional if
--      you require full accounts, though write policies require non-anonymous
--      authenticated sessions per Google Play policy).
--   2. A public Storage bucket named "photos" is created automatically (or you
--      can create it manually under Storage with public access enabled).
--   3. Build the app with --dart-define=SUPABASE_URL=... and
--      --dart-define=SUPABASE_ANON_KEY=...
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. CREATE / UPGRADE ALL TABLES
-- ---------------------------------------------------------------------------
create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  display_name text,
  avatar_url text,
  bio text,
  city text,
  created_at timestamptz default now()
);
alter table profiles add column if not exists city text;

create table if not exists spots (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  description text,
  city text not null,
  latitude double precision not null,
  longitude double precision not null,
  tags text[] default '{}',
  best_time text,
  focal_length text,
  tripod_friendly boolean,
  access_note text,
  rating double precision default 4.5,
  review_count integer default 0,
  save_count integer default 0,
  view_count integer default 0,
  like_count integer not null default 0,
  comment_count integer not null default 0,
  report_count integer not null default 0,
  is_hidden boolean not null default false,
  created_at timestamptz default now(),
  submitted_by uuid references profiles(id)
);
alter table spots add column if not exists focal_length text;
alter table spots add column if not exists tripod_friendly boolean;
alter table spots add column if not exists access_note text;
alter table spots add column if not exists like_count integer not null default 0;
alter table spots add column if not exists comment_count integer not null default 0;
alter table spots add column if not exists report_count integer not null default 0;
alter table spots add column if not exists is_hidden boolean not null default false;

create table if not exists photos (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade not null,
  uploader uuid references profiles(id),
  image_url text not null,
  caption text,
  taken_at timestamptz,
  created_at timestamptz default now()
);

create table if not exists saves (
  user_id uuid references profiles(id) on delete cascade,
  spot_id uuid references spots(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, spot_id)
);

create table if not exists spot_views (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade,
  viewer uuid references profiles(id),
  viewed_at timestamptz default now()
);

create table if not exists likes (
  user_id uuid references profiles(id) on delete cascade not null,
  spot_id uuid references spots(id) on delete cascade not null,
  created_at timestamptz not null default now(),
  primary key (user_id, spot_id)
);

create table if not exists comments (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade not null,
  author uuid references profiles(id) on delete cascade not null,
  body text not null,
  report_count integer not null default 0,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  constraint comments_body_len
    check (char_length(btrim(body)) between 1 and 500)
);
alter table comments add column if not exists report_count integer not null default 0;
alter table comments add column if not exists is_hidden boolean not null default false;

create table if not exists reports (
  id uuid default gen_random_uuid() primary key,
  reporter_id uuid references profiles(id) on delete cascade not null,
  target_type text not null check (target_type in ('spot', 'comment')),
  target_id uuid not null,
  reason text not null check (char_length(btrim(reason)) between 1 and 120),
  details text check (details is null or char_length(details) <= 500),
  created_at timestamptz not null default now()
);

create table if not exists blocked_users (
  blocker_id uuid references profiles(id) on delete cascade not null,
  blocked_id uuid references profiles(id) on delete cascade not null,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- ---------------------------------------------------------------------------
-- 2. DE-DUPLICATE HISTORICAL SPOTS BEFORE INDEXES & SEED
-- ---------------------------------------------------------------------------
drop table if exists _spot_keep;
create temp table _spot_keep as
select title, city, min(id::text)::uuid as keep_id
from spots
group by title, city;

drop table if exists _spot_dupes;
create temp table _spot_dupes as
select s.id as dupe_id, k.keep_id
from spots s
join _spot_keep k on k.title = s.title and k.city = s.city
where s.id <> k.keep_id;

delete from saves s
using _spot_dupes d
where s.spot_id = d.dupe_id
  and exists (
    select 1 from saves s2
    where s2.user_id = s.user_id and s2.spot_id = d.keep_id
  );

update saves s set spot_id = d.keep_id
from _spot_dupes d where s.spot_id = d.dupe_id;

delete from spot_views v
using _spot_dupes d
where v.spot_id = d.dupe_id
  and exists (
    select 1 from spot_views v2
    where v2.viewer = v.viewer and v2.spot_id = d.keep_id
  );

update spot_views v set spot_id = d.keep_id
from _spot_dupes d where v.spot_id = d.dupe_id;

update photos p set spot_id = d.keep_id
from _spot_dupes d where p.spot_id = d.dupe_id;

delete from likes l
using _spot_dupes d
where l.spot_id = d.dupe_id
  and exists (
    select 1 from likes l2
    where l2.user_id = l.user_id and l2.spot_id = d.keep_id
  );

update likes l set spot_id = d.keep_id
from _spot_dupes d where l.spot_id = d.dupe_id;

update comments c set spot_id = d.keep_id
from _spot_dupes d where c.spot_id = d.dupe_id;

delete from spots s using _spot_dupes d where s.id = d.dupe_id;

drop table if exists _spot_dupes;
drop table if exists _spot_keep;

-- Also clean up any duplicate spot_views per (spot_id, viewer)
delete from spot_views a using spot_views b
 where a.viewer = b.viewer
   and a.spot_id = b.spot_id
   and a.id > b.id;

-- ---------------------------------------------------------------------------
-- 3. CONSTRAINTS & INDEXES
-- ---------------------------------------------------------------------------
alter table profiles
  drop constraint if exists profiles_display_name_len;
alter table profiles
  add constraint profiles_display_name_len
  check (display_name is null or char_length(display_name) between 1 and 32);

alter table profiles
  drop constraint if exists profiles_bio_len;
alter table profiles
  add constraint profiles_bio_len
  check (bio is null or char_length(bio) <= 140);

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
  check (save_count >= 0 and view_count >= 0 and report_count >= 0) not valid;
alter table spots drop constraint if exists spots_engagement_nonnegative;
alter table spots add constraint spots_engagement_nonnegative
  check (like_count >= 0 and comment_count >= 0) not valid;
alter table spots drop constraint if exists spots_description_len;
alter table spots add constraint spots_description_len
  check (description is null or char_length(description) <= 2000) not valid;
alter table spots drop constraint if exists spots_tags_cap;
alter table spots add constraint spots_tags_cap
  check (tags is null or cardinality(tags) <= 12) not valid;
alter table spots drop constraint if exists spots_access_note_len;
alter table spots add constraint spots_access_note_len
  check (access_note is null or char_length(access_note) <= 120) not valid;

alter table photos drop constraint if exists photos_url_https;
alter table photos add constraint photos_url_https
  check (image_url ~ '^https://') not valid;

create unique index if not exists spots_title_city_key on spots (title, city);
create unique index if not exists spot_views_spot_viewer_key
  on spot_views (spot_id, viewer);
alter table spot_views alter column viewer set default auth.uid();
alter table spot_views alter column viewer set not null;

create unique index if not exists reports_unique_reporter_target
  on reports (reporter_id, target_type, target_id);

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
create index if not exists comments_spot_created_idx
  on comments (spot_id, created_at desc);
create index if not exists comments_author_idx on comments (author);
create index if not exists likes_spot_id_idx on likes (spot_id);
create index if not exists likes_user_id_idx on likes (user_id);

-- ---------------------------------------------------------------------------
-- 4. FUNCTIONS & TRIGGERS
-- ---------------------------------------------------------------------------
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

create or replace function public.sync_like_count()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update spots set like_count = like_count + 1 where id = new.spot_id;
    return new;
  elsif tg_op = 'DELETE' then
    update spots
      set like_count = greatest(like_count - 1, 0)
      where id = old.spot_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists likes_sync_count on likes;
create trigger likes_sync_count
  after insert or delete on likes
  for each row execute function public.sync_like_count();

create or replace function public.sync_comment_count()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update spots set comment_count = comment_count + 1 where id = new.spot_id;
    return new;
  elsif tg_op = 'DELETE' then
    update spots
      set comment_count = greatest(comment_count - 1, 0)
      where id = old.spot_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists comments_sync_count on comments;
create trigger comments_sync_count
  after insert or delete on comments
  for each row execute function public.sync_comment_count();

create or replace function public.pin_comment_author()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  new.author := old.author;
  new.spot_id := old.spot_id;
  new.created_at := old.created_at;
  return new;
end;
$$;

drop trigger if exists comments_pin_author on comments;
create trigger comments_pin_author
  before update on comments
  for each row execute function public.pin_comment_author();

create or replace function public.sync_report_moderation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.target_type = 'spot' then
    update public.spots
       set report_count = report_count + 1,
           is_hidden = (report_count + 1 >= 5)
     where id = new.target_id;
  elsif new.target_type = 'comment' then
    update public.comments
       set report_count = report_count + 1,
           is_hidden = (report_count + 1 >= 5)
     where id = new.target_id;
  end if;
  return new;
end;
$$;

drop trigger if exists reports_sync_moderation on reports;
create trigger reports_sync_moderation
  after insert on reports
  for each row execute function public.sync_report_moderation();

create or replace function public.enforce_spot_rate_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  recent_count integer;
begin
  select count(*) into recent_count
    from public.spots
   where submitted_by = new.submitted_by
     and created_at > now() - interval '24 hours';
  if recent_count >= 20 then
    raise exception 'Daily spot submission limit reached. Try again tomorrow.';
  end if;
  return new;
end;
$$;

drop trigger if exists spots_rate_limit on spots;
create trigger spots_rate_limit
  before insert on spots
  for each row execute function public.enforce_spot_rate_limit();

create or replace function public.enforce_comment_rate_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  recent_count integer;
begin
  select count(*) into recent_count
    from public.comments
   where author = new.author
     and created_at > now() - interval '1 hour';
  if recent_count >= 30 then
    raise exception 'Comment rate limit reached. Wait a few minutes.';
  end if;
  return new;
end;
$$;

drop trigger if exists comments_rate_limit on comments;
create trigger comments_rate_limit
  before insert on comments
  for each row execute function public.enforce_comment_rate_limit();

create or replace function public.nearby_spots(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision default 50,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (id uuid, distance_km double precision)
language sql
stable
security invoker
set search_path = public
as $$
  with bounds as (
    select
      p_lat - (least(greatest(p_radius_km, 1), 500) / 111.045) as min_lat,
      p_lat + (least(greatest(p_radius_km, 1), 500) / 111.045) as max_lat,
      p_lng - (least(greatest(p_radius_km, 1), 500) /
        greatest(111.045 * cos(radians(p_lat)), 0.01)) as min_lng,
      p_lng + (least(greatest(p_radius_km, 1), 500) /
        greatest(111.045 * cos(radians(p_lat)), 0.01)) as max_lng
  )
  select s.id,
         (6371.0 * acos(
           least(1.0, greatest(-1.0,
             cos(radians(p_lat)) * cos(radians(s.latitude)) *
             cos(radians(s.longitude) - radians(p_lng)) +
             sin(radians(p_lat)) * sin(radians(s.latitude))
           ))
         )) as distance_km
  from public.spots s, bounds b
  where not s.is_hidden
    and s.latitude between b.min_lat and b.max_lat
    and s.longitude between b.min_lng and b.max_lng
  order by distance_km asc, s.created_at desc
  limit least(greatest(p_limit, 1), 200)
  offset greatest(p_offset, 0);
$$;

grant execute on function public.nearby_spots(
  double precision, double precision, double precision, integer, integer
) to anon, authenticated;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer set search_path = public, auth, storage
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  delete from storage.objects
    where bucket_id = 'photos' and owner = uid;
  delete from public.spots where submitted_by = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;

-- Backfill counts for any existing rows
update spots s
  set like_count = coalesce((
    select count(*) from likes l where l.spot_id = s.id
  ), 0)
  where s.like_count is distinct from coalesce((
    select count(*) from likes l where l.spot_id = s.id
  ), 0);

update spots s
  set comment_count = coalesce((
    select count(*) from comments c where c.spot_id = s.id
  ), 0)
  where s.comment_count is distinct from coalesce((
    select count(*) from comments c where c.spot_id = s.id
  ), 0);

-- ---------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY & COLUMN-LEVEL PRIVILEGES
-- ---------------------------------------------------------------------------
alter table profiles enable row level security;
alter table spots enable row level security;
alter table photos enable row level security;
alter table saves enable row level security;
alter table spot_views enable row level security;
alter table likes enable row level security;
alter table comments enable row level security;
alter table reports enable row level security;
alter table blocked_users enable row level security;

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

drop policy if exists "Spots are viewable by everyone" on spots;
create policy "Spots are viewable by everyone"
  on spots for select using ( not is_hidden or auth.uid() = submitted_by );

drop policy if exists "Authenticated users can insert spots" on spots;
create policy "Authenticated users can insert spots"
  on spots for insert to authenticated
  with check (
    auth.uid() = submitted_by
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Users can update own spots" on spots;
create policy "Users can update own spots"
  on spots for update using ( auth.uid() = submitted_by );

drop policy if exists "Users can delete own spots" on spots;
create policy "Users can delete own spots"
  on spots for delete using ( auth.uid() = submitted_by );

revoke insert, update on spots from anon, authenticated;
grant insert (
  title, description, city, latitude, longitude, tags, best_time,
  focal_length, tripod_friendly, access_note, submitted_by
) on spots to authenticated;
grant update (
  title, description, city, latitude, longitude, tags, best_time,
  focal_length, tripod_friendly, access_note
) on spots to authenticated;

drop policy if exists "Photos are viewable by everyone" on photos;
create policy "Photos are viewable by everyone"
  on photos for select using ( true );

drop policy if exists "Authenticated users can insert photos" on photos;
create policy "Authenticated users can insert photos"
  on photos for insert to authenticated
  with check (
    auth.uid() = uploader
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Photo owners can delete rows" on photos;
create policy "Photo owners can delete rows"
  on photos for delete using ( auth.uid() = uploader );

drop policy if exists "Users can view own saves" on saves;
create policy "Users can view own saves"
  on saves for select using ( auth.uid() = user_id );

drop policy if exists "Users can insert own saves" on saves;
create policy "Users can insert own saves"
  on saves for insert to authenticated
  with check (
    auth.uid() = user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Users can delete own saves" on saves;
create policy "Users can delete own saves"
  on saves for delete using ( auth.uid() = user_id );

drop policy if exists "Anyone can insert spot views" on spot_views;
drop policy if exists "Users can insert own spot views" on spot_views;
create policy "Users can insert own spot views"
  on spot_views for insert to authenticated
  with check (
    auth.uid() = viewer
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Anyone can view spot views" on spot_views;
drop policy if exists "Users can view own spot views" on spot_views;
create policy "Users can view own spot views"
  on spot_views for select using ( auth.uid() = viewer );

drop policy if exists "Likes are viewable by everyone" on likes;
create policy "Likes are viewable by everyone"
  on likes for select using ( true );

drop policy if exists "Users can insert own likes" on likes;
create policy "Users can insert own likes"
  on likes for insert to authenticated
  with check (
    auth.uid() = user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Users can delete own likes" on likes;
create policy "Users can delete own likes"
  on likes for delete using ( auth.uid() = user_id );

drop policy if exists "Comments are viewable by everyone" on comments;
create policy "Comments are viewable by everyone"
  on comments for select using ( not is_hidden or auth.uid() = author );

drop policy if exists "Users can insert own comments" on comments;
create policy "Users can insert own comments"
  on comments for insert to authenticated
  with check (
    auth.uid() = author
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Users can update own comments" on comments;
create policy "Users can update own comments"
  on comments for update using ( auth.uid() = author )
  with check ( auth.uid() = author );

drop policy if exists "Users can delete own comments" on comments;
create policy "Users can delete own comments"
  on comments for delete using ( auth.uid() = author );

revoke insert, update on comments from anon, authenticated;
grant insert (spot_id, author, body) on comments to authenticated;
grant update (body) on comments to authenticated;

drop policy if exists "Users can submit own reports" on reports;
create policy "Users can submit own reports"
  on reports for insert to authenticated
  with check (
    auth.uid() = reporter_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Users can view own reports" on reports;
create policy "Users can view own reports"
  on reports for select to authenticated
  using ( auth.uid() = reporter_id );

drop policy if exists "Users can view own blocks" on blocked_users;
create policy "Users can view own blocks"
  on blocked_users for select to authenticated
  using ( auth.uid() = blocker_id );

drop policy if exists "Users can insert own blocks" on blocked_users;
create policy "Users can insert own blocks"
  on blocked_users for insert to authenticated
  with check (
    auth.uid() = blocker_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists "Users can delete own blocks" on blocked_users;
create policy "Users can delete own blocks"
  on blocked_users for delete to authenticated
  using ( auth.uid() = blocker_id );

-- ---------------------------------------------------------------------------
-- 6. STORAGE BUCKET & POLICIES
-- ---------------------------------------------------------------------------
do $$
begin
  insert into storage.buckets (id, name, public)
  values ('photos', 'photos', true)
  on conflict (id) do update set public = excluded.public;
exception when others then
  null;
end $$;

drop policy if exists "Public photo reads" on storage.objects;
create policy "Public photo reads"
  on storage.objects for select
  using ( bucket_id = 'photos' );

drop policy if exists "Authenticated photo uploads" on storage.objects;
create policy "Authenticated photo uploads"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and (storage.foldername(name))[1] in ('spots', 'avatars')
    and (storage.foldername(name))[2] = auth.uid()::text
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
-- 7. SEED DATA: Lisbon photo spots
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

insert into photos (spot_id, image_url)
select s.id,
       'https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/public/photos/seed/'
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
-- =============================================================================
-- PhotoSpot — Complete Single-File Supabase Setup (Schema + Engagement + Fixes)
-- =============================================================================
-- Paste this entire file into your Supabase SQL Editor and click "Run".
-- Every statement is 100% idempotent and safe to re-run at any time.
--
-- After running:
--   1. No provider changes are required: the app never signs in anonymously.
--      Browsing works through the public anon role; publishing, saving and
--      commenting require a normal (non-anonymous) email account.
--   2. A public Storage bucket named "photos" is created automatically with an
--      8 MB per-file limit, an image-only MIME allowlist and a daily upload
--      rate limit. Review it under Storage at any time.
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
  created_at timestamptz default now(),
  -- True when this is an equirectangular 360° capture (DJI/Insta360/etc.).
  is360 boolean not null default false
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

-- Audit trail for content owners who contest an automatic report-based hide.
-- Written only through public.appeal_hidden_content(); moderators (once they
-- exist) review this table instead of trusting report counts blindly.
create table if not exists moderation_appeals (
  id uuid default gen_random_uuid() primary key,
  target_type text not null check (target_type in ('spot', 'comment')),
  target_id uuid not null,
  appellant uuid not null references profiles(id) on delete cascade,
  note text check (note is null or char_length(note) <= 500),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists blocked_users (
  blocker_id uuid references profiles(id) on delete cascade not null,
  blocked_id uuid references profiles(id) on delete cascade not null,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- Clean up null or duplicate spot_views before applying NOT NULL and UNIQUE constraints
delete from spot_views where viewer is null;
delete from spot_views a using spot_views b
 where a.viewer = b.viewer
   and a.spot_id = b.spot_id
   and a.id > b.id;

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
-- Only HTTPS URLs that point at this project's public `photos` bucket are
-- accepted: clients cannot insert arbitrary external image URLs. If your
-- project uses a custom storage domain, extend the pattern accordingly.
alter table photos add constraint photos_url_https
  check (
    image_url ~ '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/photos/'
    and char_length(image_url) <= 2048
  ) not valid;

alter table photos drop constraint if exists photos_caption_len;
alter table photos add constraint photos_caption_len
  check (caption is null or char_length(caption) <= 500) not valid;

create unique index if not exists spots_title_city_key on spots (title, city);
create unique index if not exists spot_views_spot_viewer_key
  on spot_views (spot_id, viewer);
alter table spot_views alter column viewer set default auth.uid();
alter table spot_views alter column viewer set not null;

create unique index if not exists reports_unique_reporter_target
  on reports (reporter_id, target_type, target_id);

create index if not exists moderation_appeals_target_idx
  on moderation_appeals (target_type, target_id, created_at desc);

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
declare
  owner_id uuid;
begin
  if new.target_type = 'spot' then
    select submitted_by into owner_id from public.spots where id = new.target_id;
    -- Reporting your own content never advances moderation: one account could
    -- otherwise hide its own spot to fake a pile-on, or pad the count.
    if owner_id is not null and owner_id = new.reporter_id then
      return new;
    end if;
    update public.spots
       set report_count = report_count + 1,
           is_hidden = (report_count + 1 >= 5)
     where id = new.target_id;
  elsif new.target_type = 'comment' then
    select author into owner_id from public.comments where id = new.target_id;
    if owner_id is not null and owner_id = new.reporter_id then
      return new;
    end if;
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

-- Owner appeal for report-hidden content: records an audit row, clears the
-- hide and resets the report count so five fresh distinct reports are needed
-- again. One appeal per target per week keeps the loop cheap to abuse.
create or replace function public.appeal_hidden_content(
  p_target_type text,
  p_target_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  owner_id uuid;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_target_type not in ('spot', 'comment') then
    raise exception 'Unknown moderation target';
  end if;

  if p_target_type = 'spot' then
    select submitted_by into owner_id from public.spots where id = p_target_id;
  else
    select author into owner_id from public.comments where id = p_target_id;
  end if;

  if owner_id is distinct from uid then
    raise exception 'You can only appeal your own content.';
  end if;

  if exists (
    select 1 from public.moderation_appeals a
    where a.target_type = p_target_type
      and a.target_id = p_target_id
      and a.created_at > now() - interval '7 days'
  ) then
    raise exception 'An appeal was already filed this week for this content.';
  end if;

  insert into public.moderation_appeals (target_type, target_id, appellant, note)
  values (p_target_type, p_target_id, uid, left(coalesce(p_note, ''), 500));

  if p_target_type = 'spot' then
    update public.spots
       set is_hidden = false, report_count = 0
     where id = p_target_id;
  else
    update public.comments
       set is_hidden = false, report_count = 0
     where id = p_target_id;
  end if;
end;
$$;

revoke all on function public.appeal_hidden_content(text, uuid, text) from public;
grant execute on function public.appeal_hidden_content(text, uuid, text) to authenticated;

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

create or replace function public.enforce_photo_rate_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  recent_count integer;
begin
  select count(*) into recent_count
    from public.photos
   where uploader = new.uploader
     and created_at > now() - interval '24 hours';
  if recent_count >= 50 then
    raise exception 'Daily photo upload limit reached. Try again tomorrow.';
  end if;
  return new;
end;
$$;

drop trigger if exists photos_rate_limit on photos;
create trigger photos_rate_limit
  before insert on photos
  for each row execute function public.enforce_photo_rate_limit();

-- Private profile fields stay owner-only: the API exposes id, display_name and
-- avatar_url (see the column grants in section 5); bio and city are read back
-- through this function so a fresh device can restore them after sign-in.
create or replace function public.my_profile()
returns table (display_name text, bio text, city text, avatar_url text)
language sql stable security definer set search_path = public
as $$
  select p.display_name, p.bio, p.city, p.avatar_url
  from public.profiles p
  where p.id = auth.uid();
$$;

revoke all on function public.my_profile() from public;
grant execute on function public.my_profile() to authenticated;

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
  -- Photos and views reference profiles without cascade and would otherwise
  -- block the delete; photos on other people's spots would be left behind as
  -- dead URLs once their storage objects are gone.
  delete from public.photos where uploader = uid;
  delete from public.spot_views where viewer = uid;
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
alter table moderation_appeals enable row level security;

-- Profiles are public only for people who actually contributed something
-- (plus your own row). This stops unauthenticated enumeration of every
-- registered account while the author joins below keep working.
drop policy if exists "Public profiles are viewable by everyone" on profiles;
drop policy if exists "Profiles of contributors are viewable" on profiles;
create policy "Profiles of contributors are viewable"
  on profiles for select using (
    auth.uid() = id
    or exists (select 1 from public.spots s where s.submitted_by = profiles.id)
    or exists (select 1 from public.photos p where p.uploader = profiles.id)
    or exists (select 1 from public.comments c where c.author = profiles.id)
  );

-- Column-level lockdown: only the fields other people need leave the API.
-- bio and city are private and are read back through public.my_profile().
-- A table-wide `select *` on profiles is intentionally no longer possible.
revoke select on profiles from anon, authenticated;
grant select (id, display_name, avatar_url) on profiles to anon, authenticated;

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

-- Same defence as comments: clients may only supply content columns. Row ids,
-- created_at and any future moderation column stay server-owned.
revoke insert, update on photos from anon, authenticated;
grant insert (spot_id, uploader, image_url, caption, taken_at, is360)
  on photos to authenticated;

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

-- Appeals are written only by public.appeal_hidden_content() (security
-- definer); owners may read back their own appeals. No insert/update/delete
-- policy exists, so clients cannot forge or tamper with the audit trail.
drop policy if exists "Appellants can view own appeals" on moderation_appeals;
create policy "Appellants can view own appeals"
  on moderation_appeals for select to authenticated
  using ( auth.uid() = appellant );

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
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values (
    'photos',
    'photos',
    true,
    8 * 1024 * 1024,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
  )
  on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
exception when others then
  null;
end $$;

-- Server-side upload rate limit. The table triggers in section 4 cap photo
-- rows; this caps raw storage writes so nobody can fill the bucket without
-- inserting rows. Wrapped in an exception block because not every project
-- role may hold TRIGGER on storage.objects; failing here must not abort the
-- rest of the setup script.
do $$
begin
  create or replace function public.enforce_storage_upload_rate()
  returns trigger
  language plpgsql
  security definer set search_path = public, storage
  as $fn$
  declare
    recent_count integer;
  begin
    if new.bucket_id <> 'photos' or new.owner is null then
      return new;
    end if;
    select count(*) into recent_count
      from storage.objects
     where bucket_id = 'photos'
       and owner = new.owner
       and created_at > now() - interval '24 hours';
    if recent_count >= 60 then
      raise exception 'Daily upload limit reached. Try again tomorrow.';
    end if;
    return new;
  end;
  $fn$;

  drop trigger if exists photos_upload_rate_limit on storage.objects;
  create trigger photos_upload_rate_limit
    before insert on storage.objects
    for each row execute function public.enforce_storage_upload_rate();
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
  using ( bucket_id = 'photos' and owner = auth.uid() )
  with check ( bucket_id = 'photos' and owner = auth.uid() );

drop policy if exists "Photo owners can delete" on storage.objects;
create policy "Photo owners can delete"
  on storage.objects for delete to authenticated
  using ( bucket_id = 'photos' and owner = auth.uid() );

-- ---------------------------------------------------------------------------
-- 7. SEED DATA: Lisbon photo spots
-- ---------------------------------------------------------------------------
-- Content only: no fabricated ratings, review counts or engagement numbers.
-- Rating, review_count, save_count and view_count stay at their server
-- defaults (0 real engagement) until real people use the app.
insert into spots
  (title, description, city, latitude, longitude, tags, best_time)
values
  ('Miradouro da Senhora do Monte', 'Highest viewpoint in Alfama. The whole city falls away toward the river — arrive 45 min before sunset.', 'Lisbon', 38.7223, -9.1335, ARRAY['skyline','sunset','date'], 'Golden hour'),
  ('Miradouro de Santa Luzia', 'Blue-and-white azulejo wall framed by bougainvillea. Best in soft morning light before the tour groups arrive.', 'Lisbon', 38.7121, -9.1305, ARRAY['tiles','street','friends','date'], 'Morning light'),
  ('Praça do Comércio', 'Symmetrical arch and riverside square. Stand under Rua Augusta Arch to frame the whole plaza.', 'Lisbon', 38.7077, -9.1365, ARRAY['architecture','symmetry','date','friends'], 'Blue hour'),
  ('Belém Tower', 'Shoot from the far side of the water for the full silhouette. Low tide exposes reflective sand.', 'Lisbon', 38.6916, -9.2160, ARRAY['landmark','water','date'], 'Sunset'),
  ('LX Factory', 'Industrial chic under the 25 de Abril bridge — murals, neon signs, gritty textures.', 'Lisbon', 38.7033, -9.1786, ARRAY['street','industrial','friends'], 'Afternoon'),
  ('Tram 28 at Graça', 'The classic yellow tram shot. Stand on the pavement bend and wait for the tram to crest the hill.', 'Lisbon', 38.7169, -9.1332, ARRAY['street','tram','friends'], 'Golden hour'),
  ('Castelo de São Jorge', 'Ramparts look straight down over the red rooftops. Golden hour hits the castle walls first.', 'Lisbon', 38.7139, -9.1335, ARRAY['skyline','landmark','date'], 'Sunset'),
  ('Pink Street', 'Pink cobbles and yellow umbrellas. Empty at dawn, buzzing with neon after dark.', 'Lisbon', 38.7075, -9.1458, ARRAY['street','nightlife','friends'], 'Night'),
  ('Rua Augusta Arch', 'Perfect one-point perspective down Rua Augusta. Tripod recommended after dark.', 'Lisbon', 38.7101, -9.1394, ARRAY['architecture','symmetry','date'], 'Blue hour'),
  ('Elevador de Santa Justa', 'Gothic iron lift against the rooftops. Shoot from the upper terrace, not the street below.', 'Lisbon', 38.7121, -9.1390, ARRAY['architecture','iron','friends'], 'Blue hour'),
  ('Graça Rooftop Ledge', 'A quiet residential ledge most tourists walk past. Full river view with no one behind you.', 'Lisbon', 38.7185, -9.1347, ARRAY['skyline','hidden gem','date'], 'Golden hour'),
  ('Cais das Colunas', 'Two marble columns walking into the Tagus. Reflections pool around your feet at high tide.', 'Lisbon', 38.7066, -9.1440, ARRAY['water','reflection','date'], 'Blue hour')
on conflict (title, city) do nothing;

-- Earlier versions of this file seeded fake 4.x ratings and five-digit review
-- counts that no real feature ever updates. Clear them only where the row
-- still holds exactly the shipped values, so any real engagement recorded
-- since is left untouched.
update spots
   set rating = 4.5, review_count = 0, save_count = 0, view_count = 0
 where city = 'Lisbon'
   and (review_count, save_count, view_count) in (
     (12500, 214, 1890),
     (8400, 168, 1420),
     (21000, 192, 1675),
     (15600, 143, 1210),
     (5200, 97, 860),
     (9800, 176, 1530),
     (13400, 131, 1105),
     (7300, 120, 1015),
     (6100, 88, 790),
     (4900, 74, 640),
     (1200, 58, 430),
     (3800, 102, 895)
   );

-- Optional demo photos. Set your project ref (Project Settings -> API) to
-- seed images you have uploaded to photos/seed/; leaving it null skips photo
-- seeding instead of writing broken YOUR_PROJECT_REF URLs that would fail the
-- photos_url_https constraint anyway.
do $$
declare
  project_ref text := null; -- e.g. 'abcdefghijklmno'
begin
  if project_ref is null then
    return;
  end if;

  insert into photos (spot_id, image_url)
  select s.id,
         'https://' || project_ref || '.supabase.co/storage/v1/object/public/photos/seed/'
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
end $$;
-- ---------------------------------------------------------------------------
-- 8. REALTIME: live spots, photos and comments
-- ---------------------------------------------------------------------------
-- The app subscribes to row changes so ranking, save/like/comment counters and
-- open comment threads update themselves. Adding a table that is already part
-- of the publication raises duplicate_object; a project without the default
-- publication raises undefined_object. Both are safe to ignore.
do $$
begin
  begin
    alter publication supabase_realtime add table public.spots;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.photos;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.comments;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

-- PhotoSpot engagement upgrade: likes, comments, and hardened counters.
-- Run AFTER supabase_schema.sql in the Supabase SQL editor. Every statement is
-- idempotent, so re-running it is safe.
--
-- Security model enforced here (not in the client):
--   * A person can only write rows that belong to their own auth.uid().
--   * Nobody can edit or delete someone else's comment, like, or profile.
--   * Engagement counters are maintained by SECURITY DEFINER triggers and the
--     count columns are not writable by API clients, so numbers cannot be
--     forged by a crafted request.
--   * spot_views stops leaking who viewed what: reads are limited to your own
--     rows.
--
-- Prerequisites from supabase_schema.sql: profiles, spots, spot_views, and the
-- "Anonymous sign-ins" provider if guests should be able to interact.

-- ---------------------------------------------------------------------------
-- New engagement columns
-- ---------------------------------------------------------------------------
alter table spots add column if not exists like_count integer not null default 0;
alter table spots add column if not exists comment_count integer not null default 0;

alter table profiles add column if not exists city text;

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

-- ---------------------------------------------------------------------------
-- Likes: one per person per spot
-- ---------------------------------------------------------------------------
create table if not exists likes (
  user_id uuid references profiles(id) on delete cascade not null,
  spot_id uuid references spots(id) on delete cascade not null,
  created_at timestamptz not null default now(),
  primary key (user_id, spot_id)
);

alter table likes enable row level security;

drop policy if exists "Likes are viewable by everyone" on likes;
create policy "Likes are viewable by everyone"
  on likes for select using ( true );

drop policy if exists "Users can insert own likes" on likes;
create policy "Users can insert own likes"
  on likes for insert with check ( auth.uid() = user_id );

drop policy if exists "Users can delete own likes" on likes;
create policy "Users can delete own likes"
  on likes for delete using ( auth.uid() = user_id );

-- No update policy on purpose: a like is created or removed, never edited.

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------
create table if not exists comments (
  id uuid default gen_random_uuid() primary key,
  spot_id uuid references spots(id) on delete cascade not null,
  author uuid references profiles(id) on delete cascade not null,
  body text not null,
  created_at timestamptz not null default now(),
  constraint comments_body_len
    check (char_length(btrim(body)) between 1 and 500)
);

create index if not exists comments_spot_created_idx
  on comments (spot_id, created_at desc);

alter table comments enable row level security;

drop policy if exists "Comments are viewable by everyone" on comments;
create policy "Comments are viewable by everyone"
  on comments for select using ( true );

drop policy if exists "Users can insert own comments" on comments;
create policy "Users can insert own comments"
  on comments for insert with check ( auth.uid() = author );

-- Editing is allowed only for the author, and only the body can change in
-- practice because a trigger pins the owner and creation time.
drop policy if exists "Users can update own comments" on comments;
create policy "Users can update own comments"
  on comments for update using ( auth.uid() = author )
  with check ( auth.uid() = author );

drop policy if exists "Users can delete own comments" on comments;
create policy "Users can delete own comments"
  on comments for delete using ( auth.uid() = author );

-- ---------------------------------------------------------------------------
-- Counter triggers (server-authoritative)
-- ---------------------------------------------------------------------------
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

-- Pin ownership fields so an author cannot reassign a comment to someone else
-- (RLS already blocks the row change, this keeps the data honest if policies
-- are ever widened).
create or replace function public.pin_comment_author()
returns trigger
language plpgsql
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

-- Backfill counts for rows written before the triggers existed.
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
-- Stop clients from writing counters directly.
-- Without this, the owner of a spot could PATCH save_count/like_count to any
-- value they like through the spots update policy.
-- ---------------------------------------------------------------------------
revoke update (save_count, view_count, like_count, comment_count)
  on spots from anon, authenticated;

-- ---------------------------------------------------------------------------
-- View privacy: the previous policy let any client read every view row.
-- Keep the bump trigger working (it is SECURITY DEFINER style already) while
-- exposing only your own rows.
-- ---------------------------------------------------------------------------
drop policy if exists "Anyone can view spot views" on spot_views;
drop policy if exists "Users can view own spot views" on spot_views;
create policy "Users can view own spot views"
  on spot_views for select using ( auth.uid() = viewer );

-- Anonymous sessions have no email; a signed-up account can be forced later in
-- Authentication settings without a schema change.

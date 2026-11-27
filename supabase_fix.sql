-- PhotoSpot repair script
-- Run once in the Supabase SQL editor (Dashboard → SQL editor → paste → Run).
-- Safe to run more than once.
--
-- It fixes three things:
--   1. The seed block in supabase_schema.sql is not idempotent, so running it
--      twice created two rows per spot. This removes the duplicates.
--   2. A unique index on (title, city) so the seed can never duplicate again.
--   3. Storage write policies that actually admit an anonymous Supabase
--      session (role = authenticated), so photo uploads stop failing with
--      "new row violates row-level security policy".

-- ---------------------------------------------------------------------------
-- 1 + 2. De-duplicate seeded spots, then prevent it happening again
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

-- Re-point child rows at the surviving spot before deleting the copies.
-- saves is unique per (user_id, spot_id), so drop collisions first.
delete from saves s
using _spot_dupes d
where s.spot_id = d.dupe_id
  and exists (
    select 1 from saves s2
    where s2.user_id = s.user_id and s2.spot_id = d.keep_id
  );

update saves s set spot_id = d.keep_id
from _spot_dupes d where s.spot_id = d.dupe_id;

update spot_views v set spot_id = d.keep_id
from _spot_dupes d where v.spot_id = d.dupe_id;

update photos p set spot_id = d.keep_id
from _spot_dupes d where p.spot_id = d.dupe_id;

-- Likes and comments cascade on spot delete, so leaving them behind silently
-- destroyed real engagement on every duplicate. Move them across; likes are
-- unique per (user, spot), so drop collisions first. Guarded because this
-- script may run on a project that has not applied supabase_engagement.sql.
do $$
begin
  if to_regclass('public.likes') is not null then
    delete from likes l
    using _spot_dupes d
    where l.spot_id = d.dupe_id
      and exists (
        select 1 from likes l2
        where l2.user_id = l.user_id and l2.spot_id = d.keep_id
      );
    update likes l set spot_id = d.keep_id
    from _spot_dupes d where l.spot_id = d.dupe_id;
  end if;

  if to_regclass('public.comments') is not null then
    update comments c set spot_id = d.keep_id
    from _spot_dupes d where c.spot_id = d.dupe_id;
  end if;
end $$;

delete from spots s using _spot_dupes d where s.id = d.dupe_id;

drop table if exists _spot_dupes;
drop table if exists _spot_keep;

create unique index if not exists spots_title_city_key on spots (title, city);

-- ---------------------------------------------------------------------------
-- 3. Storage policies for the public "photos" bucket
-- ---------------------------------------------------------------------------
-- "to authenticated" plus a bucket check is the reliable form: it does not
-- depend on auth.role() being populated inside the storage API.
drop policy if exists "Authenticated photo uploads" on storage.objects;
drop policy if exists "Public photo reads" on storage.objects;
drop policy if exists "Photo owners can update" on storage.objects;
drop policy if exists "Photo owners can delete" on storage.objects;

create policy "Public photo reads"
  on storage.objects for select
  using ( bucket_id = 'photos' );

create policy "Authenticated photo uploads"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and lower(storage.extension(name)) in ('jpg','jpeg','png','webp','heic','heif')
  );

create policy "Photo owners can update"
  on storage.objects for update to authenticated
  using ( bucket_id = 'photos' and owner = auth.uid() );

create policy "Photo owners can delete"
  on storage.objects for delete to authenticated
  using ( bucket_id = 'photos' and owner = auth.uid() );

-- Table policies, restated the same way (same rules, role-scoped spelling).
drop policy if exists "Authenticated users can insert photos" on photos;
create policy "Authenticated users can insert photos"
  on photos for insert to authenticated
  with check ( auth.uid() = uploader );

drop policy if exists "Authenticated users can insert spots" on spots;
create policy "Authenticated users can insert spots"
  on spots for insert to authenticated
  with check ( auth.uid() = submitted_by );

-- Same server-owned columns as supabase_schema.sql: re-running any script must
-- leave the counters and rating unwritable.
revoke insert, update on spots from anon, authenticated;
grant insert (
  title, description, city, latitude, longitude, tags, best_time, submitted_by
) on spots to anon, authenticated;
grant update (
  title, description, city, latitude, longitude, tags, best_time
) on spots to anon, authenticated;

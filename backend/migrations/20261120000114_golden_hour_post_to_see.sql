-- Make Golden Hour's "post to see" true for the pixels.
--
-- The rule is the heart of the feature: you see the wall only once you
-- have posted to it. The app enforced that with a blur. The storage
-- policy underneath said something else — any member of the circle
-- could read any capture in it — so the photo behind the blur was one
-- signed-URL request away for anyone who had not posted.
--
-- This tightens the READ policy on the `golden-hour` bucket: a member
-- can read a capture when it is their own, or when they have a post of
-- their own for that same circle and day.
--
-- Deliberately the storage policy and NOT the `golden_hour_posts` rows.
-- The rows are what the wall is drawn from — who made it, who is still
-- to post, the attendance count, streaks — and hiding them from someone
-- who has not posted would turn "3 made it, blurred" into an empty wall
-- that tells every member the others were quiet. The rows carry no
-- content; the media is the thing the rule protects.
--
-- Object paths are `<circle_id>/<day>/<user_id>-<uuid>.<ext>` (see
-- GoldenHourService.postCapture), which is what makes this expressible:
-- folder 1 is the circle, folder 2 the day, and the file name starts
-- with its author.
--
-- The day is compared as text so that a malformed path yields "no
-- access" rather than a cast error that fails the whole request.

create or replace function public.has_golden_hour_post(p_circle_id uuid, p_day text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from public.golden_hour_posts g
    where g.circle_id = p_circle_id
      and g.user_id = public.user_id()
      and to_char(g.day, 'YYYY-MM-DD') = p_day
  );
$function$;

drop policy if exists "Golden hour members read media" on storage.objects;
create policy "Golden hour members read media"
  on storage.objects
  for select
  using (
    bucket_id = 'golden-hour'
    and is_circle_member(((storage.foldername(name))[1])::uuid)
    and (
      -- Always your own capture: the upload reads it back, and your
      -- tile must render whether or not anyone else has posted.
      starts_with(storage.filename(name), user_id() || '-')
      or has_golden_hour_post(
        ((storage.foldername(name))[1])::uuid,
        (storage.foldername(name))[2]
      )
    )
  );

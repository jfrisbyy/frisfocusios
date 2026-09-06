-- Story media outlived a block inside a shared circle.
--
-- Blocking severs the friendship, so `are_friends` closes that path on
-- its own. Circle membership deliberately survives a block — you should
-- not be ejected from a group because someone blocked you — so
-- `shares_circle_with` stayed true, and with it read access to the other
-- person's story media in storage.
--
-- Not practically reachable today: fetching needs the object path, which
-- comes from a story_posts row that RLS already hides from a blocked
-- viewer. But "you would have to already know the path" is not an access
-- rule, and this policy is the only thing standing behind it. Mirrors
-- the shape of story_posts' own SELECT policy so the two cannot drift.
--
-- The own-media branch stays outside the block check: a person can't
-- block themselves, and their own uploads must always be readable.
--
-- Golden Hour media is deliberately NOT given the same treatment: its
-- object paths are keyed by circle id, not by author, so there is no
-- user to test `is_blocked` against without changing the path layout.

drop policy if exists "Stories read own friends or circle" on storage.objects;
create policy "Stories read own friends or circle"
  on storage.objects
  for select
  using (
    bucket_id = 'stories'
    and (
      (storage.foldername(name))[1] = user_id()
      or (
        not is_blocked((storage.foldername(name))[1])
        and (
          are_friends((storage.foldername(name))[1])
          or shares_circle_with((storage.foldername(name))[1])
        )
      )
    )
  );

-- is_blocked was VOLATILE, so every policy referencing it re-ran the
-- query per row instead of once per statement. It only reads. The other
-- three helpers used the same way (are_friends, shares_circle_with,
-- is_circle_member) were already STABLE; this was the odd one out.
create or replace function public.is_blocked(other_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from blocks b
    where (b.blocker_id = user_id() and b.blocked_id = other_id)
       or (b.blocker_id = other_id and b.blocked_id = user_id())
  );
$function$;

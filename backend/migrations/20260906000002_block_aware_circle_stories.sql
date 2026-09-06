-- Make blocking work inside shared circles.
--
-- can_see_story() checked blocks only on the friend branch:
--
--     p.author_id = user_id()
--     OR (p.circle_id IS NOT NULL AND is_circle_member(p.circle_id))
--     OR (p.circle_id IS NULL AND are_friends(p.author_id) AND NOT is_blocked(...))
--
-- The circle branch had no block filter, so blocking someone you share a
-- circle with did nothing: you kept seeing their circle stories and they
-- kept seeing yours. Combined with governance that never reached the
-- server, a member in a bad situation inside a circle had no working
-- recourse short of leaving their own circle.
--
-- The block check now wraps both non-author branches. Your own posts stay
-- visible unconditionally — is_blocked() is false for yourself, but the
-- structure makes that guarantee explicit rather than incidental.

create or replace function public.can_see_story(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  SELECT EXISTS (
    SELECT 1 FROM story_posts p
    WHERE p.id = p_post_id
      AND (
        p.author_id = user_id()
        OR (
          NOT is_blocked(p.author_id)
          AND (
            (p.circle_id IS NOT NULL AND is_circle_member(p.circle_id))
            OR (p.circle_id IS NULL AND are_friends(p.author_id))
          )
        )
      )
  );
$function$;

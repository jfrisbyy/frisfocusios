-- Honour all three sharing tiers, and stop defaulting to the widest one.
--
-- get_season_cards() collapsed the app's three-level model to two:
--
--     case when coalesce(st.tier, 'full') = 'quiet' then <trimmed card>
--          else sc.card end
--     ...
--     coalesce(st.tier, 'full') as tier
--
-- Two problems. First, `open` was treated as `full`, so a friend the user
-- had deliberately placed at "Progress & rhythm — but not the actual
-- tasks" was returned as `full` and the client rendered their real task
-- rows. Second, a friendship with no share_tiers row defaulted to `full`,
-- so every new friendship shared everything until the user went looking
-- for a settings screen they had no reason to visit.
--
-- The tier is now returned truthfully and the default is the middle tier.
-- Card trimming is unchanged for `quiet`; `open` and `full` both receive
-- the season-level card, because the card carries no per-task detail —
-- the open/full distinction is a rendering decision the client makes from
-- the tier this function reports.

create or replace function public.get_season_cards(target_ids text[])
returns table(user_id text, card text, tier text)
language sql
security definer
set search_path to 'public'
as $function$
  select
    sc.user_id,
    case
      when sc.user_id = user_id() then sc.card
      when coalesce(st.tier, 'open') = 'quiet' then
        case when public.try_jsonb(sc.card) is null then null
             else (public.try_jsonb(sc.card)
                     - 'milestones' - 'intention' - 'pastSeasons'
                     - 'milestonesDone' - 'milestonesTotal')::text
        end
      else sc.card
    end as card,
    case
      when sc.user_id = user_id() then 'full'
      else coalesce(st.tier, 'open')
    end as tier
  from public.season_cards sc
  left join public.share_tiers st
    on st.owner_id = sc.user_id and st.friend_id = user_id()
  where sc.user_id = any(target_ids)
    and (
      sc.user_id = user_id()
      or (
        exists (
          select 1 from public.friendships f
          where (f.user_a = user_id() and f.user_b = sc.user_id)
             or (f.user_b = user_id() and f.user_a = sc.user_id)
        )
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = user_id() and b.blocked_id = sc.user_id)
             or (b.blocker_id = sc.user_id and b.blocked_id = user_id())
        )
      )
    )
$function$;

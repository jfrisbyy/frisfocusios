-- Let a report say what it is about.
--
-- A report could point at a person, a proof message, a story post or a
-- story comment. Two things people can actually see had no reference at
-- all:
--
--   * A Golden Hour capture. The wall's "Report" filed only the author's
--     id, and the capture deletes itself about an hour later — so by the
--     time anyone looked, there was no way to tell which capture the
--     report meant, and nothing left to look at.
--   * A circle itself. Public circles are listed to strangers in
--     Discover with an owner-written name and description, and there was
--     no way to report one.
--
-- Both columns are nullable and both are additive, so every client that
-- predates them keeps filing reports exactly as before.
--
-- ON DELETE SET NULL mirrors `reports_message_id_fkey`: when a moderator
-- removes the content, the report survives with its reason, its reporter
-- and the person it was about, and `moderation_actions` keeps the id of
-- what was removed.

alter table public.reports
  add column if not exists golden_hour_post_id uuid,
  add column if not exists circle_id uuid;

alter table public.reports
  drop constraint if exists reports_golden_hour_post_id_fkey,
  add constraint reports_golden_hour_post_id_fkey
    foreign key (golden_hour_post_id) references public.golden_hour_posts(id) on delete set null;

alter table public.reports
  drop constraint if exists reports_circle_id_fkey,
  add constraint reports_circle_id_fkey
    foreign key (circle_id) references public.circles(id) on delete set null;

-- Foreign keys get an index (see 20260906000015): without one, deleting
-- a circle or a capture scans every report to find the rows to null.
-- Partial, because almost every report leaves these empty.
create index if not exists reports_golden_hour_post_id_idx
  on public.reports (golden_hour_post_id)
  where golden_hour_post_id is not null;
create index if not exists reports_circle_id_idx
  on public.reports (circle_id)
  where circle_id is not null;

-- The sweeps hold back media that has an open report against it until
-- the report is reviewed. This is the lookup they run on every pass.
create index if not exists reports_open_story_post_idx
  on public.reports (story_post_id)
  where status = 'open' and story_post_id is not null;

-- The audit trail could say "actioned" but not what was done to what.
-- Removal and suspension need both: which kind of thing, and its id —
-- kept as text because the thing itself is usually gone by then.
alter table public.moderation_actions
  add column if not exists target_kind text,
  add column if not exists target_id text;

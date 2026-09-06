-- Pin search_path on the last two functions without one.
--
-- Both are SECURITY INVOKER, so this is not the privilege-escalation
-- case the linter usually flags. It still matters: user_id() is called
-- from inside SECURITY DEFINER functions, and an unpinned search_path
-- there resolves through whatever the caller has set. Pinning costs
-- nothing — neither function touches a table.
--
-- pg_catalog is listed explicitly so current_setting, nullif and the
-- jsonb cast resolve regardless of what public contains.

alter function public.user_id() set search_path = public, pg_catalog;
alter function public.try_jsonb(text) set search_path = public, pg_catalog;

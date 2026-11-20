-- Let a device token follow whoever is signed in on the device.
--
-- `device_tokens.token` is the primary key, and all four policies on the
-- table are `user_id = user_id()`. That is right for reading and
-- deleting, and it makes one legitimate write impossible: binding a
-- token that is already filed under a DIFFERENT account.
--
-- The client did this with an upsert on `token`. For a token nobody
-- holds that is a plain insert and works. For a token another account
-- holds, the conflict turns it into an UPDATE of a row the caller does
-- not own, the UPDATE policy's USING clause fails, and the statement is
-- refused. So after an account switch on one phone — sign out of A, sign
-- in as B — B's upsert errored, the row stayed A's, and the phone went
-- on receiving A's pushes while B received none. Sign-out now removes
-- the row first, but that is a network call made on the way out and
-- cannot be relied on (offline, app killed, session already expired),
-- so the re-bind has to be possible on its own.
--
-- Widening the UPDATE policy is the wrong fix: any signed-in account
-- could then rewrite any token row it can name. A SECURITY DEFINER
-- function narrows it to the one thing that is safe — the caller taking
-- a token FOR THEMSELVES. Nothing here lets an account file a token
-- under someone else, read anyone's tokens, or delete a row without
-- replacing it with its own.
--
-- What a caller can do with it: move a token it already knows onto its
-- own account. A token is a secret between a device and this table (no
-- policy exposes another account's rows), so knowing one means holding
-- the device. Even with a stolen token the outcome is the thief's OWN
-- notifications arriving on that device, never the reverse.

create or replace function public.claim_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me text := public.user_id();
begin
  if v_me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  -- APNs tokens reach here hex-encoded by the app: 64 characters today,
  -- and Apple reserves the right to lengthen them. Anything else is not
  -- a token and has no business becoming a row that send-push will later
  -- post to Apple.
  if p_token is null or p_token !~ '^[0-9a-f]{32,512}$' then
    raise exception 'Not a device token' using errcode = '22023';
  end if;

  -- Drop the previous account's claim outright rather than updating it
  -- in place, so created_at tells the truth about when THIS account
  -- first held the token.
  delete from public.device_tokens
   where token = p_token and user_id <> v_me;

  -- Then file it under the caller. The conflict arm covers both the
  -- ordinary case (this account re-registering its own token on every
  -- launch, which only needs updated_at moved) and a concurrent claim
  -- landing between the two statements.
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, v_me, 'ios', now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$function$;

-- Signed-in accounts only. Postgres grants EXECUTE on every new function
-- to PUBLIC and `anon` inherits it, so revoking the role alone removes
-- nothing — see 20260906000012.
revoke execute on function public.claim_device_token(text) from public;
revoke execute on function public.claim_device_token(text) from anon;
grant execute on function public.claim_device_token(text) to authenticated;

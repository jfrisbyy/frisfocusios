-- The table behind shared tasks in a group focus session.
--
-- `SocialSyncService+Grove` has always read and written
-- `focus_shared_tasks` — publish my shared tasks, read everyone's — but
-- the table was never created. Both calls failed, both failures were
-- logged and swallowed ("best-effort"), and so the task tray in a shared
-- session only ever showed your own tasks. Nothing looked broken; the
-- feature simply never arrived.
--
-- Shape taken from the client's wire struct (`FocusSharedTaskRow`):
-- block_id, user_id, task_id, title, done. The client replaces its own
-- set on every change — delete mine for this block, insert the current
-- list — so there is no upsert key to honour and a surrogate id is the
-- most forgiving primary key: a session that somehow attaches the same
-- task twice still publishes instead of failing the whole insert.

create table if not exists public.focus_shared_tasks (
  id uuid primary key default gen_random_uuid(),
  block_id uuid not null references public.focus_blocks(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  task_id uuid not null,
  title text not null,
  done boolean not null default false,
  created_at timestamptz not null default now()
);

-- Every read is "this block"; every delete is "mine in this block".
create index if not exists focus_shared_tasks_block_user_idx
  on public.focus_shared_tasks (block_id, user_id);
-- The cascade from profiles needs its own (see 20260906000016).
create index if not exists focus_shared_tasks_user_id_idx
  on public.focus_shared_tasks (user_id);

alter table public.focus_shared_tasks enable row level security;

-- Same audience as presence: the host and the participants of the
-- block, through the helper `focus_participants` already uses.
drop policy if exists "Block members read shared tasks" on public.focus_shared_tasks;
create policy "Block members read shared tasks" on public.focus_shared_tasks
  for select
  using (public.in_focus_block(block_id));

-- Only ever your own rows, and only in a block you are actually in.
drop policy if exists "Publish my shared tasks" on public.focus_shared_tasks;
create policy "Publish my shared tasks" on public.focus_shared_tasks
  for insert
  with check (user_id = public.user_id() and public.in_focus_block(block_id));

drop policy if exists "Update my shared tasks" on public.focus_shared_tasks;
create policy "Update my shared tasks" on public.focus_shared_tasks
  for update
  using (user_id = public.user_id())
  with check (user_id = public.user_id() and public.in_focus_block(block_id));

drop policy if exists "Remove my shared tasks" on public.focus_shared_tasks;
create policy "Remove my shared tasks" on public.focus_shared_tasks
  for delete
  using (user_id = public.user_id());

-- Stated rather than inherited from the project's default privileges,
-- so the table works the same wherever this file is replayed.
revoke all on public.focus_shared_tasks from anon;
grant select, insert, update, delete on public.focus_shared_tasks to authenticated;
grant all on public.focus_shared_tasks to service_role;

-- Live updates, without a second subscription.
--
-- The client's realtime channel listens to `focus_blocks` and
-- `focus_participants`, and every participant change already triggers a
-- grove refresh that re-reads the shared tasks. It does not subscribe to
-- this table, so adding the table to the `supabase_realtime` publication
-- would deliver nothing. Instead, publishing tasks touches the
-- publisher's own participant row: that is an event every device in the
-- block already receives, so a check-off shows up on a friend's screen
-- within the usual debounce, on every client version.
--
-- Statement-level with transition tables: a list of five tasks is one
-- touch, not five. SECURITY DEFINER because the touch is a consequence
-- of a write the policy above already authorised, and should not depend
-- on `focus_participants`' own update policy continuing to allow it.

create or replace function public.touch_focus_participant_for_shared_tasks()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update public.focus_participants fp
     set updated_at = now()
    from (select distinct block_id, user_id from changed_rows) c
   where fp.block_id = c.block_id
     and fp.user_id = c.user_id;
  return null;
end;
$function$;

revoke execute on function public.touch_focus_participant_for_shared_tasks() from public;
revoke execute on function public.touch_focus_participant_for_shared_tasks() from anon;
revoke execute on function public.touch_focus_participant_for_shared_tasks() from authenticated;

drop trigger if exists focus_shared_tasks_touch_ins on public.focus_shared_tasks;
create trigger focus_shared_tasks_touch_ins
  after insert on public.focus_shared_tasks
  referencing new table as changed_rows
  for each statement
  execute function public.touch_focus_participant_for_shared_tasks();

drop trigger if exists focus_shared_tasks_touch_upd on public.focus_shared_tasks;
create trigger focus_shared_tasks_touch_upd
  after update on public.focus_shared_tasks
  referencing new table as changed_rows
  for each statement
  execute function public.touch_focus_participant_for_shared_tasks();

drop trigger if exists focus_shared_tasks_touch_del on public.focus_shared_tasks;
create trigger focus_shared_tasks_touch_del
  after delete on public.focus_shared_tasks
  referencing old table as changed_rows
  for each statement
  execute function public.touch_focus_participant_for_shared_tasks();

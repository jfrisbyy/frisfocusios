-- Proof library: the permanent archive of everything a person captured.
--
-- Recovered into the repo after being applied directly. The shape below
-- is what the live database actually has (columns, policies, grants,
-- indexes and the bucket), verified against it rather than rewritten.
--
-- Two decisions worth keeping visible:
--
-- 1. Real foreign ids, not display names. The on-device library links a
--    proof to its task by TITLE, which is why "show me every proof for
--    this milestone" was impossible to answer and why renaming a task
--    orphaned its proofs.
--
-- 2. Its own bucket, holding its own copy. The library must never point
--    at the `stories` bucket: `stories-sweep` deletes that media after
--    25 hours and would quietly eat the archive.

create table if not exists public.proof_library (
    id uuid primary key default gen_random_uuid(),
    -- Cascades with the profile, so deleting an account takes the rows
    -- with it. The storage objects are a separate sweep — see the
    -- account-deletion function.
    user_id text not null references public.profiles(id) on delete cascade,
    -- When the proof was CAPTURED, which is what the grid sorts by.
    -- `created_at` is when the row reached the server, and the two can
    -- be far apart: the library is local-first and uploads on Wi-Fi.
    captured_at timestamptz not null,
    created_at timestamptz not null default now(),
    kind text not null check (kind in ('photo', 'video')),
    media_path text,
    duration double precision,
    caption text,
    task_id uuid,
    todo_id uuid,
    milestone_id uuid,
    note_id uuid,
    -- Where this proof was sent, if anywhere: 'story', 'circle',
    -- 'friend'. Empty means it was only ever kept.
    shared_to text[] not null default '{}'
);

create index if not exists proof_library_user_captured_idx
    on public.proof_library (user_id, captured_at desc);
create index if not exists proof_library_task_idx
    on public.proof_library (task_id) where task_id is not null;
create index if not exists proof_library_todo_idx
    on public.proof_library (todo_id) where todo_id is not null;
create index if not exists proof_library_milestone_idx
    on public.proof_library (milestone_id) where milestone_id is not null;
create index if not exists proof_library_note_idx
    on public.proof_library (note_id) where note_id is not null;

alter table public.proof_library enable row level security;

-- Supabase grants ALL on new public tables to anon and authenticated by
-- default, and a policy sits ON TOP of the table grant rather than
-- replacing it. Revoke first, then hand back only what a signed-in
-- person needs; anon keeps nothing at all.
revoke all on public.proof_library from anon, authenticated, public;
grant select, insert, update, delete on public.proof_library to authenticated;

drop policy if exists "Own proof library only" on public.proof_library;
create policy "Own proof library only" on public.proof_library
    for all
    using (user_id = public.user_id())
    with check (user_id = public.user_id());

-- Media lives under `{user_id}/{uuid}.{ext}`, so the first path segment
-- is the owner check.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proof-library', 'proof-library', false, 209715200, array['image/*', 'video/*'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Own library media read" on storage.objects;
create policy "Own library media read" on storage.objects
    for select
    using (bucket_id = 'proof-library' and (storage.foldername(name))[1] = public.user_id());

drop policy if exists "Own library media write" on storage.objects;
create policy "Own library media write" on storage.objects
    for insert
    with check (bucket_id = 'proof-library' and (storage.foldername(name))[1] = public.user_id());

drop policy if exists "Own library media delete" on storage.objects;
create policy "Own library media delete" on storage.objects
    for delete
    using (bucket_id = 'proof-library' and (storage.foldername(name))[1] = public.user_id());

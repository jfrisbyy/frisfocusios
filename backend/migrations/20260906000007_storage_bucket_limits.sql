-- Bound what can be uploaded.
--
-- Every bucket had file_size_limit and allowed_mime_types both NULL, which
-- means any signed-in account could upload a file of any size and any type,
-- without limit. Storage is billed by the gigabyte and these buckets accept
-- video, so this was the second unmetered cost path alongside the AI
-- functions — and an arbitrary-content upload endpoint besides.
--
-- Ceilings are set well above what the app actually produces (proofs and
-- stories are transcoded before upload) so nothing legitimate is refused;
-- they exist to bound abuse, not to ration normal use. MIME types use
-- wildcards for the same reason — the goal is "not an arbitrary file
-- host", not a fight with every camera format on the platform.

update storage.buckets set
  file_size_limit = 10485760,                        -- 10 MB
  allowed_mime_types = array['image/*']
where id = 'avatars';

update storage.buckets set
  file_size_limit = 209715200,                       -- 200 MB
  allowed_mime_types = array['image/*', 'video/*']
where id in ('proofs', 'stories', 'golden-hour');

-- Notes carry photos and voice memos.
update storage.buckets set
  file_size_limit = 104857600,                       -- 100 MB
  allowed_mime_types = array['image/*', 'audio/*', 'video/*']
where id = 'note-media';

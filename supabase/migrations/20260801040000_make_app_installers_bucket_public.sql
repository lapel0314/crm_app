-- Simpler alternative to the signed-URL/login-gated approach: serve installers
-- from a public Storage bucket instead of public GitHub Release links. This
-- decouples installer distribution from GitHub repo visibility (the repo can
-- go private without breaking downloads) while keeping the same "URL alone
-- is enough" security level the app already had with public GitHub Releases.
--
-- Upload/replace/delete stay privileged-only via the existing storage.objects
-- policies from 20260801020000_private_app_installers_storage.sql — a public
-- bucket only affects read access, which bypasses RLS entirely via Supabase's
-- public object URL path.

update storage.buckets set public = true where id = 'app-installers';

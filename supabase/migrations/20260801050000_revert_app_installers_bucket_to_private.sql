-- Reverting the public-bucket distribution experiment from
-- 20260801040000: this project's free tier caps Storage uploads at 50MiB,
-- which is too small for the Android APK (~64MB). Installer distribution
-- stays on public GitHub Release links for now (unchanged from before this
-- migration), and app_updates was never switched over to storage_path.

update storage.buckets set public = false where id = 'app-installers';

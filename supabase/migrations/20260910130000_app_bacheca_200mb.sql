-- Bacheca: allegati fino a 200 MiB (PDF/foto).
update storage.buckets
set file_size_limit = 209715200 -- 200 MiB
where id = 'app_bacheca';

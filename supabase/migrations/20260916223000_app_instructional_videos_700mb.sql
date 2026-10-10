-- Video istruttivi: limite upload 700 MiB.

update storage.buckets
set file_size_limit = 734003200 -- 700 * 1024 * 1024
where id = 'app_instructional_videos';

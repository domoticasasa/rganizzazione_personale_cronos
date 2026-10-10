-- Chat allegati: alza il limite storage da 15 MB a 50 MB.
update storage.buckets
set file_size_limit = 52428800 -- 50 * 1024 * 1024
where id = 'chat_allegati';

-- Documenti MDO: limite file 200 MB (allineato al client app).
update storage.buckets
set file_size_limit = 209715200 -- 200 MiB
where id = 'logistica_mdo_documenti';

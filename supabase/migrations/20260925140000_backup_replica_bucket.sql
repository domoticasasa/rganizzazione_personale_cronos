-- Bucket replica per copia secondaria automatica (finché non si configura S3/R2).

insert into storage.buckets (id, name, public, file_size_limit)
values ('cronos_data_backups_replica', 'cronos_data_backups_replica', false, 524288000)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit;

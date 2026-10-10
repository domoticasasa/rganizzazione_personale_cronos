-- Documenti MDO: PDF scansionati oltre 200 MB.

update storage.buckets
set file_size_limit = 536870912 -- 512 MiB
where id = 'logistica_mdo_documenti';

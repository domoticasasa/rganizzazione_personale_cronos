alter table public.personale
alter column camera_tipo_default set default 'doppia';

update public.personale
set camera_tipo_default = 'doppia'
where camera_tipo_default is null
   or camera_tipo_default not in ('singola', 'doppia')
   or camera_tipo_default = 'singola';

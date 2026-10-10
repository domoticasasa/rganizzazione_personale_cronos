-- Helper per ripristino backup dati (solo service_role / edge function).

create or replace function public._admin_backup_truncate_public_tables()
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  names text[];
  stmt text;
begin
  select coalesce(
    array_agg(quote_ident(c.relname) order by c.relname),
    '{}'::text[]
  )
  into names
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relname not like 'pg_%'
    and c.relname <> 'data_backup_runs';

  if names is null or cardinality(names) = 0 then
    return '{}'::text[];
  end if;

  stmt := 'truncate table ' || array_to_string(names, ', ') ||
    ' restart identity cascade';
  execute stmt;
  return names;
end;
$$;

comment on function public._admin_backup_truncate_public_tables() is
  'TRUNCATE di tutte le tabelle public (escluso data_backup_runs) per restore backup.';

revoke all on function public._admin_backup_truncate_public_tables()
  from public, anon, authenticated;
grant execute on function public._admin_backup_truncate_public_tables()
  to service_role;

-- Impostazioni App: utilizzo spazio database + storage (solo admin).

create or replace function public.admin_supabase_usage()
returns jsonb
language plpgsql
security definer
set search_path = public, storage, auth, pg_catalog
as $$
declare
  v_db_bytes bigint := 0;
  v_storage_bytes bigint := 0;
  v_auth_users bigint := 0;
  v_app_users bigint := 0;
  v_tables jsonb := '[]'::jsonb;
  v_buckets jsonb := '[]'::jsonb;
begin
  if public.current_user_role_norm() not in (
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  ) and not coalesce(public.has_custom_page_access('utilizzo_supabase'), false) then
    raise exception 'not allowed';
  end if;

  v_db_bytes := pg_database_size(current_database());

  select count(*)::bigint into v_auth_users from auth.users;
  select count(*)::bigint into v_app_users from public.users;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', t.name,
        'bytes', t.bytes,
        'est_rows', t.est_rows
      )
      order by t.bytes desc
    ),
    '[]'::jsonb
  )
  into v_tables
  from (
    select
      c.relname::text as name,
      pg_total_relation_size(c.oid)::bigint as bytes,
      greatest(c.reltuples, 0)::bigint as est_rows
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
    order by pg_total_relation_size(c.oid) desc
    limit 15
  ) t;

  begin
    select coalesce(sum(s.bytes), 0)::bigint, coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'files', s.files,
          'bytes', s.bytes
        )
        order by s.bytes desc
      ),
      '[]'::jsonb
    )
    into v_storage_bytes, v_buckets
    from (
      select
        b.id::text as id,
        coalesce(o.files, 0)::bigint as files,
        coalesce(o.bytes, 0)::bigint as bytes
      from storage.buckets b
      left join (
        select
          obj.bucket_id,
          count(*)::bigint as files,
          coalesce(
            sum(
              case
                when (obj.metadata->>'size') ~ '^[0-9]+$'
                  then (obj.metadata->>'size')::bigint
                else 0
              end
            ),
            0
          )::bigint as bytes
        from storage.objects obj
        group by obj.bucket_id
      ) o on o.bucket_id = b.id
    ) s;
  exception
    when others then
      v_storage_bytes := 0;
      v_buckets := '[]'::jsonb;
  end;

  return jsonb_build_object(
    'checked_at', timezone('utc', now()),
    'database_bytes', v_db_bytes,
    'storage_bytes', v_storage_bytes,
    'auth_users', v_auth_users,
    'app_users', v_app_users,
    'tables', coalesce(v_tables, '[]'::jsonb),
    'buckets', coalesce(v_buckets, '[]'::jsonb)
  );
end;
$$;

comment on function public.admin_supabase_usage() is
  'Utilizzo database Postgres e file Storage. Solo admin / pagina custom.';

grant execute on function public.admin_supabase_usage() to authenticated;

notify pgrst, 'reload schema';

-- Audit RLS pagine CRONOS: InitPlan wrap su helper costosi
-- (cronos_*, current_user_uuid, has_custom_page_access) per evitare timeout 57014.
-- Pattern: fn() → (select fn()) così Postgres valuta 1 volta per statement.

create or replace function public._cronos_rls_wrap_helpers(expr text)
returns text
language plpgsql
immutable
as $$
declare
  out text := expr;
begin
  if out is null or btrim(out) = '' then
    return out;
  end if;

  -- 1) Proteggi già wrappati: ( SELECT fn() AS ... )
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+has_custom_page_access\(([^)]*)\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___HCPA__(\1)___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+cronos_is_staff_reader\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CSR___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+cronos_is_staff_writer\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CSW___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+cronos_is_admin_writer\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CAW___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+cronos_is_staff_reader_fast\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CSRF___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+cronos_is_dt_role\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CDT___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+cronos_my_personale_uuid\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CMPU___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+cronos_my_personale_id\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CMPI___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+current_user_uuid\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CUU___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+current_user_role_norm\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___CURN___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+user_has_dt_role\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___UHDT___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+is_admin_generale_equivalent\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___IAGE___',
    'gi'
  );
  out := regexp_replace(
    out,
    '\(\s*SELECT\s+is_buoni_pasto_admin\(\)(\s+AS\s+[a-zA-Z0-9_]+)?\s*\)',
    '___IBPA___',
    'gi'
  );

  -- 2) Wrap rimanenti non protetti
  out := regexp_replace(
    out,
    'has_custom_page_access\(([^)]*)\)',
    '(select has_custom_page_access(\1))',
    'gi'
  );
  out := regexp_replace(out, 'cronos_is_staff_reader\(\)', '(select cronos_is_staff_reader())', 'gi');
  out := regexp_replace(out, 'cronos_is_staff_writer\(\)', '(select cronos_is_staff_writer())', 'gi');
  out := regexp_replace(out, 'cronos_is_admin_writer\(\)', '(select cronos_is_admin_writer())', 'gi');
  out := regexp_replace(out, 'cronos_is_staff_reader_fast\(\)', '(select cronos_is_staff_reader_fast())', 'gi');
  out := regexp_replace(out, 'cronos_is_dt_role\(\)', '(select cronos_is_dt_role())', 'gi');
  out := regexp_replace(out, 'cronos_my_personale_uuid\(\)', '(select cronos_my_personale_uuid())', 'gi');
  out := regexp_replace(out, 'cronos_my_personale_id\(\)', '(select cronos_my_personale_id())', 'gi');
  out := regexp_replace(out, 'current_user_uuid\(\)', '(select current_user_uuid())', 'gi');
  out := regexp_replace(out, 'current_user_role_norm\(\)', '(select current_user_role_norm())', 'gi');
  out := regexp_replace(out, 'user_has_dt_role\(\)', '(select user_has_dt_role())', 'gi');
  out := regexp_replace(out, 'is_admin_generale_equivalent\(\)', '(select is_admin_generale_equivalent())', 'gi');
  out := regexp_replace(out, 'is_buoni_pasto_admin\(\)', '(select is_buoni_pasto_admin())', 'gi');

  -- 3) Ripristina placeholder → forma InitPlan canonica
  out := regexp_replace(out, '___HCPA__\(([^)]*)\)___', '(select has_custom_page_access(\1))', 'g');
  out := replace(out, '___CSR___', '(select cronos_is_staff_reader())');
  out := replace(out, '___CSW___', '(select cronos_is_staff_writer())');
  out := replace(out, '___CAW___', '(select cronos_is_admin_writer())');
  out := replace(out, '___CSRF___', '(select cronos_is_staff_reader_fast())');
  out := replace(out, '___CDT___', '(select cronos_is_dt_role())');
  out := replace(out, '___CMPU___', '(select cronos_my_personale_uuid())');
  out := replace(out, '___CMPI___', '(select cronos_my_personale_id())');
  out := replace(out, '___CUU___', '(select current_user_uuid())');
  out := replace(out, '___CURN___', '(select current_user_role_norm())');
  out := replace(out, '___UHDT___', '(select user_has_dt_role())');
  out := replace(out, '___IAGE___', '(select is_admin_generale_equivalent())');
  out := replace(out, '___IBPA___', '(select is_buoni_pasto_admin())');

  return out;
end;
$$;

do $$
declare
  r record;
  new_using text;
  new_check text;
  roles_sql text;
  cmd_sql text;
  perm_sql text;
  to_sql text;
  ddl text;
  changed int := 0;
begin
  for r in
    select
      n.nspname as schema_name,
      c.relname as table_name,
      p.polname as policy_name,
      p.polcmd as polcmd,
      p.polpermissive as permissive,
      p.polroles as polroles,
      pg_get_expr(p.polqual, p.polrelid) as using_expr,
      pg_get_expr(p.polwithcheck, p.polrelid) as check_expr
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
  loop
    new_using := public._cronos_rls_wrap_helpers(r.using_expr);
    new_check := public._cronos_rls_wrap_helpers(r.check_expr);

    if new_using is not distinct from r.using_expr
       and new_check is not distinct from r.check_expr then
      continue;
    end if;

    cmd_sql := case r.polcmd
      when 'r' then 'select'
      when 'a' then 'insert'
      when 'w' then 'update'
      when 'd' then 'delete'
      when '*' then 'all'
      else null
    end;
    if cmd_sql is null then
      raise notice 'skip unknown polcmd % on %.%', r.polcmd, r.table_name, r.policy_name;
      continue;
    end if;

    perm_sql := case when r.permissive then 'permissive' else 'restrictive' end;

    if r.polroles is null or cardinality(r.polroles) = 0 then
      to_sql := 'public';
    else
      select string_agg(quote_ident(oid::regrole::text), ', ' order by oid::regrole::text)
        into to_sql
      from unnest(r.polroles) as oid;
      if to_sql is null or btrim(to_sql) = '' then
        to_sql := 'public';
      end if;
    end if;

    execute format(
      'drop policy if exists %I on %I.%I',
      r.policy_name, r.schema_name, r.table_name
    );

    ddl := format(
      'create policy %I on %I.%I as %s for %s to %s',
      r.policy_name, r.schema_name, r.table_name, perm_sql, cmd_sql, to_sql
    );

    if new_using is not null then
      ddl := ddl || ' using (' || new_using || ')';
    end if;
    if new_check is not null then
      ddl := ddl || ' with check (' || new_check || ')';
    end if;

    begin
      execute ddl;
      changed := changed + 1;
    exception when others then
      raise exception
        'RLS wrap failed on %.%: % | ddl=%',
        r.table_name, r.policy_name, sqlerrm, ddl;
    end;
  end loop;

  raise notice 'cronos RLS InitPlan wrap: % policies updated', changed;
end;
$$;

-- Hygiene: RLS su tabelle carburante / multicard
do $$
begin
  if to_regclass('public.logistica_rcc_carburante') is not null then
    execute 'alter table public.logistica_rcc_carburante enable row level security';
  end if;
  if to_regclass('public.logistica_rcc_mdo_carburante') is not null then
    execute 'alter table public.logistica_rcc_mdo_carburante enable row level security';
  end if;
  if to_regclass('public.logistica_multicard') is not null then
    execute 'alter table public.logistica_multicard enable row level security';
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'logistica_multicard'
        and policyname = 'logistica_multicard_select_role_allowed'
    ) then
      execute $pol$
        create policy logistica_multicard_select_role_allowed
        on public.logistica_multicard for select to authenticated
        using (
          (select public.cronos_is_staff_reader())
          or coalesce((select public.has_custom_page_access('logistica')), false)
          or coalesce((select public.has_custom_page_access('logistica_multicard')), false)
        )
      $pol$;
      execute $pol$
        create policy logistica_multicard_write_role_allowed
        on public.logistica_multicard for all to authenticated
        using (
          (select public.cronos_is_staff_writer())
          or coalesce((select public.has_custom_page_access('logistica')), false)
          or coalesce((select public.has_custom_page_access('logistica_multicard')), false)
        )
        with check (
          (select public.cronos_is_staff_writer())
          or coalesce((select public.has_custom_page_access('logistica')), false)
          or coalesce((select public.has_custom_page_access('logistica_multicard')), false)
        )
      $pol$;
    end if;
  end if;
end;
$$;

drop function if exists public._cronos_rls_wrap_helpers(text);

notify pgrst, 'reload schema';

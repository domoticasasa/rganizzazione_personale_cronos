-- Fix lettura/download PDF assegnazione mezzi + attrezzature:
-- helper con secondary_role (cronos_has_role) + InitPlan su storage/table.

create or replace function public.is_assegnazione_mezzi_stradali_documenti_reader()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (select public.cronos_has_role(
      'admin',
      'admin_generale',
      'admin_vista',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_treno_aereo',
      'admin_dpi',
      'admin_formazione',
      'dt',
      'assistente_dt',
      'logistica'
    ))
    or coalesce((select public.has_custom_page_access('logistica_assegnazione_mezzi_stradali')), false)
    or coalesce((select public.has_custom_page_access('logistica_mezzi_stradali')), false)
    or coalesce((select public.has_custom_page_access('mezzi_stradali')), false)
    or coalesce((select public.has_custom_page_access('logistica')), false);
$$;

create or replace function public.can_write_assegnazione_mezzi_stradali_documenti()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (select public.cronos_has_role(
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'admin_dpi',
    'admin_formazione',
    'logistica'
  ));
$$;

create or replace function public.is_assegnazione_attrezzature_documenti_reader()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (select public.cronos_has_role(
      'admin',
      'admin_generale',
      'admin_vista',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_treno_aereo',
      'admin_dpi',
      'admin_formazione',
      'dt',
      'assistente_dt',
      'logistica'
    ))
    or coalesce((select public.has_custom_page_access('logistica_assegnazione_attrezzature')), false)
    or coalesce((select public.has_custom_page_access('logistica_attrezzature')), false)
    or coalesce((select public.has_custom_page_access('attrezzature')), false)
    or coalesce((select public.has_custom_page_access('logistica')), false);
$$;

create or replace function public.can_write_assegnazione_attrezzature_documenti()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (select public.cronos_has_role(
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'admin_dpi',
    'admin_formazione',
    'logistica'
  ));
$$;

-- Re-assert storage SELECT policies (createSignedUrl / download)
drop policy if exists logistica_assegnazione_mezzi_doc_storage_select
  on storage.objects;
create policy logistica_assegnazione_mezzi_doc_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'logistica_assegnazione_mezzi_stradali_documenti'
    and (select public.is_assegnazione_mezzi_stradali_documenti_reader())
  );

drop policy if exists logistica_assegnazione_mezzi_doc_storage_insert
  on storage.objects;
create policy logistica_assegnazione_mezzi_doc_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'logistica_assegnazione_mezzi_stradali_documenti'
    and (select public.can_write_assegnazione_mezzi_stradali_documenti())
  );

drop policy if exists logistica_assegnazione_attrezzature_doc_storage_select
  on storage.objects;
create policy logistica_assegnazione_attrezzature_doc_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'logistica_assegnazione_attrezzature_documenti'
    and (select public.is_assegnazione_attrezzature_documenti_reader())
  );

drop policy if exists logistica_assegnazione_attrezzature_doc_storage_insert
  on storage.objects;
create policy logistica_assegnazione_attrezzature_doc_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'logistica_assegnazione_attrezzature_documenti'
    and (select public.can_write_assegnazione_attrezzature_documenti())
  );

notify pgrst, 'reload schema';

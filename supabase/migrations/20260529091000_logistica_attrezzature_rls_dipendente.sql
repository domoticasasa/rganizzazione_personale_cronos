-- Attrezzature: admin/logistica scrivono, DT solo lettura,
-- dipendente vede solo quelle assegnate a se stesso (match per nome).

-- Normalizza un nome persona: minuscolo, spazi collassati, token ordinati.
-- Permette match robusto "COGNOME NOME" vs "Nome Cognome".
create or replace function public.norm_person_tokens(p text)
returns text
language sql
immutable
as $$
  select coalesce(
    array_to_string(
      array(
        select t
        from unnest(
          regexp_split_to_array(
            lower(regexp_replace(trim(coalesce(p, '')), '\s+', ' ', 'g')),
            ' '
          )
        ) as t
        where t <> ''
        order by t
      ),
      ' '
    ),
    ''
  );
$$;

-- SELECT: ruoli gestione (DT/assistente DT in sola lettura) + admin/logistica.
drop policy if exists logistica_attrezzature_select_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_select_role_allowed
on public.logistica_attrezzature
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

-- SELECT: dipendente vede solo le attrezzature assegnate a se stesso.
drop policy if exists logistica_attrezzature_select_dipendente on public.logistica_attrezzature;
create policy logistica_attrezzature_select_dipendente
on public.logistica_attrezzature
for select
to authenticated
using (
  coalesce(logistica_attrezzature.assegnatario, '') <> ''
  and exists (
    select 1
    from public.users u
    left join public.personale p on (p.user_id::text = u.id::text)
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dipendente', 'user')
      and (
        public.norm_person_tokens(logistica_attrezzature.assegnatario)
          = public.norm_person_tokens(u.full_name)
        or public.norm_person_tokens(logistica_attrezzature.assegnatario)
          = public.norm_person_tokens(p.full_name)
      )
  )
);

-- WRITE: solo admin/logistica. DT, assistente DT e dipendente NON modificano.
drop policy if exists logistica_attrezzature_insert_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_insert_role_allowed
on public.logistica_attrezzature
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

drop policy if exists logistica_attrezzature_update_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_update_role_allowed
on public.logistica_attrezzature
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

drop policy if exists logistica_attrezzature_delete_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_delete_role_allowed
on public.logistica_attrezzature
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

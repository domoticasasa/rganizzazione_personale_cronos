-- Allinea is_cronos_admin_role ai ruoli admin che possono salvare layout UI
-- (come canMutateAsAdmin in Dart). Prima mancavano admin_formazione / admin_dpi:
-- l'UI mostrava «Salva per tutti» ma RLS scartava l'upsert senza errore.

create or replace function public.is_cronos_admin_role()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(replace(replace(coalesce(u.role, ''), ' ', '_'), '/', '_')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_treno_aereo',
        'admin_formazione',
        'admin_dpi'
      )
  );
$$;

notify pgrst, 'reload schema';
